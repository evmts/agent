# Implement Advanced Configuration Management Module

<task_definition>
Enhance the configuration management system with advanced features including configuration validation, hot reloading, environment-specific configurations, and integration with the existing SSH server and database systems. This builds upon the basic configuration module to provide enterprise-grade configuration management with comprehensive security and operational features.
</task_definition>

<context_and_constraints>

<technical_requirements>

- **Language/Framework**: Zig - https://ziglang.org/documentation/master/
- **Dependencies**: Builds on basic configuration module from issue #15
- **Location**: Extensions to `src/config/config.zig` and new `src/config/` modules
- **Features**: Hot reloading, validation schemas, environment profiles
- **Security**: Configuration encryption, audit logging, change detection
- **Memory**: Efficient change detection, minimal allocation overhead
- **Integration**: SSH server config, database config, HTTP server config

</technical_requirements>

<business_context>

Advanced configuration management is required for production deployments:

- **Hot Reloading**: Update configuration without service restart
- **Environment Profiles**: Development, staging, production configurations
- **Configuration Validation**: Schema validation with detailed error reporting
- **Change Auditing**: Track configuration changes for compliance
- **Secret Management**: Encrypted configuration values and secure key rotation
- **Service Integration**: Seamless integration with all Plue services

This enables zero-downtime configuration updates and ensures configuration consistency across environments.

</business_context>

</context_and_constraints>

<detailed_specifications>

<input>

Extended configuration features:

1. **Environment Profiles**:
   ```ini
   # config/development.ini
   [server]
   host = 127.0.0.1
   port = 8080
   debug = true
   
   # config/production.ini
   [server]
   host = 0.0.0.0
   port = 80
   debug = false
   ```

2. **Configuration Schema**:
   ```zig
   const ConfigSchema = struct {
       server: ServerSchema,
       database: DatabaseSchema,
       ssh: SshSchema,
       
       const ServerSchema = struct {
           host: SchemaField(.string, .{ .required = true }),
           port: SchemaField(.integer, .{ .min = 1, .max = 65535 }),
           debug: SchemaField(.boolean, .{ .default = false }),
       };
   };
   ```

3. **Hot Reload Triggers**:
   - File system change detection
   - Signal-based reload (SIGHUP)
   - Admin API configuration endpoint
   - Automatic validation before applying changes

4. **Secret Management**:
   ```ini
   [security]
   secret_key = ${PLUE_SECRET_KEY}
   database_password = ${PLUE_DB_PASSWORD}
   jwt_secret = ${PLUE_JWT_SECRET}
   ```

</input>

<expected_output>

Advanced configuration system providing:

1. **Hot Reload Manager**: Monitor and apply configuration changes
2. **Environment Profiles**: Development, staging, production configurations
3. **Schema Validation**: Comprehensive validation with detailed error reporting
4. **Change Auditing**: Log all configuration changes with timestamps
5. **Secret Management**: Encrypted values and environment variable substitution
6. **Service Integration**: Automatic service reconfiguration on changes
7. **Configuration API**: REST endpoints for configuration management
8. **Backup and Rollback**: Configuration versioning and rollback capability

Example advanced API:
```zig
// Configuration manager with hot reloading
var config_manager = try ConfigManager.init(allocator, .{
    .config_dir = "/etc/plue/",
    .environment = .production,
    .hot_reload = true,
    .audit_enabled = true,
});
defer config_manager.deinit(allocator);

// Register change callback
try config_manager.onConfigChange(allocator, onServerConfigChanged);

// Get current configuration
const config = config_manager.getCurrentConfig();

// Validate new configuration
const validation_result = try config_manager.validateConfig(allocator, new_config_content);
if (!validation_result.isValid()) {
    for (validation_result.errors) |error_msg| {
        log.err("Validation error: {s}", .{error_msg});
    }
}

// Apply configuration with rollback support
try config_manager.applyConfig(allocator, new_config_content, .{ .backup = true });
```

</expected_output>

<implementation_steps>

**CRITICAL**: Follow TDD approach. Build on existing configuration module. Run `zig build && zig build test` after EVERY change.

**CRITICAL**: Zero tolerance for regressions. All existing configuration tests must continue passing.

<phase_1>
<title>Phase 1: Configuration Schema and Validation Framework (TDD)</title>

1. **Write tests for configuration schema**
   ```zig
   test "configuration schema validates server section" {
       const schema = ConfigSchema{};
       const config_data = .{
           .server = .{
               .host = "127.0.0.1",
               .port = 8080,
               .debug = true,
           },
       };
       
       const validation_result = try schema.validate(allocator, config_data);
       try testing.expect(validation_result.isValid());
   }
   
   test "schema validation reports detailed errors" {
       const schema = ConfigSchema{};
       const invalid_config = .{
           .server = .{
               .host = "", // Invalid empty host
               .port = 99999, // Invalid port range
           },
       };
       
       const validation_result = try schema.validate(allocator, invalid_config);
       try testing.expect(!validation_result.isValid());
       try testing.expect(validation_result.errors.len >= 2);
   }
   ```

2. **Implement configuration schema framework**
3. **Add detailed validation error reporting**
4. **Test complex validation rules**

</phase_1>

<phase_2>
<title>Phase 2: Environment Profile Management (TDD)</title>

1. **Write tests for environment profiles**
   ```zig
   test "loads development environment configuration" {
       const allocator = testing.allocator;
       
       // Create temporary config files
       const dev_config = try createTempConfig(allocator, "development", dev_config_content);
       defer dev_config.cleanup();
       
       var manager = try ConfigManager.init(allocator, .{
           .config_dir = dev_config.dir_path,
           .environment = .development,
       });
       defer manager.deinit(allocator);
       
       const config = manager.getCurrentConfig();
       try testing.expect(config.server.debug);
       try testing.expectEqualStrings("127.0.0.1", config.server.host);
   }
   ```

2. **Implement environment profile loading**
3. **Add profile inheritance and overrides**
4. **Test profile validation and merging**

</phase_2>

<phase_3>
<title>Phase 3: Hot Reload and Change Detection (TDD)</title>

1. **Write tests for file change detection**
   ```zig
   test "detects configuration file changes" {
       const allocator = testing.allocator;
       
       var manager = try ConfigManager.init(allocator, .{
           .hot_reload = true,
           .poll_interval_ms = 100,
       });
       defer manager.deinit(allocator);
       
       var change_detected = false;
       try manager.onConfigChange(allocator, struct {
           fn callback(old_config: *const Config, new_config: *const Config, ctx: *anyopaque) void {
               _ = old_config;
               _ = new_config;
               const flag = @as(*bool, @ptrCast(@alignCast(ctx)));
               flag.* = true;
           }
       }.callback, &change_detected);
       
       // Modify configuration file
       try modifyConfigFile(manager.config_file_path, "port = 9090");
       
       // Wait for change detection
       std.time.sleep(200 * std.time.ns_per_ms);
       try testing.expect(change_detected);
   }
   ```

2. **Implement file system change monitoring**
3. **Add configuration change callbacks**
4. **Test hot reload error handling**

</phase_3>

<phase_4>
<title>Phase 4: Secret Management and Security (TDD)</title>

1. **Write tests for secret substitution**
   ```zig
   test "substitutes environment variables in configuration" {
       const allocator = testing.allocator;
       
       // Set test environment variable
       try std.process.putEnv(allocator, "TEST_SECRET", "super_secret_value");
       defer std.process.delEnv("TEST_SECRET");
       
       const config_content = 
           \\[security]
           \\secret_key = ${TEST_SECRET}
       ;
       
       const config = try Config.parseWithSubstitution(allocator, config_content);
       defer config.deinit(allocator);
       
       try testing.expectEqualStrings("super_secret_value", config.security.secret_key);
   }
   ```

2. **Implement environment variable substitution**
3. **Add configuration encryption support**
4. **Test secret sanitization for logging**

</phase_4>

<phase_5>
<title>Phase 5: Service Integration and Change Management (TDD)</title>

1. **Write tests for service integration**
   ```zig
   test "notifies SSH server of configuration changes" {
       const allocator = testing.allocator;
       
       var ssh_server = try SshServer.init(allocator, initial_config.ssh);
       defer ssh_server.deinit();
       
       var config_manager = try ConfigManager.init(allocator, .{});
       defer config_manager.deinit(allocator);
       
       // Register SSH server for config updates
       try config_manager.registerService(allocator, &ssh_server);
       
       // Update SSH configuration
       const new_ssh_config = SshConfig{ .port = 2222, .max_connections = 200 };
       try config_manager.updateSshConfig(allocator, new_ssh_config);
       
       // Verify SSH server was updated
       try testing.expectEqual(@as(u16, 2222), ssh_server.config.port);
   }
   ```

2. **Implement service registration and notification**
3. **Add configuration change management**
4. **Test rollback and backup functionality**

</phase_5>

<phase_6>
<title>Phase 6: Configuration API and Audit Logging (TDD)</title>

1. **Write tests for configuration API**
2. **Implement REST endpoints for configuration management**
3. **Add comprehensive audit logging**
4. **Test configuration versioning and history**

</phase_6>

</implementation_steps>

</detailed_specifications>

<quality_assurance>

<testing_requirements>

- **File System Testing**: Real file operations with temporary directories
- **Concurrency Testing**: Hot reload with concurrent access
- **Integration Testing**: Test with actual SSH and HTTP servers
- **Security Testing**: Secret handling and permission validation
- **Performance Testing**: Large configuration files and frequent changes
- **Error Recovery**: Test recovery from invalid configurations

</testing_requirements>

<success_criteria>

1. **All tests pass**: Including existing configuration module tests
2. **Hot reload functionality**: Configuration changes without service restart
3. **Schema validation**: Comprehensive validation with detailed error reporting
4. **Security compliance**: Secret management and audit logging
5. **Service integration**: SSH and HTTP servers respond to configuration changes
6. **Performance**: Minimal overhead for configuration monitoring
7. **Documentation**: Complete API documentation with examples

</success_criteria>

</quality_assurance>

<reference_implementations>

- **Hot reload patterns**: File system monitoring and signal handling
- **Configuration validation**: JSON Schema and similar validation frameworks
- **Secret management**: HashiCorp Vault and Kubernetes secrets patterns
- **Service integration**: Observer pattern and event-driven architecture

</reference_implementations>