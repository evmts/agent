const std = @import("std");
const testing = std.testing;

pub const AuthenticationMethod = enum {
    http_basic,
    bearer_token,
    api_key_header,
    ssh_key_over_http,
    session_cookie,
    organization_token,
    temporary_token,
};

pub const TokenScope = enum {
    repo_read,
    repo_write,
    repo_admin,
    org_read,
    org_write,
    org_admin,
    user_read,
    user_write,
};

pub const RateLimitTier = enum {
    free,
    pro,
    enterprise,
};

pub const AuthenticationResult = struct {
    authenticated: bool,
    user_id: u32,
    organization_id: ?u32 = null,
    team_ids: []u32 = &.{},
    token_scopes: []TokenScope = &.{},
    rate_limit_tier: RateLimitTier = .free,
    expires_at: ?i64 = null,
};

pub const UserContext = struct {
    user_id: u32,
    username: []const u8,
    email: []const u8,
    is_admin: bool = false,
};

pub const TeamContext = struct {
    team_id: u32,
    team_name: []const u8,
    organization_id: u32,
    permissions: []TokenScope,
};

pub const OrganizationContext = struct {
    organization_id: u32,
    organization_name: []const u8,
    user_role: []const u8,
    teams: []TeamContext,
};

// Mock database structures for testing
pub const MockUser = struct {
    id: u32,
    username: []const u8,
    email: []const u8,
    password_hash: []const u8,
    is_admin: bool = false,
};

pub const MockApiToken = struct {
    id: u32,
    token: []const u8,
    user_id: u32,
    scopes: []TokenScope,
    expires_at: ?i64 = null,
};

pub const MockDatabase = struct {
    users: std.ArrayList(MockUser),
    api_tokens: std.ArrayList(MockApiToken),
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) MockDatabase {
        return .{
            .users = std.ArrayList(MockUser).init(allocator),
            .api_tokens = std.ArrayList(MockApiToken).init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *MockDatabase) void {
        // Free allocated strings in users and tokens
        for (self.users.items) |user| {
            self.allocator.free(user.username);
            self.allocator.free(user.email);
            self.allocator.free(user.password_hash);
        }
        for (self.api_tokens.items) |token| {
            self.allocator.free(token.token);
            self.allocator.free(token.scopes);
        }
        self.users.deinit();
        self.api_tokens.deinit();
    }
    
    pub fn createUser(self: *MockDatabase, username: []const u8, email: []const u8, password_hash: []const u8) !u32 {
        const user_id = @as(u32, @intCast(self.users.items.len + 1));
        try self.users.append(.{
            .id = user_id,
            .username = try self.allocator.dupe(u8, username),
            .email = try self.allocator.dupe(u8, email),
            .password_hash = try self.allocator.dupe(u8, password_hash),
        });
        return user_id;
    }
    
    pub fn createApiToken(self: *MockDatabase, user_id: u32, scopes: []const TokenScope) !MockApiToken {
        const token_id = @as(u32, @intCast(self.api_tokens.items.len + 1));
        const token = try std.fmt.allocPrint(self.allocator, "token_{d}_{d}", .{ user_id, token_id });
        const scopes_copy = try self.allocator.dupe(TokenScope, scopes);
        
        const api_token = MockApiToken{
            .id = token_id,
            .token = token,
            .user_id = user_id,
            .scopes = scopes_copy,
        };
        
        try self.api_tokens.append(api_token);
        return api_token;
    }
    
    pub fn findUserByToken(self: *const MockDatabase, token: []const u8) ?MockUser {
        for (self.api_tokens.items) |api_token| {
            if (std.mem.eql(u8, api_token.token, token)) {
                for (self.users.items) |user| {
                    if (user.id == api_token.user_id) {
                        return user;
                    }
                }
            }
        }
        return null;
    }
    
    pub fn findTokenByValue(self: *const MockDatabase, token: []const u8) ?MockApiToken {
        for (self.api_tokens.items) |api_token| {
            if (std.mem.eql(u8, api_token.token, token)) {
                return api_token;
            }
        }
        return null;
    }
    
    pub fn deleteUser(self: *MockDatabase, user_id: u32) !void {
        for (self.users.items, 0..) |user, i| {
            if (user.id == user_id) {
                const removed = self.users.swapRemove(i);
                self.allocator.free(removed.username);
                self.allocator.free(removed.email);
                self.allocator.free(removed.password_hash);
                return;
            }
        }
    }
    
    pub fn revokeApiToken(self: *MockDatabase, token_id: u32) !void {
        for (self.api_tokens.items, 0..) |token, i| {
            if (token.id == token_id) {
                const removed = self.api_tokens.swapRemove(i);
                self.allocator.free(removed.token);
                self.allocator.free(removed.scopes);
                return;
            }
        }
    }
};

pub const MultiTierAuthManager = struct {
    database: *MockDatabase,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, database: *MockDatabase) MultiTierAuthManager {
        return .{
            .allocator = allocator,
            .database = database,
        };
    }
    
    pub fn authenticateBasic(self: *MultiTierAuthManager, auth_header: []const u8) !AuthenticationResult {
        // Parse Basic auth: "Basic base64(username:password)"
        if (!std.mem.startsWith(u8, auth_header, "Basic ")) {
            return AuthenticationResult{ .authenticated = false, .user_id = 0 };
        }
        
        const encoded = auth_header[6..]; // Skip "Basic "
        const decoded = try self.decodeBase64(encoded);
        defer self.allocator.free(decoded);
        
        const colon_pos = std.mem.indexOf(u8, decoded, ":") orelse {
            return AuthenticationResult{ .authenticated = false, .user_id = 0 };
        };
        
        const username = decoded[0..colon_pos];
        const password_or_token = decoded[colon_pos + 1 ..];
        
        // Check if it's an API token (api-key:token format)
        if (std.mem.eql(u8, username, "api-key")) {
            if (self.database.findUserByToken(password_or_token)) |user| {
                const token = self.database.findTokenByValue(password_or_token).?;
                return AuthenticationResult{
                    .authenticated = true,
                    .user_id = user.id,
                    .token_scopes = token.scopes,
                    .rate_limit_tier = if (user.is_admin) .enterprise else .free,
                };
            }
        }
        
        return AuthenticationResult{ .authenticated = false, .user_id = 0 };
    }
    
    fn decodeBase64(self: *MultiTierAuthManager, encoded: []const u8) ![]u8 {
        // Simple base64 decode for testing - in production use std.base64
        // For tests, just return the "encoded" string as is (mock)
        return self.allocator.dupe(u8, encoded);
    }
};

// Test request structure from git_server.zig
const TestRequest = struct {
    method: std.http.Method,
    path: []const u8,
    query: ?[]const u8 = null,
    headers: []const Header = &.{},
    body: ?[]const u8 = null,
    client_ip: []const u8 = "127.0.0.1",
    allocator: std.mem.Allocator,
    
    const Header = struct {
        name: []const u8,
        value: []const u8,
    };
    
    fn getHeader(self: *const TestRequest, name: []const u8) ?[]const u8 {
        for (self.headers) |header| {
            if (std.mem.eql(u8, header.name, name)) {
                return header.value;
            }
        }
        return null;
    }
    
    pub fn deinit(self: *TestRequest) void {
        _ = self;
    }
};

fn createTestRequest(allocator: std.mem.Allocator, options: struct {
    method: std.http.Method,
    path: []const u8,
    query: ?[]const u8 = null,
    headers: []const TestRequest.Header = &.{},
    body: ?[]const u8 = null,
    client_ip: []const u8 = "127.0.0.1",
}) !TestRequest {
    return TestRequest{
        .allocator = allocator,
        .method = options.method,
        .path = options.path,
        .query = options.query,
        .headers = options.headers,
        .body = options.body,
        .client_ip = options.client_ip,
    };
}

fn createTestUser(db: *MockDatabase, allocator: std.mem.Allocator, options: struct {
    username: []const u8 = "testuser",
    email: []const u8 = "test@example.com",
    password: []const u8 = "password123",
    is_admin: bool = false,
}) !u32 {
    _ = allocator;
    _ = options;
    return try db.createUser("testuser", "test@example.com", "hashed_password");
}

// Tests for Phase 2: Authentication and Authorization
test "authenticates HTTP Basic Auth for Git operations" {
    const allocator = testing.allocator;
    
    var db = MockDatabase.init(allocator);
    defer db.deinit();
    
    // Create test user with API token
    const user_id = try createTestUser(&db, allocator, .{});
    defer _ = db.deleteUser(user_id) catch {};
    
    const api_token = try db.createApiToken(user_id, &.{.repo_read});
    defer _ = db.revokeApiToken(api_token.id) catch {};
    
    var auth_manager = MultiTierAuthManager.init(allocator, &db);
    
    // Mock base64 encoding: "api-key:token_1_1" -> "api-key:token_1_1"
    const auth_header = try std.fmt.allocPrint(allocator, "Basic api-key:{s}", .{api_token.token});
    defer allocator.free(auth_header);
    
    var request = try createTestRequest(allocator, .{
        .method = .GET,
        .path = "/owner/repo.git/info/refs",
        .headers = &.{.{ .name = "Authorization", .value = auth_header }},
    });
    defer request.deinit();
    
    const auth_context = try auth_manager.authenticateBasic(auth_header);
    try testing.expect(auth_context.authenticated);
    try testing.expectEqual(user_id, auth_context.user_id);
    try testing.expectEqual(@as(usize, 1), auth_context.token_scopes.len);
    try testing.expectEqual(TokenScope.repo_read, auth_context.token_scopes[0]);
}

test "rejects invalid authentication credentials" {
    const allocator = testing.allocator;
    
    var db = MockDatabase.init(allocator);
    defer db.deinit();
    
    var auth_manager = MultiTierAuthManager.init(allocator, &db);
    
    // Test invalid Basic auth format
    const invalid_auth = "Basic invalid-token";
    const auth_result = try auth_manager.authenticateBasic(invalid_auth);
    try testing.expect(!auth_result.authenticated);
    
    // Test non-existent token
    const nonexistent_auth = "Basic api-key:nonexistent-token";
    const auth_result2 = try auth_manager.authenticateBasic(nonexistent_auth);
    try testing.expect(!auth_result2.authenticated);
}

test "validates token scopes for operations" {
    const allocator = testing.allocator;
    
    var db = MockDatabase.init(allocator);
    defer db.deinit();
    
    // Create user with read-only token
    const user_id = try createTestUser(&db, allocator, .{});
    defer _ = db.deleteUser(user_id) catch {};
    
    const read_token = try db.createApiToken(user_id, &.{.repo_read});
    defer _ = db.revokeApiToken(read_token.id) catch {};
    
    // Create user with write token
    const write_user_id = try createTestUser(&db, allocator, .{});
    defer _ = db.deleteUser(write_user_id) catch {};
    
    const write_token = try db.createApiToken(write_user_id, &.{ .repo_read, .repo_write });
    defer _ = db.revokeApiToken(write_token.id) catch {};
    
    var auth_manager = MultiTierAuthManager.init(allocator, &db);
    
    // Test read-only token
    const read_auth = try std.fmt.allocPrint(allocator, "Basic api-key:{s}", .{read_token.token});
    defer allocator.free(read_auth);
    
    const read_result = try auth_manager.authenticateBasic(read_auth);
    try testing.expect(read_result.authenticated);
    try testing.expectEqual(@as(usize, 1), read_result.token_scopes.len);
    try testing.expectEqual(TokenScope.repo_read, read_result.token_scopes[0]);
    
    // Test write token
    const write_auth = try std.fmt.allocPrint(allocator, "Basic api-key:{s}", .{write_token.token});
    defer allocator.free(write_auth);
    
    const write_result = try auth_manager.authenticateBasic(write_auth);
    try testing.expect(write_result.authenticated);
    try testing.expectEqual(@as(usize, 2), write_result.token_scopes.len);
}

test "handles multiple authentication methods" {
    const allocator = testing.allocator;
    
    var db = MockDatabase.init(allocator);
    defer db.deinit();
    
    var auth_manager = MultiTierAuthManager.init(allocator, &db);
    
    // Test missing Authorization header
    const no_auth_result = try auth_manager.authenticateBasic("");
    try testing.expect(!no_auth_result.authenticated);
    
    // Test malformed Basic auth
    const malformed_auth = "Bearer some-token";
    const malformed_result = try auth_manager.authenticateBasic(malformed_auth);
    try testing.expect(!malformed_result.authenticated);
}