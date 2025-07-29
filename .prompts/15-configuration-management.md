# Implement Configuration Management Module

<task_definition>
Implement a comprehensive configuration management system for the Plue application that handles INI-style configuration files, environment variable overrides, and command-line arguments. This module will provide type-safe access to all application settings with secure defaults, validation, and proper memory management following Plue's strict coding standards.
</task_definition>

<context_and_constraints>

<technical_requirements>

- **Language/Framework**: Zig - https://ziglang.org/documentation/master/
- **Dependencies**: None (uses only Zig standard library)
- **File Format**: INI-style configuration files with section support
- **Location**: `src/config/config.zig`
- **Security**: File permission validation, secure defaults, secret sanitization
- **Memory**: Zero allocator storage in structs, explicit defer patterns
- **Testing**: Real file I/O tests, no mocking, comprehensive validation

</technical_requirements>

<business_context>

Plue requires centralized configuration management to handle:

- **Server Configuration**: Host, port, worker threads, timeouts
- **Database Settings**: PostgreSQL URLs, connection pools, migration settings
- **Repository Management**: Base paths, size limits, Git configuration
- **Security Settings**: Secret keys, token expiration, authentication
- **SSH Server Settings**: Host keys, port, connection limits
- **Environment Overrides**: Development vs production configurations

The system must prevent common security vulnerabilities like exposed secrets, weak defaults, and configuration injection attacks.

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

Environment variable mapping:
- `PLUE_SERVER_HOST` → `[server] host`
- `PLUE_DATABASE_URL` → `[database] connection_url`
- `PLUE_SECRET_KEY` → `[security] secret_key`

</input>

<expected_output>

A complete configuration system providing:

1. **Type-safe configuration structure** with all application settings
2. **Multi-source loading** with proper precedence handling
3. **Comprehensive validation** with detailed error messages
4. **Security features** including secret sanitization and permission checks
5. **Memory safety** with explicit allocation/deallocation patterns
6. **Environment detection** for development vs production settings
7. **Configuration reload** capability for runtime updates
8. **Logging integration** with secure value masking

Example API usage:
```zig
// Load configuration
var config = try Config.load(allocator, config_file_path);
defer config.deinit(allocator);

// Type-safe access
const server_port = config.server.port;
const db_url = config.database.connection_url;
const secret = config.security.secret_key;

// Validation results
if (!config.isValid()) {
    for (config.getValidationErrors()) |error_msg| {
        log.err("Config error: {s}", .{error_msg});
    }
}

// Environment detection
if (config.isDevelopment()) {
    log.info("Running in development mode");
}
```

</expected_output>

<implementation_steps>

**CRITICAL**: Follow TDD approach - write tests first, then implementation. Run `zig build && zig build test` after EVERY change. Tests must be in the same file as source code.

**CRITICAL**: Zero tolerance for compilation or test failures. Any failing tests after your changes indicate YOU caused a regression.

<phase_1>
<title>Phase 1: Core Configuration Types and Validation (TDD)</title>

1. **Create module and test data structures**
   ```bash
   mkdir -p src/config
   touch src/config/config.zig
   ```

2. **Write tests for configuration sections**
   ```zig
   test "ServerConfig validates host and port" {
       const config = ServerConfig{
           .host = "127.0.0.1",
           .port = 8080,
           .worker_threads = 4,
           .read_timeout = 30,
           .write_timeout = 30,
       };
       try testing.expect(config.isValid());
   }

   test "ServerConfig rejects invalid port" {
       const config = ServerConfig{
           .host = "127.0.0.1", 
           .port = 0, // Invalid
           .worker_threads = 4,
           .read_timeout = 30,
           .write_timeout = 30,
       };
       try testing.expect(!config.isValid());
   }
   ```

3. **Implement configuration section types**
   ```zig
   const ServerConfig = struct {
       host: []const u8,
       port: u16,
       worker_threads: u32,
       read_timeout: u32,
       write_timeout: u32,

       pub fn isValid(self: *const ServerConfig) bool {
           return self.port > 0 and self.port <= 65535 and
                  self.worker_threads > 0 and self.worker_threads <= 1000;
       }
   };
   ```

</phase_1>

<phase_2>
<title>Phase 2: INI File Parsing and Validation (TDD)</title>

1. **Write tests for INI parsing**
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

2. **Implement INI parser with error handling**
3. **Add configuration file validation**
4. **Test malformed INI handling**

</phase_2>

<phase_3>
<title>Phase 3: Environment Variable Override System (TDD)</title>

1. **Write tests for environment variable parsing**
2. **Implement environment variable mapping**
3. **Test precedence order (env vars override file values)**
4. **Add environment variable validation**

</phase_3>

<phase_4>
<title>Phase 4: Security and File Permission Validation (TDD)</title>

1. **Write tests for file permission checking**
   ```zig
   test "rejects configuration file with unsafe permissions" {
       // Create file with 0644 permissions
       // Should warn or reject for security-sensitive configs
   }
   ```

2. **Implement secure default values**
3. **Add secret key validation and generation**
4. **Test configuration sanitization for logging**

</phase_4>

<phase_5>
<title>Phase 5: Complete Configuration API and Integration (TDD)</title>

1. **Write tests for complete configuration loading**
2. **Implement main Config struct with all sections**
3. **Add configuration validation and error reporting**
4. **Test memory management and cleanup**
5. **Add configuration reload capability**

</phase_5>

</implementation_steps>

</detailed_specifications>

<quality_assurance>

<testing_requirements>

- **File I/O Testing**: Use real files, no mocking
- **Error Handling**: Test all failure scenarios (missing files, malformed content, permission errors)
- **Memory Safety**: Verify no leaks with comprehensive allocation tracking
- **Security**: Test file permission validation and secret sanitization
- **Integration**: Test with actual environment variables and command-line args
- **Performance**: Validate parsing performance with large configuration files

</testing_requirements>

<success_criteria>

1. **All tests pass**: `zig build test` shows 100% success rate
2. **Memory safety**: Zero memory leaks detected
3. **Security compliance**: File permissions and secret handling validated
4. **Type safety**: All configuration access is compile-time validated
5. **Error handling**: Comprehensive error messages for all failure cases
6. **Documentation**: All public APIs documented with examples
7. **Integration ready**: Ready for use by SSH server, HTTP server, and database modules

</success_criteria>

</quality_assurance>

<reference_implementations>

- **Zig INI parsing**: Standard library examples and community implementations
- **Configuration patterns**: Common configuration management practices in systems programming
- **Security standards**: OWASP configuration security guidelines
- **Gitea configuration**: Reference implementation for Git hosting configuration

</reference_implementations>