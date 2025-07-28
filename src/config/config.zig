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

const IniParser = struct {
    allocator: std.mem.Allocator,
    sections: std.StringHashMap(Section),
    
    const Section = std.StringHashMap([]const u8);
    
    pub fn init(allocator: std.mem.Allocator) !IniParser {
        return .{
            .allocator = allocator,
            .sections = std.StringHashMap(Section).init(allocator),
        };
    }
    
    pub fn deinit(self: *IniParser) void {
        var section_iter = self.sections.iterator();
        while (section_iter.next()) |entry| {
            var section = entry.value_ptr.*;
            
            var value_iter = section.iterator();
            while (value_iter.next()) |value_entry| {
                self.allocator.free(value_entry.key_ptr.*);
                self.allocator.free(value_entry.value_ptr.*);
            }
            
            section.deinit();
            self.allocator.free(entry.key_ptr.*);
        }
        self.sections.deinit();
    }
    
    pub fn parse(self: *IniParser, content: []const u8) !void {
        var lines = std.mem.tokenize(u8, content, "\n\r");
        var current_section: ?[]const u8 = null;
        
        while (lines.next()) |line| {
            // Trim whitespace
            const trimmed = std.mem.trim(u8, line, " \t");
            
            // Skip empty lines and comments
            if (trimmed.len == 0 or trimmed[0] == '#' or trimmed[0] == ';') {
                continue;
            }
            
            // Check for section header
            if (trimmed[0] == '[' and trimmed[trimmed.len - 1] == ']') {
                const section_name = trimmed[1 .. trimmed.len - 1];
                
                // Validate section name
                if (std.mem.indexOf(u8, section_name, " ") != null) {
                    return ConfigError.ParseError;
                }
                
                const section_key = try self.allocator.dupe(u8, section_name);
                try self.sections.put(section_key, Section.init(self.allocator));
                current_section = section_key;
                continue;
            }
            
            // Parse key-value pair
            if (current_section == null) {
                return ConfigError.ParseError;
            }
            
            const eq_pos = std.mem.indexOf(u8, trimmed, "=") orelse return ConfigError.ParseError;
            
            const key = std.mem.trim(u8, trimmed[0..eq_pos], " \t");
            var value = std.mem.trim(u8, trimmed[eq_pos + 1 ..], " \t");
            
            // Remove inline comments
            if (std.mem.indexOf(u8, value, "#")) |comment_pos| {
                value = std.mem.trim(u8, value[0..comment_pos], " \t");
            }
            if (std.mem.indexOf(u8, value, ";")) |comment_pos| {
                value = std.mem.trim(u8, value[0..comment_pos], " \t");
            }
            
            // Store key-value pair
            var section = self.sections.getPtr(current_section.?).?;
            const key_copy = try self.allocator.dupe(u8, key);
            const value_copy = try self.allocator.dupe(u8, value);
            try section.put(key_copy, value_copy);
        }
    }
    
    pub fn getValue(self: *IniParser, section: []const u8, key: []const u8) ![]const u8 {
        const section_map = self.sections.get(section) orelse return ConfigError.InvalidSection;
        return section_map.get(key) orelse return ConfigError.InvalidKey;
    }
};

pub const Config = struct {
    allocator: std.mem.Allocator,
    server: ServerConfig,
    database: DatabaseConfig,
    repository: RepositoryConfig,
    security: SecurityConfig,
    
    // Store allocated strings for cleanup
    allocated_strings: std.ArrayList([]u8),
    
    pub fn init(allocator: std.mem.Allocator) !Config {
        return .{
            .allocator = allocator,
            .server = .{},
            .database = .{},
            .repository = .{},
            .security = .{},
            .allocated_strings = std.ArrayList([]u8).init(allocator),
        };
    }
    
    pub fn deinit(self: *Config) void {
        for (self.allocated_strings.items) |str| {
            self.allocator.free(str);
        }
        self.allocated_strings.deinit();
    }
    
    pub fn loadEnvironmentOverrides(self: *Config) !void {
        // Server overrides
        if (try self.getEnvValue("server", "host")) |value| {
            self.server.host = value;
        }
        if (try self.getEnvValue("server", "port")) |value| {
            const port = std.fmt.parseInt(u16, value, 10) catch return ConfigError.InvalidPort;
            if (port == 0) return ConfigError.InvalidPort;
            self.server.port = port;
        }
        if (try self.getEnvValue("server", "worker_threads")) |value| {
            const threads = std.fmt.parseInt(u32, value, 10) catch return ConfigError.InvalidValue;
            if (threads == 0 or threads > 1024) return ConfigError.InvalidValue;
            self.server.worker_threads = threads;
        }
        
        // Database overrides
        if (try self.getEnvValue("database", "connection_url")) |value| {
            // Validate connection URL
            if (!std.mem.startsWith(u8, value, "postgresql://") and
                !std.mem.startsWith(u8, value, "postgres://")) {
                return ConfigError.InvalidUrl;
            }
            self.database.connection_url = value;
        }
        if (try self.getEnvValue("database", "max_connections")) |value| {
            const connections = std.fmt.parseInt(u32, value, 10) catch return ConfigError.InvalidValue;
            if (connections == 0 or connections > 1000) return ConfigError.InvalidValue;
            self.database.max_connections = connections;
        }
        
        // Repository overrides
        if (try self.getEnvValue("repository", "base_path")) |value| {
            // Validate path exists and is directory
            const stat = std.fs.cwd().statFile(value) catch return ConfigError.InvalidPath;
            if (stat.kind != .directory) return ConfigError.InvalidPath;
            self.repository.base_path = value;
        }
        
        // Security overrides
        if (try self.getEnvValue("security", "secret_key")) |value| {
            if (value.len < 32) return ConfigError.WeakSecretKey;
            self.security.secret_key = value;
        }
        if (try self.getEnvValue("security", "enable_registration")) |value| {
            self.security.enable_registration = std.mem.eql(u8, value, "true") or std.mem.eql(u8, value, "1");
        }
    }
    
    fn getEnvValue(self: *Config, section: []const u8, key: []const u8) !?[]const u8 {
        const env_name = try buildEnvVarName(self.allocator, section, key);
        defer self.allocator.free(env_name);
        
        // Regular environment variable
        const value = try std.process.getEnvVarOwned(self.allocator, env_name) catch |err| switch (err) {
            error.EnvironmentVariableNotFound => return null,
            else => return err,
        };
        
        // Already owned from getEnvVarOwned, just track it
        try self.allocated_strings.append(value);
        
        return value;
    }
    
    pub fn validate(self: *const Config) !void {
        try self.validateServer();
        try self.validateDatabase();
        try self.validateRepository();
        try self.validateSecurity();
    }
    
    fn validateServer(self: *const Config) !void {
        if (self.server.port == 0) {
            return ConfigError.InvalidPort;
        }
        
        if (self.server.host.len == 0) {
            return ConfigError.InvalidValue;
        }
        
        if (self.server.worker_threads == 0 or self.server.worker_threads > 1024) {
            return ConfigError.InvalidValue;
        }
        
        if (self.server.request_timeout_ms < 1000) { // Minimum 1 second
            return ConfigError.InvalidValue;
        }
    }
    
    fn validateDatabase(self: *const Config) !void {
        if (self.database.connection_url.len == 0) {
            return ConfigError.MissingRequired;
        }
        
        // Validate PostgreSQL URL format
        if (!std.mem.startsWith(u8, self.database.connection_url, "postgresql://") and
            !std.mem.startsWith(u8, self.database.connection_url, "postgres://")) {
            return ConfigError.InvalidUrl;
        }
        
        if (self.database.max_connections == 0 or self.database.max_connections > 1000) {
            return ConfigError.InvalidValue;
        }
        
        if (self.database.connection_timeout_seconds == 0) {
            return ConfigError.InvalidValue;
        }
    }
    
    fn validateRepository(self: *const Config) !void {
        if (self.repository.base_path.len == 0) {
            return ConfigError.InvalidPath;
        }
        
        // Enforce absolute paths
        if (!std.fs.path.isAbsolute(self.repository.base_path)) {
            std.log.err("Repository base_path must be an absolute path, got: {s}", .{self.repository.base_path});
            return ConfigError.PathNotAbsolute;
        }
        
        // Check if base path exists and is directory
        const stat = std.fs.cwd().statFile(self.repository.base_path) catch |err| switch (err) {
            error.FileNotFound => return ConfigError.InvalidPath,
            else => return ConfigError.InvalidPath,
        };
        
        if (stat.kind != .directory) {
            return ConfigError.InvalidPath;
        }
        
        if (self.repository.max_repo_size == 0) {
            return ConfigError.InvalidValue;
        }
        
        if (self.repository.default_branch.len == 0) {
            return ConfigError.InvalidValue;
        }
    }
    
    fn validateSecurity(self: *const Config) !void {
        // Check for default/weak secret key
        if (std.mem.eql(u8, self.security.secret_key, "CHANGE-ME-GENERATE-RANDOM-KEY-IN-PRODUCTION")) {
            std.log.err("CRITICAL: Using default secret key! Generate a secure random key for production.", .{});
            return ConfigError.WeakSecretKey;
        }
        
        if (self.security.secret_key.len < 32) {
            std.log.err("Secret key too short. Minimum 32 characters required.", .{});
            return ConfigError.WeakSecretKey;
        }
        
        if (self.security.min_password_length < 8) {
            return ConfigError.InvalidValue;
        }
        
        if (self.security.bcrypt_cost < 10 or self.security.bcrypt_cost > 31) {
            return ConfigError.InvalidValue;
        }
        
        if (self.security.token_expiration_hours == 0 or self.security.token_expiration_hours > 24 * 365) {
            return ConfigError.InvalidValue;
        }
    }
};

fn buildEnvVarName(allocator: std.mem.Allocator, section: []const u8, key: []const u8) ![]u8 {
    // Convert to PLUE_SECTION_KEY format
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();
    
    try result.appendSlice("PLUE_");
    
    // Uppercase section
    for (section) |c| {
        try result.append(std.ascii.toUpper(c));
    }
    
    try result.append('_');
    
    // Uppercase key, converting camelCase to SNAKE_CASE
    for (key, 0..) |c, i| {
        if (i > 0 and std.ascii.isUpper(c)) {
            try result.append('_');
        }
        try result.append(std.ascii.toUpper(c));
    }
    
    return result.toOwnedSlice();
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

test "parses basic INI format" {
    const allocator = std.testing.allocator;
    
    const ini_content =
        \\[server]
        \\host = 0.0.0.0
        \\port = 9000
        \\
        \\[database]
        \\connection_url = postgresql://localhost/test
        \\max_connections = 50
    ;
    
    var parser = try IniParser.init(allocator);
    defer parser.deinit();
    
    try parser.parse(ini_content);
    
    const server_host = try parser.getValue("server", "host");
    try std.testing.expectEqualStrings("0.0.0.0", server_host);
    
    const server_port = try parser.getValue("server", "port");
    try std.testing.expectEqualStrings("9000", server_port);
    
    const db_url = try parser.getValue("database", "connection_url");
    try std.testing.expectEqualStrings("postgresql://localhost/test", db_url);
}

test "handles comments and empty lines" {
    const allocator = std.testing.allocator;
    
    const ini_content =
        \\# This is a comment
        \\[server]
        \\host = localhost  # inline comment
        \\
        \\# Another comment
        \\port = 8080
        \\
        \\; Semicolon comment
        \\[database]
        \\; connection_url = postgresql://prod  ; commented out
        \\connection_url = postgresql://dev
    ;
    
    var parser = try IniParser.init(allocator);
    defer parser.deinit();
    
    try parser.parse(ini_content);
    
    const host = try parser.getValue("server", "host");
    try std.testing.expectEqualStrings("localhost", host);
    
    const url = try parser.getValue("database", "connection_url");
    try std.testing.expectEqualStrings("postgresql://dev", url);
}

test "handles malformed INI gracefully" {
    const allocator = std.testing.allocator;
    
    var parser = try IniParser.init(allocator);
    defer parser.deinit();
    
    // Missing section header
    try std.testing.expectError(ConfigError.ParseError, parser.parse("key = value"));
    
    // Invalid section format
    try std.testing.expectError(ConfigError.ParseError, parser.parse("[invalid section with spaces]"));
    
    // No equals sign
    try std.testing.expectError(ConfigError.ParseError, parser.parse("[section]\nkey value"));
}

test "environment variables override config file values" {
    const allocator = std.testing.allocator;
    
    // Set test environment variables
    try std.testing.expectEqual(true, try std.process.hasEnvVar(allocator, "PATH"));
    try std.posix.setenv("PLUE_SERVER_PORT", "9999", 1);
    try std.posix.setenv("PLUE_DATABASE_MAX_CONNECTIONS", "100", 1);
    defer {
        std.posix.unsetenv("PLUE_SERVER_PORT") catch {};
        std.posix.unsetenv("PLUE_DATABASE_MAX_CONNECTIONS") catch {};
    }
    
    var config = try Config.init(allocator);
    defer config.deinit();
    
    // Load base configuration
    config.server.port = 8000;
    config.database.max_connections = 25;
    
    // Apply environment overrides
    try config.loadEnvironmentOverrides();
    
    try std.testing.expectEqual(@as(u16, 9999), config.server.port);
    try std.testing.expectEqual(@as(u32, 100), config.database.max_connections);
}

test "environment variable name format" {
    // Test the conversion function
    const allocator = std.testing.allocator;
    
    const env_name = try buildEnvVarName(allocator, "server", "worker_threads");
    defer allocator.free(env_name);
    try std.testing.expectEqualStrings("PLUE_SERVER_WORKER_THREADS", env_name);
    
    const env_name2 = try buildEnvVarName(allocator, "database", "connection_url");
    defer allocator.free(env_name2);
    try std.testing.expectEqualStrings("PLUE_DATABASE_CONNECTION_URL", env_name2);
}

test "validates server configuration" {
    const allocator = std.testing.allocator;
    
    var config = try Config.init(allocator);
    defer config.deinit();
    
    // Valid configuration
    config.server.port = 8080;
    config.server.host = "0.0.0.0";
    try config.validateServer();
    
    // Invalid port (0)
    config.server.port = 0;
    try std.testing.expectError(ConfigError.InvalidPort, config.validateServer());
    
    // Invalid host
    config.server.host = "";
    config.server.port = 8080;
    try std.testing.expectError(ConfigError.InvalidValue, config.validateServer());
}

test "validates database configuration" {
    const allocator = std.testing.allocator;
    
    var config = try Config.init(allocator);
    defer config.deinit();
    
    // Missing connection URL
    try std.testing.expectError(ConfigError.MissingRequired, config.validateDatabase());
    
    // Invalid URL format
    config.database.connection_url = "mysql://localhost/db";
    try std.testing.expectError(ConfigError.InvalidUrl, config.validateDatabase());
    
    // Valid PostgreSQL URL
    config.database.connection_url = "postgresql://user:pass@localhost:5432/plue";
    try config.validateDatabase();
}

test "validates security configuration" {
    const allocator = std.testing.allocator;
    
    var config = try Config.init(allocator);
    defer config.deinit();
    
    // Default secret key should trigger error
    try std.testing.expectError(ConfigError.WeakSecretKey, config.validateSecurity());
    
    // Weak secret key
    config.security.secret_key = "too-short";
    try std.testing.expectError(ConfigError.WeakSecretKey, config.validateSecurity());
    
    // Valid secret key
    config.security.secret_key = "this-is-a-sufficiently-long-secret-key-for-production-use";
    try config.validateSecurity();
    
    // Invalid bcrypt cost
    config.security.bcrypt_cost = 3;
    try std.testing.expectError(ConfigError.InvalidValue, config.validateSecurity());
}