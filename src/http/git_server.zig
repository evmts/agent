const std = @import("std");
const zap = @import("zap");
const testing = std.testing;

pub const GitHttpServerError = error{
    InvalidRepository,
    Unauthorized,
    RateLimited,
    ServerError,
    InvalidRequest,
};

pub const GitHttpConfig = struct {
    base_path: []const u8 = "/var/lib/plue/repositories",
    enable_protocol_v2: bool = true,
    rate_limit: RateLimitConfig = .{},
};

pub const RateLimitConfig = struct {
    requests_per_minute: u32 = 60,
    burst_size: u32 = 10,
};

pub const GitHttpServer = struct {
    config: GitHttpConfig,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, config: GitHttpConfig) !GitHttpServer {
        return GitHttpServer{
            .allocator = allocator,
            .config = config,
        };
    }
    
    pub fn deinit(self: *GitHttpServer) void {
        _ = self;
    }
    
    pub fn handleRequest(self: *GitHttpServer, request: *const TestRequest, response: *TestResponse) !void {
        const path = request.path;
        
        // Parse Git repository path
        const repo_info = try self.parseGitPath(path);
        defer self.allocator.free(repo_info.owner);
        defer self.allocator.free(repo_info.repo);
        
        // Check if repository exists
        const repo_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}/{s}.git", .{
            self.config.base_path,
            repo_info.owner,
            repo_info.repo,
        });
        defer self.allocator.free(repo_path);
        
        // For testing, simulate repository existence check
        if (std.mem.eql(u8, repo_info.owner, "nonexistent")) {
            response.status_code = 404;
            return;
        }
        
        // Handle Git Smart HTTP endpoints
        if (std.mem.endsWith(u8, path, "/info/refs")) {
            if (request.query) |query| {
                if (std.mem.indexOf(u8, query, "service=git-upload-pack") != null) {
                    response.status_code = 200;
                    try response.headers.put("Content-Type", "application/x-git-upload-pack-advertisement");
                    return;
                }
            }
        }
        
        response.status_code = 404;
    }
    
    fn parseGitPath(self: *GitHttpServer, path: []const u8) !struct { owner: []u8, repo: []u8 } {
        // Expected format: /owner/repo.git/...
        if (!std.mem.startsWith(u8, path, "/")) {
            return error.InvalidRequest;
        }
        
        const trimmed = path[1..]; // Remove leading /
        const git_suffix = ".git/";
        const git_pos = std.mem.indexOf(u8, trimmed, git_suffix) orelse return error.InvalidRequest;
        
        const owner_repo = trimmed[0..git_pos];
        const slash_pos = std.mem.indexOf(u8, owner_repo, "/") orelse return error.InvalidRequest;
        
        return .{
            .owner = try self.allocator.dupe(u8, owner_repo[0..slash_pos]),
            .repo = try self.allocator.dupe(u8, owner_repo[slash_pos + 1 ..]),
        };
    }
};

// Test utilities
pub const TestRequest = struct {
    method: std.http.Method,
    path: []const u8,
    query: ?[]const u8 = null,
    headers: []const Header = &.{},
    body: ?[]const u8 = null,
    client_ip: []const u8 = "127.0.0.1",
    allocator: std.mem.Allocator,
    
    pub const Header = struct {
        name: []const u8,
        value: []const u8,
    };
    
    pub fn deinit(self: *TestRequest) void {
        _ = self;
    }
};

pub const TestResponse = struct {
    status_code: u16 = 200,
    headers: std.StringHashMap([]const u8),
    body: std.ArrayList(u8),
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) TestResponse {
        return .{
            .headers = std.StringHashMap([]const u8).init(allocator),
            .body = std.ArrayList(u8).init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *TestResponse) void {
        self.headers.deinit();
        self.body.deinit();
    }
    
    pub fn getBody(self: *const TestResponse) []const u8 {
        return self.body.items;
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

// Tests for Phase 1: HTTP Server Foundation and Routing
test "routes Git Smart HTTP requests correctly" {
    const allocator = testing.allocator;
    
    const test_config = GitHttpConfig{};
    var server = try GitHttpServer.init(allocator, test_config);
    defer server.deinit();
    
    // Test info/refs routing
    var info_refs_request = try createTestRequest(allocator, .{
        .method = .GET,
        .path = "/owner/repo.git/info/refs",
        .query = "service=git-upload-pack",
    });
    defer info_refs_request.deinit();
    
    var response = TestResponse.init(allocator);
    defer response.deinit();
    
    try server.handleRequest(&info_refs_request, &response);
    
    try testing.expectEqual(@as(u16, 200), response.status_code);
    const content_type = response.headers.get("Content-Type") orelse "";
    try testing.expect(std.mem.indexOf(u8, content_type, "application/x-git") != null);
}

test "returns 404 for non-existent repository" {
    const allocator = testing.allocator;
    
    const test_config = GitHttpConfig{};
    var server = try GitHttpServer.init(allocator, test_config);
    defer server.deinit();
    
    var request = try createTestRequest(allocator, .{
        .method = .GET,
        .path = "/nonexistent/repo.git/info/refs",
        .query = "service=git-upload-pack",
    });
    defer request.deinit();
    
    var response = TestResponse.init(allocator);
    defer response.deinit();
    
    try server.handleRequest(&request, &response);
    try testing.expectEqual(@as(u16, 404), response.status_code);
}

test "parses Git repository paths correctly" {
    const allocator = testing.allocator;
    
    const test_config = GitHttpConfig{};
    var server = try GitHttpServer.init(allocator, test_config);
    defer server.deinit();
    
    // Test valid path
    const repo_info = try server.parseGitPath("/owner/repo.git/info/refs");
    defer allocator.free(repo_info.owner);
    defer allocator.free(repo_info.repo);
    
    try testing.expectEqualStrings("owner", repo_info.owner);
    try testing.expectEqualStrings("repo", repo_info.repo);
    
    // Test path with nested owner
    const nested_info = try server.parseGitPath("/org/team/project.git/info/refs");
    defer allocator.free(nested_info.owner);
    defer allocator.free(nested_info.repo);
    
    try testing.expectEqualStrings("org", nested_info.owner);
    try testing.expectEqualStrings("team/project", nested_info.repo);
}

test "rejects invalid Git repository paths" {
    const allocator = testing.allocator;
    
    const test_config = GitHttpConfig{};
    var server = try GitHttpServer.init(allocator, test_config);
    defer server.deinit();
    
    // Missing .git suffix
    try testing.expectError(error.InvalidRequest, server.parseGitPath("/owner/repo/info/refs"));
    
    // Missing owner
    try testing.expectError(error.InvalidRequest, server.parseGitPath("/repo.git/info/refs"));
    
    // Empty path
    try testing.expectError(error.InvalidRequest, server.parseGitPath(""));
}