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
        
        // Check for __FILE suffix first
        const file_env_name = try std.fmt.allocPrint(self.allocator, "{s}__FILE", .{env_name});
        defer self.allocator.free(file_env_name);
        
        const file_value = try std.process.getEnvVarOwned(self.allocator, file_env_name) catch |err| switch (err) {
            error.EnvironmentVariableNotFound => null,
            else => return err,
        };
        defer if (file_value) |v| self.allocator.free(v);
        
        if (file_value) |file_path| {
            // Load from file
            const content = try self.loadSecretFromFile(file_path);
            return content;
        }
        
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
    
    fn loadSecretFromFile(self: *Config, path: []const u8) ![]const u8 {
        // Validate file permissions first
        try validateConfigFilePermissions(path);
        
        // Read file content with size limit
        const MAX_SECRET_FILE_SIZE = 64 * 1024; // 64KB max for secrets
        const content = std.fs.cwd().readFileAlloc(self.allocator, path, MAX_SECRET_FILE_SIZE) catch |err| switch (err) {
            error.FileNotFound => return ConfigError.FileNotFound,
            error.AccessDenied => return ConfigError.PermissionDenied,
            error.FileTooBig => return ConfigError.FileSizeTooLarge,
            else => return err,
        };
        errdefer self.allocator.free(content);
        
        // Trim whitespace and newlines
        const trimmed = std.mem.trim(u8, content, " \t\n\r");
        
        // Empty file is an error for secrets
        if (trimmed.len == 0) {
            self.allocator.free(content);
            return ConfigError.EmptySecretFile;
        }
        
        // Store the secret
        const secret_copy = try self.allocator.dupe(u8, trimmed);
        try self.allocated_strings.append(secret_copy);
        self.allocator.free(content);
        
        return secret_copy;
    }
    
    // Main loading function
    pub fn load(allocator: std.mem.Allocator, config_path: []const u8) !Config {
        var config = try Config.init(allocator);
        errdefer config.deinit();
        
        // Step 1: Load from file
        try config.loadFromFileInternal(config_path);
        
        // Step 2: Apply environment overrides
        try config.loadEnvironmentOverrides();
        
        // Step 3: Validate final configuration
        try config.validate();
        
        return config;
    }
    
    pub fn loadFromFile(allocator: std.mem.Allocator, path: []const u8) !Config {
        var config = try Config.init(allocator);
        errdefer config.deinit();
        
        try config.loadFromFileInternal(path);
        
        return config;
    }
    
    fn loadFromFileInternal(self: *Config, path: []const u8) !void {
        // Validate file permissions
        try validateConfigFilePermissions(path);
        
        // Read file content
        const content = try std.fs.cwd().readFileAlloc(self.allocator, path, 1024 * 1024); // 1MB max
        defer self.allocator.free(content);
        
        // Parse INI
        var parser = try IniParser.init(self.allocator);
        defer parser.deinit();
        
        try parser.parse(content);
        
        // Load server section
        if (parser.getValue("server", "host")) |value| {
            const host_copy = try self.allocator.dupe(u8, value);
            try self.allocated_strings.append(host_copy);
            self.server.host = host_copy;
        } else |_| {}
        
        if (parser.getValue("server", "port")) |value| {
            self.server.port = try std.fmt.parseInt(u16, value, 10);
        } else |_| {}
        
        if (parser.getValue("server", "worker_threads")) |value| {
            self.server.worker_threads = try std.fmt.parseInt(u32, value, 10);
        } else |_| {}
        
        if (parser.getValue("server", "request_timeout_ms")) |value| {
            self.server.request_timeout_ms = try std.fmt.parseInt(u32, value, 10);
        } else |_| {}
        
        if (parser.getValue("server", "max_request_size")) |value| {
            self.server.max_request_size = try std.fmt.parseInt(usize, value, 10);
        } else |_| {}
        
        // Load database section
        if (parser.getValue("database", "connection_url")) |value| {
            const url_copy = try self.allocator.dupe(u8, value);
            try self.allocated_strings.append(url_copy);
            self.database.connection_url = url_copy;
        } else |_| {}
        
        if (parser.getValue("database", "max_connections")) |value| {
            self.database.max_connections = try std.fmt.parseInt(u32, value, 10);
        } else |_| {}
        
        if (parser.getValue("database", "connection_timeout_seconds")) |value| {
            self.database.connection_timeout_seconds = try std.fmt.parseInt(u32, value, 10);
        } else |_| {}
        
        // Load repository section
        if (parser.getValue("repository", "base_path")) |value| {
            const path_copy = try self.allocator.dupe(u8, value);
            try self.allocated_strings.append(path_copy);
            self.repository.base_path = path_copy;
        } else |_| {}
        
        if (parser.getValue("repository", "max_repo_size")) |value| {
            self.repository.max_repo_size = try std.fmt.parseInt(u64, value, 10);
        } else |_| {}
        
        if (parser.getValue("repository", "allow_force_push")) |value| {
            self.repository.allow_force_push = std.mem.eql(u8, value, "true") or std.mem.eql(u8, value, "1");
        } else |_| {}
        
        if (parser.getValue("repository", "enable_lfs")) |value| {
            self.repository.enable_lfs = std.mem.eql(u8, value, "true") or std.mem.eql(u8, value, "1");
        } else |_| {}
        
        if (parser.getValue("repository", "default_branch")) |value| {
            const branch_copy = try self.allocator.dupe(u8, value);
            try self.allocated_strings.append(branch_copy);
            self.repository.default_branch = branch_copy;
        } else |_| {}
        
        // Load security section
        if (parser.getValue("security", "secret_key")) |value| {
            const key_copy = try self.allocator.dupe(u8, value);
            try self.allocated_strings.append(key_copy);
            self.security.secret_key = key_copy;
        } else |_| {}
        
        if (parser.getValue("security", "token_expiration_hours")) |value| {
            self.security.token_expiration_hours = try std.fmt.parseInt(u32, value, 10);
        } else |_| {}
        
        if (parser.getValue("security", "enable_registration")) |value| {
            self.security.enable_registration = std.mem.eql(u8, value, "true") or std.mem.eql(u8, value, "1");
        } else |_| {}
        
        if (parser.getValue("security", "require_email_verification")) |value| {
            self.security.require_email_verification = std.mem.eql(u8, value, "true") or std.mem.eql(u8, value, "1");
        } else |_| {}
        
        if (parser.getValue("security", "min_password_length")) |value| {
            self.security.min_password_length = try std.fmt.parseInt(u32, value, 10);
        } else |_| {}
        
        if (parser.getValue("security", "bcrypt_cost")) |value| {
            self.security.bcrypt_cost = try std.fmt.parseInt(u32, value, 10);
        } else |_| {}
    }
    
    pub fn sanitizeForLogging(self: *const Config, allocator: std.mem.Allocator) !Config {
        var sanitized = try Config.init(allocator);
        errdefer sanitized.deinit();
        
        // Copy non-sensitive values
        sanitized.server = self.server;
        sanitized.repository = self.repository;
        sanitized.database = self.database;
        sanitized.security = self.security;
        
        // Sanitize sensitive values
        const redacted = try allocator.dupe(u8, "[REDACTED]");
        try sanitized.allocated_strings.append(redacted);
        sanitized.security.secret_key = redacted;
        
        // Sanitize database URL
        if (std.mem.indexOf(u8, self.database.connection_url, "://")) |scheme_end| {
            if (std.mem.indexOf(u8, self.database.connection_url[scheme_end..], "@")) |at_pos| {
                // Extract parts
                const scheme = self.database.connection_url[0..scheme_end + 3];
                const after_at = self.database.connection_url[scheme_end + at_pos + 1..];
                
                const sanitized_url = try std.fmt.allocPrint(
                    allocator, 
                    "{s}[REDACTED]@{s}", 
                    .{scheme, after_at}
                );
                try sanitized.allocated_strings.append(sanitized_url);
                sanitized.database.connection_url = sanitized_url;
            } else {
                const url_copy = try allocator.dupe(u8, self.database.connection_url);
                try sanitized.allocated_strings.append(url_copy);
                sanitized.database.connection_url = url_copy;
            }
        } else {
            // No scheme found, just copy as-is
            const url_copy = try allocator.dupe(u8, self.database.connection_url);
            try sanitized.allocated_strings.append(url_copy);
            sanitized.database.connection_url = url_copy;
        }
        
        return sanitized;
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

pub fn generateDefaultConfig(allocator: std.mem.Allocator) ![]u8 {
    var buffer = std.ArrayList(u8).init(allocator);
    errdefer buffer.deinit();
    
    const writer = buffer.writer();
    
    try writer.print(
        \\# Plue Configuration File
        \\# 
        \\# This file should be readable only by the owner (chmod 600)
        \\# Environment variables can override these values using PLUE_SECTION_KEY format
        \\#
        \\# For file-based secrets, use: file:///path/to/secret
        \\
        \\[server]
        \\# Interface to bind to (0.0.0.0 for all interfaces)
        \\host = {s}
        \\# Port to listen on
        \\port = {d}
        \\# Number of worker threads
        \\worker_threads = {d}
        \\# Request timeout in milliseconds
        \\request_timeout_ms = {d}
        \\# Maximum request size in bytes
        \\max_request_size = {d}
        \\
        \\[database]
        \\# PostgreSQL connection URL
        \\# Example: postgresql://username:password@localhost:5432/database
        \\connection_url = {s}
        \\# Maximum number of database connections
        \\max_connections = {d}
        \\# Connection timeout in seconds
        \\connection_timeout_seconds = {d}
        \\# Idle connection timeout in seconds
        \\idle_timeout_seconds = {d}
        \\# Statement cache size
        \\statement_cache_size = {d}
        \\
        \\[repository]
        \\# Base path for git repositories
        \\base_path = {s}
        \\# Maximum repository size in bytes (default: 1GB)
        \\max_repo_size = {d}
        \\# Allow force push operations
        \\allow_force_push = {s}
        \\# Enable Git LFS support
        \\enable_lfs = {s}
        \\# Default branch name for new repositories
        \\default_branch = {s}
        \\
        \\[security]
        \\# Secret key for session encryption (CHANGE THIS!)
        \\# Generate with: openssl rand -hex 32
        \\secret_key = {s}
        \\# Token expiration time in hours
        \\token_expiration_hours = {d}
        \\# Allow new user registration
        \\enable_registration = {s}
        \\# Require email verification for new users
        \\require_email_verification = {s}
        \\# Minimum password length
        \\min_password_length = {d}
        \\# Bcrypt cost factor (10-31, higher is more secure but slower)
        \\bcrypt_cost = {d}
        \\
    , .{
        ServerConfig{}.host,
        ServerConfig{}.port,
        ServerConfig{}.worker_threads,
        ServerConfig{}.request_timeout_ms,
        ServerConfig{}.max_request_size,
        DatabaseConfig{}.connection_url,
        DatabaseConfig{}.max_connections,
        DatabaseConfig{}.connection_timeout_seconds,
        DatabaseConfig{}.idle_timeout_seconds,
        DatabaseConfig{}.statement_cache_size,
        RepositoryConfig{}.base_path,
        RepositoryConfig{}.max_repo_size,
        if (RepositoryConfig{}.allow_force_push) "true" else "false",
        if (RepositoryConfig{}.enable_lfs) "true" else "false",
        RepositoryConfig{}.default_branch,
        SecurityConfig{}.secret_key,
        SecurityConfig{}.token_expiration_hours,
        if (SecurityConfig{}.enable_registration) "true" else "false",
        if (SecurityConfig{}.require_email_verification) "true" else "false",
        SecurityConfig{}.min_password_length,
        SecurityConfig{}.bcrypt_cost,
    });
    
    return buffer.toOwnedSlice();
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

test "loads environment values from files with __FILE suffix" {
    const allocator = std.testing.allocator;
    
    // Create test directory
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    // Create secret file
    const secret_file = "env_secret.txt";
    const file = try tmp_dir.dir.createFile(secret_file, .{ .mode = 0o600 });
    try file.writeAll("secret-from-env-file");
    file.close();
    
    // Get full path
    const full_path = try tmp_dir.dir.realpathAlloc(allocator, secret_file);
    defer allocator.free(full_path);
    
    // Set environment variable with __FILE suffix
    try std.posix.setenv("PLUE_SECURITY_SECRET_KEY__FILE", full_path, 1);
    defer std.posix.unsetenv("PLUE_SECURITY_SECRET_KEY__FILE") catch {};
    
    var config = try Config.init(allocator);
    defer config.deinit();
    
    try config.loadEnvironmentOverrides();
    
    try std.testing.expectEqualStrings("secret-from-env-file", config.security.secret_key);
}

test "validates secret file permissions" {
    const allocator = std.testing.allocator;
    
    // Create test directory
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    // Create test secret file with bad permissions
    const secret_file = "bad_secret.txt";
    const file = try tmp_dir.dir.createFile(secret_file, .{ .mode = 0o644 });
    try file.writeAll("secret");
    file.close();
    
    // Get full path
    const full_path = try tmp_dir.dir.realpathAlloc(allocator, secret_file);
    defer allocator.free(full_path);
    
    var config = try Config.init(allocator);
    defer config.deinit();
    
    const result = config.loadSecretFromFile(full_path);
    try std.testing.expectError(ConfigError.FilePermissionTooOpen, result);
}

test "loads complete configuration from file" {
    const allocator = std.testing.allocator;
    
    // Create test directory
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    // Create test config file
    const config_content =
        \\[server]
        \\host = 0.0.0.0
        \\port = 8080
        \\worker_threads = 8
        \\
        \\[database]
        \\connection_url = postgresql://testuser:testpass@localhost:5432/testdb
        \\max_connections = 30
        \\
        \\[repository]
        \\base_path = /tmp
        \\max_repo_size = 2147483648
        \\
        \\[security]
        \\secret_key = test-secret-key-that-is-long-enough-for-validation
        \\token_expiration_hours = 48
        \\enable_registration = false
    ;
    
    const config_file = "test_config.ini";
    const file = try tmp_dir.dir.createFile(config_file, .{ .mode = 0o600 });
    try file.writeAll(config_content);
    file.close();
    
    // Get full path
    const full_path = try tmp_dir.dir.realpathAlloc(allocator, config_file);
    defer allocator.free(full_path);
    
    var config = try Config.loadFromFile(allocator, full_path);
    defer config.deinit();
    
    try std.testing.expectEqualStrings("0.0.0.0", config.server.host);
    try std.testing.expectEqual(@as(u16, 8080), config.server.port);
    try std.testing.expectEqual(@as(u32, 8), config.server.worker_threads);
    
    try std.testing.expectEqualStrings("postgresql://testuser:testpass@localhost:5432/testdb", config.database.connection_url);
    try std.testing.expectEqual(@as(u32, 30), config.database.max_connections);
    
    try std.testing.expectEqualStrings("/tmp", config.repository.base_path);
    try std.testing.expectEqual(@as(u64, 2147483648), config.repository.max_repo_size);
    
    try std.testing.expectEqual(false, config.security.enable_registration);
}

test "complete configuration lifecycle with overrides" {
    const allocator = std.testing.allocator;
    
    // Create test directory
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    // Set environment override
    try std.posix.setenv("PLUE_SERVER_PORT", "9090", 1);
    defer std.posix.unsetenv("PLUE_SERVER_PORT") catch {};
    
    // Create minimal config file
    const config_content =
        \\[server]
        \\host = 127.0.0.1
        \\port = 8000
        \\
        \\[database]
        \\connection_url = postgresql://localhost/plue
        \\
        \\[security]
        \\secret_key = production-secret-key-with-sufficient-length-123456
    ;
    
    const config_file = "test_lifecycle.ini";
    const file = try tmp_dir.dir.createFile(config_file, .{ .mode = 0o600 });
    try file.writeAll(config_content);
    file.close();
    
    // Get full path
    const full_path = try tmp_dir.dir.realpathAlloc(allocator, config_file);
    defer allocator.free(full_path);
    
    // Load with all steps
    var config = try Config.load(allocator, full_path);
    defer config.deinit();
    
    // Environment should override file
    try std.testing.expectEqual(@as(u16, 9090), config.server.port);
    
    // File values should be loaded
    try std.testing.expectEqualStrings("127.0.0.1", config.server.host);
    
    // Defaults should be used for missing values
    try std.testing.expectEqual(@as(u32, 4), config.server.worker_threads);
}

test "sanitizes configuration for logging" {
    const allocator = std.testing.allocator;
    
    var config = try Config.init(allocator);
    defer config.deinit();
    
    config.security.secret_key = "super-secret-key-12345";
    config.database.connection_url = "postgresql://user:password@localhost:5432/plue";
    
    const sanitized = try config.sanitizeForLogging(allocator);
    defer sanitized.deinit();
    
    try std.testing.expectEqualStrings("[REDACTED]", sanitized.security.secret_key);
    try std.testing.expect(std.mem.indexOf(u8, sanitized.database.connection_url, "password") == null);
    try std.testing.expect(std.mem.indexOf(u8, sanitized.database.connection_url, "[REDACTED]") != null);
}

test "example: generating default configuration" {
    const allocator = std.testing.allocator;
    
    const default_config = try generateDefaultConfig(allocator);
    defer allocator.free(default_config);
    
    // Should generate a valid INI file
    try std.testing.expect(std.mem.indexOf(u8, default_config, "[server]") != null);
    try std.testing.expect(std.mem.indexOf(u8, default_config, "[database]") != null);
    try std.testing.expect(std.mem.indexOf(u8, default_config, "[repository]") != null);
    try std.testing.expect(std.mem.indexOf(u8, default_config, "[security]") != null);
    
    // Create test directory for example file
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    // Write to file for user
    const file = try tmp_dir.dir.createFile("plue.ini.example", .{});
    defer file.close();
    try file.writeAll(default_config);
}