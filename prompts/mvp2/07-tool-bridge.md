# Create Tool System Bridge

## Context

You are implementing the tool system bridge that connects Plue's C FFI tool API to OpenCode's comprehensive tool execution system. This enables AI agents to interact with the environment through various tools like bash commands, file operations, and web fetching.

### Project State

From previous tasks, you have:
- OpenCode API client with tool endpoints (`src/opencode/api.zig`)
- Session management for tool context
- Message system for tool invocations
- Provider bridge for AI interactions

Now you need to implement the tool execution system.

### Tool API Requirements (from PLUE_CORE_API.md)

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

### OpenCode Tool System

OpenCode provides a rich set of tools:

```typescript
// Core tools
const TOOLS = {
  // Shell execution
  "bash": { timeout: 120000, streaming: true },
  
  // File operations
  "read": { maxLines: 2000 },
  "write": { atomic: true },
  "edit": { validation: true },
  "multi_edit": { transactional: true },
  
  // Search tools
  "glob": { pattern: "**/*.ts" },
  "grep": { regex: true, ripgrep: true },
  "list": { recursive: false },
  
  // Advanced tools
  "patch": { unified: true },
  "web_fetch": { timeout: 30000 },
  "todo_read": {},
  "todo_write": {},
  "task": { subtools: true },
  
  // LSP tools (when available)
  "lsp_hover": {},
  "lsp_diagnostics": {},
};

// Tool result format
interface ToolResult {
  success: boolean;
  output?: string;
  error?: string;
  metadata?: {
    duration?: number;
    bytesRead?: number;
    filesChanged?: string[];
  };
}
```

## Requirements

### 1. Tool Types (`src/tool/types.zig`)

Define tool-related types:

```zig
const std = @import("std");

pub const ToolName = []const u8;

pub const ToolContext = struct {
    /// Session ID for context
    session_id: ?[]const u8,
    
    /// Message ID for tracking
    message_id: ?[]const u8,
    
    /// Abort signal to check
    abort_signal: ?*std.atomic.Value(bool),
    
    /// Metadata callback
    metadata_callback: ?MetadataCallback,
    
    /// User data for callback
    user_data: ?*anyopaque,
    
    /// Check if aborted
    pub fn isAborted(self: *const ToolContext) bool {
        if (self.abort_signal) |signal| {
            return signal.load(.acquire);
        }
        return false;
    }
    
    /// Send metadata
    pub fn sendMetadata(self: *const ToolContext, metadata: anytype) !void {
        if (self.metadata_callback) |callback| {
            const json = try std.json.stringifyAlloc(
                std.heap.page_allocator, // Temporary allocator
                metadata,
                .{},
            );
            defer std.heap.page_allocator.free(json);
            
            callback.call(json, self.user_data);
        }
    }
};

pub const MetadataCallback = struct {
    fn_ptr: *const fn ([*c]const u8, ?*anyopaque) callconv(.C) void,
    
    pub fn call(self: MetadataCallback, json: []const u8, user_data: ?*anyopaque) void {
        self.fn_ptr(@ptrCast([*c]const u8, json.ptr), user_data);
    }
};

pub const ToolDefinition = struct {
    name: []const u8,
    description: []const u8,
    parameters: std.json.Value, // JSON Schema
    streaming: bool = false,
    timeout_ms: u32 = 30000,
};

pub const ToolParams = std.json.Value;

pub const ToolResult = struct {
    success: bool,
    output: ?[]const u8 = null,
    error: ?[]const u8 = null,
    metadata: ?ToolMetadata = null,
};

pub const ToolMetadata = struct {
    duration_ms: ?u32 = null,
    bytes_read: ?usize = null,
    bytes_written: ?usize = null,
    files_changed: ?[]const []const u8 = null,
    commands_executed: ?u32 = null,
    exit_code: ?i32 = null,
};

pub const ToolCategory = enum {
    shell,
    file_system,
    search,
    development,
    information,
    task_management,
    
    pub fn getTools(self: ToolCategory) []const ToolName {
        return switch (self) {
            .shell => &[_]ToolName{"bash"},
            .file_system => &[_]ToolName{ "read", "write", "edit", "multi_edit" },
            .search => &[_]ToolName{ "glob", "grep", "list" },
            .development => &[_]ToolName{ "patch", "lsp_hover", "lsp_diagnostics" },
            .information => &[_]ToolName{"web_fetch"},
            .task_management => &[_]ToolName{ "todo_read", "todo_write", "task" },
        };
    }
};

pub const StreamingToolEvent = union(enum) {
    output: []const u8,
    error: []const u8,
    metadata: ToolMetadata,
    progress: struct {
        current: usize,
        total: ?usize,
        message: ?[]const u8,
    },
    done: ToolResult,
};
```

### 2. Tool Registry (`src/tool/registry.zig`)

Maintain tool definitions and metadata:

```zig
pub const ToolRegistry = struct {
    allocator: std.mem.Allocator,
    tools: std.StringHashMap(ToolDefinition),
    
    /// Initialize with built-in tools
    pub fn init(allocator: std.mem.Allocator) !ToolRegistry {
        var registry = ToolRegistry{
            .allocator = allocator,
            .tools = std.StringHashMap(ToolDefinition).init(allocator),
        };
        
        // Register all built-in tools
        try registry.registerBuiltinTools();
        
        return registry;
    }
    
    /// Register built-in tools
    fn registerBuiltinTools(self: *ToolRegistry) !void {
        // Bash tool
        try self.tools.put("bash", .{
            .name = "bash",
            .description = "Execute bash commands",
            .parameters = try createBashSchema(self.allocator),
            .streaming = true,
            .timeout_ms = 120000,
        });
        
        // Read tool
        try self.tools.put("read", .{
            .name = "read",
            .description = "Read file contents",
            .parameters = try createReadSchema(self.allocator),
            .streaming = false,
            .timeout_ms = 10000,
        });
        
        // Write tool
        try self.tools.put("write", .{
            .name = "write",
            .description = "Write file contents",
            .parameters = try createWriteSchema(self.allocator),
            .streaming = false,
            .timeout_ms = 10000,
        });
        
        // Edit tool
        try self.tools.put("edit", .{
            .name = "edit",
            .description = "Edit file contents",
            .parameters = try createEditSchema(self.allocator),
            .streaming = false,
            .timeout_ms = 10000,
        });
        
        // Multi-edit tool
        try self.tools.put("multi_edit", .{
            .name = "multi_edit",
            .description = "Make multiple edits to a file",
            .parameters = try createMultiEditSchema(self.allocator),
            .streaming = false,
            .timeout_ms = 20000,
        });
        
        // Glob tool
        try self.tools.put("glob", .{
            .name = "glob",
            .description = "Find files matching pattern",
            .parameters = try createGlobSchema(self.allocator),
            .streaming = false,
            .timeout_ms = 30000,
        });
        
        // Grep tool
        try self.tools.put("grep", .{
            .name = "grep",
            .description = "Search file contents",
            .parameters = try createGrepSchema(self.allocator),
            .streaming = true,
            .timeout_ms = 60000,
        });
        
        // List tool
        try self.tools.put("list", .{
            .name = "list",
            .description = "List directory contents",
            .parameters = try createListSchema(self.allocator),
            .streaming = false,
            .timeout_ms = 10000,
        });
        
        // Web fetch tool
        try self.tools.put("web_fetch", .{
            .name = "web_fetch",
            .description = "Fetch web content",
            .parameters = try createWebFetchSchema(self.allocator),
            .streaming = false,
            .timeout_ms = 30000,
        });
        
        // TODO tools
        try self.tools.put("todo_read", .{
            .name = "todo_read",
            .description = "Read todo list",
            .parameters = try createEmptySchema(self.allocator),
            .streaming = false,
            .timeout_ms = 5000,
        });
        
        try self.tools.put("todo_write", .{
            .name = "todo_write",
            .description = "Update todo list",
            .parameters = try createTodoWriteSchema(self.allocator),
            .streaming = false,
            .timeout_ms = 5000,
        });
    }
    
    /// Get tool definition
    pub fn getTool(self: *ToolRegistry, name: []const u8) ?ToolDefinition {
        return self.tools.get(name);
    }
    
    /// List all tools
    pub fn listTools(self: *ToolRegistry) !std.json.Value {
        var result = std.json.ObjectMap.init(self.allocator);
        
        var it = self.tools.iterator();
        while (it.next()) |entry| {
            var tool_obj = std.json.ObjectMap.init(self.allocator);
            try tool_obj.put("description", .{ .string = entry.value_ptr.description });
            try tool_obj.put("parameters", entry.value_ptr.parameters);
            try result.put(entry.key_ptr.*, .{ .object = tool_obj });
        }
        
        return .{ .object = result };
    }
};

// Schema creation functions
fn createBashSchema(allocator: std.mem.Allocator) !std.json.Value {
    var schema = std.json.ObjectMap.init(allocator);
    var properties = std.json.ObjectMap.init(allocator);
    
    // Command property
    var command = std.json.ObjectMap.init(allocator);
    try command.put("type", .{ .string = "string" });
    try command.put("description", .{ .string = "Command to execute" });
    try properties.put("command", .{ .object = command });
    
    // Description property
    var description = std.json.ObjectMap.init(allocator);
    try description.put("type", .{ .string = "string" });
    try description.put("description", .{ .string = "What this command does" });
    try properties.put("description", .{ .object = description });
    
    // Timeout property
    var timeout = std.json.ObjectMap.init(allocator);
    try timeout.put("type", .{ .string = "number" });
    try timeout.put("description", .{ .string = "Timeout in milliseconds" });
    try properties.put("timeout", .{ .object = timeout });
    
    try schema.put("type", .{ .string = "object" });
    try schema.put("properties", .{ .object = properties });
    
    var required = std.json.Array.init(allocator);
    try required.append(.{ .string = "command" });
    try schema.put("required", .{ .array = required });
    
    return .{ .object = schema };
}

fn createReadSchema(allocator: std.mem.Allocator) !std.json.Value {
    var schema = std.json.ObjectMap.init(allocator);
    var properties = std.json.ObjectMap.init(allocator);
    
    // File path property
    var file_path = std.json.ObjectMap.init(allocator);
    try file_path.put("type", .{ .string = "string" });
    try file_path.put("description", .{ .string = "Path to file to read" });
    try properties.put("file_path", .{ .object = file_path });
    
    // Limit property
    var limit = std.json.ObjectMap.init(allocator);
    try limit.put("type", .{ .string = "number" });
    try limit.put("description", .{ .string = "Maximum lines to read" });
    try properties.put("limit", .{ .object = limit });
    
    // Offset property
    var offset = std.json.ObjectMap.init(allocator);
    try offset.put("type", .{ .string = "number" });
    try offset.put("description", .{ .string = "Line offset to start from" });
    try properties.put("offset", .{ .object = offset });
    
    try schema.put("type", .{ .string = "object" });
    try schema.put("properties", .{ .object = properties });
    
    var required = std.json.Array.init(allocator);
    try required.append(.{ .string = "file_path" });
    try schema.put("required", .{ .array = required });
    
    return .{ .object = schema };
}

// ... more schema creation functions
```

### 3. Tool Executor (`src/tool/executor.zig`)

Execute tools through OpenCode:

```zig
pub const ToolExecutor = struct {
    allocator: std.mem.Allocator,
    api: *opencode.OpenCodeApi,
    registry: *ToolRegistry,
    active_executions: std.StringHashMap(*ExecutionState),
    mutex: std.Thread.Mutex,
    
    const ExecutionState = struct {
        tool_name: []const u8,
        start_time: i64,
        context: ToolContext,
        abort_requested: std.atomic.Value(bool),
    };
    
    /// Execute a tool
    pub fn execute(
        self: *ToolExecutor,
        tool_name: []const u8,
        params: std.json.Value,
        context: ToolContext,
    ) !ToolResult {
        // Check if tool exists
        const tool_def = self.registry.getTool(tool_name) orelse {
            return ToolResult{
                .success = false,
                .error = "Unknown tool",
            };
        };
        
        // Validate parameters
        try self.validateParams(tool_def, params);
        
        // Create execution state
        const state = try self.allocator.create(ExecutionState);
        state.* = .{
            .tool_name = tool_name,
            .start_time = std.time.milliTimestamp(),
            .context = context,
            .abort_requested = std.atomic.Value(bool).init(false),
        };
        
        // Track execution
        const exec_id = try std.fmt.allocPrint(self.allocator, "{s}_{d}", .{ tool_name, state.start_time });
        self.mutex.lock();
        try self.active_executions.put(exec_id, state);
        self.mutex.unlock();
        
        defer {
            self.mutex.lock();
            _ = self.active_executions.remove(exec_id);
            self.mutex.unlock();
            self.allocator.free(exec_id);
            self.allocator.destroy(state);
        }
        
        // Send initial metadata
        try context.sendMetadata(.{
            .tool = tool_name,
            .status = "started",
            .timestamp = state.start_time,
        });
        
        // Execute via OpenCode
        const result = self.api.tool.execute(
            tool_name,
            params,
            context.session_id,
            &state.abort_requested,
        ) catch |err| {
            const error_msg = try std.fmt.allocPrint(
                self.allocator,
                "Tool execution failed: {}",
                .{err},
            );
            defer self.allocator.free(error_msg);
            
            return ToolResult{
                .success = false,
                .error = error_msg,
            };
        };
        
        // Calculate duration
        const duration = @intCast(u32, std.time.milliTimestamp() - state.start_time);
        
        // Add metadata
        var final_result = result;
        if (final_result.metadata == null) {
            final_result.metadata = .{};
        }
        final_result.metadata.?.duration_ms = duration;
        
        // Send completion metadata
        try context.sendMetadata(.{
            .tool = tool_name,
            .status = "completed",
            .duration_ms = duration,
            .success = result.success,
        });
        
        return final_result;
    }
    
    /// Execute tool with streaming
    pub fn executeStreaming(
        self: *ToolExecutor,
        tool_name: []const u8,
        params: std.json.Value,
        context: ToolContext,
        callback: StreamCallback,
    ) !void {
        // Similar to execute but with streaming support
        const tool_def = self.registry.getTool(tool_name) orelse {
            return error.UnknownTool;
        };
        
        if (!tool_def.streaming) {
            // Fall back to non-streaming
            const result = try self.execute(tool_name, params, context);
            try callback.onEvent(.{ .done = result }, callback.user_data);
            return;
        }
        
        // Stream via OpenCode
        try self.api.tool.executeStream(
            tool_name,
            params,
            context.session_id,
            struct {
                executor: *ToolExecutor,
                callback: StreamCallback,
                start_time: i64,
                
                pub fn handleEvent(event: opencode.ToolStreamEvent, ctx: *anyopaque) !void {
                    const self_ctx = @ptrCast(*@This(), @alignCast(@alignOf(@This()), ctx));
                    
                    const streaming_event = switch (event) {
                        .output => |text| StreamingToolEvent{ .output = text },
                        .metadata => |meta| blk: {
                            const converted = try self_ctx.executor.convertMetadata(meta);
                            break :blk StreamingToolEvent{ .metadata = converted };
                        },
                        .done => |result| StreamingToolEvent{ .done = result },
                    };
                    
                    try self_ctx.callback.onEvent(streaming_event, self_ctx.callback.user_data);
                }
            }{
                .executor = self,
                .callback = callback,
                .start_time = std.time.milliTimestamp(),
            }.handleEvent,
            null,
        );
    }
    
    /// Validate parameters against schema
    fn validateParams(self: *ToolExecutor, tool: ToolDefinition, params: std.json.Value) !void {
        // Basic validation - in production, use a proper JSON Schema validator
        if (params != .object) {
            return error.InvalidParams;
        }
        
        // Check required fields
        if (tool.parameters.object.get("required")) |required| {
            for (required.array.items) |req_field| {
                const field_name = req_field.string;
                if (!params.object.contains(field_name)) {
                    return error.MissingRequiredParam;
                }
            }
        }
    }
    
    /// Convert metadata format
    fn convertMetadata(self: *ToolExecutor, meta: std.json.Value) !ToolMetadata {
        // Convert from OpenCode format to our format
        return ToolMetadata{
            .duration_ms = if (meta.object.get("duration")) |d| @intCast(u32, d.integer) else null,
            .bytes_read = if (meta.object.get("bytesRead")) |b| @intCast(usize, b.integer) else null,
            .bytes_written = if (meta.object.get("bytesWritten")) |b| @intCast(usize, b.integer) else null,
        };
    }
};

pub const StreamCallback = struct {
    fn_ptr: *const fn (event: StreamingToolEvent, user_data: ?*anyopaque) anyerror!void,
    user_data: ?*anyopaque,
    
    pub fn onEvent(self: StreamCallback, event: StreamingToolEvent, user_data: ?*anyopaque) !void {
        try self.fn_ptr(event, user_data);
    }
};
```

### 4. FFI Implementation (`src/tool/ffi.zig`)

Implement C FFI functions:

```zig
const std = @import("std");
const c = @cImport({});
const types = @import("types.zig");
const ToolRegistry = @import("registry.zig").ToolRegistry;
const ToolExecutor = @import("executor.zig").ToolExecutor;
const error_handling = @import("../error/handling.zig");

/// Global tool system
var tool_registry: ?*ToolRegistry = null;
var tool_executor: ?*ToolExecutor = null;

/// Initialize tool system
pub fn init(allocator: std.mem.Allocator, api: *opencode.OpenCodeApi) !void {
    tool_registry = try allocator.create(ToolRegistry);
    tool_registry.?.* = try ToolRegistry.init(allocator);
    
    tool_executor = try allocator.create(ToolExecutor);
    tool_executor.?.* = .{
        .allocator = allocator,
        .api = api,
        .registry = tool_registry.?,
        .active_executions = std.StringHashMap(*ToolExecutor.ExecutionState).init(allocator),
        .mutex = .{},
    };
}

/// List all available tools as JSON
export fn plue_tool_list() [*c]u8 {
    const registry = tool_registry orelse {
        error_handling.setLastError(error.NotInitialized, "Tool registry not initialized");
        return null;
    };
    
    const tools_json = registry.listTools() catch |err| {
        error_handling.setLastError(err, "Failed to list tools");
        return null;
    };
    
    const json_string = std.json.stringifyAlloc(
        registry.allocator,
        tools_json,
        .{},
    ) catch |err| {
        error_handling.setLastError(err, "Failed to serialize tools");
        return null;
    };
    
    return json_string.ptr;
}

/// Execute a tool
export fn plue_tool_execute(
    tool_name: [*:0]const u8,
    params_json: [*:0]const u8,
    context: *const c.plue_tool_context_t,
) [*c]u8 {
    if (tool_name == null or params_json == null or context == null) {
        error_handling.setLastError(error.InvalidParam, "Invalid parameters");
        return null;
    }
    
    const executor = tool_executor orelse {
        error_handling.setLastError(error.NotInitialized, "Tool executor not initialized");
        return null;
    };
    
    const tool_name_slice = std.mem.span(tool_name);
    const params_slice = std.mem.span(params_json);
    
    // Parse parameters
    const params = std.json.parseFromSlice(
        std.json.Value,
        executor.allocator,
        params_slice,
        .{},
    ) catch |err| {
        error_handling.setLastError(err, "Failed to parse parameters");
        return null;
    };
    defer params.deinit();
    
    // Convert context
    const zig_context = types.ToolContext{
        .session_id = if (context.session_id) |sid| std.mem.span(sid) else null,
        .message_id = if (context.message_id) |mid| std.mem.span(mid) else null,
        .abort_signal = if (context.abort_signal) |sig| @ptrCast(*std.atomic.Value(bool), @alignCast(@alignOf(std.atomic.Value(bool)), sig)) else null,
        .metadata_callback = if (context.metadata_callback) |cb| types.MetadataCallback{ .fn_ptr = cb } else null,
        .user_data = context.user_data,
    };
    
    // Execute tool
    const result = executor.execute(
        tool_name_slice,
        params.value,
        zig_context,
    ) catch |err| {
        error_handling.setLastError(err, "Tool execution failed");
        return null;
    };
    
    // Convert result to JSON
    const result_json = std.json.stringifyAlloc(
        executor.allocator,
        result,
        .{},
    ) catch |err| {
        error_handling.setLastError(err, "Failed to serialize result");
        return null;
    };
    
    return result_json.ptr;
}

/// C-compatible context structure
pub const c_plue_tool_context_t = extern struct {
    session_id: [*c]const u8,
    message_id: [*c]const u8,
    abort_signal: ?*anyopaque,
    metadata_callback: ?*const fn ([*c]const u8, ?*anyopaque) callconv(.C) void,
    user_data: ?*anyopaque,
};
```

### 5. Tool Validators (`src/tool/validators.zig`)

Validate tool inputs and outputs:

```zig
pub const Validators = struct {
    /// Validate file path
    pub fn validatePath(path: []const u8) !void {
        // Prevent directory traversal
        if (std.mem.indexOf(u8, path, "..") != null) {
            return error.InvalidPath;
        }
        
        // Check absolute path
        if (!std.fs.path.isAbsolute(path)) {
            return error.PathNotAbsolute;
        }
    }
    
    /// Validate bash command
    pub fn validateCommand(command: []const u8) !void {
        // Check for dangerous patterns
        const dangerous = [_][]const u8{
            "rm -rf /",
            ":(){ :|:& };:",  // Fork bomb
            "> /dev/sda",
        };
        
        for (dangerous) |pattern| {
            if (std.mem.indexOf(u8, command, pattern) != null) {
                return error.DangerousCommand;
            }
        }
    }
    
    /// Validate URL
    pub fn validateUrl(url: []const u8) !void {
        // Basic URL validation
        if (!std.mem.startsWith(u8, url, "http://") and
            !std.mem.startsWith(u8, url, "https://")) {
            return error.InvalidUrl;
        }
        
        // Check for local addresses
        const local_patterns = [_][]const u8{
            "localhost",
            "127.0.0.1",
            "0.0.0.0",
            "::1",
        };
        
        for (local_patterns) |pattern| {
            if (std.mem.indexOf(u8, url, pattern) != null) {
                return error.LocalUrlNotAllowed;
            }
        }
    }
    
    /// Validate file size
    pub fn validateFileSize(size: usize) !void {
        const max_size = 10 * 1024 * 1024; // 10MB
        if (size > max_size) {
            return error.FileTooLarge;
        }
    }
};
```

### 6. Tool Permissions (`src/tool/permissions.zig`)

Handle tool access control:

```zig
pub const ToolPermissions = struct {
    allocator: std.mem.Allocator,
    allowed_paths: std.ArrayList([]const u8),
    denied_tools: std.StringHashMap(void),
    read_only: bool = false,
    
    /// Check if tool is allowed
    pub fn isToolAllowed(self: *ToolPermissions, tool_name: []const u8) bool {
        if (self.denied_tools.contains(tool_name)) {
            return false;
        }
        
        // Check read-only mode
        if (self.read_only) {
            const write_tools = [_][]const u8{ "write", "edit", "multi_edit", "bash" };
            for (write_tools) |write_tool| {
                if (std.mem.eql(u8, tool_name, write_tool)) {
                    return false;
                }
            }
        }
        
        return true;
    }
    
    /// Check if path is allowed
    pub fn isPathAllowed(self: *ToolPermissions, path: []const u8) bool {
        // If no allowed paths specified, allow all
        if (self.allowed_paths.items.len == 0) {
            return true;
        }
        
        // Check if path is under allowed directories
        for (self.allowed_paths.items) |allowed| {
            if (std.mem.startsWith(u8, path, allowed)) {
                return true;
            }
        }
        
        return false;
    }
    
    /// Add allowed path
    pub fn allowPath(self: *ToolPermissions, path: []const u8) !void {
        const path_copy = try self.allocator.dupe(u8, path);
        try self.allowed_paths.append(path_copy);
    }
    
    /// Deny specific tool
    pub fn denyTool(self: *ToolPermissions, tool_name: []const u8) !void {
        try self.denied_tools.put(tool_name, {});
    }
};
```

## Implementation Steps

### Step 1: Define Tool Types
1. Create `src/tool/types.zig`
2. Define all tool structures
3. Add streaming event types
4. Write type tests

### Step 2: Create Tool Registry
1. Create `src/tool/registry.zig`
2. Register all built-in tools
3. Define tool schemas
4. Test registry operations

### Step 3: Implement Tool Executor
1. Create `src/tool/executor.zig`
2. Add execution logic
3. Implement streaming support
4. Handle abort signals

### Step 4: Create FFI Functions
1. Create `src/tool/ffi.zig`
2. Implement exports
3. Add context conversion
4. Test with C client

### Step 5: Add Validators
1. Create `src/tool/validators.zig`
2. Implement safety checks
3. Add path validation
4. Test edge cases

### Step 6: Implement Permissions
1. Create `src/tool/permissions.zig`
2. Add access control
3. Support read-only mode
4. Test permission enforcement

## Testing Requirements

1. **Unit Tests** (>95% coverage):
   - Tool execution
   - Parameter validation
   - Result formatting
   - Permission checks

2. **Integration Tests**:
   - All tool types
   - Streaming tools
   - Abort handling
   - Error scenarios

3. **Safety Tests**:
   - Path traversal prevention
   - Command injection prevention
   - Resource limits
   - Permission enforcement

## Example Usage (from C)

```c
// List available tools
char* tools_json = plue_tool_list();
printf("Available tools: %s\n", tools_json);
plue_free_json(tools_json);

// Prepare tool context
plue_tool_context_t ctx = {
    .session_id = "session_123",
    .message_id = "msg_456",
    .abort_signal = NULL,
    .metadata_callback = on_metadata,
    .user_data = NULL
};

// Execute bash command
const char* bash_params = "{\"command\": \"ls -la\", \"description\": \"List files\"}";
char* result = plue_tool_execute("bash", bash_params, &ctx);
if (result) {
    printf("Result: %s\n", result);
    plue_free_json(result);
}

// Read a file
const char* read_params = "{\"file_path\": \"/tmp/test.txt\"}";
result = plue_tool_execute("read", read_params, &ctx);
if (result) {
    printf("File contents: %s\n", result);
    plue_free_json(result);
}

// Metadata callback
void on_metadata(const char* metadata_json, void* user_data) {
    printf("Tool metadata: %s\n", metadata_json);
}
```

## Success Criteria

The implementation is complete when:
- [ ] All OpenCode tools are accessible
- [ ] Tool execution works reliably
- [ ] Streaming tools provide real-time output
- [ ] Abort signals interrupt execution
- [ ] Permissions are enforced correctly
- [ ] Validation prevents dangerous operations
- [ ] All tests pass with >95% coverage
- [ ] Memory usage is stable

## Git Workflow

Continue in the same worktree:
```bash
cd ../plue-server-management
```

Commit with conventional commits:
- `feat: define tool types and registry`
- `feat: implement tool executor`
- `feat: add tool FFI functions`
- `feat: implement tool validators`
- `feat: add permission system`
- `test: add tool bridge tests`

The branch remains: `feat_add_opencode_server_management`