# Implement Secure Configuration Management Module (ENHANCED WITH GITEA PRODUCTION PATTERNS)

<task_definition>
Implement a comprehensive configuration management system for the Plue application that handles INI-style configuration files, environment variable overrides, file-based secrets, and advanced security patterns. This system provides type-safe access to all application settings with secure defaults, validation, memory management, and production-grade security features following Gitea's battle-tested patterns.
</task_definition>

<context_and_constraints>

<technical_requirements>

- **Language/Framework**: Zig - https://ziglang.org/documentation/master/
- **Dependencies**: None (uses only Zig standard library)
- **File Format**: INI-style configuration files with section support
- **Location**: `src/config/config.zig`
- **Security**: File-based secrets, conflict detection, memory clearing, URI loading
- **Memory**: Zero allocator storage in structs, explicit defer patterns
- **Testing**: Real file I/O tests, no mocking, comprehensive validation

</technical_requirements>

<business_context>

Plue requires centralized configuration management with enterprise-grade security to handle:

- **Server Configuration**: Host, port, worker threads, timeouts
- **Database Settings**: PostgreSQL URLs, connection pools, migration settings
- **Repository Management**: Base paths, size limits, Git configuration
- **Security Settings**: Secret keys, token expiration, authentication
- **SSH Server Settings**: Host keys, port, connection limits
- **File-based Secrets**: `__FILE` suffix pattern for loading secrets from files
- **Environment Overrides**: Development vs production configurations with conflict detection

The system must prevent common security vulnerabilities like exposed secrets, weak defaults, configuration injection attacks, and memory leakage of sensitive data.

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

🆕 **Enhanced Configuration Loading (Gitea Pattern)**:
```zig
const Config = struct {
    // Enhanced error types matching production reality
    pub const ConfigError = error{
        FileNotFound,
        ParseError,
        InvalidValue,
        MissingRequired,
        SecurityError,
        PermissionError,
        ConflictingConfiguration,     // NEW: Direct and __FILE env var conflict
        FileSizeTooLarge,            // NEW: Secret file too large
        EmptySecretFile,             // NEW: Secret file is empty
        PathNotAbsolute,             // NEW: Required path is not absolute
        PortConflict,                // NEW: Port conflicts detected
        WeakSecret,                  // NEW: Secret doesn't meet strength requirements
        OutOfMemory,
    };

    // Enhanced loading with conflict detection
    pub fn load(allocator: std.mem.Allocator, path: []const u8, clap_args: anytype) !Config {
        var config = Config.init(allocator);
        errdefer config.deinit(allocator);
        
        // 1. Parse INI file with absolute path validation
        try config.loadFromIniFile(allocator, path);
        
        // 2. Load environment variable overrides with conflict detection
        try config.loadEnvironmentOverrides(allocator);
        
        // 3. Override with CLI arguments
        try config.applyCliOverrides(clap_args);
        
        // 4. Load file-based secrets with validation
        try config.loadFileSecrets(allocator);
        
        // 5. Validate complete configuration
        try config.validateConfiguration();
        
        // 6. Log sanitized configuration (for debugging)
        try config.logConfiguration();
        
        return config;
    }
    
    // 🆕 Memory clearing for sensitive data (Gitea security pattern)
    pub fn clearSensitiveMemory(self: *Config) void {
        clearSensitiveData(self.security.secret_key);
        clearSensitiveData(self.database.password);
        clearSensitiveData(self.security.jwt_secret);
    }
};

// 🆕 Memory clearing helper (prevents compiler optimization)
fn clearSensitiveData(data: []u8) void {
    for (data) |*byte| {
        @volatileStore(u8, byte, 0);
    }
}
```

</expected_output>

<implementation_steps>

**CRITICAL**: Follow TDD approach - write tests first, then implementation. Run `zig build && zig build test` after EVERY change. Tests must be in the same file as source code.

**CRITICAL**: Zero tolerance for compilation or test failures. Any failing tests after your changes indicate YOU caused a regression.

<phase_1>
<title>Phase 1: Core Configuration Types and Enhanced Error Handling (TDD)</title>

1. **Create module and test data structures**
   ```bash
   mkdir -p src/config
   touch src/config/config.zig
   ```

2. **Write tests for configuration sections with enhanced validation**
   ```zig
   test "ServerConfig validates host and port with conflict detection" {
       const config = ServerConfig{
           .host = "127.0.0.1",
           .http_port = 8080,
           .ssh_port = 2222,
       };
       try testing.expect(config.isValid());
   }

   test "ServerConfig detects port conflicts" {
       const config = ServerConfig{
           .host = "127.0.0.1", 
           .http_port = 3000,
           .ssh_port = 3000, // Same port - should conflict
       };
       try testing.expectError(ConfigError.PortConflict, config.validate());
   }
   
   test "SecurityConfig detects weak secrets" {
       const config = SecurityConfig{
           .secret_key = "changeme", // Weak secret
       };
       try testing.expectError(ConfigError.WeakSecret, config.validate());
   }
   ```

3. **Implement configuration section types with enhanced validation**
4. **Add enhanced error types matching production reality**

</phase_1>

<phase_2>
<title>Phase 2: INI File Parsing and Validation (TDD)</title>

1. **Write tests for INI parsing with real files**
   ```zig
   test "parses valid INI configuration file" {
       const allocator = testing.allocator;
       const ini_content = 
           \\[server]
           \\host = 127.0.0.1
           \\port = 8080
           \\
           \\[database]
           \\connection_url = postgresql://localhost/test
       ;
       
       // Create temporary file
       const config = try Config.parseIni(allocator, ini_content);
       defer config.deinit(allocator);
       
       try testing.expectEqualStrings("127.0.0.1", config.server.host);
       try testing.expectEqual(@as(u16, 8080), config.server.port);
   }
   ```

2. **Implement robust INI parser with comment/whitespace handling**
3. **Add configuration file validation**
4. **Test malformed INI handling with detailed error reporting**

</phase_2>

<phase_3>
<title>Phase 3: File-based Secret Loading with Conflict Detection (TDD)</title>

1. **Write tests for file-based secret loading**
   ```zig
   test "loads secrets from files with __FILE suffix" {
       const allocator = testing.allocator;
       
       // Create temporary secret file
       const secret_content = "super-secret-password";
       const secret_file = "test_secret.txt";
       try std.fs.cwd().writeFile(secret_file, secret_content);
       defer std.fs.cwd().deleteFile(secret_file) catch {};
       
       // Set permissions to 0600
       try std.fs.cwd().chmod(secret_file, 0o600);
       
       // Set environment variable with __FILE suffix
       try std.os.setenv("PLUE_DATABASE_PASSWORD__FILE", secret_file);
       defer std.os.unsetenv("PLUE_DATABASE_PASSWORD__FILE") catch {};
       
       var config = Config.init(allocator);
       defer config.deinit(allocator);
       
       try config.loadEnvironmentOverrides(allocator);
       
       try testing.expectEqualStrings(secret_content, config.database.password);
   }
   
   test "detects conflicting direct and __FILE environment variables" {
       // Set both direct and __FILE environment variables
       try std.os.setenv("PLUE_DATABASE_PASSWORD", "direct-password");
       try std.os.setenv("PLUE_DATABASE_PASSWORD__FILE", "/path/to/file");
       defer std.os.unsetenv("PLUE_DATABASE_PASSWORD") catch {};
       defer std.os.unsetenv("PLUE_DATABASE_PASSWORD__FILE") catch {};
       
       const env_map = try std.process.getEnvMap(testing.allocator);
       defer env_map.deinit();
       
       // Should detect conflict
       try testing.expectError(ConfigError.ConflictingConfiguration, 
           checkForConflictingConfigurations(&env_map));
   }
   ```

2. **Implement `__FILE` suffix environment variable loading**
3. **Add URI-based secret loading (file:// scheme)**
4. **Implement conflict detection between direct and file-based secrets**
5. **Add secret file permission and size validation**

</phase_3>

<phase_4>
<title>Phase 4: Memory Security and Sensitive Data Handling (TDD)</title>

1. **Write tests for memory security**
   ```zig
   test "clears sensitive data from memory" {
       var sensitive_data = [_]u8{ 'p', 'a', 's', 's', 'w', 'o', 'r', 'd' };
       
       clearSensitiveMemory(&sensitive_data);
       
       // Verify all bytes are cleared
       for (sensitive_data) |byte| {
           try testing.expect(byte == 0);
       }
   }
   
   test "redacts sensitive values in logging" {
       const allocator = testing.allocator;
       
       var config = Config.init(allocator);
       defer config.deinit(allocator);
       
       config.security.secret_key = "actual-secret-key";
       config.database.password = "actual-password";
       
       const sanitized = sanitizeForLogging(&config);
       
       try testing.expectEqualStrings("[REDACTED]", sanitized.security.secret_key);
       try testing.expectEqualStrings("[REDACTED]", sanitized.database.password);
   }
   ```

2. **Implement memory clearing with `@volatileStore`**
3. **Add automatic redaction for logging**
4. **Test secure file permission validation**

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

1. **All tests pass**: `zig build test` shows 100% success rate
2. **🆕 File-based Secret Loading**: `__FILE` suffix and URI schemes work correctly
3. **🆕 Conflict Detection**: Prevents runtime issues from conflicting configurations
4. **🆕 Memory Security**: Sensitive data clearing verified with `@volatileStore`
5. **Memory safety**: Zero memory leaks detected
6. **Security compliance**: File permissions and secret handling validated
7. **Type safety**: All configuration access is compile-time validated
8. **Error handling**: Comprehensive error messages for all failure cases
9. **Documentation**: All public APIs documented with examples
10. **Integration ready**: Ready for use by SSH server, HTTP server, and database modules

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

</reference_implementations>