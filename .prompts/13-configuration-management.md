# Implement Production-Grade Configuration Management Module (ENHANCED WITH GITEA + RESEARCH INSIGHTS)

## Implementation Summary

The production-grade configuration management system was comprehensively implemented following TDD principles across multiple phases:

### Phase 1: Type-Safe Foundations
**Commit**: 92eede3 - ✅ feat: implement TDD Phase 1 - production-grade config foundations (Jul 29, 2025)

**What was implemented**:
- Created src/config/config.zig module
- Type-safe configuration structures (ServerConfig, DatabaseConfig, etc.)
- Comprehensive ConfigError set covering all production scenarios
- ArenaAllocator ownership model for memory management
- Basic validation including port conflict detection
- Weak secret detection patterns
- Tests for memory ownership and error scenarios

### Phase 2: Zero-Dependency INI Parser
**Commit**: 43fd09f - ✅ feat: complete TDD Phase 2 - zero-dependency INI parser (Jul 29, 2025)

**What was implemented**:
- Buffered INI file parser using std.io.bufferedReader
- State machine for section/key-value parsing
- Comment handling (# and ; styles)
- Whitespace trimming and normalization
- Robust key-value splitting with embedded delimiters
- Detailed parse error reporting
- Integration with arena allocator for string memory

### Phase 3: Advanced Secret Management
**Commit**: 327649b - ✅ feat: complete TDD Phase 3 - advanced secret management (Jul 29, 2025)

**What was implemented**:
- File-based secret loading with __FILE suffix pattern
- Comprehensive security validations:
  - Absolute path requirement
  - File permission checks (0600 required)
  - File size limits (DoS prevention)
  - Empty file detection
- Environment variable conflict detection
- URI-based secret loading (file:// scheme)
- Proactive configuration conflict prevention

### Phase 4: Memory Security and Logging
**Commit**: d93fe91 - ✅ test: phase 4 - secure memory clearing and production logging (Jul 29, 2025)

**What was implemented**:
- Secure memory clearing with @volatileStore
- clearSensitiveData function defeating compiler optimization
- Automatic credential redaction in logging
- Stack-allocated secure logging patterns
- Integration with configuration lifecycle
- Memory security throughout arena allocator usage

### Phase 5: Complete Configuration Loading
**Commit**: 807bd1c - ✅ test: phase 5 - complete configuration loading with comprehensive validation (Jul 29, 2025)

**What was implemented**:
- Complete Config.load orchestration pipeline
- Multi-source configuration precedence
- Environment variable overrides with PLUE_ prefix
- Comprehensive validation across all sections
- Path validation (absolute paths, existence checks)
- Integration of all security features
- Production-ready error handling

### Additional Implementation (Earlier phases)
**Earlier commits show additional features**:
- 8493117 - Complete configuration loading with integration tests
- 39e2478 - Configuration sanitization and security enhancements
- 86896b1 - Usage examples and helper functions
- 5c27175 - Dependency injection for environment variables

**Current Status**:
- ✅ Zero-dependency architecture using only Zig stdlib
- ✅ ArenaAllocator ownership model
- ✅ Comprehensive ConfigError set
- ✅ Buffered INI parser with state machine
- ✅ File-based secrets with __FILE suffix
- ✅ URI-based secret loading
- ✅ Conflict detection and prevention
- ✅ Secure memory clearing with @volatileStore
- ✅ Automatic credential redaction
- ✅ Multi-source configuration loading
- ✅ Complete validation pipeline
- ✅ Production-grade error handling

**What was NOT completed**:
- Advanced Gitea patterns (hex encoding for complex env vars)
- Configuration saving capabilities
- Section mapping for dynamic struct conversion
- Installation lock pattern
- Some minor Gitea-specific enhancements

**Key architectural decisions**:
1. Zero external dependencies - custom INI parser
2. Single ArenaAllocator owns all configuration memory
3. @volatileStore for secure memory clearing
4. Comprehensive security validations on secret files
5. Proactive conflict detection between configuration sources
6. Stack-allocated logging for credential safety

**How it went**:
The implementation was completed successfully following strict TDD principles. Each phase built upon the previous, resulting in a production-grade configuration system with enterprise security features. The zero-dependency approach required implementing a custom INI parser but provides better control over memory management and security. All tests pass and the system is integrated with the broader application.

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

</business_context>

</context_and_constraints>

<detailed_specifications>

<input>

Configuration sources with precedence order (highest to lowest):
1. **Command-line arguments** (--config-file path)
2. **Environment variables** (PLUE_* prefixed)
3. **Configuration file** (INI format)
4. **Hardcoded defaults** (secure fallbacks)

Expected INI configuration structure:
```ini
[server]
host = 0.0.0.0
port = 8080
worker_threads = 4
read_timeout = 30
write_timeout = 30

[database]
connection_url = postgresql://user:pass@localhost:5432/plue
max_connections = 25
connection_timeout = 30
migration_auto = false

[repository]
base_path = /var/lib/plue/repositories
max_repo_size = 1073741824
git_timeout = 300

[security]
secret_key = CHANGE_ME_IN_PRODUCTION
token_expiration_hours = 24
enable_registration = true
min_password_length = 8

[ssh]
host = 0.0.0.0
port = 22
host_key_path = /etc/plue/ssh_host_key
max_connections = 100
connection_timeout = 600
```

🆕 **File-based Secret Loading (Gitea Pattern)**:
```bash
# Environment variables with __FILE suffix
export PLUE_DATABASE_PASSWORD__FILE="/etc/plue/secrets/db_password"
export PLUE_SECRET_KEY__FILE="/etc/plue/secrets/app_key"

# URI-based secret loading
export PLUE_JWT_SECRET="file:///etc/plue/secrets/jwt_key"
```

🆕 **Conflict Detection**:
- Detect conflicting direct env vars and `__FILE` variants
- Warn about configuration source conflicts
- Validate secret file permissions and sizes

Environment variable mapping:
- `PLUE_SERVER_HOST` → `[server] host`
- `PLUE_DATABASE_URL` → `[database] connection_url`
- `PLUE_SECRET_KEY` → `[security] secret_key`
- `PLUE_SECRET_KEY__FILE` → Load from file path

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

</expected_output>

<implementation_steps>

**CRITICAL**: Follow TDD approach - write tests first, then implementation. Run `zig build && zig build test` after EVERY change. Tests must be in the same file as source code.

**CRITICAL**: Zero tolerance for compilation or test failures. Any failing tests after your changes indicate YOU caused a regression.

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

</phase_4>

<phase_5>
<title>Phase 5: Complete Configuration Loading and Integration (TDD)</title>

1. **Write tests for complete configuration loading**
2. **Implement main Config struct with all enhanced features**
3. **Add comprehensive validation with detailed error reporting**
4. **Test memory management and cleanup**
5. **Add production-grade path validation and security checks**

</phase_5>

</implementation_steps>

</detailed_specifications>

<quality_assurance>

<testing_requirements>

- **File I/O Testing**: Use real files, no mocking
- **🆕 File-based Secret Testing**: Test `__FILE` suffix loading and URI schemes
- **🆕 Conflict Detection Testing**: Test detection of conflicting configuration sources
- **🆕 Memory Security Testing**: Verify sensitive data clearing and redaction
- **Error Handling**: Test all failure scenarios (missing files, malformed content, permission errors)
- **Memory Safety**: Verify no leaks with comprehensive allocation tracking
- **Security**: Test file permission validation and secret sanitization
- **Integration**: Test with actual environment variables and command-line args
- **Performance**: Validate parsing performance with large configuration files

</testing_requirements>

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

</quality_assurance>

<reference_implementations>

**🆕 Enhanced with Gitea Production Patterns:**
- [🆕 Gitea Configuration Loading](https://github.com/go-gitea/gitea/blob/main/modules/setting/setting.go)
- [🆕 Gitea Environment Variable Handling](https://github.com/go-gitea/gitea/blob/main/modules/setting/config_env.go)
- [🆕 Gitea Security Configuration](https://github.com/go-gitea/gitea/blob/main/modules/setting/security.go)
- [🆕 Gitea Configuration Provider Interface](https://github.com/go-gitea/gitea/blob/main/modules/setting/config_provider.go)
- [🆕 Gitea Path Validation](https://github.com/go-gitea/gitea/blob/main/modules/setting/path.go)
- [INI Parsing](https://github.com/go-ini/ini) (Gitea uses this library, we'll need a Zig equivalent)

**🆕 Key Gitea Patterns Implemented:**
- File-based secret loading with `__FILE` suffix
- URI-based secret loading (`file://` scheme)
- Configuration conflict detection
- Sensitive data memory clearing with `@volatileStore`
- Advanced validation with multiple severity levels
- Comprehensive error types matching real-world scenarios

**🎯 Additional Minor Enhancements (Optional):**
- Environment variable hex encoding for complex section names (`_0X2E_` for dots)
- Configuration saving capabilities for dynamic updates
- Section mapping for type-safe struct conversions
- Installation lock pattern for setup security

</reference_implementations>