# Implement Configuration Integration System

## Context

You are implementing the configuration integration system that merges Plue's configuration with OpenCode's settings. This ensures both systems work harmoniously while maintaining Plue's configuration precedence.

### Project State

From previous tasks, you have:
- OpenCode server management
- All API bridges (session, message, provider, tool)
- Working communication between Plue and OpenCode

Now you need to create a unified configuration system.

### Configuration API Requirements (from PLUE_CORE_API.md)

```c
// Load configuration from default locations
export fn plue_config_load() c_int;

// Get current configuration as JSON
export fn plue_config_get() [*c]u8;

// Update configuration
export fn plue_config_update(config_json: [*:0]const u8, persist: bool) c_int;

// Get configuration schema as JSON Schema
export fn plue_config_get_schema() [*c]u8;
```

### Configuration Sources

Both Plue and OpenCode support multiple configuration sources:

1. **Global Config**: 
   - Plue: `~/.config/plue/config.json`
   - OpenCode: `~/.config/opencode/config.json`

2. **Project Config**: 
   - Plue: `.plue/config.json` in git root
   - OpenCode: `opencode.json` or `opencode.jsonc` (searches upward)

3. **Environment Variables**: 
   - Plue: `PLUE_*` prefix
   - OpenCode: Provider-specific env vars (e.g., `ANTHROPIC_API_KEY`)

4. **Runtime Updates**: Programmatic configuration changes

5. **OpenCode Specifics**:
   - Searches upward for `opencode.json[c]` files
   - Deep merges configs from root to current directory
   - Auto-migrates legacy TOML configs to JSON
   - Caches model data from https://models.dev/api.json

### OpenCode Configuration Structure

```typescript
// OpenCode config schema (actual from implementation)
interface OpenCodeConfig {
  $schema?: string;        // JSON schema reference
  theme?: string;          // Theme name (not limited to light/dark)
  keybinds?: Record<string, string>; // ~25 configurable actions
  autoshare?: boolean;     // Auto-share new sessions
  autoupdate?: boolean;    // Auto-update OpenCode
  disabled_providers?: string[]; // Providers to disable
  model?: string;          // Format: "provider/model-id"
  
  // Provider configurations with model overrides
  provider?: {
    [providerId: string]: {
      api?: string;        // API endpoint override
      name?: string;       // Display name
      env?: string[];      // Required env vars
      models?: {           // Model overrides
        [modelId: string]: {
          name?: string;
          attachment?: boolean;
          reasoning?: boolean;
          temperature?: boolean;
          tool_call?: boolean;
          cost?: {
            input: number;
            output: number;
            cache_read?: number;
            cache_write?: number;
          };
          limit?: {
            context: number;
            output: number;
          };
          options?: Record<string, any>;
        };
      };
      options?: Record<string, any>; // Provider-specific options
    };
  };
  
  // MCP (Model Context Protocol) servers
  mcp?: Record<string, MCPServerConfig>;
}

// MCP server types
type MCPServerConfig = 
  | { type: "local"; command: string[]; environment?: Record<string, string> }
  | { type: "remote"; url: string };

// Important: No separate tool config - tools configured via providers
```

## Requirements

### 1. Configuration Types (`src/config/types.zig`)

Define unified configuration structure:

```zig
const std = @import("std");

pub const ConfigSource = enum {
    defaults,
    global_opencode,
    global_plue,
    project_opencode,
    project_plue,
    environment,
    runtime,
    
    pub fn getPriority(self: ConfigSource) u8 {
        // Higher number = higher priority
        return switch (self) {
            .defaults => 0,
            .global_opencode => 1,
            .global_plue => 2,
            .project_opencode => 3,
            .project_plue => 4,
            .environment => 5,
            .runtime => 6,
        };
    }
};

pub const Theme = enum {
    light,
    dark,
    system,
    
    pub fn jsonStringify(self: Theme, writer: anytype) !void {
        try writer.writeAll(@tagName(self));
    }
};

pub const PlueConfig = struct {
    /// UI theme
    theme: Theme = .system,
    
    /// Provider configurations
    providers: std.json.ObjectMap = .{},
    
    /// Tool configurations
    tools: ToolConfig = .{},
    
    /// Keybindings
    keybindings: std.StringHashMap([]const u8) = .{},
    
    /// Server configuration
    server: ServerConfig = .{},
    
    /// Experimental features
    experimental: std.StringHashMap(bool) = .{},
    
    /// Plue-specific settings
    plue: PlueSpecificConfig = .{},
    
    /// OpenCode passthrough settings
    opencode: std.json.Value = .{ .null = {} },
};

pub const ToolConfig = struct {
    /// Bash tool settings
    bash: struct {
        default_timeout_ms: u32 = 120000,
        shell: []const u8 = "/bin/bash",
        env_filter: []const []const u8 = &.{},
    } = .{},
    
    /// File tool settings
    file: struct {
        max_file_size: usize = 10 * 1024 * 1024, // 10MB
        allowed_extensions: ?[]const []const u8 = null,
        ignored_patterns: []const []const u8 = &.{ "*.pyc", "__pycache__", ".git" },
    } = .{},
    
    /// Web fetch settings
    web_fetch: struct {
        timeout_ms: u32 = 30000,
        max_response_size: usize = 5 * 1024 * 1024, // 5MB
        allowed_domains: ?[]const []const u8 = null,
    } = .{},
};

pub const ServerConfig = struct {
    /// OpenCode server port
    opencode_port: u16 = 3000,
    
    /// OpenCode server host
    opencode_host: []const u8 = "127.0.0.1",
    
    /// Auto-start OpenCode server
    auto_start: bool = true,
    
    /// Server startup timeout
    startup_timeout_ms: u32 = 30000,
    
    /// Health check interval
    health_check_interval_ms: u32 = 5000,
};

pub const PlueSpecificConfig = struct {
    /// Session auto-save interval
    auto_save_interval_ms: u32 = 60000,
    
    /// Maximum session history
    max_session_history: u32 = 100,
    
    /// Enable telemetry
    telemetry_enabled: bool = false,
    
    /// Log level
    log_level: LogLevel = .info,
    
    /// Custom prompts directory
    prompts_dir: ?[]const u8 = null,
};

pub const LogLevel = enum {
    trace,
    debug,
    info,
    warn,
    err,
    fatal,
};

pub const ConfigValue = struct {
    value: std.json.Value,
    source: ConfigSource,
    timestamp: i64,
};

pub const ConfigSchema = struct {
    /// JSON Schema for validation
    schema: std.json.Value,
    
    /// Version of the schema
    version: []const u8,
};
```

### 2. Configuration Manager (`src/config/manager.zig`)

Core configuration management:

```zig
pub const ConfigManager = struct {
    allocator: std.mem.Allocator,
    config: PlueConfig,
    values: std.StringHashMap(ConfigValue),
    watchers: std.ArrayList(ConfigWatcher),
    paths: ConfigPaths,
    mutex: std.Thread.Mutex,
    
    pub const ConfigPaths = struct {
        home_dir: []const u8,
        project_dir: ?[]const u8,
        global_plue: []const u8,
        global_opencode: []const u8,
        project_plue: ?[]const u8,
        project_opencode: ?[]const u8,
    };
    
    pub const ConfigWatcher = struct {
        callback: *const fn (key: []const u8, old_value: ?std.json.Value, new_value: std.json.Value) void,
        filter: ?[]const u8 = null,
    };
    
    /// Initialize configuration manager
    pub fn init(allocator: std.mem.Allocator) !ConfigManager {
        const home_dir = try std.process.getEnvVarOwned(allocator, "HOME");
        const project_dir = try findProjectRoot(allocator);
        
        const paths = ConfigPaths{
            .home_dir = home_dir,
            .project_dir = project_dir,
            .global_plue = try std.fs.path.join(allocator, &.{ home_dir, ".config", "plue", "config.json" }),
            .global_opencode = try std.fs.path.join(allocator, &.{ home_dir, ".config", "opencode", "config.json" }),
            .project_plue = if (project_dir) |pd| try std.fs.path.join(allocator, &.{ pd, ".plue", "config.json" }) else null,
            .project_opencode = if (project_dir) |pd| try std.fs.path.join(allocator, &.{ pd, ".opencode", "config.json" }) else null,
        };
        
        return ConfigManager{
            .allocator = allocator,
            .config = .{},
            .values = std.StringHashMap(ConfigValue).init(allocator),
            .watchers = std.ArrayList(ConfigWatcher).init(allocator),
            .paths = paths,
            .mutex = .{},
        };
    }
    
    /// Load all configuration sources
    pub fn load(self: *ConfigManager) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        // Clear existing values
        self.values.clearAndFree();
        
        // Load in priority order
        try self.loadDefaults();
        try self.loadFile(self.paths.global_opencode, .global_opencode);
        try self.loadFile(self.paths.global_plue, .global_plue);
        if (self.paths.project_opencode) |path| {
            try self.loadFile(path, .project_opencode);
        }
        if (self.paths.project_plue) |path| {
            try self.loadFile(path, .project_plue);
        }
        try self.loadEnvironment();
        
        // Merge into final config
        try self.mergeConfig();
        
        // Validate against schema
        try self.validate();
        
        // Notify watchers
        self.notifyWatchers();
    }
    
    /// Load default configuration
    fn loadDefaults(self: *ConfigManager) !void {
        const defaults = .{
            .theme = "system",
            .server = .{
                .opencode_port = 3000,
                .auto_start = true,
            },
            .plue = .{
                .log_level = "info",
            },
        };
        
        const json_value = try std.json.parseFromValue(
            std.json.Value,
            self.allocator,
            defaults,
            .{},
        );
        
        try self.addValues(json_value, .defaults);
    }
    
    /// Load configuration from file
    fn loadFile(self: *ConfigManager, path: []const u8, source: ConfigSource) !void {
        const file = std.fs.openFileAbsolute(path, .{}) catch |err| {
            if (err == error.FileNotFound) return;
            return err;
        };
        defer file.close();
        
        const content = try file.readToEndAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(content);
        
        const parsed = try std.json.parseFromSlice(
            std.json.Value,
            self.allocator,
            content,
            .{},
        );
        defer parsed.deinit();
        
        try self.addValues(parsed.value, source);
    }
    
    /// Load environment variables
    fn loadEnvironment(self: *ConfigManager) !void {
        var env_map = try std.process.getEnvMap(self.allocator);
        defer env_map.deinit();
        
        var env_config = std.json.ObjectMap.init(self.allocator);
        
        var it = env_map.iterator();
        while (it.next()) |entry| {
            // Handle PLUE_ prefixed variables
            if (std.mem.startsWith(u8, entry.key_ptr.*, "PLUE_")) {
                const key = entry.key_ptr.*[5..]; // Skip "PLUE_"
                const path = try parseEnvKey(self.allocator, key);
                try setNestedValue(&env_config, path, .{ .string = entry.value_ptr.* });
            }
            
            // Handle OPENCODE_ variables for compatibility
            if (std.mem.startsWith(u8, entry.key_ptr.*, "OPENCODE_")) {
                const key = entry.key_ptr.*[9..]; // Skip "OPENCODE_"
                const path = try parseEnvKey(self.allocator, key);
                try setNestedValue(&env_config, path, .{ .string = entry.value_ptr.* });
            }
        }
        
        try self.addValues(.{ .object = env_config }, .environment);
    }
    
    /// Add values from a source
    fn addValues(self: *ConfigManager, value: std.json.Value, source: ConfigSource) !void {
        const timestamp = std.time.milliTimestamp();
        try self.addValuesRecursive("", value, source, timestamp);
    }
    
    /// Recursively add values
    fn addValuesRecursive(
        self: *ConfigManager,
        prefix: []const u8,
        value: std.json.Value,
        source: ConfigSource,
        timestamp: i64,
    ) !void {
        switch (value) {
            .object => |obj| {
                var it = obj.iterator();
                while (it.next()) |entry| {
                    const key = if (prefix.len > 0)
                        try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ prefix, entry.key_ptr.* })
                    else
                        entry.key_ptr.*;
                    
                    try self.addValuesRecursive(key, entry.value_ptr.*, source, timestamp);
                }
            },
            else => {
                const config_value = ConfigValue{
                    .value = value,
                    .source = source,
                    .timestamp = timestamp,
                };
                
                // Only add if higher priority or doesn't exist
                if (self.values.get(prefix)) |existing| {
                    if (source.getPriority() >= existing.source.getPriority()) {
                        try self.values.put(prefix, config_value);
                    }
                } else {
                    try self.values.put(prefix, config_value);
                }
            },
        }
    }
    
    /// Merge values into final config
    fn mergeConfig(self: *ConfigManager) !void {
        // Convert flat values back to nested structure
        var result = std.json.ObjectMap.init(self.allocator);
        
        var it = self.values.iterator();
        while (it.next()) |entry| {
            const path = try std.mem.split(u8, entry.key_ptr.*, ".");
            try setNestedValue(&result, path, entry.value_ptr.value);
        }
        
        // Parse into PlueConfig
        self.config = try std.json.parseFromValue(
            PlueConfig,
            self.allocator,
            .{ .object = result },
            .{ .ignore_unknown_fields = true },
        );
    }
    
    /// Update configuration
    pub fn update(self: *ConfigManager, updates: std.json.Value, persist: bool) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        // Add updates with runtime source
        try self.addValues(updates, .runtime);
        
        // Remerge config
        try self.mergeConfig();
        
        // Validate
        try self.validate();
        
        // Persist if requested
        if (persist) {
            try self.save();
        }
        
        // Notify watchers
        self.notifyWatchers();
    }
    
    /// Save configuration to appropriate location
    fn save(self: *ConfigManager) !void {
        // Determine where to save based on what exists
        const save_path = self.paths.project_plue orelse self.paths.global_plue;
        
        // Create directory if needed
        const dir_path = std.fs.path.dirname(save_path) orelse return error.InvalidPath;
        try std.fs.makeDirAbsolute(dir_path);
        
        // Filter runtime values for saving
        var save_config = std.json.ObjectMap.init(self.allocator);
        defer save_config.deinit();
        
        var it = self.values.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.source == .runtime or
                entry.value_ptr.source == .project_plue or
                entry.value_ptr.source == .global_plue) {
                const path = try std.mem.split(u8, entry.key_ptr.*, ".");
                try setNestedValue(&save_config, path, entry.value_ptr.value);
            }
        }
        
        // Write to file
        const json_string = try std.json.stringifyAlloc(
            self.allocator,
            std.json.Value{ .object = save_config },
            .{ .whitespace = .indent_2 },
        );
        defer self.allocator.free(json_string);
        
        try std.fs.cwd().writeFile(save_path, json_string);
    }
    
    /// Get configuration as JSON
    pub fn getJson(self: *ConfigManager) !std.json.Value {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        return try std.json.parseFromValue(
            std.json.Value,
            self.allocator,
            self.config,
            .{},
        );
    }
    
    /// Get specific value
    pub fn getValue(self: *ConfigManager, key: []const u8) ?ConfigValue {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        return self.values.get(key);
    }
    
    /// Validate configuration
    fn validate(self: *ConfigManager) !void {
        // Basic validation rules
        if (self.config.server.opencode_port == 0) {
            return error.InvalidPort;
        }
        
        if (self.config.server.health_check_interval_ms < 1000) {
            return error.IntervalTooSmall;
        }
        
        // Validate provider configs
        var it = self.config.providers.iterator();
        while (it.next()) |entry| {
            const provider_config = entry.value_ptr.*;
            if (provider_config.object.get("apiKey")) |key| {
                if (key.string.len == 0) {
                    return error.EmptyApiKey;
                }
            }
        }
    }
    
    /// Watch for configuration changes
    pub fn watch(self: *ConfigManager, watcher: ConfigWatcher) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        try self.watchers.append(watcher);
    }
    
    /// Notify watchers of changes
    fn notifyWatchers(self: *ConfigManager) void {
        for (self.watchers.items) |watcher| {
            // TODO: Track actual changes and call watchers
        }
    }
};

/// Find project root by looking for .git directory
fn findProjectRoot(allocator: std.mem.Allocator) !?[]const u8 {
    var current_dir = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(current_dir);
    
    while (true) {
        const git_path = try std.fs.path.join(allocator, &.{ current_dir, ".git" });
        defer allocator.free(git_path);
        
        if (std.fs.accessAbsolute(git_path, .{})) {
            return try allocator.dupe(u8, current_dir);
        } else |_| {}
        
        const parent = std.fs.path.dirname(current_dir) orelse break;
        if (std.mem.eql(u8, parent, current_dir)) break;
        
        const new_dir = try allocator.dupe(u8, parent);
        allocator.free(current_dir);
        current_dir = new_dir;
    }
    
    return null;
}

/// Parse environment variable key (THEME -> theme, SERVER_PORT -> server.port)
fn parseEnvKey(allocator: std.mem.Allocator, key: []const u8) ![][]const u8 {
    var parts = std.ArrayList([]const u8).init(allocator);
    
    var it = std.mem.tokenize(u8, key, "_");
    while (it.next()) |part| {
        // Convert to lowercase
        const lower = try std.ascii.allocLowerString(allocator, part);
        try parts.append(lower);
    }
    
    return parts.toOwnedSlice();
}

/// Set nested value in object map
fn setNestedValue(
    map: *std.json.ObjectMap,
    path: [][]const u8,
    value: std.json.Value,
) !void {
    if (path.len == 0) return;
    
    if (path.len == 1) {
        try map.put(path[0], value);
        return;
    }
    
    // Get or create nested object
    const key = path[0];
    var nested = if (map.get(key)) |existing|
        switch (existing) {
            .object => |obj| obj,
            else => std.json.ObjectMap.init(map.allocator),
        }
    else
        std.json.ObjectMap.init(map.allocator);
    
    try setNestedValue(&nested, path[1..], value);
    try map.put(key, .{ .object = nested });
}
```

### 3. FFI Implementation (`src/config/ffi.zig`)

Implement C FFI functions:

```zig
const std = @import("std");
const c = @cImport({});
const ConfigManager = @import("manager.zig").ConfigManager;
const error_handling = @import("../error/handling.zig");

/// Global config manager
var config_manager: ?*ConfigManager = null;

/// Initialize config manager
pub fn init(allocator: std.mem.Allocator) !void {
    config_manager = try allocator.create(ConfigManager);
    config_manager.?.* = try ConfigManager.init(allocator);
}

/// Load configuration from default locations
export fn plue_config_load() c_int {
    const manager = config_manager orelse {
        error_handling.setLastError(error.NotInitialized, "Config manager not initialized");
        return -1;
    };
    
    manager.load() catch |err| {
        error_handling.setLastError(err, "Failed to load configuration");
        return -1;
    };
    
    return 0;
}

/// Get current configuration as JSON
export fn plue_config_get() [*c]u8 {
    const manager = config_manager orelse {
        error_handling.setLastError(error.NotInitialized, "Config manager not initialized");
        return null;
    };
    
    const config_json = manager.getJson() catch |err| {
        error_handling.setLastError(err, "Failed to get configuration");
        return null;
    };
    
    const json_string = std.json.stringifyAlloc(
        manager.allocator,
        config_json,
        .{ .whitespace = .indent_2 },
    ) catch |err| {
        error_handling.setLastError(err, "Failed to serialize configuration");
        return null;
    };
    
    return json_string.ptr;
}

/// Update configuration
export fn plue_config_update(config_json: [*:0]const u8, persist: bool) c_int {
    if (config_json == null) {
        error_handling.setLastError(error.InvalidParam, "Config JSON is null");
        return -1;
    }
    
    const manager = config_manager orelse {
        error_handling.setLastError(error.NotInitialized, "Config manager not initialized");
        return -1;
    };
    
    const json_slice = std.mem.span(config_json);
    
    // Parse updates
    const updates = std.json.parseFromSlice(
        std.json.Value,
        manager.allocator,
        json_slice,
        .{},
    ) catch |err| {
        error_handling.setLastError(err, "Failed to parse configuration");
        return -1;
    };
    defer updates.deinit();
    
    // Apply updates
    manager.update(updates.value, persist) catch |err| {
        error_handling.setLastError(err, "Failed to update configuration");
        return -1;
    };
    
    return 0;
}

/// Get configuration schema as JSON Schema
export fn plue_config_get_schema() [*c]u8 {
    const manager = config_manager orelse {
        error_handling.setLastError(error.NotInitialized, "Config manager not initialized");
        return null;
    };
    
    // Return static schema
    const schema = 
        \\{
        \\  "$schema": "http://json-schema.org/draft-07/schema#",
        \\  "type": "object",
        \\  "properties": {
        \\    "theme": {
        \\      "type": "string",
        \\      "enum": ["light", "dark", "system"],
        \\      "default": "system"
        \\    },
        \\    "providers": {
        \\      "type": "object",
        \\      "additionalProperties": {
        \\        "type": "object",
        \\        "properties": {
        \\          "apiKey": { "type": "string" },
        \\          "baseUrl": { "type": "string", "format": "uri" }
        \\        }
        \\      }
        \\    },
        \\    "server": {
        \\      "type": "object",
        \\      "properties": {
        \\        "opencode_port": { "type": "integer", "minimum": 1024, "maximum": 65535 },
        \\        "auto_start": { "type": "boolean", "default": true }
        \\      }
        \\    }
        \\  }
        \\}
    ;
    
    return @ptrCast([*c]u8, @constCast(schema.ptr));
}
```

### 4. Schema Validator (`src/config/schema.zig`)

JSON Schema validation:

```zig
pub const SchemaValidator = struct {
    allocator: std.mem.Allocator,
    schema: std.json.Value,
    
    /// Validate value against schema
    pub fn validate(self: *SchemaValidator, value: std.json.Value) !void {
        try self.validateValue(value, self.schema, "");
    }
    
    fn validateValue(
        self: *SchemaValidator,
        value: std.json.Value,
        schema: std.json.Value,
        path: []const u8,
    ) !void {
        const schema_obj = schema.object;
        
        // Check type
        if (schema_obj.get("type")) |expected_type| {
            const type_str = expected_type.string;
            
            const valid = switch (value) {
                .null => std.mem.eql(u8, type_str, "null"),
                .bool => std.mem.eql(u8, type_str, "boolean"),
                .integer => std.mem.eql(u8, type_str, "integer") or std.mem.eql(u8, type_str, "number"),
                .float => std.mem.eql(u8, type_str, "number"),
                .string => std.mem.eql(u8, type_str, "string"),
                .array => std.mem.eql(u8, type_str, "array"),
                .object => std.mem.eql(u8, type_str, "object"),
            };
            
            if (!valid) {
                std.log.err("Type mismatch at {s}: expected {s}, got {}", .{ path, type_str, value });
                return error.TypeMismatch;
            }
        }
        
        // Check enum values
        if (schema_obj.get("enum")) |enum_values| {
            var found = false;
            for (enum_values.array.items) |enum_val| {
                if (std.json.Value.jsonEquals(value, enum_val)) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                return error.InvalidEnumValue;
            }
        }
        
        // Validate object properties
        if (value == .object and schema_obj.get("properties")) |properties| {
            const props = properties.object;
            var prop_it = props.iterator();
            while (prop_it.next()) |prop| {
                const prop_path = try std.fmt.allocPrint(
                    self.allocator,
                    "{s}.{s}",
                    .{ path, prop.key_ptr.* },
                );
                defer self.allocator.free(prop_path);
                
                if (value.object.get(prop.key_ptr.*)) |prop_value| {
                    try self.validateValue(prop_value, prop.value_ptr.*, prop_path);
                } else if (self.isRequired(schema_obj, prop.key_ptr.*)) {
                    return error.MissingRequiredProperty;
                }
            }
        }
        
        // Check minimum/maximum for numbers
        if (value == .integer or value == .float) {
            const num = switch (value) {
                .integer => |i| @floatFromInt(f64, i),
                .float => |f| f,
                else => unreachable,
            };
            
            if (schema_obj.get("minimum")) |min| {
                if (num < min.float) return error.BelowMinimum;
            }
            if (schema_obj.get("maximum")) |max| {
                if (num > max.float) return error.AboveMaximum;
            }
        }
    }
    
    fn isRequired(self: *SchemaValidator, schema: std.json.ObjectMap, property: []const u8) bool {
        if (schema.get("required")) |required| {
            for (required.array.items) |req| {
                if (std.mem.eql(u8, req.string, property)) {
                    return true;
                }
            }
        }
        return false;
    }
};
```

### 5. OpenCode Config Sync (`src/config/opencode_sync.zig`)

Synchronize configuration with OpenCode:

```zig
pub const OpenCodeSync = struct {
    allocator: std.mem.Allocator,
    api: *opencode.OpenCodeApi,
    config_manager: *ConfigManager,
    
    /// Sync configuration to OpenCode
    pub fn syncToOpenCode(self: *OpenCodeSync) !void {
        const config = self.config_manager.config;
        
        // Prepare OpenCode configuration
        var opencode_config = std.json.ObjectMap.init(self.allocator);
        defer opencode_config.deinit();
        
        // Map Plue config to OpenCode format
        try opencode_config.put("theme", .{ .string = @tagName(config.theme) });
        
        // Copy provider configurations
        if (config.providers.count() > 0) {
            try opencode_config.put("provider", .{ .object = config.providers });
        }
        
        // Map tool configurations
        var tool_config = std.json.ObjectMap.init(self.allocator);
        try tool_config.put("bash", .{
            .object = try self.mapBashConfig(config.tools.bash),
        });
        try opencode_config.put("tool", .{ .object = tool_config });
        
        // Add OpenCode-specific settings
        if (config.opencode != .null) {
            var it = config.opencode.object.iterator();
            while (it.next()) |entry| {
                try opencode_config.put(entry.key_ptr.*, entry.value_ptr.*);
            }
        }
        
        // Send to OpenCode
        try self.api.config.update(opencode_config);
    }
    
    /// Sync configuration from OpenCode
    pub fn syncFromOpenCode(self: *OpenCodeSync) !void {
        // Get OpenCode configuration
        const opencode_config = try self.api.config.get();
        
        // Store as opencode passthrough
        try self.config_manager.update(
            .{
                .object = .{
                    .opencode = opencode_config,
                },
            },
            false, // Don't persist automatically
        );
    }
    
    fn mapBashConfig(self: *OpenCodeSync, bash: anytype) !std.json.ObjectMap {
        var result = std.json.ObjectMap.init(self.allocator);
        try result.put("defaultTimeout", .{ .integer = @intCast(i64, bash.default_timeout_ms) });
        return result;
    }
};
```

### 6. Configuration Events (`src/config/events.zig`)

Event system for configuration changes:

```zig
const event_bus = @import("../event/bus.zig");

pub const ConfigEvent = union(enum) {
    loaded: struct {
        source: []const u8,
    },
    updated: struct {
        key: []const u8,
        old_value: ?std.json.Value,
        new_value: std.json.Value,
        source: ConfigSource,
    },
    saved: struct {
        path: []const u8,
    },
    error: struct {
        operation: []const u8,
        error: []const u8,
    },
};

pub fn emitConfigEvent(event: ConfigEvent) !void {
    const bus = event_bus.getInstance();
    try bus.emit("config", event);
}
```

## Implementation Steps

### Step 1: Define Configuration Types
1. Create `src/config/types.zig`
2. Define unified config structure
3. Add source priorities
4. Write type tests

### Step 2: Implement Config Manager
1. Create `src/config/manager.zig`
2. Add loading from all sources
3. Implement merging logic
4. Add persistence

### Step 3: Create FFI Functions
1. Create `src/config/ffi.zig`
2. Implement all exports
3. Add schema generation
4. Test with C client

### Step 4: Add Schema Validation
1. Create `src/config/schema.zig`
2. Implement JSON Schema validator
3. Add custom validation rules
4. Test edge cases

### Step 5: Implement OpenCode Sync
1. Create `src/config/opencode_sync.zig`
2. Map between config formats
3. Handle bidirectional sync
4. Test synchronization

### Step 6: Add Event System
1. Create `src/config/events.zig`
2. Emit change events
3. Support watchers
4. Test event delivery

## Testing Requirements

1. **Unit Tests** (>95% coverage):
   - Configuration loading
   - Merging priorities
   - Schema validation
   - Environment parsing

2. **Integration Tests**:
   - Multi-source loading
   - OpenCode synchronization
   - File persistence
   - Change detection

3. **Edge Cases**:
   - Invalid configurations
   - Missing files
   - Permission errors
   - Concurrent updates

## Example Usage (from C)

```c
// Load configuration
if (plue_config_load() != 0) {
    printf("Failed to load config: %s\n", plue_get_last_error());
}

// Get current config
char* config_json = plue_config_get();
printf("Current config: %s\n", config_json);
plue_free_json(config_json);

// Update configuration
const char* updates = "{\"theme\": \"dark\", \"server\": {\"opencode_port\": 3456}}";
if (plue_config_update(updates, true) == 0) {
    printf("Configuration updated and saved\n");
}

// Get schema for validation
char* schema = plue_config_get_schema();
printf("Config schema: %s\n", schema);
// Note: Schema is static, no need to free
```

## Configuration Examples

### Global Plue Config (~/.config/plue/config.json)
```json
{
  "theme": "dark",
  "providers": {
    "anthropic": {
      "apiKey": "sk-ant-..."
    }
  },
  "plue": {
    "telemetry_enabled": false,
    "log_level": "debug"
  }
}
```

### Project Config (.plue/config.json)
```json
{
  "tools": {
    "file": {
      "ignored_patterns": ["node_modules", "*.pyc", "__pycache__"]
    }
  },
  "server": {
    "opencode_port": 3456
  }
}
```

### Environment Variables
```bash
export PLUE_THEME=light
export PLUE_SERVER_OPENCODE_PORT=4000
export PLUE_PROVIDERS_OPENAI_API_KEY=sk-...
```

## Corner Cases and Implementation Details

Based on OpenCode's implementation, handle these critical scenarios:

### Configuration Loading Architecture
1. **Hierarchical Search**: OpenCode searches upward for config files
2. **Deep Merge**: Configs merge from root to current directory
3. **JSONC Support**: OpenCode accepts JSON with comments
4. **Legacy Migration**: Auto-converts TOML to JSON format
5. **Validation**: Uses Zod with strict mode for type safety

### Provider Configuration Specifics
1. **Model Format**: Uses "provider/model-id" format everywhere
2. **Auto-Enable**: Providers enable when env vars present
3. **Disabled List**: `disabled_providers` overrides auto-detection
4. **Cost Override**: User config overrides registry costs
5. **Model Registry**: Fetches from models.dev, caches locally

### Keybind System Details
1. **25+ Actions**: Comprehensive keybind system
2. **Leader Keys**: Support for multi-key combinations
3. **Categories**: Navigation, session, editor, system actions
4. **Defaults**: System provides sensible defaults
5. **Override**: User config overrides all defaults

### MCP Server Integration
1. **Local Servers**: Spawn with command and environment
2. **Remote Servers**: Connect via SSE to URL
3. **Error Handling**: Graceful failure with error events
4. **Tool Integration**: MCP tools appear in tool list
5. **State Management**: Servers managed as app state

### Environment Variable Handling
1. **Provider Detection**: Each provider has specific env vars
2. **No OPENCODE_ Prefix**: Direct env vars (e.g., ANTHROPIC_API_KEY)
3. **Priority**: Env vars checked before config file
4. **Plue Override**: PLUE_ vars should override provider defaults
5. **Validation**: Validate API key formats

### Schema and Validation
1. **Zod Schemas**: All configs validated with Zod
2. **OpenAPI Generation**: Schema exportable as OpenAPI
3. **Strict Mode**: Unknown fields cause validation errors
4. **Default Values**: Sensible defaults for all fields
5. **Type Safety**: Full TypeScript type generation

### State Management Patterns
1. **App State**: Config loaded as cached app state
2. **Lazy Loading**: Config loaded on first access
3. **No Hot Reload**: Changes require restart
4. **Memory Cache**: Parsed config kept in memory
5. **Thread Safety**: Consider concurrent access

### File Format Edge Cases
1. **JSON Comments**: Must strip comments before parsing
2. **Unicode**: Handle UTF-8 properly in all configs
3. **Large Files**: Set reasonable size limits
4. **Syntax Errors**: Provide helpful error messages
5. **Missing Files**: Return empty config, not error

### UX Improvements
1. **Config Wizard**: Guide users through initial setup
2. **Validation Messages**: Clear errors with fix suggestions
3. **Auto-Complete**: Provide schema for IDE support
4. **Migration Tool**: Help users upgrade configs
5. **Diff View**: Show what changed after updates

### Potential Bugs to Watch Out For
1. **Circular Imports**: Config loading config manager
2. **Race Conditions**: Multiple config updates
3. **Memory Leaks**: Large config objects not freed
4. **Path Resolution**: Relative vs absolute paths
5. **Permission Errors**: Config files not readable
6. **Merge Conflicts**: Deep merge creating invalid state
7. **Type Coercion**: String env vars to typed values
8. **Provider Loops**: Provider config loading providers
9. **Cache Invalidation**: Stale model registry data
10. **Schema Drift**: Config schema version mismatches

## Success Criteria

The implementation is complete when:
- [ ] Configuration loads from all sources with proper priority
- [ ] Hierarchical file search works like OpenCode
- [ ] Deep merge produces valid configurations
- [ ] JSONC files parse correctly with comments
- [ ] Legacy TOML configs auto-migrate
- [ ] Provider auto-detection via env vars works
- [ ] Plue config properly overrides OpenCode settings
- [ ] Schema validation provides helpful errors
- [ ] MCP server configs integrate properly
- [ ] All tests pass with >95% coverage
- [ ] Memory usage is stable with large configs
- [ ] Thread-safe access to configuration

## Git Workflow

Continue in the same worktree:
```bash
cd ../plue-server-management
```

Commit with conventional commits:
- `feat: define configuration types`
- `feat: implement config manager`
- `feat: add config FFI functions`
- `feat: implement schema validation`
- `feat: add OpenCode config sync`
- `test: add configuration tests`

The branch remains: `feat_add_opencode_server_management`