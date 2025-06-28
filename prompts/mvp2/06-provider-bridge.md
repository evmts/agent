# Implement Provider Management Bridge

## Context

You are implementing the provider management bridge that connects Plue's C FFI provider API to OpenCode's provider endpoints. This handles AI provider configuration, authentication, and model management.

### Project State

From previous tasks, you have:
- OpenCode API client with provider endpoints (`src/opencode/api.zig`)
- Session and message bridges working
- HTTP client with authentication support

Now you need to implement provider management for AI services like Anthropic, OpenAI, GitHub Copilot, etc.

### Provider API Requirements (from PLUE_CORE_API.md)

```c
// List all available providers as JSON
export fn plue_provider_list() [*c]u8;

// Configure a provider
export fn plue_provider_configure(provider_id: [*:0]const u8, config_json: [*:0]const u8) c_int;

// Get provider configuration
export fn plue_provider_get_config(provider_id: [*:0]const u8) [*c]u8;

// Test provider authentication
export fn plue_provider_test_auth(provider_id: [*:0]const u8) c_int;

// Get available models for a provider
export fn plue_provider_get_models(provider_id: [*:0]const u8) [*c]u8;
```

### OpenCode Provider System

OpenCode supports multiple providers with different authentication methods:

```typescript
// Provider structure from ModelsDev
interface Provider {
  id: string;              // e.g., "anthropic", "openai"
  name: string;            // Display name
  api?: string;            // API endpoint override
  env: string[];           // Environment variables for API keys
  npm?: string;            // NPM package name
  models: Record<string, Model>;
}

// Model structure from ModelsDev
interface Model {
  id: string;              // e.g., "claude-3-opus-20240229"
  name: string;            // Display name
  attachment: boolean;     // Supports file attachments
  reasoning: boolean;      // Supports reasoning/thinking
  temperature: boolean;    // Supports temperature control
  tool_call: boolean;      // Supports function calling
  cost: {
    input: number;         // $ per 1M input tokens
    output: number;        // $ per 1M output tokens
    cache_read?: number;   // $ per 1M cached tokens (Anthropic)
    cache_write?: number;  // $ per 1M tokens to cache
  };
  limit: {
    context: number;       // Max context window
    output: number;        // Max output tokens
  };
  options: Record<string, any>; // Provider-specific options
}

// Provider list response
interface ProviderListResponse {
  providers: Provider[];   // All available providers
  default: Record<string, string>; // Default model per provider
}
```

**Important Details**:
- Providers loaded from `models.json` via macro at build time
- Authentication handled by custom loaders (anthropic, github-copilot)
- Environment variables checked first, then config, then OAuth
- Provider list includes pre-sorted models and defaults
- No separate enable/disable endpoint - managed by config

## Requirements

### 1. Provider Types (`src/provider/types.zig`)

Define provider-related types:

```zig
const std = @import("std");
const opencode = @import("../opencode/types.zig");

pub const ProviderId = enum {
    anthropic,
    openai,
    github_copilot,
    bedrock,
    google,
    azure,
    ollama,
    openrouter,
    
    pub fn toString(self: ProviderId) []const u8 {
        return @tagName(self);
    }
    
    pub fn fromString(str: []const u8) !ProviderId {
        inline for (std.meta.fields(ProviderId)) |field| {
            if (std.mem.eql(u8, field.name, str)) {
                return @field(ProviderId, field.name);
            }
        }
        return error.UnknownProvider;
    }
};

pub const AuthType = enum {
    api_key,
    oauth,
    browser,
};

pub const ProviderConfig = struct {
    /// API key for providers that use it
    api_key: ?[]const u8 = null,
    
    /// Base URL override
    base_url: ?[]const u8 = null,
    
    /// Organization ID (OpenAI)
    org_id: ?[]const u8 = null,
    
    /// OAuth tokens
    oauth: ?struct {
        access_token: []const u8,
        refresh_token: ?[]const u8 = null,
        expires_at: ?i64 = null,
    } = null,
    
    /// Custom headers
    headers: ?std.StringHashMap([]const u8) = null,
    
    /// Provider-specific settings
    extras: ?std.json.Value = null,
};

pub const ProviderStatus = struct {
    id: ProviderId,
    name: []const u8,
    enabled: bool,
    authenticated: bool,
    auth_type: AuthType,
    last_error: ?[]const u8 = null,
    models_loaded: bool = false,
};

pub const ModelCapabilities = struct {
    /// Supports function/tool calling
    tools: bool = false,
    
    /// Supports vision/images
    vision: bool = false,
    
    /// Supports streaming
    streaming: bool = true,
    
    /// Max output tokens
    max_output: ?u32 = null,
};

pub const ModelInfo = struct {
    id: []const u8,
    name: []const u8,
    provider_id: ProviderId,
    context_length: u32,
    input_cost: ?f64 = null,
    output_cost: ?f64 = null,
    capabilities: ModelCapabilities = .{},
    deprecated: bool = false,
};
```

### 2. Provider Manager (`src/provider/manager.zig`)

Core provider management logic:

```zig
pub const ProviderManager = struct {
    allocator: std.mem.Allocator,
    api: *opencode.OpenCodeApi,
    providers: std.EnumMap(ProviderId, ProviderState),
    model_cache: std.StringHashMap([]ModelInfo),
    config_path: []const u8,
    mutex: std.Thread.Mutex,
    
    const ProviderState = struct {
        config: ProviderConfig,
        status: ProviderStatus,
        models: ?[]ModelInfo = null,
        last_refresh: i64 = 0,
    };
    
    /// Initialize provider manager
    pub fn init(allocator: std.mem.Allocator, api: *opencode.OpenCodeApi, config_path: []const u8) !ProviderManager {
        var manager = ProviderManager{
            .allocator = allocator,
            .api = api,
            .providers = std.EnumMap(ProviderId, ProviderState){},
            .model_cache = std.StringHashMap([]ModelInfo).init(allocator),
            .config_path = config_path,
            .mutex = .{},
        };
        
        // Initialize all providers
        inline for (std.meta.fields(ProviderId)) |field| {
            const provider_id = @field(ProviderId, field.name);
            manager.providers.put(provider_id, ProviderState{
                .config = .{},
                .status = .{
                    .id = provider_id,
                    .name = getProviderDisplayName(provider_id),
                    .enabled = false,
                    .authenticated = false,
                    .auth_type = getProviderAuthType(provider_id),
                },
            });
        }
        
        // Load saved configurations
        try manager.loadConfigurations();
        
        return manager;
    }
    
    /// List all providers via OpenCode API
    pub fn listProviders(self: *ProviderManager) !ProviderListResult {
        // Get provider list from OpenCode
        const response = try self.api.provider.list();
        
        // Update our cache with authentication status
        self.mutex.lock();
        defer self.mutex.unlock();
        
        // Check each provider's auth status
        for (response.providers) |provider| {
            const provider_id = try ProviderId.fromString(provider.id);
            if (self.providers.getPtr(provider_id)) |state| {
                // Check if we have credentials
                state.status.authenticated = self.hasCredentials(provider_id);
                state.status.enabled = state.status.authenticated;
                
                // Cache models
                if (state.models) |old_models| {
                    self.allocator.free(old_models);
                }
                state.models = try self.convertProviderModels(provider);
                state.last_refresh = std.time.milliTimestamp();
            }
        }
        
        return response;
    }
    
    /// Check if provider has credentials
    fn hasCredentials(self: *ProviderManager, provider_id: ProviderId) bool {
        const state = self.providers.get(provider_id) orelse return false;
        
        // Check for API key
        if (state.config.api_key) |key| {
            return key.len > 0;
        }
        
        // Check for OAuth
        if (state.config.oauth) |oauth| {
            return oauth.access_token.len > 0;
        }
        
        // Check environment variables
        const provider_info = getProviderInfo(provider_id);
        for (provider_info.env_vars) |env_var| {
            if (std.process.getEnvVarOwned(self.allocator, env_var)) |value| {
                defer self.allocator.free(value);
                return value.len > 0;
            } else |_| {}
        }
        
        return false;
    }
    
    /// Configure a provider
    pub fn configure(self: *ProviderManager, provider_id: ProviderId, config: ProviderConfig) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        var state = self.providers.getPtr(provider_id) orelse return error.UnknownProvider;
        
        // Update config
        state.config = config;
        
        // Configure via OpenCode
        const config_json = try std.json.stringifyAlloc(self.allocator, config, .{});
        defer self.allocator.free(config_json);
        
        try self.api.provider.configure(provider_id.toString(), config);
        
        // Update status
        state.status.authenticated = try self.checkAuthentication(provider_id);
        state.status.enabled = state.status.authenticated;
        
        // Save configuration
        try self.saveConfigurations();
        
        // Emit event
        try emitProviderEvent(.{
            .configured = .{
                .provider_id = provider_id,
                .authenticated = state.status.authenticated,
            },
        });
    }
    
    /// Enable/disable provider
    pub fn setEnabled(self: *ProviderManager, provider_id: ProviderId, enabled: bool) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        var state = self.providers.getPtr(provider_id) orelse return error.UnknownProvider;
        
        if (enabled and !state.status.authenticated) {
            return error.NotAuthenticated;
        }
        
        state.status.enabled = enabled;
        
        // Update via OpenCode
        try self.api.provider.setEnabled(provider_id.toString(), enabled);
        
        // Save state
        try self.saveConfigurations();
        
        // Emit event
        try emitProviderEvent(.{
            .status_changed = .{
                .provider_id = provider_id,
                .enabled = enabled,
            },
        });
    }
    
    /// Test authentication
    pub fn testAuth(self: *ProviderManager, provider_id: ProviderId) !bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        const authenticated = try self.checkAuthentication(provider_id);
        
        var state = self.providers.getPtr(provider_id) orelse return error.UnknownProvider;
        state.status.authenticated = authenticated;
        
        if (authenticated) {
            state.status.last_error = null;
        } else {
            state.status.last_error = "Authentication failed";
        }
        
        return authenticated;
    }
    
    /// Get models for provider
    pub fn getModels(self: *ProviderManager, provider_id: ProviderId) ![]ModelInfo {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        var state = self.providers.getPtr(provider_id) orelse return error.UnknownProvider;
        
        // Check cache age
        const now = std.time.milliTimestamp();
        const cache_age = now - state.last_refresh;
        
        if (state.models == null or cache_age > 3600000) { // 1 hour
            // Fetch from OpenCode
            const models = try self.api.provider.getModels(provider_id.toString());
            
            // Convert and store
            var model_infos = try self.allocator.alloc(ModelInfo, models.len);
            for (models, 0..) |model, i| {
                model_infos[i] = try self.convertModel(provider_id, model);
            }
            
            // Update cache
            if (state.models) |old_models| {
                self.allocator.free(old_models);
            }
            state.models = model_infos;
            state.last_refresh = now;
            state.status.models_loaded = true;
        }
        
        return state.models.?;
    }
    
    /// Check if provider is authenticated
    fn checkAuthentication(self: *ProviderManager, provider_id: ProviderId) !bool {
        // Try to get models as auth check
        self.api.provider.getModels(provider_id.toString()) catch |err| {
            if (err == error.Unauthorized or err == error.Forbidden) {
                return false;
            }
            return err;
        };
        return true;
    }
    
    /// Convert OpenCode model to our format
    fn convertModel(self: *ProviderManager, provider_id: ProviderId, model: opencode.Model) !ModelInfo {
        return ModelInfo{
            .id = try self.allocator.dupe(u8, model.id),
            .name = try self.allocator.dupe(u8, model.name),
            .provider_id = provider_id,
            .context_length = model.context_length,
            .input_cost = model.input_cost,
            .output_cost = model.output_cost,
            .capabilities = getModelCapabilities(provider_id, model.id),
        };
    }
    
    /// Save configurations to disk
    fn saveConfigurations(self: *ProviderManager) !void {
        var configs = std.json.ObjectMap.init(self.allocator);
        defer configs.deinit();
        
        var it = self.providers.iterator();
        while (it.next()) |entry| {
            if (entry.value.config.api_key != null or entry.value.config.oauth != null) {
                try configs.put(
                    entry.key.toString(),
                    try std.json.Value.jsonParse(self.allocator, entry.value.config),
                );
            }
        }
        
        const json = try std.json.stringify(configs, .{}, self.allocator);
        defer self.allocator.free(json);
        
        try std.fs.cwd().writeFile(self.config_path, json);
    }
    
    /// Load configurations from disk
    fn loadConfigurations(self: *ProviderManager) !void {
        const file = std.fs.cwd().openFile(self.config_path, .{}) catch |err| {
            if (err == error.FileNotFound) return;
            return err;
        };
        defer file.close();
        
        const content = try file.readToEndAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(content);
        
        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, content, .{});
        defer parsed.deinit();
        
        const configs = parsed.value.object;
        var it = configs.iterator();
        while (it.next()) |entry| {
            const provider_id = try ProviderId.fromString(entry.key_ptr.*);
            const config = try std.json.parseFromValue(ProviderConfig, self.allocator, entry.value_ptr.*, .{});
            
            if (self.providers.getPtr(provider_id)) |state| {
                state.config = config.value;
            }
        }
    }
};

/// Get display name for provider
fn getProviderDisplayName(provider_id: ProviderId) []const u8 {
    return switch (provider_id) {
        .anthropic => "Anthropic Claude",
        .openai => "OpenAI",
        .github_copilot => "GitHub Copilot",
        .bedrock => "AWS Bedrock",
        .google => "Google AI",
        .azure => "Azure OpenAI",
        .ollama => "Ollama (Local)",
        .openrouter => "OpenRouter",
    };
}

/// Get auth type for provider
fn getProviderAuthType(provider_id: ProviderId) AuthType {
    return switch (provider_id) {
        .anthropic => .api_key,
        .openai => .api_key,
        .github_copilot => .oauth,
        .bedrock => .api_key,
        .google => .api_key,
        .azure => .api_key,
        .ollama => .api_key,
        .openrouter => .api_key,
    };
}

/// Get model capabilities
fn getModelCapabilities(provider_id: ProviderId, model_id: []const u8) ModelCapabilities {
    // Provider-specific capabilities
    return switch (provider_id) {
        .anthropic => .{
            .tools = true,
            .vision = std.mem.indexOf(u8, model_id, "claude-3") != null,
            .streaming = true,
            .max_output = 4096,
        },
        .openai => .{
            .tools = std.mem.indexOf(u8, model_id, "gpt-4") != null,
            .vision = std.mem.indexOf(u8, model_id, "vision") != null,
            .streaming = true,
            .max_output = 4096,
        },
        else => .{},
    };
}

/// Convert model to JSON
fn modelToJson(allocator: std.mem.Allocator, model: ModelInfo) !std.json.Value {
    var obj = std.json.ObjectMap.init(allocator);
    try obj.put("id", .{ .string = model.id });
    try obj.put("name", .{ .string = model.name });
    try obj.put("contextLength", .{ .integer = @intCast(i64, model.context_length) });
    
    if (model.input_cost) |cost| {
        try obj.put("inputCost", .{ .float = cost });
    }
    if (model.output_cost) |cost| {
        try obj.put("outputCost", .{ .float = cost });
    }
    
    return .{ .object = obj };
}
```

### 3. FFI Implementation (`src/provider/ffi.zig`)

Implement C FFI functions:

```zig
const std = @import("std");
const c = @cImport({});
const ProviderManager = @import("manager.zig").ProviderManager;
const types = @import("types.zig");
const error_handling = @import("../error/handling.zig");

/// Global provider manager
var provider_manager: ?*ProviderManager = null;

/// Initialize provider manager
pub fn init(allocator: std.mem.Allocator, api: *opencode.OpenCodeApi) !void {
    provider_manager = try allocator.create(ProviderManager);
    provider_manager.?.* = try ProviderManager.init(
        allocator,
        api,
        "providers.json", // TODO: Get from config
    );
}

/// List all available providers as JSON
export fn plue_provider_list() [*c]u8 {
    const manager = provider_manager orelse {
        error_handling.setLastError(error.NotInitialized, "Provider manager not initialized");
        return null;
    };
    
    const providers_json = manager.listProviders() catch |err| {
        error_handling.setLastError(err, "Failed to list providers");
        return null;
    };
    
    const json_string = std.json.stringifyAlloc(manager.allocator, providers_json, .{}) catch |err| {
        error_handling.setLastError(err, "Failed to serialize providers");
        return null;
    };
    
    return json_string.ptr;
}

/// Configure a provider
export fn plue_provider_configure(provider_id: [*:0]const u8, config_json: [*:0]const u8) c_int {
    if (provider_id == null or config_json == null) {
        error_handling.setLastError(error.InvalidParam, "Invalid parameters");
        return -1;
    }
    
    const manager = provider_manager orelse {
        error_handling.setLastError(error.NotInitialized, "Provider manager not initialized");
        return -1;
    };
    
    const provider_id_slice = std.mem.span(provider_id);
    const config_slice = std.mem.span(config_json);
    
    // Parse provider ID
    const pid = types.ProviderId.fromString(provider_id_slice) catch {
        error_handling.setLastError(error.UnknownProvider, "Unknown provider ID");
        return -1;
    };
    
    // Parse configuration
    const config = std.json.parseFromSlice(
        types.ProviderConfig,
        manager.allocator,
        config_slice,
        .{ .ignore_unknown_fields = true },
    ) catch |err| {
        error_handling.setLastError(err, "Failed to parse configuration");
        return -1;
    };
    defer config.deinit();
    
    // Configure provider
    manager.configure(pid, config.value) catch |err| {
        error_handling.setLastError(err, "Failed to configure provider");
        return -1;
    };
    
    return 0;
}

/// Get provider configuration
export fn plue_provider_get_config(provider_id: [*:0]const u8) [*c]u8 {
    if (provider_id == null) {
        error_handling.setLastError(error.InvalidParam, "Provider ID is null");
        return -1;
    }
    
    const manager = provider_manager orelse {
        error_handling.setLastError(error.NotInitialized, "Provider manager not initialized");
        return -1;
    };
    
    const provider_id_slice = std.mem.span(provider_id);
    
    // Parse provider ID
    const pid = types.ProviderId.fromString(provider_id_slice) catch {
        error_handling.setLastError(error.UnknownProvider, "Unknown provider ID");
        return -1;
    };
    
    // Get config from manager
    const config = manager.getConfig(pid) catch |err| {
        error_handling.setLastError(err, "Failed to get provider config");
        return null;
    };
    
    // Serialize config (excluding sensitive data)
    var safe_config = std.json.ObjectMap.init(manager.allocator);
    defer safe_config.deinit();
    
    try safe_config.put("provider_id", .{ .string = provider_id_slice });
    try safe_config.put("authenticated", .{ .bool = config.authenticated });
    try safe_config.put("has_api_key", .{ .bool = config.api_key != null });
    
    if (config.base_url) |url| {
        try safe_config.put("base_url", .{ .string = url });
    }
    
    const json_string = std.json.stringifyAlloc(
        manager.allocator,
        std.json.Value{ .object = safe_config },
        .{},
    ) catch |err| {
        error_handling.setLastError(err, "Failed to serialize config");
        return null;
    };
    
    return json_string.ptr;
}

/// Test provider authentication
export fn plue_provider_test_auth(provider_id: [*:0]const u8) c_int {
    if (provider_id == null) {
        error_handling.setLastError(error.InvalidParam, "Provider ID is null");
        return -1;
    }
    
    const manager = provider_manager orelse {
        error_handling.setLastError(error.NotInitialized, "Provider manager not initialized");
        return -1;
    };
    
    const provider_id_slice = std.mem.span(provider_id);
    
    // Parse provider ID
    const pid = types.ProviderId.fromString(provider_id_slice) catch {
        error_handling.setLastError(error.UnknownProvider, "Unknown provider ID");
        return -1;
    };
    
    // Test authentication
    const authenticated = manager.testAuth(pid) catch |err| {
        error_handling.setLastError(err, "Failed to test authentication");
        return -1;
    };
    
    return if (authenticated) 0 else -1;
}

/// Get available models for a provider
export fn plue_provider_get_models(provider_id: [*:0]const u8) [*c]u8 {
    if (provider_id == null) {
        error_handling.setLastError(error.InvalidParam, "Provider ID is null");
        return null;
    }
    
    const manager = provider_manager orelse {
        error_handling.setLastError(error.NotInitialized, "Provider manager not initialized");
        return null;
    };
    
    const provider_id_slice = std.mem.span(provider_id);
    
    // Parse provider ID
    const pid = types.ProviderId.fromString(provider_id_slice) catch {
        error_handling.setLastError(error.UnknownProvider, "Unknown provider ID");
        return null;
    };
    
    // Get models
    const models = manager.getModels(pid) catch |err| {
        error_handling.setLastError(err, "Failed to get models");
        return null;
    };
    
    // Convert to JSON array
    var models_array = std.json.Array.init(manager.allocator);
    for (models) |model| {
        models_array.append(try modelToJson(manager.allocator, model)) catch |err| {
            error_handling.setLastError(err, "Failed to convert model");
            return null;
        };
    }
    
    const json_string = std.json.stringifyAlloc(
        manager.allocator,
        std.json.Value{ .array = models_array },
        .{},
    ) catch |err| {
        error_handling.setLastError(err, "Failed to serialize models");
        return null;
    };
    
    return json_string.ptr;
}
```

### 4. Provider Events (`src/provider/events.zig`)

Event system for provider changes:

```zig
const event_bus = @import("../event/bus.zig");
const types = @import("types.zig");

pub const ProviderEvent = union(enum) {
    configured: struct {
        provider_id: types.ProviderId,
        authenticated: bool,
    },
    status_changed: struct {
        provider_id: types.ProviderId,
        enabled: bool,
    },
    models_loaded: struct {
        provider_id: types.ProviderId,
        count: usize,
    },
    auth_failed: struct {
        provider_id: types.ProviderId,
        error: []const u8,
    },
};

pub fn emitProviderEvent(event: ProviderEvent) !void {
    const bus = event_bus.getInstance();
    try bus.emit("provider", event);
}
```

### 5. Authentication Handler (`src/provider/auth.zig`)

Handle different authentication methods:

```zig
pub const AuthHandler = struct {
    allocator: std.mem.Allocator,
    
    /// Handle API key authentication
    pub fn authenticateApiKey(
        self: *AuthHandler,
        provider_id: types.ProviderId,
        api_key: []const u8,
    ) !void {
        // Validate API key format
        switch (provider_id) {
            .anthropic => {
                if (!std.mem.startsWith(u8, api_key, "sk-ant-")) {
                    return error.InvalidApiKey;
                }
            },
            .openai => {
                if (!std.mem.startsWith(u8, api_key, "sk-")) {
                    return error.InvalidApiKey;
                }
            },
            else => {},
        }
    }
    
    /// Handle OAuth authentication
    pub fn authenticateOAuth(
        self: *AuthHandler,
        provider_id: types.ProviderId,
    ) !types.ProviderConfig {
        // OAuth flow would be handled by OpenCode
        // This is a placeholder for the response
        return types.ProviderConfig{
            .oauth = .{
                .access_token = "mock_token",
                .refresh_token = "mock_refresh",
                .expires_at = std.time.milliTimestamp() + 3600000,
            },
        };
    }
    
    /// Refresh OAuth token if needed
    pub fn refreshTokenIfNeeded(
        self: *AuthHandler,
        config: *types.ProviderConfig,
    ) !bool {
        if (config.oauth) |oauth| {
            if (oauth.expires_at) |expires| {
                const now = std.time.milliTimestamp();
                if (now >= expires - 300000) { // 5 minutes before expiry
                    // TODO: Call OpenCode to refresh
                    return true;
                }
            }
        }
        return false;
    }
};
```

### 6. Cost Calculator (`src/provider/cost.zig`)

Calculate usage costs:

```zig
pub const CostCalculator = struct {
    /// Calculate cost for tokens
    pub fn calculateCost(
        model: types.ModelInfo,
        input_tokens: u32,
        output_tokens: u32,
    ) f64 {
        var cost: f64 = 0;
        
        if (model.input_cost) |input_cost| {
            cost += @floatFromInt(f64, input_tokens) * input_cost / 1_000_000;
        }
        
        if (model.output_cost) |output_cost| {
            cost += @floatFromInt(f64, output_tokens) * output_cost / 1_000_000;
        }
        
        return cost;
    }
    
    /// Format cost as string
    pub fn formatCost(allocator: std.mem.Allocator, cost: f64) ![]const u8 {
        if (cost < 0.01) {
            return std.fmt.allocPrint(allocator, "<$0.01", .{});
        } else if (cost < 1.0) {
            return std.fmt.allocPrint(allocator, "${d:.2}", .{cost});
        } else {
            return std.fmt.allocPrint(allocator, "${d:.2}", .{cost});
        }
    }
};
```

## Implementation Steps

### Step 1: Define Provider Types
1. Create `src/provider/types.zig`
2. Define all provider enums and structures
3. Add serialization support
4. Write type tests

### Step 2: Implement Provider Manager
1. Create `src/provider/manager.zig`
2. Add provider configuration logic
3. Implement model caching
4. Handle authentication

### Step 3: Create FFI Functions
1. Create `src/provider/ffi.zig`
2. Implement all exports
3. Add error handling
4. Test with C client

### Step 4: Add Event System
1. Create `src/provider/events.zig`
2. Define event types
3. Integrate with manager
4. Test event delivery

### Step 5: Implement Authentication
1. Create `src/provider/auth.zig`
2. Handle different auth types
3. Add token refresh
4. Test auth flows

### Step 6: Add Cost Calculation
1. Create `src/provider/cost.zig`
2. Implement cost logic
3. Add formatting utilities
4. Test calculations

## Testing Requirements

1. **Unit Tests** (>95% coverage):
   - Provider configuration
   - Model management
   - Authentication logic
   - Cost calculations

2. **Integration Tests**:
   - Full provider setup
   - Authentication flows
   - Model discovery
   - Configuration persistence

3. **Mock Tests**:
   - Test without real API keys
   - Simulate auth failures
   - Test error scenarios

## Example Usage (from C)

```c
// List providers - returns providers array and default models
char* providers_json = plue_provider_list();
// Response format:
// {
//   "providers": [{
//     "id": "anthropic",
//     "name": "Anthropic",
//     "models": {...},
//     "env": ["ANTHROPIC_API_KEY"],
//     ...
//   }],
//   "default": {
//     "anthropic": "claude-3-5-sonnet-20241022",
//     "openai": "gpt-4o",
//     ...
//   }
// }
printf("Available providers: %s\n", providers_json);
plue_free_json(providers_json);

// Configure Anthropic with API key
const char* config = "{\"api_key\": \"sk-ant-api03-...\"}";
if (plue_provider_configure("anthropic", config) == 0) {
    printf("Anthropic configured successfully\n");
}

// Test authentication (tries to load models)
if (plue_provider_test_auth("anthropic") == 0) {
    printf("Authentication successful\n");
}

// Get provider config (safe view without secrets)
char* config_json = plue_provider_get_config("anthropic");
printf("Provider config: %s\n", config_json);
plue_free_json(config_json);

// Get models for a specific provider
char* models_json = plue_provider_get_models("anthropic");
printf("Available models: %s\n", models_json);
plue_free_json(models_json);
```

## Corner Cases and Implementation Details

Based on OpenCode's implementation, handle these critical scenarios:

### Provider System Architecture
1. **Models.json Source**: Provider data loaded from models.json via build-time macro
2. **No Direct Enable/Disable**: Providers are enabled by having valid credentials
3. **Custom Loaders**: Special handling for anthropic and github-copilot OAuth
4. **Environment First**: Check env vars before config file for API keys
5. **Default Models**: Pre-calculated default model per provider in response

### Authentication Patterns
1. **Anthropic OAuth**: Uses "anthropic-beta: oauth-2025-04-20" header
2. **GitHub Copilot**: Complex OAuth flow with refresh tokens
3. **API Key Format**: Anthropic keys start with "sk-ant-", OpenAI with "sk-"
4. **No API Key in Headers**: OAuth providers remove x-api-key header
5. **Cost Override**: OAuth providers set costs to 0 (free for users)

### Model Management Details
1. **Model Features**: attachment, reasoning, temperature, tool_call flags
2. **Cost Structure**: input/output per million, plus cache costs for Anthropic
3. **Context Limits**: Both context window and max output limits
4. **Provider Options**: Model-specific options in options field
5. **Pre-Sorted Models**: Models returned in preference order by Provider.sort()

### Configuration Edge Cases
1. **Multiple Auth Sources**: env → config → OAuth precedence
2. **API Endpoint Override**: Custom api field for enterprise/proxy setups
3. **NPM Package**: Some providers require npm package installation
4. **Environment Arrays**: Multiple env var names per provider (fallbacks)
5. **No Persistence**: OpenCode doesn't persist provider config - client must

### Error Handling Specifics
1. **Silent Failures**: Missing credentials don't error - just not authenticated
2. **Model Loading**: Models always returned even if not authenticated
3. **OAuth Expiry**: Must handle token refresh for OAuth providers
4. **Network Errors**: Distinguish auth failures from network issues
5. **Partial Success**: Some providers may auth while others fail

### Cost Calculation Nuances
1. **Zero Cost OAuth**: Anthropic/Copilot OAuth users get free usage
2. **Cache Costs**: Only Anthropic has cache read/write costs currently
3. **Currency**: All costs in USD per million tokens
4. **Decimal Precision**: Use appropriate precision for small costs
5. **Cost Updates**: Costs may change - don't hardcode

### UX Improvements
1. **Credential Hints**: Show which env var or config field needed
2. **Auth Status Icons**: Visual indicators for each provider's status
3. **Model Search**: Filter/search across all provider models
4. **Cost Comparison**: Show cost differences between similar models
5. **Quick Actions**: One-click auth test and credential entry

### Potential Bugs to Watch Out For
1. **Race Conditions**: Multiple auth checks for same provider
2. **Memory Leaks**: Model arrays not freed when updating cache
3. **OAuth Token Expiry**: Tokens expire during long sessions
4. **Environment Encoding**: Special characters in API keys
5. **Case Sensitivity**: Provider IDs must match exactly
6. **Circular Dependencies**: Provider loading during startup
7. **Network Timeouts**: Slow provider endpoints blocking UI
8. **Config Corruption**: Invalid JSON in saved config file
9. **Model ID Changes**: Providers may rename model IDs
10. **Thread Safety**: Concurrent access to provider state

## Success Criteria

The implementation is complete when:
- [ ] All providers can be configured via API key or OAuth
- [ ] Authentication status correctly reflects credentials
- [ ] Models are discovered with all metadata fields
- [ ] Configuration persists across restarts  
- [ ] Events fire for all auth state changes
- [ ] Cost calculation handles all cost types including cache
- [ ] OAuth token refresh works seamlessly
- [ ] All tests pass with >95% coverage
- [ ] Memory usage is stable during model updates
- [ ] Thread-safe access to provider state

## Git Workflow

Continue in the same worktree:
```bash
cd ../plue-server-management
```

Commit with conventional commits:
- `feat: define provider types and enums`
- `feat: implement provider manager`
- `feat: add provider FFI functions`
- `feat: implement authentication handling`
- `feat: add cost calculation`
- `test: add provider bridge tests`

The branch remains: `feat_add_opencode_server_management`