# Implement Production-Grade Configuration Management Module (ENHANCED WITH GITEA + RESEARCH INSIGHTS)

<task_definition>
Implement a comprehensive, enterprise-grade configuration management system for the Plue application that handles INI-style configuration files, environment variable overrides, file-based secrets, and advanced security patterns. This system provides type-safe access to all application settings with secure defaults, rigorous validation, memory management, and production-grade security features following Gitea's battle-tested patterns and comprehensive research insights for zero-dependency, performance-optimized implementation.
</task_definition>

<context_and_constraints>

<technical_requirements>

- **Language/Framework**: Zig - https://ziglang.org/documentation/master/
- **Dependencies**: Zero external dependencies (uses only Zig standard library primitives)
- **File Format**: INI-style configuration files with robust section support and comment handling
- **Location**: `src/config/config.zig`
- **🆕 Architecture**: Single ArenaAllocator ownership model with guaranteed memory safety
- **🆕 Parsing**: Custom zero-dependency INI parser using buffered I/O and state machine
- **🆕 Security**: Advanced file-based secrets, proactive conflict detection, secure memory clearing with @volatileStore
- **🆕 Performance**: Buffered file reading, minimal syscalls, efficient string handling
- **🆕 Error Handling**: Comprehensive ConfigError set with production-grade error granularity
- **🆕 Validation**: Multi-layer validation with port conflict detection and weak secret prevention
- **Memory**: Zero allocator storage in structs, ArenaAllocator ownership, explicit defer/errdefer patterns
- **Testing**: Real file I/O tests, security feature verification, comprehensive validation scenarios

</technical_requirements>

<business_context>

🆕 **Production-Grade Configuration Management Requirements**:

- **🆕 Enterprise Security**: Zero-dependency system preventing exposed secrets, weak defaults, and memory leakage
- **🆕 Multi-Source Configuration**: Layered precedence (CLI > ENV > INI > defaults) with conflict detection
- **🆕 Advanced Secret Management**: File-based secrets (`__FILE` suffix), URI loading (`file://`), secure permission validation
- **🆕 Performance-Critical Parsing**: Buffered I/O, minimal allocations, efficient string processing for high-frequency reloads
- **🆕 Memory Safety Guarantees**: ArenaAllocator ownership, secure memory clearing with @volatileStore, guaranteed cleanup
- **Server Configuration**: Host, port, worker threads, timeouts with validation
- **Database Settings**: PostgreSQL URLs, connection pools, migration settings with credential protection
- **Repository Management**: Base paths, size limits, Git configuration with absolute path validation
- **Security Settings**: Secret keys, token expiration, authentication with weak secret detection
- **SSH Server Settings**: Host keys, port, connection limits with port conflict prevention
- **🆕 Production Logging**: Secure logging with automatic credential redaction and sanitization
- **🆕 Robust Error Handling**: Comprehensive ConfigError set covering all real-world failure scenarios

The system must be production-ready with enterprise-grade reliability, security, and performance suitable for high-traffic Git hosting environments.

The configuration system must be secure by default, preventing common vulnerabilities like exposed secrets or weak credentials.
</business_context>

</context_and_constraints>

<detailed_specifications>

<input>

The configuration module will accept inputs from multiple sources with a clear precedence order:

1. Default values hardcoded in the application
2. Configuration file (INI format) from specified path
3. Environment variables (highest precedence)
4. Command-line arguments (for config file path)

Configuration file format:
```ini
[server]
host = 0.0.0.0
port = 8000
worker_threads = 4

[database]
connection_url = postgresql://user:pass@localhost:5432/plue
max_connections = 25
connection_timeout = 30

[repository]
base_path = /var/plue/repos
max_repo_size = 1073741824

[security]
secret_key = change-me-in-production
token_expiration_hours = 24
enable_registration = true
```
</input>

<expected_output>

A complete configuration system providing:

1. **Type-safe configuration structure** with all application settings
2. **Multi-source loading** with proper precedence handling
3. **🆕 File-based Secret Loading** with `__FILE` suffix pattern and URI support
4. **🆕 Configuration Conflict Detection** preventing runtime issues
5. **🆕 Memory Security** with sensitive data clearing using `@volatileStore`
6. **Comprehensive validation** with detailed error messages
7. **Security features** including secret sanitization and permission checks
8. **🆕 Advanced Error Handling** with multiple severity levels
9. **Environment detection** for development vs production settings
10. **Logging integration** with secure value masking

Example API usage:
```zig
// Load configuration with all Gitea patterns
var config = try Config.load(allocator, config_file_path, clap_args);
defer config.deinit(allocator);

// Type-safe access
const server_port = config.server.port;
const db_url = config.database.connection_url;
const secret = config.security.secret_key;

// Validation results with enhanced error types
if (!config.isValid()) {
    for (config.getValidationErrors()) |error_msg| {
        log.err("Config error: {s}", .{error_msg});
    }
}

// Environment detection
if (config.isDevelopment()) {
    log.info("Running in development mode");
}

// 🆕 Secure memory clearing for sensitive data
defer config.clearSensitiveMemory();
```

🆕 **Production-Grade Architecture with Research Insights**:
```zig
const Config = struct {
    // 🆕 COMPREHENSIVE ERROR SET: Based on real-world production failures
    pub const ConfigError = error{
        // Filesystem and I/O Errors (granular for actionable debugging)
        FileNotFound,
        PermissionError,
        ReadError,
        PathNotAbsolute,             // Security: prevent relative path vulnerabilities
        
        // Parsing and Validation Errors (precise error location)
        ParseError,
        InvalidValue,
        MissingRequired,
        PortConflict,                // Operational: prevent service conflicts
        WeakSecret,                  // Security: enforce strong cryptographic material
        
        // Security and Secret-Handling Errors (proactive vulnerability prevention)
        SecurityError,
        ConflictingConfiguration,    // Critical: FOO and FOO__FILE both set
        FileSizeTooLarge,           // DoS prevention: secret file size limits
        EmptySecretFile,            // Validation: ensure secrets contain data
        
        // System Errors
        OutOfMemory,
    };
    
    // 🆕 ARENA ALLOCATOR OWNERSHIP MODEL: Simplified memory management
    server: ServerConfig = .{},
    database: DatabaseConfig = .{},
    repository: RepositoryConfig = .{},
    security: SecurityConfig = .{},
    ssh: SshConfig = .{},
    
    // Single owner of all configuration memory
    arena: std.heap.ArenaAllocator,

    // 🆕 ORCHESTRATED LOADING PIPELINE: Multi-source with guaranteed cleanup
    pub fn load(gpa: std.mem.Allocator, config_file_path: []const u8) !Config {
        var config = Config{
            .arena = std.heap.ArenaAllocator.init(gpa),
        };
        // 🆕 CRITICAL: Guaranteed cleanup on ANY failure path
        errdefer config.deinit();
        
        // 🆕 PHASE 1: Buffered INI parsing with state machine
        try config.loadFromIniFile(config_file_path);
        
        // 🆕 PHASE 2: Environment variables with __FILE suffix and conflict detection
        try config.loadEnvironmentOverrides();
        
        // 🆕 PHASE 3: URI-based secret loading (file:// scheme)
        try config.loadUriSecrets();
        
        // 🆕 PHASE 4: Comprehensive validation (ports, paths, secrets)
        try config.validate();
        
        // 🆕 PHASE 5: Secure logging with credential redaction
        try config.logConfigurationSecurely();
        
        return config;
    }
    
    // 🆕 GUARANTEED CLEANUP: Memory safety and sensitive data clearing
    pub fn deinit(self: *Config) void {
        self.clearSensitiveMemory();
        self.arena.deinit();
    }
    
    // 🆕 SECURE MEMORY CLEARING: Defeats compiler dead store elimination
    pub fn clearSensitiveMemory(self: *Config) void {
        clearSensitiveData(self.security.secret_key);
        clearSensitiveData(self.database.password);
        clearSensitiveData(self.security.jwt_secret);
    }
    
    // 🆕 PRODUCTION VALIDATION: Multi-layer security and operational checks
    pub fn validate(self: *const Config) ConfigError!void {
        // Cross-section validation (port conflicts)
        if (self.server.port == self.ssh.port) {
            return error.PortConflict;
        }
        
        // Section-specific validation
        try self.server.validate();
        try self.database.validate();
        try self.repository.validate();
        try self.security.validate();
        try self.ssh.validate();
    }
    
    // 🆕 SECURE LOGGING: Automatic credential redaction
    pub fn logConfigurationSecurely(self: *const Config) !void {
        // Create stack-allocated redacted copy
        var redacted = self.*;
        
        // Overwrite sensitive fields with redaction markers
        redacted.security.secret_key = "[REDACTED]";
        redacted.database.password = "[REDACTED]";
        redacted.security.jwt_secret = "[REDACTED]";
        
        // Log the sanitized configuration
        std.log.info("Configuration loaded: server.port={d}, database.max_connections={d}", .{
            redacted.server.port,
            redacted.database.max_connections,
        });
    }
    
    // 🆕 Minor Enhancement: Environment variable key encoding (Gitea advanced pattern)
    // Supports complex environment variables: PLUE__service_0X2E_name__key -> [service.name] key
    fn decodeEnvSectionKey(allocator: std.mem.Allocator, encoded: []const u8) !struct { section: []const u8, key: []const u8 } {
        // Handle hex-encoded characters for special chars in section names
        // _0X2E_ = dot, _0X2D_ = dash, etc.
        var decoded_section = std.ArrayList(u8).init(allocator);
        defer decoded_section.deinit();
        
        // Parse encoded environment variable key similar to Gitea's implementation
        // This enables complex section names with special characters
        // Example: PLUE__git_0X2E_lfs__max_file_size
        
        // Implementation would decode hex sequences and split on __
        // This is an optional advanced feature for complex deployments
        return .{
            .section = try decoded_section.toOwnedSlice(),
            .key = "", // Extracted key portion
        };
    }
    
    // 🆕 Minor Enhancement: Configuration saving support (optional)
    pub fn save(self: *Config, allocator: std.mem.Allocator, path: []const u8) !void {
        // Save current configuration back to INI file
        // Useful for dynamic configuration updates in admin interfaces
        // Similar to Gitea's configuration persistence capabilities
    }
    
    // 🆕 Minor Enhancement: Section mapping for type safety (optional convenience)
    pub fn mapSection(
        self: *Config,
        allocator: std.mem.Allocator,
        section_name: []const u8,
        comptime T: type,
    ) !T {
        // Automatically map INI section to Zig struct
        // Similar to Gitea's MapTo functionality for custom configurations
        // Provides type-safe access to dynamic configuration sections
    }
};

// 🆕 SECURE MEMORY CLEARING: Defeats compiler dead store elimination
/// Securely clears a slice of memory, preventing the compiler from optimizing
/// away the operation. This should be used on any buffers that have held
/// sensitive data, such as passwords or secret keys.
fn clearSensitiveData(data: []u8) void {
    for (data) |*byte| {
        // @volatileStore ensures this write is not optimized out by the compiler
        // as a "dead store" even though the memory will be freed later
        @volatileStore(u8, byte, 0);
    }
}

// 🆕 PRODUCTION-GRADE SECRET FILE LOADING: Comprehensive security validation
fn loadSecretFromFile(allocator: std.mem.Allocator, path: []const u8) ConfigError![]u8 {
    // Security: Only absolute paths allowed (prevents path traversal)
    if (!std.fs.path.isAbsolute(path)) {
        return error.PathNotAbsolute;
    }
    
    // Open file and get metadata for security checks
    const file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return error.FileNotFound,
        error.AccessDenied => return error.PermissionError,
        else => return error.ReadError,
    };
    defer file.close();
    
    const stat = try file.stat();
    
    // Security: Enforce restrictive permissions (owner-only readable)
    if (stat.mode & 0o077 != 0) {
        return error.PermissionError;
    }
    
    // Security: Prevent DoS from reading massive files
    const max_secret_size = 1024 * 1024; // 1MB limit
    if (stat.size > max_secret_size) {
        return error.FileSizeTooLarge;
    }
    
    // Security: Reject empty secret files
    if (stat.size == 0) {
        return error.EmptySecretFile;
    }
    
    // Read and trim the secret content
    const content = try file.readToEndAlloc(allocator, max_secret_size);
    return std.mem.trim(u8, content, " \t\r\n");
}

// 🆕 Minor Enhancement: Installation lock pattern (Gitea security feature)
const InstallationLock = struct {
    locked: bool = false,
    
    pub fn validateInstallation(self: *const InstallationLock) !void {
        if (!self.locked) {
            std.log.warn("Installation not locked - this may be a security risk in production");
            return error.InstallationNotLocked;
        }
    }
    
    pub fn lock(self: *InstallationLock) void {
        self.locked = true;
        std.log.info("Installation locked - setup completed");
    }
};
```

1. Loads and validates configuration from multiple sources
2. Provides structured access to configuration values
3. Validates all inputs according to security requirements
4. Reports detailed errors for invalid configurations
5. Detects configuration conflicts and mismatches
6. Ensures zero memory leaks with proper cleanup
7. Sanitizes sensitive values for logging
8. Distinguishes between fatal errors and warnings
</expected_output>

<implementation_steps>

**CRITICAL**: Follow TDD approach - write tests first, then implementation. Run `zig build && zig build test` after EVERY change. Always add tests to the same file as the source code.

**CRITICAL**: Zero tolerance for compilation or test failures. The codebase has NO pre-existing failures. If tests fail after your changes, YOU caused a regression.

<phase_1>
<title>Phase 1: Type-Safe Foundations and Memory Architecture (TDD)</title>

1. **🆕 Create zero-dependency module architecture**
   ```bash
   mkdir -p src/config
   touch src/config/config.zig
   ```

2. **🆕 Write tests for ArenaAllocator ownership model**
   ```zig
   test "Config arena allocator owns all string memory" {
       const allocator = testing.allocator;
       
       var config = Config{ .arena = std.heap.ArenaAllocator.init(allocator) };
       defer config.deinit();
       
       const arena_allocator = config.arena.allocator();
       
       // Test that strings are allocated in arena
       const test_string = try arena_allocator.dupe(u8, "test-value");
       config.server.host = test_string;
       
       // Verify memory ownership
       try testing.expect(config.server.host.ptr >= config.arena.state.buffer_list.first.?.data.ptr);
   }

   test "ConfigError set covers all production failure scenarios" {
       // Test that our error set is comprehensive
       const test_errors = [_]ConfigError{
           error.FileNotFound,
           error.PermissionError,
           error.PathNotAbsolute,
           error.ConflictingConfiguration,
           error.WeakSecret,
           error.PortConflict,
           error.FileSizeTooLarge,
           error.EmptySecretFile,
       };
       
       for (test_errors) |err| {
           try testing.expect(@errorName(err).len > 0);
       }
   }
   
   test "Config validation detects port conflicts across sections" {
       var config = Config{ .arena = undefined }; // Arena not needed for validation test
       config.server.port = 8080;
       config.ssh.port = 8080; // Conflict!
       
       try testing.expectError(ConfigError.PortConflict, config.validate());
   }
   
   test "SecurityConfig detects weak secrets with production patterns" {
       const weak_secrets = [_][]const u8{
           "CHANGE_ME_IN_PRODUCTION",
           "secret",
           "password",
           "changeme",
           "short", // Too short
       };
       
       for (weak_secrets) |weak_secret| {
           const config = SecurityConfig{ .secret_key = weak_secret };
           try testing.expectError(ConfigError.WeakSecret, config.validate());
       }
   }
   ```

3. **🆕 Implement namespaced configuration structs with validation**
4. **🆕 Add comprehensive ConfigError set based on research insights**
5. **🆕 Test memory safety guarantees with arena allocator**

   ```zig
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
       warning,  // Log and continue with defaults
       error,    // Return error, allow caller to decide
       fatal,    // Immediately terminate application
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
   ```
</phase_1>

<phase_2>
<title>Phase 2: Zero-Dependency INI Parser with Buffered I/O (TDD)</title>

1. **🆕 Write tests for buffered file parsing with state machine**
   ```zig
   test "buffered INI parser handles real files efficiently" {
       const allocator = testing.allocator;
       
       // Create temporary INI file
       var tmp_dir = testing.tmpDir(.{});
       defer tmp_dir.cleanup();
       
       const ini_content = 
           \\# Configuration file for Plue
           \\[server]
           \\host = 127.0.0.1
           \\port = 8080
           \\worker_threads = 4
           \\
           \\[database]
           \\connection_url = postgresql://localhost/test
           \\max_connections = 25
           \\
           \\[security]
           \\secret_key = production-secret-key-here
       ;
       
       try tmp_dir.dir.writeFile("test.ini", ini_content);
       const config_path = try tmp_dir.dir.realpathAlloc(allocator, "test.ini");
       defer allocator.free(config_path);
       
       var config = try Config.load(allocator, config_path);
       defer config.deinit();
       
       // Verify parsed values
       try testing.expectEqualStrings("127.0.0.1", config.server.host);
       try testing.expectEqual(@as(u16, 8080), config.server.port);
       try testing.expectEqual(@as(u32, 4), config.server.worker_threads);
       try testing.expectEqualStrings("postgresql://localhost/test", config.database.connection_url);
       try testing.expectEqual(@as(u32, 25), config.database.max_connections);
   }
   
   test "INI parser handles comments and whitespace robustly" {
       const allocator = testing.allocator;
       
       const tricky_ini = 
           \\# This is a comment
           \\
           \\[server] # Section comment
           \\   host   =   127.0.0.1   # Host comment
           \\port=8080
           \\
           \\; Semicolon comment style
           \\[database]
           \\connection_url = postgres://user:pass@host/db?param=value=with=equals
       ;
       
       var tmp_dir = testing.tmpDir(.{});
       defer tmp_dir.cleanup();
       
       try tmp_dir.dir.writeFile("tricky.ini", tricky_ini);
       const config_path = try tmp_dir.dir.realpathAlloc(allocator, "tricky.ini");
       defer allocator.free(config_path);
       
       var config = try Config.load(allocator, config_path);
       defer config.deinit();
       
       try testing.expectEqualStrings("127.0.0.1", config.server.host);
       try testing.expect(std.mem.indexOf(u8, config.database.connection_url, "param=value=with=equals") != null);
   }
   
   test "INI parser provides detailed error locations for malformed input" {
       const allocator = testing.allocator;
       
       const malformed_ini = 
           \\[server]
           \\host = 127.0.0.1
           \\invalid_line_without_equals
           \\port = 8080
       ;
       
       var tmp_dir = testing.tmpDir(.{});
       defer tmp_dir.cleanup();
       
       try tmp_dir.dir.writeFile("malformed.ini", malformed_ini);
       const config_path = try tmp_dir.dir.realpathAlloc(allocator, "malformed.ini");
       defer allocator.free(config_path);
       
       try testing.expectError(ConfigError.ParseError, Config.load(allocator, config_path));
   }
   ```

2. **🆕 Implement buffered I/O parser using std.io.bufferedReader for performance**
3. **🆕 Add state machine for section/key-value parsing with precise error locations**
4. **🆕 Test robust key-value splitting handling complex values with embedded delimiters**
5. **🆕 Verify arena allocator integration for string memory management**

   ```zig
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
   ```
</phase_2>

<phase_3>
<title>Phase 3: Advanced Secret Management with Production Security (TDD)</title>

1. **🆕 Write tests for comprehensive secret file security validation**
   ```zig
   test "loadSecretFromFile enforces comprehensive security validations" {
       const allocator = testing.allocator;
       
       var tmp_dir = testing.tmpDir(.{});
       defer tmp_dir.cleanup();
       
       // Test 1: Absolute path requirement
       try testing.expectError(ConfigError.PathNotAbsolute, 
           loadSecretFromFile(allocator, "relative/path/secret.txt"));
       
       // Test 2: File permission validation (0600 required)
       const secret_content = "my-secret-key";
       try tmp_dir.dir.writeFile("secret.txt", secret_content);
       
       const secret_path = try tmp_dir.dir.realpathAlloc(allocator, "secret.txt");
       defer allocator.free(secret_path);
       
       // Set overly permissive permissions (world-readable)
       try tmp_dir.dir.chmod("secret.txt", 0o644);
       try testing.expectError(ConfigError.PermissionError, 
           loadSecretFromFile(allocator, secret_path));
       
       // Fix permissions and test successful loading
       try tmp_dir.dir.chmod("secret.txt", 0o600);
       const loaded_secret = try loadSecretFromFile(allocator, secret_path);
       defer allocator.free(loaded_secret);
       try testing.expectEqualStrings(secret_content, loaded_secret);
       
       // Test 3: Empty file detection
       try tmp_dir.dir.writeFile("empty_secret.txt", "");
       try tmp_dir.dir.chmod("empty_secret.txt", 0o600);
       const empty_path = try tmp_dir.dir.realpathAlloc(allocator, "empty_secret.txt");
       defer allocator.free(empty_path);
       try testing.expectError(ConfigError.EmptySecretFile, 
           loadSecretFromFile(allocator, empty_path));
       
       // Test 4: File size limit (simulate large file)
       const large_content = "x" ** (1024 * 1024 + 1); // 1MB + 1 byte
       try tmp_dir.dir.writeFile("large_secret.txt", large_content);
       try tmp_dir.dir.chmod("large_secret.txt", 0o600);
       const large_path = try tmp_dir.dir.realpathAlloc(allocator, "large_secret.txt");
       defer allocator.free(large_path);
       try testing.expectError(ConfigError.FileSizeTooLarge, 
           loadSecretFromFile(allocator, large_path));
   }
   
   test "environment variable conflict detection prevents ambiguous configuration" {
       const allocator = testing.allocator;
       
       // Set up conflicting environment variables
       try std.os.setenv("PLUE_SECRET_KEY", "direct-secret");
       try std.os.setenv("PLUE_SECRET_KEY__FILE", "/path/to/secret/file");
       defer std.os.unsetenv("PLUE_SECRET_KEY") catch {};
       defer std.os.unsetenv("PLUE_SECRET_KEY__FILE") catch {};
       
       var config = Config{ .arena = std.heap.ArenaAllocator.init(allocator) };
       defer config.deinit();
       
       // Should fail with conflict detection
       try testing.expectError(ConfigError.ConflictingConfiguration, 
           config.loadEnvironmentOverrides());
   }
   
   test "__FILE suffix and URI schemes load secrets with identical security validation" {
       const allocator = testing.allocator;
       
       var tmp_dir = testing.tmpDir(.{});
       defer tmp_dir.cleanup();
       
       const secret_content = "uri-loaded-secret";
       try tmp_dir.dir.writeFile("uri_secret.txt", secret_content);
       try tmp_dir.dir.chmod("uri_secret.txt", 0o600);
       
       const secret_path = try tmp_dir.dir.realpathAlloc(allocator, "uri_secret.txt");
       defer allocator.free(secret_path);
       
       // Test __FILE suffix loading
       const file_suffix_value = try std.fmt.allocPrint(allocator, "{s}", .{secret_path});
       defer allocator.free(file_suffix_value);
       
       try std.os.setenv("PLUE_JWT_SECRET__FILE", file_suffix_value);
       defer std.os.unsetenv("PLUE_JWT_SECRET__FILE") catch {};
       
       // Test file:// URI loading
       const uri_value = try std.fmt.allocPrint(allocator, "file://{s}", .{secret_path});
       defer allocator.free(uri_value);
       
       try std.os.setenv("PLUE_DATABASE_PASSWORD", uri_value);
       defer std.os.unsetenv("PLUE_DATABASE_PASSWORD") catch {};
       
       var config = Config{ .arena = std.heap.ArenaAllocator.init(allocator) };
       defer config.deinit();
       
       try config.loadEnvironmentOverrides();
       try config.loadUriSecrets();
       
       // Both should load the same secret content
       try testing.expectEqualStrings(secret_content, config.security.jwt_secret);
       try testing.expectEqualStrings(secret_content, config.database.password);
   }
   ```

2. **🆕 Implement production-grade secret file loading with comprehensive security checks**
3. **🆕 Add proactive conflict detection preventing ambiguous configurations**
4. **🆕 Implement URI-based secret loading with identical security validation**
5. **🆕 Test file permission enforcement and DoS prevention**

   ```zig
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
   ```
</phase_3>

<phase_4>
<title>Phase 4: Memory Security and Production Logging (TDD)</title>

1. **🆕 Write tests for secure memory clearing defeating compiler optimization**
   ```zig
   test "clearSensitiveData defeats compiler dead store elimination" {
       var sensitive_data = [_]u8{ 'p', 'a', 's', 's', 'w', 'o', 'r', 'd' };
       
       // Before clearing
       try testing.expect(sensitive_data[0] == 'p');
       
       clearSensitiveData(&sensitive_data);
       
       // After clearing - all bytes should be zero
       for (sensitive_data) |byte| {
           try testing.expect(byte == 0);
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
   
   test "Config.clearSensitiveMemory clears all sensitive fields" {
       const allocator = testing.allocator;
       
       var config = Config{ .arena = std.heap.ArenaAllocator.init(allocator) };
       defer config.deinit();
       
       const arena_allocator = config.arena.allocator();
       
       // Set sensitive data
       config.security.secret_key = try arena_allocator.dupe(u8, "secret-key-data");
       config.database.password = try arena_allocator.dupe(u8, "database-password");
       config.security.jwt_secret = try arena_allocator.dupe(u8, "jwt-secret-data");
       
       // Verify data is present
       try testing.expectEqualStrings("secret-key-data", config.security.secret_key);
       
       // Clear sensitive memory
       config.clearSensitiveMemory();
       
       // Verify all sensitive fields are zeroed (check first byte as indicator)
       try testing.expect(config.security.secret_key[0] == 0);
       try testing.expect(config.database.password[0] == 0);
       try testing.expect(config.security.jwt_secret[0] == 0);
   }
   
   test "secure logging redacts credentials automatically" {
       const allocator = testing.allocator;
       
       var config = Config{ .arena = std.heap.ArenaAllocator.init(allocator) };
       defer config.deinit();
       
       const arena_allocator = config.arena.allocator();
       
       // Set both sensitive and non-sensitive data
       config.security.secret_key = try arena_allocator.dupe(u8, "actual-secret-key");
       config.database.password = try arena_allocator.dupe(u8, "actual-password");
       config.security.jwt_secret = try arena_allocator.dupe(u8, "jwt-secret");
       config.server.port = 8080;
       config.database.max_connections = 25;
       
       // Test that logging would be secure (we can't easily test actual log output,
       // but we can test the redaction logic)
       
       // This is a simulation of what logConfigurationSecurely does internally
       var redacted = config;
       redacted.security.secret_key = "[REDACTED]";
       redacted.database.password = "[REDACTED]";
       redacted.security.jwt_secret = "[REDACTED]";
       
       // Verify sensitive data is redacted
       try testing.expectEqualStrings("[REDACTED]", redacted.security.secret_key);
       try testing.expectEqualStrings("[REDACTED]", redacted.database.password);
       try testing.expectEqualStrings("[REDACTED]", redacted.security.jwt_secret);
       
       // Verify non-sensitive data is preserved
       try testing.expectEqual(@as(u16, 8080), redacted.server.port);
       try testing.expectEqual(@as(u32, 25), redacted.database.max_connections);
   }
   
   test "memory security integrated with full configuration lifecycle" {
       const allocator = testing.allocator;
       
       // Create temporary config with secrets
       var tmp_dir = testing.tmpDir(.{});
       defer tmp_dir.cleanup();
       
       const ini_content = 
           \\[security]
           \\secret_key = production-secret-here
           \\
           \\[database]
           \\connection_url = postgresql://user:pass@localhost/db
       ;
       
       try tmp_dir.dir.writeFile("secure.ini", ini_content);
       const config_path = try tmp_dir.dir.realpathAlloc(allocator, "secure.ini");
       defer allocator.free(config_path);
       
       // Load configuration
       var config = try Config.load(allocator, config_path);
       
       // Verify secrets are loaded
       try testing.expectEqualStrings("production-secret-here", config.security.secret_key);
       
       // Manually trigger memory clearing (normally happens in deinit)
       config.clearSensitiveMemory();
       
       // Verify secrets are cleared
       try testing.expect(config.security.secret_key[0] == 0);
       
       // Clean up (deinit will clear again, but that's safe)
       config.deinit();
   }
   ```

2. **🆕 Implement @volatileStore-based memory clearing preventing compiler optimization**
3. **🆕 Add stack-allocated secure logging with automatic credential redaction**
4. **🆕 Test integrated memory security throughout configuration lifecycle**
5. **🆕 Verify memory clearing works with arena allocator ownership model**

   ```zig
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
       for (key) |c, i| {
           if (i > 0 and std.ascii.isUpper(c)) {
               try result.append('_');
           }
           try result.append(std.ascii.toUpper(c));
       }
       
       return result.toOwnedSlice();
   }

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
           // Check for conflicting configurations first
           try self.checkForConflictingConfigurations();
           
           // Server overrides
           if (try self.getEnvValue("server", "host")) |value| {
               self.server.host = value;
           }
           if (try self.getEnvValue("server", "port")) |value| {
               const port = std.fmt.parseInt(u16, value, 10) catch return ConfigError.InvalidPort;
               if (port == 0) return ConfigError.InvalidPort;
               try validatePort(port);
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

       fn checkForConflictingConfigurations(self: *Config) !void {
           // Check each field that could have both direct and file values
           const fields = .{
               .{ "security", "secret_key" },
               .{ "database", "connection_url" },
           };
           
           inline for (fields) |field| {
               const env_name = try buildEnvVarName(self.allocator, field[0], field[1]);
               defer self.allocator.free(env_name);
               
               const file_env_name = try std.fmt.allocPrint(self.allocator, "{s}__FILE", .{env_name});
               defer self.allocator.free(file_env_name);
               
               // Check if both are set
               const has_direct = std.process.hasEnvVar(self.allocator, env_name) catch false;
               const has_file = std.process.hasEnvVar(self.allocator, file_env_name) catch false;
               
               if (has_direct and has_file) {
                   std.log.err("FATAL: Both {s} and {s} are set. Only one method allowed.", .{env_name, file_env_name});
                   return ConfigError.ConflictingConfiguration;
               }
           }
       }
   };
   ```
</phase_4>

<phase_5>
<title>Phase 5: Configuration Validation (TDD)</title>

1. **Write tests for validation logic**

   ```zig
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

   test "validates port ranges and warnings" {
       const allocator = std.testing.allocator;
       
       // Test privileged port warning
       const severity = try validatePortWithSeverity(80);
       try std.testing.expectEqual(ConfigSeverity.warning, severity);
       
       // Test SSH port conflict warning
       const ssh_severity = try validatePortWithSeverity(22);
       try std.testing.expectEqual(ConfigSeverity.warning, ssh_severity);
       
       // Test normal port
       const normal_severity = try validatePortWithSeverity(8080);
       try std.testing.expectEqual(ConfigSeverity.error, normal_severity);
   }

   test "enforces absolute paths for critical settings" {
       const allocator = std.testing.allocator;
       
       var config = try Config.init(allocator);
       defer config.deinit();
       
       // Relative path should fail for base_path
       config.repository.base_path = "relative/path";
       try std.testing.expectError(ConfigError.PathNotAbsolute, config.validateRepository());
       
       // Absolute path should pass
       config.repository.base_path = "/var/plue/repos";
       try config.validateRepository();
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
   ```

2. **Implement validation methods**

   ```zig
   // Add to Config struct
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
       
       // Validate port with warnings
       _ = try validatePortWithSeverity(self.server.port);
       
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

   fn validatePort(port: u16) !void {
       if (port == 0) return ConfigError.InvalidPort;
       
       // Additional validation handled by validatePortWithSeverity
       _ = try validatePortWithSeverity(port);
   }

   fn validatePortWithSeverity(port: u16) !ConfigSeverity {
       if (port == 0) return ConfigError.InvalidPort;
       
       if (port < 1024 and !isRunningAsRoot()) {
           std.log.warn("Port {d} requires root privileges", .{port});
           return .warning;
       }
       
       if (port == 22) {
           std.log.warn("Port 22 conflicts with SSH. Consider using a different port.", .{});
           return .warning;
       }
       
       return .error; // Normal case
   }

   fn isRunningAsRoot() bool {
       return switch (builtin.os.tag) {
           .windows => false,
           .linux => std.os.linux.getuid() == 0,
           .macos => std.c.getuid() == 0,
           else => false,
       };
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
   ```
</phase_5>

<phase_6>
<title>Phase 6: File-based Secrets Support (TDD)</title>

1. **Write tests for secret file handling**

   ```zig
   test "loads secrets from files" {
       const allocator = std.testing.allocator;
       
       // Create test directory
       var tmp_dir = std.testing.tmpDir(.{});
       defer tmp_dir.cleanup();
       
       // Create test secret file
       const secret_file = "test_secret.txt";
       const secret_content = "super-secret-key-from-file-1234567890";
       
       const file = try tmp_dir.dir.createFile(secret_file, .{ .mode = 0o600 });
       try file.writeAll(secret_content);
       file.close();
       
       // Get full path
       const full_path = try tmp_dir.dir.realpathAlloc(allocator, secret_file);
       defer allocator.free(full_path);
       
       var config = try Config.init(allocator);
       defer config.deinit();
       
       // Set secret to file path
       config.security.secret_key = try std.fmt.allocPrint(allocator, "file://{s}", .{full_path});
       try config.allocated_strings.append(config.security.secret_key);
       
       // Load secrets from files
       try config.loadFileSecrets();
       
       try std.testing.expectEqualStrings(secret_content, config.security.secret_key);
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
       
       config.security.secret_key = try std.fmt.allocPrint(allocator, "file://{s}", .{full_path});
       try config.allocated_strings.append(config.security.secret_key);
       
       const result = config.loadFileSecrets();
       try std.testing.expectError(ConfigError.FilePermissionTooOpen, result);
   }
   ```

2. **Implement file-based secrets**

   ```zig
   // Add to Config struct
   pub fn loadFileSecrets(self: *Config) !void {
       // Check security.secret_key
       if (std.mem.startsWith(u8, self.security.secret_key, "file://")) {
           const file_path = self.security.secret_key[7..];
           const secret = try self.loadSecretFromFile(file_path);
           self.security.secret_key = secret;
       }
       
       // Check database.connection_url
       if (std.mem.startsWith(u8, self.database.connection_url, "file://")) {
           const file_path = self.database.connection_url[7..];
           const secret = try self.loadSecretFromFile(file_path);
           self.database.connection_url = secret;
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
       
       // Clear original content from memory
       clearSensitiveMemory(content);
       
       return secret_copy;
   }
   ```
</phase_6>

<phase_7>
<title>Phase 7: Complete Configuration Loading (TDD)</title>

1. **Write integration tests**

   ```zig
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
       try std.process.setEnvVar("PLUE_SERVER_PORT", "9090");
       defer std.process.unsetEnvVar("PLUE_SERVER_PORT");
       
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
   ```

2. **Implement complete loading logic**

   ```zig
   // Main loading function
   pub fn load(allocator: std.mem.Allocator, config_path: []const u8) !Config {
       var config = try Config.init(allocator);
       errdefer config.deinit();
       
       // Step 1: Load from file
       try config.loadFromFileInternal(config_path);
       
       // Step 2: Apply environment overrides
       try config.loadEnvironmentOverrides();
       
       // Step 3: Load file-based secrets
       try config.loadFileSecrets();
       
       // Step 4: Validate final configuration
       try config.validate();
       
       // Step 5: Log sanitized configuration
       try config.logConfiguration(allocator);
       
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
       
       // Read file content with size validation
       const content = try std.fs.cwd().readFileAlloc(self.allocator, path, MAX_CONFIG_FILE_SIZE);
       defer self.allocator.free(content);
       
       // Validate size
       try validateConfigSize(content);
       
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
   ```
</phase_7>

<phase_7_5>
<title>Phase 7.5: Security Enhancements and Logging (TDD)</title>

1. **Write tests for configuration sanitization**

   ```zig
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

   test "clears sensitive memory after use" {
       const allocator = std.testing.allocator;
       
       var config = try Config.init(allocator);
       defer config.deinit();
       
       // Allocate sensitive data
       var sensitive = try allocator.alloc(u8, 32);
       @memcpy(sensitive, "sensitive-secret-data-here-12345");
       
       // Clear it
       clearSensitiveMemory(sensitive);
       
       // Verify it's cleared
       for (sensitive) |byte| {
           try std.testing.expectEqual(@as(u8, 0), byte);
       }
       
       allocator.free(sensitive);
   }

   test "validates config file size limits" {
       const allocator = std.testing.allocator;
       
       const huge_content = try allocator.alloc(u8, 2 * 1024 * 1024); // 2MB
       defer allocator.free(huge_content);
       @memset(huge_content, 'a');
       
       const result = validateConfigSize(huge_content);
       try std.testing.expectError(ConfigError.FileSizeTooLarge, result);
   }
   ```

2. **Implement security enhancements**

   ```zig
   const MAX_CONFIG_FILE_SIZE = 1024 * 1024; // 1MB
   const MAX_KEY_LENGTH = 255;
   const MAX_VALUE_LENGTH = 65535;

   fn validateConfigSize(content: []const u8) !void {
       if (content.len > MAX_CONFIG_FILE_SIZE) {
           std.log.err("Configuration file too large: {} bytes (max: {} bytes)", .{content.len, MAX_CONFIG_FILE_SIZE});
           return ConfigError.FileSizeTooLarge;
       }
   }

   fn clearSensitiveMemory(buffer: []u8) void {
       // Use volatile to prevent compiler optimization
       const volatile_ptr = @as([*]volatile u8, @ptrCast(buffer.ptr));
       @memset(volatile_ptr[0..buffer.len], 0);
   }

   pub fn sanitizeForLogging(self: *const Config, allocator: std.mem.Allocator) !Config {
       var sanitized = try Config.init(allocator);
       errdefer sanitized.deinit();
       
       // Copy non-sensitive values
       sanitized.server = self.server;
       sanitized.repository = self.repository;
       
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
       }
       
       return sanitized;
   }

   // Add to Config struct
   pub fn logConfiguration(self: *const Config, allocator: std.mem.Allocator) !void {
       const sanitized = try self.sanitizeForLogging(allocator);
       defer sanitized.deinit();
       
       std.log.info("Configuration loaded:", .{});
       std.log.info("  Server: {s}:{d}", .{sanitized.server.host, sanitized.server.port});
       std.log.info("  Database: {s}", .{sanitized.database.connection_url});
       std.log.info("  Repository base: {s}", .{sanitized.repository.base_path});
       std.log.info("  Security: secret_key={s}", .{sanitized.security.secret_key});
   }
   ```
</phase_7_5>

<phase_8>
<title>Phase 8: Usage Examples and Integration (TDD)</title>

1. **Write usage example tests**

   ```zig
   test "example: loading configuration in server" {
       const allocator = std.testing.allocator;
       
       // Create test directory
       var tmp_dir = std.testing.tmpDir(.{});
       defer tmp_dir.cleanup();
       
       // Create example config
       const config_content =
           \\[server]
           \\host = 0.0.0.0
           \\port = 8000
           \\
           \\[database]
           \\connection_url = postgresql://plue:password@localhost:5432/plue
           \\
           \\[repository]
           \\base_path = /var/plue/repos
           \\
           \\[security]
           \\secret_key = my-super-secret-key-for-production-use-only-12345
       ;
       
       const config_file = "plue.ini";
       const file = try tmp_dir.dir.createFile(config_file, .{ .mode = 0o600 });
       try file.writeAll(config_content);
       file.close();
       
       // Get full path
       const full_path = try tmp_dir.dir.realpathAlloc(allocator, config_file);
       defer allocator.free(full_path);
       
       // Example server initialization
       const config = try Config.load(allocator, full_path);
       defer config.deinit();
       
       // Use configuration values
       std.log.info("Starting server on {s}:{d}", .{ config.server.host, config.server.port });
       std.log.info("Database: {s}", .{config.database.connection_url});
       std.log.info("Repository path: {s}", .{config.repository.base_path});
       
       try std.testing.expectEqualStrings("0.0.0.0", config.server.host);
       try std.testing.expectEqual(@as(u16, 8000), config.server.port);
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
   ```

2. **Add helper functions**

   ```zig
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
           ServerConfig.host,
           ServerConfig.port,
           ServerConfig.worker_threads,
           ServerConfig.request_timeout_ms,
           ServerConfig.max_request_size,
           DatabaseConfig.connection_url,
           DatabaseConfig.max_connections,
           DatabaseConfig.connection_timeout_seconds,
           DatabaseConfig.idle_timeout_seconds,
           DatabaseConfig.statement_cache_size,
           RepositoryConfig.base_path,
           RepositoryConfig.max_repo_size,
           if (RepositoryConfig.allow_force_push) "true" else "false",
           if (RepositoryConfig.enable_lfs) "true" else "false",
           RepositoryConfig.default_branch,
           SecurityConfig.secret_key,
           SecurityConfig.token_expiration_hours,
           if (SecurityConfig.enable_registration) "true" else "false",
           if (SecurityConfig.require_email_verification) "true" else "false",
           SecurityConfig.min_password_length,
           SecurityConfig.bcrypt_cost,
       });
       
       return buffer.toOwnedSlice();
   }

   // Convenience function for getting config from a known location
   pub fn loadDefault(allocator: std.mem.Allocator) !Config {
       // Try multiple locations in order
       const config_paths = [_][]const u8{
           "plue.ini",
           "/etc/plue/plue.ini",
           "/usr/local/etc/plue.ini",
       };
       
       for (config_paths) |path| {
           if (load(allocator, path)) |config| {
               std.log.info("Loaded configuration from: {s}", .{path});
               return config;
           } else |err| switch (err) {
               ConfigError.FileNotFound => continue,
               else => return err,
           }
       }
       
       return ConfigError.FileNotFound;
   }
   ```
</phase_8>

</implementation_steps>

</detailed_specifications>

<critical_implementation_details>

<memory_management>
<title>Memory Management</title>
- Never store allocators in structs - pass them to methods
- Track all allocated strings in `allocated_strings` array
- Free all allocations in `deinit()` method
- Use `errdefer` for cleanup on error paths
- Duplicate strings when storing configuration values
- Clear sensitive data from memory after use
</memory_management>

<security_hardening>
<title>Security Hardening</title>
- Enforce 0600 permissions on configuration files
- Validate all inputs before use
- Support file-based secrets for sensitive values
- Prevent default/weak secret keys
- Sanitize database connection URLs in logs
- Clear secrets from memory after validation
</security_hardening>

<error_handling>
<title>Error Handling</title>
- Provide specific error types for different failures
- Include context in error messages
- Validate early and fail fast
- Use error unions for all fallible operations
- Log security-related errors at appropriate levels
</error_handling>

<testing_requirements>
<title>Testing Requirements</title>
- All tests must be in the same file as implementation
- Tests must be self-contained with no abstractions
- Use actual file I/O, no mocking
- Clean up test files in defer blocks
- Test both success and failure paths
</testing_requirements>

</critical_implementation_details>

<common_pitfalls>

<memory_leaks>
<title>Memory Leaks</title>
- Forgetting to add allocated strings to tracking array
- Not freeing parser internal structures
- Leaking on error paths without errdefer
- Not clearing sensitive data after use
</memory_leaks>

<security_issues>
<title>Security Issues</title>
- Accepting world-readable config files
- Logging sensitive configuration values
- Using weak default secret keys
- Not validating file-based secret permissions
</security_issues>

<parsing_errors>
<title>Parsing Errors</title>
- Not handling comments correctly
- Failing on valid but unusual INI syntax
- Not trimming whitespace properly
- Case sensitivity in section/key names
</parsing_errors>

</common_pitfalls>

<code_style_and_architecture>

<design_patterns>

- **Builder Pattern**: For constructing configuration incrementally
- **Validation Pattern**: Separate validation methods for each section
- **Override Pattern**: Clear precedence for configuration sources
- **Factory Pattern**: For creating configuration from different sources
</design_patterns>

<code_organization>

```
project/
├── src/
│   ├── config/
│   │   └── config.zig      # All configuration code in one file
│   ├── main.zig           # Uses Config.load()
│   └── server/
│       └── server.zig     # Uses validated configuration
```
</code_organization>

<integration_example>

```zig
// In main.zig
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Load configuration
    const config_path = try getConfigPath(allocator);
    defer allocator.free(config_path);
    
    const config = try Config.load(allocator, config_path);
    defer config.deinit();
    
    // Initialize server with configuration
    var server = try Server.init(allocator, config);
    defer server.deinit();
    
    // Start server
    try server.listen();
}
```
</integration_example>

</code_style_and_architecture>

<success_criteria>

1. **🆕 All tests pass**: `zig build && zig build test` shows 100% success rate with comprehensive coverage
2. **🆕 Zero-Dependency Architecture**: No external dependencies, using only Zig standard library primitives
3. **🆕 Memory Safety Guarantees**: ArenaAllocator ownership, @volatileStore clearing, guaranteed cleanup with errdefer
4. **🆕 Production-Grade Security**: File-based secrets, conflict detection, permission validation, DoS prevention
5. **🆕 Performance Optimization**: Buffered I/O, minimal syscalls, efficient string handling, state machine parsing
6. **🆕 Comprehensive Error Handling**: Granular ConfigError set covering all real-world failure scenarios
7. **🆕 Advanced Secret Management**: `__FILE` suffix, URI schemes, comprehensive security validation
8. **🆕 Secure Logging**: Automatic credential redaction, stack-allocated sanitization
9. **🆕 Multi-Source Configuration**: Layered precedence with proactive conflict detection
10. **🆕 Type Safety**: Compile-time validated configuration access with namespaced sections
11. **🆕 Production Ready**: Enterprise-grade reliability, security, and performance patterns from Gitea
12. **🆕 Integration Ready**: Clean API suitable for SSH server, HTTP server, and database modules

</success_criteria>

<build_verification_protocol>

**MANDATORY**: After EVERY code change:

```bash
zig build && zig build test
```

- Build takes <10 seconds - NO EXCUSES
- Zero tolerance for compilation failures
- If tests fail, YOU caused a regression
- Fix immediately before proceeding
</build_verification_protocol>

<example_usage>

```bash
# Generate example configuration
plue config generate > plue.ini.example

# Validate configuration file
plue config validate -f /etc/plue/plue.ini

# Test configuration loading
PLUE_SERVER_PORT=9000 plue config test

# Start with configuration
plue --config /etc/plue/plue.ini server
```

**Example Configuration File**:

```ini
[server]
host = 0.0.0.0
port = 8000
worker_threads = 4

[database]
# Use file-based secret for production
connection_url = file:///var/plue/secrets/db_url
max_connections = 50

[repository]
base_path = /var/plue/repos
max_repo_size = 5368709120  # 5GB

[security]
# Generated with: openssl rand -hex 32
secret_key = file:///var/plue/secrets/app_key
token_expiration_hours = 24
enable_registration = false
```
</example_usage>

<references>

- INI File Format: https://en.wikipedia.org/wiki/INI_file
- Zig Error Handling: https://ziglang.org/documentation/master/#Errors
- Configuration Best Practices: https://12factor.net/config
- Security Configuration: OWASP Configuration Guide
- GitHub Issue: https://github.com/evmts/agent/issues/15
- Gitea Configuration Reference: https://github.com/go-gitea/gitea/tree/main/modules/setting
</references>

<amendments>

<issue_clarification>
<title>Configuration Management Module Requirements from GitHub Issue #15</title>

Based on the GitHub issue from evmts/agent repository, this prompt implements a configuration management module with the following key requirements:

1. **INI-style configuration file parsing** - Simple, human-readable format
2. **Environment variable overrides** - Using PLUE_SECTION_KEY naming convention
3. **Type-safe configuration access** - Structured configuration with compile-time safety
4. **Strict security validations** - File permissions, secret strength, input validation
5. **Memory management** - No allocators in structs, explicit cleanup
6. **Testing philosophy** - All tests in same file, no abstractions

The implementation emphasizes security (file permissions, secret validation) and proper memory management patterns as specified in the issue.
</issue_clarification>

<gitea_patterns>
<title>Critical Patterns from Gitea Reference Implementation</title>

Based on analysis of Gitea's configuration system, the following patterns have been incorporated:

1. **__FILE Suffix Pattern**: Environment variables with `__FILE` suffix load values from files (e.g., `PLUE_SECURITY_SECRET_KEY__FILE=/path/to/secret`)

2. **Conflict Detection**: Fatal error if both direct value and file-based value are provided for the same configuration

3. **Severity Levels**: Distinguish between warnings (continue with defaults), errors (return error), and fatal (terminate application)

4. **Port Validation**: Warnings for privileged ports (<1024) and conflicts with known services (SSH on port 22)

5. **Path Requirements**: Critical paths like `base_path` must be absolute paths

6. **Configuration Sanitization**: Sensitive values are replaced with `[REDACTED]` when logging

7. **Size Limits**: Configuration files limited to 1MB, secret files to 64KB

8. **Empty File Handling**: Empty secret files are treated as errors, not empty strings

9. **Memory Clearing**: Sensitive data is explicitly cleared from memory after use

10. **Installation State**: Configuration validation can vary based on installation state (not_installed vs installed)

These patterns ensure the configuration system matches production-grade systems like Gitea in terms of security and robustness.
</gitea_patterns>
<production_patterns>
<title>Production-Ready Patterns Summary</title>

The configuration management module now includes the following production-grade patterns based on Gitea's reference implementation:

**Security Enhancements**:
- File permission validation (0600 required for config files)
- `__FILE` suffix pattern for loading secrets from files
- Conflict detection when both direct and file values are provided
- Memory clearing for sensitive data after use
- Configuration sanitization for logging (replaces secrets with `[REDACTED]`)
- Size limits: 1MB for config files, 64KB for secret files
- Empty secret files treated as errors

**Validation Improvements**:
- Severity levels: warnings (log and continue), errors (return error), fatal (terminate)
- Port validation with warnings for privileged ports and known conflicts
- Absolute path requirements for critical directories
- Installation state awareness (lenient during setup, strict when installed)
- Comprehensive error messages with context

**Robustness Features**:
- Graceful handling of corrupted configuration files
- Thread-safe configuration access with mutex protection
- Clear precedence order: defaults → file → environment → __FILE suffix
- Detailed logging of sanitized configuration on startup
- Recovery mechanisms for common configuration errors

**Best Practices**:
- All tests in the same file (no test abstractions)
- Memory tracked in `allocated_strings` array
- No allocators stored in structs
- Explicit defer/errdefer for all allocations
- Clear separation of concerns between loading, validation, and usage

These patterns ensure the configuration system is production-ready, secure, and maintainable.
</production_patterns>
</amendments>