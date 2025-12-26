//! Integration test harness
//!
//! Provides infrastructure for running integration tests against a real PostgreSQL database.
//! Tests use a separate test database (specified by TEST_DATABASE_URL env var).

const std = @import("std");
const httpz = @import("httpz");
const pg = @import("pg");
const config = @import("../../config.zig");
const db = @import("db");
const Context = @import("../../main.zig").Context;
const middleware = @import("../../middleware/mod.zig");
const routes = @import("../../routes.zig");

const log = std.log.scoped(.integration_test);

// Re-export test modules
pub const auth_test = @import("auth_test.zig");
pub const repo_test = @import("repo_test.zig");

// =============================================================================
// Test Configuration
// =============================================================================

pub const TestConfig = struct {
    database_url: []const u8,
    cleanup_on_success: bool = true,
    cleanup_on_failure: bool = false,
};

/// Get test database URL from environment or use default
pub fn getTestDatabaseUrl() []const u8 {
    return std.posix.getenv("TEST_DATABASE_URL") orelse
        "postgres://localhost:5432/plue_test";
}

// =============================================================================
// Test Context
// =============================================================================

/// Test context wraps the full application context with additional test helpers
pub const TestContext = struct {
    allocator: std.mem.Allocator,
    pool: *db.Pool,
    server: *httpz.Server(*Context),
    app_context: *Context,
    config: TestConfig,

    // Store created resources for cleanup
    created_users: std.ArrayList(i32), // Changed from i64 to match Postgres INTEGER type
    created_sessions: std.ArrayList([]const u8),
    created_repos: std.ArrayList(i64), // TODO: Check if repos.id should also be i32

    /// Initialize test context with database connection and test server
    pub fn init(allocator: std.mem.Allocator, test_config: TestConfig) !*TestContext {
        log.info("Initializing test context...", .{});

        // Parse database URL and create pool
        const uri = try std.Uri.parse(test_config.database_url);
        const pool = try allocator.create(db.Pool);
        pool.* = try db.Pool.initUri(allocator, uri, .{
            .size = 5,
            .timeout = 10_000,
        });

        log.info("Database pool created", .{});

        // Initialize CSRF store
        const csrf_store = try allocator.create(middleware.CsrfStore);
        csrf_store.* = middleware.CsrfStore.init(allocator);

        // Create application context
        const app_context = try allocator.create(Context);
        app_context.* = .{
            .allocator = allocator,
            .pool = pool,
            .config = .{
                .host = "127.0.0.1",
                .port = 0, // Don't actually bind to a port
                .database_url = test_config.database_url,
                .jwt_secret = "test-secret-key",
                .electric_url = "",
                .cors_origins = &.{},
                .is_production = false,
                .ssh_enabled = false,
                .ssh_host = "127.0.0.1",
                .ssh_port = 0,
                .watcher_enabled = false,
                .edge_url = "",
                .edge_push_secret = "",
            },
            .csrf_store = csrf_store,
            .repo_watcher = null,
            .edge_notifier = null,
            .connection_manager = null,
            .user = null,
            .session_key = null,
            .token_scopes = null,
        };

        // Initialize HTTP server (won't actually listen)
        const server = try allocator.create(httpz.Server(*Context));
        server.* = try httpz.Server(*Context).init(allocator, .{
            .port = 0,
            .address = "127.0.0.1",
        }, app_context);

        // Configure routes
        try routes.configure(server);

        log.info("Test server configured", .{});

        // Create test context
        const self = try allocator.create(TestContext);
        self.* = .{
            .allocator = allocator,
            .pool = pool,
            .server = server,
            .app_context = app_context,
            .config = test_config,
            .created_users = std.ArrayList(i32).init(allocator), // Changed from i64 to match Postgres INTEGER type
            .created_sessions = std.ArrayList([]const u8).init(allocator),
            .created_repos = std.ArrayList(i64).init(allocator),
        };

        // Clean database before tests
        try self.cleanDatabase();

        log.info("Test context initialized successfully", .{});
        return self;
    }

    /// Clean up test context and optionally clean database
    pub fn deinit(self: *TestContext, success: bool) void {
        log.info("Cleaning up test context...", .{});

        const should_cleanup = if (success)
            self.config.cleanup_on_success
        else
            self.config.cleanup_on_failure;

        if (should_cleanup) {
            self.cleanDatabase() catch |err| {
                log.err("Failed to clean database: {}", .{err});
            };
        }

        // Free tracked resources
        for (self.created_sessions.items) |session| {
            self.allocator.free(session);
        }
        self.created_sessions.deinit();
        self.created_users.deinit();
        self.created_repos.deinit();

        // Deinit server and services
        self.server.deinit();
        self.app_context.csrf_store.deinit();

        // Deinit pool
        self.pool.deinit();

        // Free allocated structures
        self.allocator.destroy(self.app_context.csrf_store);
        self.allocator.destroy(self.server);
        self.allocator.destroy(self.app_context);
        self.allocator.destroy(self.pool);
        self.allocator.destroy(self);

        log.info("Test context cleanup complete", .{});
    }

    /// Clean all test data from database
    pub fn cleanDatabase(self: *TestContext) !void {
        log.info("Cleaning test database...", .{});

        var conn = try self.pool.acquire();
        defer conn.release();

        // Delete in order to respect foreign key constraints
        _ = try conn.exec("DELETE FROM parts", .{});
        _ = try conn.exec("DELETE FROM messages", .{});
        _ = try conn.exec("DELETE FROM sessions", .{});
        _ = try conn.exec("DELETE FROM issue_labels", .{});
        _ = try conn.exec("DELETE FROM labels", .{});
        _ = try conn.exec("DELETE FROM issue_assignees", .{});
        _ = try conn.exec("DELETE FROM comments", .{});
        _ = try conn.exec("DELETE FROM issues", .{});
        _ = try conn.exec("DELETE FROM milestones", .{});
        _ = try conn.exec("DELETE FROM repositories WHERE user_id IS NOT NULL", .{}); // Keep system repos
        _ = try conn.exec("DELETE FROM access_tokens", .{});
        _ = try conn.exec("DELETE FROM auth_sessions", .{});
        _ = try conn.exec("DELETE FROM email_addresses", .{});
        _ = try conn.exec("DELETE FROM siwe_nonces", .{});
        _ = try conn.exec("DELETE FROM users WHERE username NOT IN ('evilrabbit', 'ghost', 'null')", .{}); // Keep seed users

        log.info("Database cleaned", .{});
    }

    /// Create a test user
    pub fn createTestUser(self: *TestContext, username: []const u8, email: ?[]const u8) !i32 { // Changed from i64 to match Postgres INTEGER type
        var conn = try self.pool.acquire();
        defer conn.release();

        const lower_username = try std.ascii.allocLowerString(self.allocator, username);
        defer self.allocator.free(lower_username);

        const lower_email = if (email) |e| try std.ascii.allocLowerString(self.allocator, e) else null;
        defer if (lower_email) |le| self.allocator.free(le);

        var result = try conn.query(
            \\INSERT INTO users (username, lower_username, email, lower_email, is_active)
            \\VALUES ($1, $2, $3, $4, true)
            \\RETURNING id
        , .{ username, lower_username, email, lower_email });
        defer result.deinit();

        if (try result.next()) |row| {
            const user_id = row.get(i32, 0); // Changed from i64 to match Postgres INTEGER type
            try self.created_users.append(user_id);
            return user_id;
        }

        return error.FailedToCreateUser;
    }

    /// Create a test session
    pub fn createTestSession(self: *TestContext, user_id: i32, username: []const u8, is_admin: bool) ![]const u8 { // Changed from i64 to match Postgres INTEGER type
        const session_key = try db.createSession(self.pool, self.allocator, user_id, username, is_admin);
        try self.created_sessions.append(session_key);
        return session_key;
    }

    /// Create a test repository
    pub fn createTestRepo(self: *TestContext, user_id: i64, name: []const u8) !i64 {
        var conn = try self.pool.acquire();
        defer conn.release();

        var result = try conn.query(
            \\INSERT INTO repositories (user_id, name, is_public)
            \\VALUES ($1, $2, true)
            \\RETURNING id
        , .{ user_id, name });
        defer result.deinit();

        if (try result.next()) |row| {
            const repo_id = row.get(i64, 0);
            try self.created_repos.append(repo_id);
            return repo_id;
        }

        return error.FailedToCreateRepo;
    }
};

// =============================================================================
// Test HTTP Client
// =============================================================================

/// Simple HTTP client for making test requests
pub const TestClient = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) TestClient {
        return .{ .allocator = allocator };
    }

    /// Make a GET request and return the response body
    pub fn get(self: TestClient, path: []const u8, session_key: ?[]const u8) ![]const u8 {
        _ = self;
        _ = path;
        _ = session_key;
        // Note: In a full implementation, this would make actual HTTP requests
        // For now, tests will directly call route handlers
        return error.NotImplemented;
    }

    /// Make a POST request and return the response body
    pub fn post(self: TestClient, path: []const u8, body: []const u8, session_key: ?[]const u8) ![]const u8 {
        _ = self;
        _ = path;
        _ = body;
        _ = session_key;
        return error.NotImplemented;
    }
};

// =============================================================================
// Test Assertions
// =============================================================================

/// Assert that a database query returns the expected number of rows
pub fn assertRowCount(pool: *db.Pool, query: []const u8, expected: usize) !void {
    var conn = try pool.acquire();
    defer conn.release();

    var result = try conn.query(query, .{});
    defer result.deinit();

    var count: usize = 0;
    while (try result.next()) |_| {
        count += 1;
    }

    if (count != expected) {
        log.err("Expected {} rows, got {}", .{ expected, count });
        return error.AssertionFailed;
    }
}

/// Assert that a user exists with the given username
pub fn assertUserExists(pool: *db.Pool, username: []const u8) !void {
    const user = try db.getUserByUsername(pool, username);
    if (user == null) {
        log.err("Expected user '{}' to exist", .{std.zig.fmtEscapes(username)});
        return error.UserNotFound;
    }
}

/// Assert that a repository exists
pub fn assertRepoExists(pool: *db.Pool, user_id: i64, repo_name: []const u8) !bool {
    var conn = try pool.acquire();
    defer conn.release();

    var result = try conn.query(
        \\SELECT id FROM repositories WHERE user_id = $1 AND name = $2
    , .{ user_id, repo_name });
    defer result.deinit();

    return (try result.next()) != null;
}
