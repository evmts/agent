const std = @import("std");

pub const ServerConfig = struct {
    /// Path to OpenCode directory
    opencode_path: []const u8,

    /// Port to run the server on (0 = auto-assign)
    port: u16 = 0,

    /// Host to bind to
    host: []const u8 = "127.0.0.1",

    /// Environment variables to pass to OpenCode
    env: ?std.process.EnvMap = null,

    /// Maximum startup time in milliseconds
    startup_timeout_ms: u32 = 30000,

    /// Event stream reconnect interval in milliseconds
    event_stream_reconnect_ms: u32 = 1000,

    /// Maximum consecutive connection failures before restart
    max_connection_failures: u32 = 3,

    /// Force kill timeout after graceful shutdown
    force_kill_timeout_ms: u32 = 5000,

    /// Log file path (optional)
    log_file_path: ?[]const u8 = null,

    const Self = @This();

    pub fn initDefault(allocator: std.mem.Allocator, opencode_path: []const u8) !ServerConfig {
        // Create default environment map
        var env_map = std.process.EnvMap.init(allocator);
        errdefer env_map.deinit();

        // Copy current environment
        var env_it = try std.process.getEnvMap(allocator);
        defer env_it.deinit();

        var it = env_it.iterator();
        while (it.next()) |entry| {
            try env_map.put(entry.key_ptr.*, entry.value_ptr.*);
        }

        return ServerConfig{
            .opencode_path = opencode_path,
            .env = env_map,
        };
    }

    pub fn validate(self: *const Self) !void {
        // Check if OpenCode path exists
        var opencode_dir = std.fs.openDirAbsolute(self.opencode_path, .{}) catch |err| {
            std.log.err("OpenCode path does not exist or is not accessible: {s}", .{self.opencode_path});
            return err;
        };
        opencode_dir.close();

        // Validate port range
        if (self.port > 0 and self.port < 1024) {
            std.log.warn("Using privileged port {d}, may require elevated permissions", .{self.port});
        }

        // Validate timeouts
        if (self.startup_timeout_ms < 1000) {
            std.log.warn("Startup timeout is very low: {d}ms", .{self.startup_timeout_ms});
        }

        if (self.force_kill_timeout_ms < 100) {
            return error.InvalidConfiguration;
        }

        // Validate host
        if (self.host.len == 0) {
            return error.InvalidConfiguration;
        }

        // Check if log file path is writable if specified
        if (self.log_file_path) |log_path| {
            // Try to get parent directory
            const dir_path = std.fs.path.dirname(log_path) orelse ".";
            var log_dir = std.fs.openDirAbsolute(dir_path, .{}) catch |err| {
                std.log.err("Log file directory is not accessible: {s}", .{dir_path});
                return err;
            };
            log_dir.close();
        }
    }

    pub fn deinit(self: *Self) void {
        if (self.env) |*env| {
            env.deinit();
        }
    }

    /// Update OPENCODE_SERVER environment variable with the actual server URL
    pub fn updateServerUrl(self: *Self, server_url: []const u8) !void {
        if (self.env) |*env| {
            try env.put("OPENCODE_SERVER", server_url);
        }
    }

    /// Get environment variables as a pointer for process spawning
    pub fn getEnvMapPtr(self: *Self) ?*std.process.EnvMap {
        return if (self.env) |*env| env else null;
    }
};

test "ServerConfig initDefault" {
    const allocator = std.testing.allocator;

    var config = try ServerConfig.initDefault(allocator, "/tmp/opencode");
    defer config.deinit();

    try std.testing.expectEqualStrings("/tmp/opencode", config.opencode_path);
    try std.testing.expect(config.port == 0);
    try std.testing.expectEqualStrings("127.0.0.1", config.host);
    try std.testing.expect(config.startup_timeout_ms == 30000);
    try std.testing.expect(config.env != null);
}

test "ServerConfig validate - valid config" {
    const allocator = std.testing.allocator;

    // Create a temporary directory for testing
    const tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var config = ServerConfig{
        .opencode_path = tmp_path,
        .port = 3000,
        .host = "localhost",
    };

    try config.validate();
}

test "ServerConfig validate - invalid path" {
    var config = ServerConfig{
        .opencode_path = "/nonexistent/path/to/opencode",
        .port = 3000,
        .host = "localhost",
    };

    const result = config.validate();
    try std.testing.expectError(error.FileNotFound, result);
}

test "ServerConfig validate - invalid timeout" {
    const allocator = std.testing.allocator;

    const tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var config = ServerConfig{
        .opencode_path = tmp_path,
        .force_kill_timeout_ms = 50, // Too low
        .host = "localhost",
    };

    const result = config.validate();
    try std.testing.expectError(error.InvalidConfiguration, result);
}

test "ServerConfig updateServerUrl" {
    const allocator = std.testing.allocator;

    var config = try ServerConfig.initDefault(allocator, "/tmp/opencode");
    defer config.deinit();

    try config.updateServerUrl("http://localhost:52341");

    if (config.env) |env| {
        const server_url = env.get("OPENCODE_SERVER");
        try std.testing.expect(server_url != null);
        try std.testing.expectEqualStrings("http://localhost:52341", server_url.?);
    } else {
        try std.testing.expect(false); // Should have env map
    }
}