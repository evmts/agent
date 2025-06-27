# Implement Tool Registry System for Plue AI Editor

You are an AI agent executing a well-scoped task to build an AI editor in Zig. This task focuses on creating the tool registry system that manages all tools available to AI agents, including registration, discovery, execution, and metadata tracking.

## Context

<context>
<project_overview>
Plue's tool system enables AI agents to interact with the environment:
- Tools are functions that agents can call (bash, file operations, web fetch, etc.)
- Each tool has a schema defining its parameters and return type
- Tools execute in a controlled context with abort signals
- Tool invocations are tracked in message history
- The registry provides tool discovery and validation
</project_overview>

<existing_infrastructure>
From previous implementations:
- Message system tracks tool invocations via ToolUsePart and ToolResultPart
- Session management provides abort signals for cancellation
- Error handling system provides robust error propagation
- JSON utilities handle parameter validation
- FFI patterns are established for C interop
</existing_infrastructure>

<api_specification>
From PLUE_CORE_API.md:
```c
// Tool execution context passed to tool implementations
typedef struct {
    const char* session_id;
    const char* message_id;
    void* abort_signal;
    void (*metadata_callback)(const char* metadata_json, void* user_data);
    void* user_data;
} plue_tool_context_t;

// List all available tools as JSON
export fn plue_tool_list() [*c]u8;

// Execute a tool
export fn plue_tool_execute(
    tool_name: [*:0]const u8,
    params_json: [*:0]const u8,
    context: *const plue_tool_context_t
) [*c]u8;
```
</api_specification>

<reference_implementation>
OpenCode (in opencode/) has a comprehensive tool system:
- opencode/packages/opencode/src/tool/tool.ts - Tool registry and types
- Each tool has a JSON schema for parameters
- Tools support streaming metadata during execution
- Execution context includes abort signals and session info
- Tools are discovered dynamically at runtime
</reference_implementation>
</context>

## Task: Implement Tool Registry System

### Requirements

1. **Create tool abstraction** that defines:
   - Tool metadata (name, description)
   - Parameter schema for validation
   - Execution interface
   - Result formatting
   - Error handling

2. **Build registry system** for:
   - Tool registration at startup
   - Dynamic tool discovery
   - Schema validation
   - Tool listing with metadata
   - Execution routing

3. **Implement execution context**:
   - Session and message tracking
   - Abort signal propagation
   - Metadata streaming callbacks
   - Resource cleanup on cancellation

4. **Add tool lifecycle management**:
   - Initialization and cleanup
   - Dependency injection
   - Configuration support
   - Performance metrics

### Detailed Steps

1. **Create src/tool/tool.zig with core abstractions**:
   ```zig
   const std = @import("std");
   const json = @import("../json.zig");
   const error_handling = @import("../error.zig");
   
   // Tool metadata and schema
   pub const ToolInfo = struct {
       name: []const u8,
       description: []const u8,
       parameters_schema: json.Schema,
       returns_schema: json.Schema,
       
       pub fn toJson(self: ToolInfo, allocator: Allocator) !json.Value {
           var obj = std.StringHashMap(json.Value).init(allocator);
           try obj.put("name", json.Value{ .string = self.name });
           try obj.put("description", json.Value{ .string = self.description });
           try obj.put("parameters", try self.parameters_schema.toJson(allocator));
           try obj.put("returns", try self.returns_schema.toJson(allocator));
           return json.Value{ .object = obj };
       }
   };
   
   // Execution context for tools
   pub const ToolContext = struct {
       session_id: []const u8,
       message_id: []const u8,
       abort_signal: *std.Thread.ResetEvent,
       metadata_callback: ?MetadataCallback,
       user_data: ?*anyopaque,
       allocator: Allocator,
       
       pub const MetadataCallback = fn (metadata_json: [*:0]const u8, user_data: ?*anyopaque) callconv(.C) void;
       
       pub fn sendMetadata(self: *ToolContext, metadata: anytype) !void {
           if (self.metadata_callback) |callback| {
               const metadata_json = try json.stringifyZ(self.allocator, metadata, .{});
               defer self.allocator.free(metadata_json);
               callback(metadata_json.ptr, self.user_data);
           }
       }
       
       pub fn checkAbort(self: *ToolContext) !void {
           if (self.abort_signal.isSet()) {
               return error.Aborted;
           }
       }
   };
   
   // Tool interface that all tools must implement
   pub const Tool = struct {
       // Static metadata
       info: ToolInfo,
       
       // Dynamic execution function
       executeFn: fn (self: *Tool, params: json.Value, context: *ToolContext) anyerror!json.Value,
       
       // Optional initialization
       initFn: ?fn (self: *Tool, allocator: Allocator) anyerror!void = null,
       
       // Optional cleanup
       deinitFn: ?fn (self: *Tool) void = null,
       
       // Execute with parameter validation
       pub fn execute(self: *Tool, params_json: []const u8, context: *ToolContext) !json.Value {
           // Parse parameters
           const params = try json.parse(context.allocator, params_json);
           defer params.deinit();
           
           // Validate against schema
           try self.info.parameters_schema.validate(params);
           
           // Execute tool
           const result = try self.executeFn(self, params, context);
           
           // Validate result
           try self.info.returns_schema.validate(result);
           
           return result;
       }
   };
   ```

2. **Implement tool registry**:
   ```zig
   pub const ToolRegistry = struct {
       allocator: Allocator,
       tools: std.StringHashMap(*Tool),
       mutex: std.Thread.Mutex,
       
       pub fn init(allocator: Allocator) ToolRegistry {
           return ToolRegistry{
               .allocator = allocator,
               .tools = std.StringHashMap(*Tool).init(allocator),
               .mutex = std.Thread.Mutex{},
           };
       }
       
       pub fn register(self: *ToolRegistry, tool: *Tool) !void {
           self.mutex.lock();
           defer self.mutex.unlock();
           
           // Initialize tool if needed
           if (tool.initFn) |initFn| {
               try initFn(tool, self.allocator);
           }
           
           // Add to registry
           try self.tools.put(tool.info.name, tool);
           
           std.log.info("Registered tool: {s}", .{tool.info.name});
       }
       
       pub fn unregister(self: *ToolRegistry, name: []const u8) void {
           self.mutex.lock();
           defer self.mutex.unlock();
           
           if (self.tools.fetchRemove(name)) |entry| {
               // Cleanup tool if needed
               if (entry.value.deinitFn) |deinitFn| {
                   deinitFn(entry.value);
               }
           }
       }
       
       pub fn get(self: *ToolRegistry, name: []const u8) ?*Tool {
           self.mutex.lock();
           defer self.mutex.unlock();
           
           return self.tools.get(name);
       }
       
       pub fn list(self: *ToolRegistry, allocator: Allocator) ![]u8 {
           self.mutex.lock();
           defer self.mutex.unlock();
           
           var tools_obj = std.StringHashMap(json.Value).init(allocator);
           defer tools_obj.deinit();
           
           var iter = self.tools.iterator();
           while (iter.next()) |entry| {
               const tool_info = try entry.value_ptr.*.info.toJson(allocator);
               try tools_obj.put(entry.key_ptr.*, tool_info);
           }
           
           return json.stringify(allocator, json.Value{ .object = tools_obj }, .{});
       }
       
       pub fn execute(
           self: *ToolRegistry,
           tool_name: []const u8,
           params_json: []const u8,
           context: *ToolContext,
       ) !json.Value {
           // Get tool from registry
           const tool = self.get(tool_name) orelse return error.NotFound;
           
           // Track execution metrics
           const start_time = std.time.milliTimestamp();
           defer {
               const duration = std.time.milliTimestamp() - start_time;
               std.log.info("Tool {s} executed in {d}ms", .{ tool_name, duration });
           }
           
           // Execute with error handling
           return tool.execute(params_json, context) catch |err| {
               std.log.err("Tool {s} failed: {}", .{ tool_name, err });
               
               // Send error metadata
               try context.sendMetadata(.{
                   .type = "error",
                   .tool = tool_name,
                   .error = @errorName(err),
               });
               
               return err;
           };
       }
   };
   ```

3. **Create schema builder utilities**:
   ```zig
   pub const SchemaBuilder = struct {
       allocator: Allocator,
       
       pub fn init(allocator: Allocator) SchemaBuilder {
           return SchemaBuilder{ .allocator = allocator };
       }
       
       pub fn object(self: SchemaBuilder, properties: anytype) !json.Schema {
           var props = std.StringHashMap(json.SchemaNode).init(self.allocator);
           
           inline for (std.meta.fields(@TypeOf(properties))) |field| {
               const schema_node = @field(properties, field.name);
               try props.put(field.name, schema_node);
           }
           
           return json.Schema{
               .root = json.SchemaNode{
                   .object = json.ObjectSchema{
                       .properties = props,
                       .required = null, // TODO: Add required fields
                       .additional_properties = false,
                   },
               },
           };
       }
       
       pub fn string(self: SchemaBuilder) json.SchemaNode {
           return json.SchemaNode{
               .string = json.StringSchema{
                   .min_length = null,
                   .max_length = null,
                   .pattern = null,
               },
           };
       }
       
       pub fn number(self: SchemaBuilder) json.SchemaNode {
           return json.SchemaNode{
               .number = json.NumberSchema{
                   .minimum = null,
                   .maximum = null,
                   .exclusive_minimum = false,
                   .exclusive_maximum = false,
               },
           };
       }
       
       pub fn boolean(self: SchemaBuilder) json.SchemaNode {
           return json.SchemaNode{ .boolean = {} };
       }
       
       pub fn array(self: SchemaBuilder, items: json.SchemaNode) json.SchemaNode {
           return json.SchemaNode{
               .array = json.ArraySchema{
                   .items = &items,
                   .min_items = null,
                   .max_items = null,
               },
           };
       }
   };
   ```

4. **Implement base tool helpers**:
   ```zig
   // Helper for creating simple tools
   pub fn createSimpleTool(
       comptime name: []const u8,
       comptime description: []const u8,
       comptime ParamsType: type,
       comptime ResultType: type,
       comptime executeFn: fn (params: ParamsType, context: *ToolContext) anyerror!ResultType,
   ) type {
       return struct {
           tool: Tool,
           
           pub fn init(allocator: Allocator) !@This() {
               const builder = SchemaBuilder.init(allocator);
               
               return @This(){
                   .tool = Tool{
                       .info = ToolInfo{
                           .name = name,
                           .description = description,
                           .parameters_schema = try builder.fromType(ParamsType),
                           .returns_schema = try builder.fromType(ResultType),
                       },
                       .executeFn = executeWrapper,
                   },
               };
           }
           
           fn executeWrapper(tool: *Tool, params: json.Value, context: *ToolContext) !json.Value {
               // Parse JSON to typed params
               const typed_params = try json.parseInto(ParamsType, context.allocator, params);
               defer typed_params.deinit();
               
               // Execute with typed params
               const result = try executeFn(typed_params, context);
               
               // Convert result to JSON
               return json.toValue(context.allocator, result);
           }
       };
   }
   ```

5. **Add execution tracking and metrics**:
   ```zig
   pub const ToolMetrics = struct {
       execution_count: std.atomic.Atomic(u64),
       total_duration_ms: std.atomic.Atomic(u64),
       error_count: std.atomic.Atomic(u64),
       last_execution: std.atomic.Atomic(i64),
       
       pub fn init() ToolMetrics {
           return ToolMetrics{
               .execution_count = std.atomic.Atomic(u64).init(0),
               .total_duration_ms = std.atomic.Atomic(u64).init(0),
               .error_count = std.atomic.Atomic(u64).init(0),
               .last_execution = std.atomic.Atomic(i64).init(0),
           };
       }
       
       pub fn recordExecution(self: *ToolMetrics, duration_ms: u64, success: bool) void {
           _ = self.execution_count.fetchAdd(1, .Monotonic);
           _ = self.total_duration_ms.fetchAdd(duration_ms, .Monotonic);
           if (!success) {
               _ = self.error_count.fetchAdd(1, .Monotonic);
           }
           self.last_execution.store(std.time.milliTimestamp(), .Monotonic);
       }
       
       pub fn getStats(self: *ToolMetrics) ToolStats {
           const count = self.execution_count.load(.Monotonic);
           const total_ms = self.total_duration_ms.load(.Monotonic);
           
           return ToolStats{
               .execution_count = count,
               .average_duration_ms = if (count > 0) total_ms / count else 0,
               .error_count = self.error_count.load(.Monotonic),
               .last_execution = self.last_execution.load(.Monotonic),
           };
       }
   };
   ```

6. **Implement FFI exports**:
   ```zig
   // Global tool registry
   var g_tool_registry: ?*ToolRegistry = null;
   
   export fn plue_tool_list() [*c]u8 {
       const list_json = g_tool_registry.?.list(g_allocator) catch |err| {
           error_handling.setError(err, "Failed to list tools", .{});
           return null;
       };
       
       return list_json.ptr;
   }
   
   export fn plue_tool_execute(
       tool_name: [*:0]const u8,
       params_json: [*:0]const u8,
       c_context: *const plue_tool_context_t,
   ) [*c]u8 {
       // Convert C context to Zig context
       var context = ToolContext{
           .session_id = std.mem.span(c_context.session_id),
           .message_id = std.mem.span(c_context.message_id),
           .abort_signal = @ptrCast(*std.Thread.ResetEvent, @alignCast(@alignOf(std.Thread.ResetEvent), c_context.abort_signal)),
           .metadata_callback = @ptrCast(?ToolContext.MetadataCallback, c_context.metadata_callback),
           .user_data = c_context.user_data,
           .allocator = g_allocator,
       };
       
       // Execute tool
       const result = g_tool_registry.?.execute(
           std.mem.span(tool_name),
           std.mem.span(params_json),
           &context,
       ) catch |err| {
           error_handling.setError(err, "Tool execution failed", .{});
           
           // Return error as JSON
           const error_json = json.stringify(g_allocator, .{
               .error = @errorName(err),
               .message = error_handling.getLastError(),
           }, .{}) catch return null;
           
           return error_json.ptr;
       };
       
       // Serialize result
       const result_json = json.stringify(g_allocator, result, .{}) catch |err| {
           error_handling.setError(err, "Failed to serialize tool result", .{});
           return null;
       };
       
       return result_json.ptr;
   }
   ```

### Implementation Approach

Follow TDD methodology:

1. **Write comprehensive tests**:
   - Test tool registration and discovery
   - Test parameter validation
   - Test execution with various inputs
   - Test abort signal handling
   - Test metadata callbacks
   - Test concurrent tool execution

2. **Implement incrementally**:
   - Core abstractions first
   - Registry implementation
   - Schema validation
   - Execution with context
   - Metrics and tracking
   - FFI integration

3. **Commit after each component**:
   - Tool abstractions complete
   - Registry working
   - Schema validation added
   - Execution context implemented
   - FFI exports working

### Git Workflow

```bash
git worktree add worktrees/tool-registry -b feat/tool-registry
cd worktrees/tool-registry
```

Commits:
- `feat: define tool abstraction and interfaces`
- `feat: implement tool registry with discovery`
- `feat: add json schema validation for tools`
- `feat: create execution context with abort support`
- `feat: add tool metrics and tracking`
- `feat: export tool FFI functions`
- `test: comprehensive tool registry tests`

## Success Criteria

✅ **Task is complete when**:
1. Tools can be registered with metadata and schemas
2. Tool discovery lists all available tools
3. Parameter validation works with clear errors
4. Execution context propagates abort signals
5. Metadata callbacks stream updates correctly
6. Concurrent tool execution is thread-safe
7. FFI functions work correctly from Swift
8. Test coverage exceeds 95%

## Technical Considerations

<zig_patterns>
- Use comptime for tool creation helpers
- Implement proper error propagation
- Use atomics for metrics counters
- Follow interface segregation principle
- Leverage Zig's type system for safety
</zig_patterns>

<schema_validation>
- Support JSON Schema draft-07 features
- Provide clear validation error messages
- Cache compiled schemas for performance
- Allow custom validators for complex rules
- Consider schema evolution/versioning
</schema_validation>

<performance_requirements>
- Tool discovery should be O(1)
- Schema validation should be cached
- Minimize overhead for simple tools
- Support streaming for large outputs
- Clean up resources on cancellation
</performance_requirements>

Remember: The tool system is how AI agents interact with the world. Make it robust, extensible, and easy to use. This foundation will support all concrete tool implementations.