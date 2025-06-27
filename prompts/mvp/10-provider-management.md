# Implement Provider Management API for Plue AI Editor

You are an AI agent executing a well-scoped task to build an AI editor in Zig. This task focuses on implementing the provider management system that coordinates between the Zig core and the AI provider wrapper executable, handling configuration, authentication, and model discovery.

## Context

<context>
<project_overview>
The provider management system is the bridge between Zig and AI providers:
- Manages multiple AI providers (Anthropic, OpenAI, Copilot, etc.)
- Handles provider configuration and authentication
- Discovers available models and their capabilities
- Routes streaming responses from provider executable to message system
- Tracks costs and usage across providers
</project_overview>

<existing_infrastructure>
From previous implementations:
- AI provider wrapper executable handles actual API communication
- Message system supports streaming responses and token tracking
- Session management provides context for AI interactions
- Error handling propagates provider-specific errors
- Bun executable spawning is available for IPC
</existing_infrastructure>

<api_specification>
From PLUE_CORE_API.md:
```c
// List all available providers as JSON
export fn plue_provider_list() [*c]u8;

// Configure a provider
export fn plue_provider_configure(provider_id: [*:0]const u8, config_json: [*:0]const u8) c_int;

// Enable or disable a provider
export fn plue_provider_set_enabled(provider_id: [*:0]const u8, enabled: bool) c_int;

// Test provider authentication
export fn plue_provider_test_auth(provider_id: [*:0]const u8) c_int;

// Get available models for a provider
export fn plue_provider_get_models(provider_id: [*:0]const u8) [*c]u8;
```
</api_specification>

<reference_implementation>
OpenCode (in opencode/) has a mature provider system:
- opencode/packages/opencode/src/provider/provider.ts - Provider abstraction
- Providers are discovered and loaded dynamically
- Configuration is stored securely
- Models are cached with capabilities
- Streaming is handled efficiently
</reference_implementation>
</context>

## Task: Implement Provider Management API

### Requirements

1. **Create provider abstraction** that:
   - Defines provider metadata and capabilities
   - Manages provider configuration
   - Handles authentication state
   - Tracks enabled/disabled status

2. **Implement provider registry** for:
   - Built-in provider registration
   - Dynamic provider discovery
   - Configuration persistence
   - Provider lifecycle management

3. **Build communication layer** to:
   - Spawn AI provider executable
   - Send requests via JSON IPC
   - Handle streaming responses
   - Manage timeouts and errors

4. **Add model management**:
   - Cache available models
   - Track model capabilities
   - Calculate costs per model
   - Validate model selection

### Detailed Steps

1. **Create src/provider/provider.zig with core types**:
   ```zig
   const std = @import("std");
   const json = @import("../json.zig");
   const process = @import("../process.zig");
   
   pub const ProviderId = []const u8;
   pub const ModelId = []const u8;
   
   // Provider metadata and configuration
   pub const Provider = struct {
       id: ProviderId,
       name: []const u8,
       description: []const u8,
       enabled: bool,
       auth_type: AuthType,
       config: ProviderConfig,
       models: ?[]Model,
       last_auth_check: ?i64,
       
       pub const AuthType = enum {
           api_key,
           oauth,
           aws_credentials,
           service_account,
           
           pub fn toString(self: AuthType) []const u8 {
               return switch (self) {
                   .api_key => "api_key",
                   .oauth => "oauth",
                   .aws_credentials => "aws_credentials",
                   .service_account => "service_account",
               };
           }
       };
       
       pub fn init(allocator: std.mem.Allocator, id: ProviderId, name: []const u8) !Provider {
           return Provider{
               .id = try allocator.dupe(u8, id),
               .name = try allocator.dupe(u8, name),
               .description = "",
               .enabled = false,
               .auth_type = .api_key,
               .config = ProviderConfig.init(allocator),
               .models = null,
               .last_auth_check = null,
           };
       }
       
       pub fn toJson(self: Provider, allocator: std.mem.Allocator) !json.Value {
           var obj = std.StringHashMap(json.Value).init(allocator);
           
           try obj.put("id", json.Value{ .string = self.id });
           try obj.put("name", json.Value{ .string = self.name });
           try obj.put("description", json.Value{ .string = self.description });
           try obj.put("enabled", json.Value{ .bool = self.enabled });
           try obj.put("auth_type", json.Value{ .string = self.auth_type.toString() });
           
           if (self.models) |models| {
               var models_array = std.ArrayList(json.Value).init(allocator);
               for (models) |model| {
                   try models_array.append(try model.toJson(allocator));
               }
               try obj.put("models", json.Value{ .array = models_array });
           }
           
           return json.Value{ .object = obj };
       }
   };
   
   // Provider-specific configuration
   pub const ProviderConfig = struct {
       allocator: std.mem.Allocator,
       values: std.StringHashMap([]const u8),
       
       pub fn init(allocator: std.mem.Allocator) ProviderConfig {
           return ProviderConfig{
               .allocator = allocator,
               .values = std.StringHashMap([]const u8).init(allocator),
           };
       }
       
       pub fn set(self: *ProviderConfig, key: []const u8, value: []const u8) !void {
           const key_copy = try self.allocator.dupe(u8, key);
           const value_copy = try self.allocator.dupe(u8, value);
           
           // Free old value if exists
           if (self.values.fetchRemove(key_copy)) |entry| {
               self.allocator.free(entry.key);
               self.allocator.free(entry.value);
           }
           
           try self.values.put(key_copy, value_copy);
       }
       
       pub fn get(self: ProviderConfig, key: []const u8) ?[]const u8 {
           return self.values.get(key);
       }
       
       pub fn toJson(self: ProviderConfig, allocator: std.mem.Allocator) !json.Value {
           var obj = std.StringHashMap(json.Value).init(allocator);
           
           var iter = self.values.iterator();
           while (iter.next()) |entry| {
               // Mask sensitive values
               const value = if (std.mem.indexOf(u8, entry.key_ptr.*, "key") != null or
                               std.mem.indexOf(u8, entry.key_ptr.*, "token") != null)
                   "***REDACTED***"
               else
                   entry.value_ptr.*;
               
               try obj.put(entry.key_ptr.*, json.Value{ .string = value });
           }
           
           return json.Value{ .object = obj };
       }
   };
   ```

2. **Define model types**:
   ```zig
   pub const Model = struct {
       id: ModelId,
       name: []const u8,
       description: []const u8,
       context_length: u32,
       max_output: u32,
       supports_tools: bool,
       supports_vision: bool,
       pricing: Pricing,
       
       pub const Pricing = struct {
           input_per_million: f64,  // USD per million tokens
           output_per_million: f64, // USD per million tokens
           
           pub fn calculateCost(self: Pricing, input_tokens: u32, output_tokens: u32) f64 {
               const input_cost = @intToFloat(f64, input_tokens) * self.input_per_million / 1_000_000;
               const output_cost = @intToFloat(f64, output_tokens) * self.output_per_million / 1_000_000;
               return input_cost + output_cost;
           }
       };
       
       pub fn toJson(self: Model, allocator: std.mem.Allocator) !json.Value {
           var obj = std.StringHashMap(json.Value).init(allocator);
           
           try obj.put("id", json.Value{ .string = self.id });
           try obj.put("name", json.Value{ .string = self.name });
           try obj.put("description", json.Value{ .string = self.description });
           try obj.put("context_length", json.Value{ .integer = @intCast(i64, self.context_length) });
           try obj.put("max_output", json.Value{ .integer = @intCast(i64, self.max_output) });
           try obj.put("supports_tools", json.Value{ .bool = self.supports_tools });
           try obj.put("supports_vision", json.Value{ .bool = self.supports_vision });
           
           var pricing = std.StringHashMap(json.Value).init(allocator);
           try pricing.put("input_per_million", json.Value{ .float = self.pricing.input_per_million });
           try pricing.put("output_per_million", json.Value{ .float = self.pricing.output_per_million });
           try obj.put("pricing", json.Value{ .object = pricing });
           
           return json.Value{ .object = obj };
       }
   };
   ```

3. **Implement provider manager**:
   ```zig
   pub const ProviderManager = struct {
       allocator: std.mem.Allocator,
       providers: std.StringHashMap(*Provider),
       config_path: []const u8,
       executable_path: []const u8,
       mutex: std.Thread.Mutex,
       
       pub fn init(allocator: std.mem.Allocator, config_path: []const u8) !ProviderManager {
           var manager = ProviderManager{
               .allocator = allocator,
               .providers = std.StringHashMap(*Provider).init(allocator),
               .config_path = config_path,
               .executable_path = "plue-ai-provider", // TODO: Make configurable
               .mutex = std.Thread.Mutex{},
           };
           
           // Register built-in providers
           try manager.registerBuiltinProviders();
           
           // Load saved configurations
           try manager.loadConfigurations();
           
           return manager;
       }
       
       fn registerBuiltinProviders(self: *ProviderManager) !void {
           // Anthropic
           {
               const provider = try self.allocator.create(Provider);
               provider.* = try Provider.init(self.allocator, "anthropic", "Anthropic Claude");
               provider.description = "Claude 3 family of models";
               provider.auth_type = .api_key;
               try self.providers.put(provider.id, provider);
           }
           
           // OpenAI
           {
               const provider = try self.allocator.create(Provider);
               provider.* = try Provider.init(self.allocator, "openai", "OpenAI");
               provider.description = "GPT-4 and GPT-3.5 models";
               provider.auth_type = .api_key;
               try self.providers.put(provider.id, provider);
           }
           
           // GitHub Copilot
           {
               const provider = try self.allocator.create(Provider);
               provider.* = try Provider.init(self.allocator, "github-copilot", "GitHub Copilot");
               provider.description = "GitHub Copilot Chat";
               provider.auth_type = .oauth;
               try self.providers.put(provider.id, provider);
           }
           
           // Add other providers...
           
           std.log.info("Registered {} built-in providers", .{self.providers.count()});
       }
       
       pub fn configure(self: *ProviderManager, provider_id: ProviderId, config_json: []const u8) !void {
           self.mutex.lock();
           defer self.mutex.unlock();
           
           const provider = self.providers.get(provider_id) orelse return error.NotFound;
           
           // Parse configuration
           const config = try json.parse(self.allocator, config_json);
           defer config.deinit();
           
           // Update provider configuration
           var iter = config.object.iterator();
           while (iter.next()) |entry| {
               try provider.config.set(entry.key_ptr.*, entry.value_ptr.*.string);
           }
           
           // Clear cached auth status
           provider.last_auth_check = null;
           
           // Save configuration
           try self.saveConfiguration(provider);
       }
       
       pub fn setEnabled(self: *ProviderManager, provider_id: ProviderId, enabled: bool) !void {
           self.mutex.lock();
           defer self.mutex.unlock();
           
           const provider = self.providers.get(provider_id) orelse return error.NotFound;
           provider.enabled = enabled;
           
           // If enabling, test authentication
           if (enabled) {
               try self.testAuth(provider_id);
           }
           
           try self.saveConfiguration(provider);
       }
   };
   ```

4. **Implement provider communication**:
   ```zig
   pub fn testAuth(self: *ProviderManager, provider_id: ProviderId) !void {
       const provider = self.providers.get(provider_id) orelse return error.NotFound;
       
       // Build request for provider executable
       const request = try json.stringify(self.allocator, .{
           .action = "authenticate",
           .provider = provider_id,
           .params = try provider.config.toJson(self.allocator),
       }, .{});
       defer self.allocator.free(request);
       
       // Spawn provider executable
       const response = try self.callProviderExecutable(request, 30000);
       defer self.allocator.free(response);
       
       // Parse response
       const result = try json.parse(self.allocator, response);
       defer result.deinit();
       
       if (!result.object.get("success").?.bool) {
           const error_msg = result.object.get("error").?.object.get("message").?.string;
           std.log.err("Provider auth failed: {s}", .{error_msg});
           return error.ProviderAuthFailed;
       }
       
       // Update auth check timestamp
       provider.last_auth_check = std.time.milliTimestamp();
   }
   
   pub fn getModels(self: *ProviderManager, provider_id: ProviderId, allocator: std.mem.Allocator) ![]u8 {
       self.mutex.lock();
       defer self.mutex.unlock();
       
       const provider = self.providers.get(provider_id) orelse return error.NotFound;
       
       // Return cached models if recent
       if (provider.models) |models| {
           if (provider.last_auth_check) |last_check| {
               const age_ms = std.time.milliTimestamp() - last_check;
               if (age_ms < 3600_000) { // 1 hour cache
                   var models_array = std.ArrayList(json.Value).init(allocator);
                   for (models) |model| {
                       try models_array.append(try model.toJson(allocator));
                   }
                   return json.stringify(allocator, models_array.items, .{});
               }
           }
       }
       
       // Fetch fresh models from provider
       const request = try json.stringify(self.allocator, .{
           .action = "list_models",
           .provider = provider_id,
           .params = .{},
       }, .{});
       defer self.allocator.free(request);
       
       const response = try self.callProviderExecutable(request, 10000);
       defer self.allocator.free(response);
       
       // Parse and cache models
       const result = try json.parse(self.allocator, response);
       defer result.deinit();
       
       if (result.object.get("success").?.bool) {
           const models_data = result.object.get("data").?.array;
           
           // Clear old models
           if (provider.models) |old_models| {
               for (old_models) |model| {
                   model.deinit(self.allocator);
               }
               self.allocator.free(old_models);
           }
           
           // Parse new models
           var models = std.ArrayList(Model).init(self.allocator);
           for (models_data.items) |model_json| {
               const model = try self.parseModel(model_json);
               try models.append(model);
           }
           
           provider.models = try models.toOwnedSlice();
       }
       
       // Return models as JSON
       return self.getModels(provider_id, allocator); // Recursive call returns cached version
   }
   
   fn callProviderExecutable(self: *ProviderManager, request: []const u8, timeout_ms: u32) ![]u8 {
       // Spawn provider executable
       const argv = [_][]const u8{ self.executable_path };
       
       var child = std.ChildProcess.init(&argv, self.allocator);
       child.stdin_behavior = .Pipe;
       child.stdout_behavior = .Pipe;
       child.stderr_behavior = .Pipe;
       
       try child.spawn();
       
       // Send request
       try child.stdin.?.writeAll(request);
       child.stdin.?.close();
       
       // Read response with timeout
       var response = std.ArrayList(u8).init(self.allocator);
       defer response.deinit();
       
       const start_time = std.time.milliTimestamp();
       var buffer: [4096]u8 = undefined;
       
       while (true) {
           const bytes_read = child.stdout.?.read(&buffer) catch |err| {
               if (err == error.EndOfStream) break;
               return err;
           };
           
           if (bytes_read == 0) break;
           
           try response.appendSlice(buffer[0..bytes_read]);
           
           // Check timeout
           if (std.time.milliTimestamp() - start_time > timeout_ms) {
               _ = child.kill() catch {};
               return error.Timeout;
           }
       }
       
       // Wait for process to exit
       const result = try child.wait();
       if (result != .Exited or result.Exited != 0) {
           // Read stderr for error details
           const stderr = try child.stderr.?.readToEndAlloc(self.allocator, 1024 * 1024);
           defer self.allocator.free(stderr);
           std.log.err("Provider executable failed: {s}", .{stderr});
           return error.ProviderExecutableFailed;
       }
       
       return response.toOwnedSlice();
   }
   ```

5. **Add streaming support for messages**:
   ```zig
   pub const StreamRequest = struct {
       provider_id: ProviderId,
       model_id: ModelId,
       messages: []json.Value,
       options: StreamOptions,
       
       pub const StreamOptions = struct {
           temperature: ?f32 = null,
           max_tokens: ?u32 = null,
           stop_sequences: ?[][]const u8 = null,
           tools: ?[]json.Value = null,
       };
   };
   
   pub fn streamChat(
       self: *ProviderManager,
       request: StreamRequest,
       handler: anytype,
   ) !void {
       const provider = self.providers.get(request.provider_id) orelse return error.NotFound;
       
       if (!provider.enabled) return error.ProviderDisabled;
       
       // Verify model exists
       if (provider.models) |models| {
           var found = false;
           for (models) |model| {
               if (std.mem.eql(u8, model.id, request.model_id)) {
                   found = true;
                   break;
               }
           }
           if (!found) return error.ModelNotFound;
       }
       
       // Build streaming request
       const stream_request = try json.stringify(self.allocator, .{
           .action = "stream_chat",
           .provider = request.provider_id,
           .params = .{
               .messages = request.messages,
               .model = request.model_id,
               .options = request.options,
           },
       }, .{});
       defer self.allocator.free(stream_request);
       
       // Spawn provider and handle streaming
       try self.streamFromProvider(stream_request, handler);
   }
   
   fn streamFromProvider(self: *ProviderManager, request: []const u8, handler: anytype) !void {
       const argv = [_][]const u8{ self.executable_path };
       
       var child = std.ChildProcess.init(&argv, self.allocator);
       child.stdin_behavior = .Pipe;
       child.stdout_behavior = .Pipe;
       child.stderr_behavior = .Pipe;
       
       try child.spawn();
       
       // Send request
       try child.stdin.?.writeAll(request);
       child.stdin.?.close();
       
       // Process streaming response
       var line_buffer = std.ArrayList(u8).init(self.allocator);
       defer line_buffer.deinit();
       
       var buffer: [4096]u8 = undefined;
       while (true) {
           const bytes_read = child.stdout.?.read(&buffer) catch |err| {
               if (err == error.EndOfStream) break;
               return err;
           };
           
           if (bytes_read == 0) break;
           
           // Process line by line (newline-delimited JSON)
           for (buffer[0..bytes_read]) |byte| {
               if (byte == '\n') {
                   if (line_buffer.items.len > 0) {
                       const chunk = try json.parse(self.allocator, line_buffer.items);
                       defer chunk.deinit();
                       
                       try handler.handleChunk(chunk);
                       line_buffer.clearRetainingCapacity();
                   }
               } else {
                   try line_buffer.append(byte);
               }
           }
       }
       
       // Process final line if any
       if (line_buffer.items.len > 0) {
           const chunk = try json.parse(self.allocator, line_buffer.items);
           defer chunk.deinit();
           try handler.handleChunk(chunk);
       }
       
       // Wait for process
       _ = try child.wait();
   }
   ```

6. **Implement FFI exports**:
   ```zig
   var g_provider_manager: ?*ProviderManager = null;
   
   export fn plue_provider_list() [*c]u8 {
       const providers_json = blk: {
           var providers_obj = std.StringHashMap(json.Value).init(g_allocator);
           defer providers_obj.deinit();
           
           var iter = g_provider_manager.?.providers.iterator();
           while (iter.next()) |entry| {
               const provider_json = entry.value_ptr.*.toJson(g_allocator) catch |err| {
                   error_handling.setError(err, "Failed to serialize provider", .{});
                   return null;
               };
               providers_obj.put(entry.key_ptr.*, provider_json) catch |err| {
                   error_handling.setError(err, "Failed to build provider list", .{});
                   return null;
               };
           }
           
           break :blk json.stringify(g_allocator, json.Value{ .object = providers_obj }, .{}) catch |err| {
               error_handling.setError(err, "Failed to stringify providers", .{});
               return null;
           };
       };
       
       return providers_json.ptr;
   }
   
   export fn plue_provider_configure(provider_id: [*:0]const u8, config_json: [*:0]const u8) c_int {
       g_provider_manager.?.configure(
           std.mem.span(provider_id),
           std.mem.span(config_json)
       ) catch |err| {
           error_handling.setError(err, "Failed to configure provider", .{});
           return error_handling.errorToCode(err);
       };
       
       return 0;
   }
   
   export fn plue_provider_set_enabled(provider_id: [*:0]const u8, enabled: bool) c_int {
       g_provider_manager.?.setEnabled(
           std.mem.span(provider_id),
           enabled
       ) catch |err| {
           error_handling.setError(err, "Failed to set provider enabled state", .{});
           return error_handling.errorToCode(err);
       };
       
       return 0;
   }
   
   export fn plue_provider_test_auth(provider_id: [*:0]const u8) c_int {
       g_provider_manager.?.testAuth(std.mem.span(provider_id)) catch |err| {
           error_handling.setError(err, "Provider authentication failed", .{});
           return error_handling.errorToCode(err);
       };
       
       return 0;
   }
   
   export fn plue_provider_get_models(provider_id: [*:0]const u8) [*c]u8 {
       const models_json = g_provider_manager.?.getModels(
           std.mem.span(provider_id),
           g_allocator
       ) catch |err| {
           error_handling.setError(err, "Failed to get provider models", .{});
           return null;
       };
       
       return models_json.ptr;
   }
   ```

### Implementation Approach

Follow TDD methodology:

1. **Write comprehensive tests**:
   - Test provider registration
   - Test configuration persistence
   - Test authentication flows
   - Test model discovery
   - Test streaming communication
   - Test error handling

2. **Implement incrementally**:
   - Provider types and registry
   - Configuration management
   - Executable communication
   - Model caching
   - Streaming support
   - FFI integration

3. **Focus on reliability**:
   - Handle executable crashes
   - Timeout long operations
   - Cache appropriately
   - Validate all inputs

### Git Workflow

```bash
git worktree add worktrees/provider-management -b feat/provider-management
cd worktrees/provider-management
```

Commits:
- `feat: define provider types and registry`
- `feat: implement provider configuration`
- `feat: add provider executable communication`
- `feat: implement model discovery and caching`
- `feat: add streaming chat support`
- `feat: export provider FFI functions`
- `test: comprehensive provider tests`
- `feat: integrate providers with message system`

## Success Criteria

✅ **Task is complete when**:
1. All built-in providers are registered
2. Configuration persists across restarts
3. Authentication works for all provider types
4. Models are discovered and cached properly
5. Streaming works reliably with the message system
6. Provider executable crashes are handled gracefully
7. FFI functions work correctly from Swift
8. Test coverage exceeds 95%

## Technical Considerations

<security_requirements>
- Never log API keys or tokens
- Mask sensitive config in JSON
- Validate provider responses
- Sanitize error messages
- Use secure storage for credentials
</security_requirements>

<reliability_requirements>
- Handle executable crashes
- Implement timeouts
- Retry transient failures
- Cache model lists
- Clean up zombie processes
</reliability_requirements>

<performance_requirements>
- Minimize executable spawning
- Stream responses efficiently
- Cache when appropriate
- Reuse connections
- Handle backpressure
</performance_requirements>

Remember: The provider system is critical for AI functionality. It must be robust, secure, and handle various authentication methods and streaming protocols gracefully.