const std = @import("std");
const builtin = @import("builtin");

pub const ConfigError = error{
    FileNotFound,
    PermissionDenied,
    ParseError,
    InvalidSection,
    InvalidKey,
    InvalidValue,
    InvalidPort,
    InvalidUrl,
    InvalidPath,
    MissingRequired,
    ValidationFailed,
    FilePermissionTooOpen,
    WeakSecretKey,
    EnvironmentError,
    ConflictingConfiguration,
    FileSizeTooLarge,
    PathNotAbsolute,
    EmptySecretFile,
};

pub const ConfigSeverity = enum {
    warning, // Log and continue with defaults
    error, // Return error, allow caller to decide
    fatal, // Immediately terminate application
};

pub const InstallationState = enum {
    not_installed,
    installing,
    installed,
};

pub const ServerConfig = struct {
    host: []const u8 = "127.0.0.1",
    port: u16 = 8000,
    worker_threads: u32 = 4,
    request_timeout_ms: u32 = 30000,
    max_request_size: usize = 10 * 1024 * 1024, // 10MB
};

pub const DatabaseConfig = struct {
    connection_url: []const u8 = "",
    max_connections: u32 = 25,
    connection_timeout_seconds: u32 = 30,
    idle_timeout_seconds: u32 = 600,
    statement_cache_size: u32 = 100,
};

pub const RepositoryConfig = struct {
    base_path: []const u8 = "/var/plue/repos",
    max_repo_size: u64 = 1024 * 1024 * 1024, // 1GB
    allow_force_push: bool = false,
    enable_lfs: bool = false,
    default_branch: []const u8 = "main",
};

pub const SecurityConfig = struct {
    secret_key: []const u8 = "CHANGE-ME-GENERATE-RANDOM-KEY-IN-PRODUCTION",
    token_expiration_hours: u32 = 24,
    enable_registration: bool = true,
    require_email_verification: bool = false,
    min_password_length: u32 = 8,
    bcrypt_cost: u32 = 10,
    allowed_hosts: []const []const u8 = &.{},
};

fn validateConfigFilePermissions(path: []const u8) ConfigError!void {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return ConfigError.FileNotFound,
        error.AccessDenied => return ConfigError.PermissionDenied,
        else => return ConfigError.PermissionDenied,
    };
    defer file.close();
    
    const stat = file.stat() catch return ConfigError.PermissionDenied;
    
    // Check if file is readable by others (security risk)
    if (builtin.os.tag != .windows) {
        const mode = stat.mode;
        const others_read = mode & 0o004;
        const others_write = mode & 0o002;
        const group_write = mode & 0o020;
        
        if (others_read != 0 or others_write != 0 or group_write != 0) {
            std.log.warn("Config file {s} has too open permissions: {o}", .{ path, mode });
            std.log.warn("Recommended permissions: 0600 (owner read/write only)", .{});
            return ConfigError.FilePermissionTooOpen;
        }
    }
}

test "ConfigError provides detailed error information" {
    const err = ConfigError.InvalidPort;
    try std.testing.expectEqual(ConfigError.InvalidPort, err);
    
    const err2 = ConfigError.PermissionDenied;
    try std.testing.expectEqual(ConfigError.PermissionDenied, err2);
}

test "configuration sections have sensible defaults" {
    const server = ServerConfig{};
    try std.testing.expectEqualStrings("127.0.0.1", server.host);
    try std.testing.expectEqual(@as(u16, 8000), server.port);
    try std.testing.expectEqual(@as(u32, 4), server.worker_threads);
    
    const security = SecurityConfig{};
    try std.testing.expect(security.secret_key.len >= 32);
    try std.testing.expectEqual(@as(u32, 24), security.token_expiration_hours);
}

test "validates file permissions for security" {
    const allocator = std.testing.allocator;
    
    // Create test directory
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    // Create test config file with different permissions
    const test_file = "test_config.ini";
    const file = try tmp_dir.dir.createFile(test_file, .{ .mode = 0o644 });
    file.close();
    
    // Get full path
    const full_path = try tmp_dir.dir.realpathAlloc(allocator, test_file);
    defer allocator.free(full_path);
    
    // Should fail with too-open permissions
    const result = validateConfigFilePermissions(full_path);
    try std.testing.expectError(ConfigError.FilePermissionTooOpen, result);
    
    // Fix permissions and retry
    try tmp_dir.dir.chmod(test_file, 0o600);
    try validateConfigFilePermissions(full_path);
}

test "handles missing config files gracefully" {
    const result = validateConfigFilePermissions("nonexistent.ini");
    try std.testing.expectError(ConfigError.FileNotFound, result);
}