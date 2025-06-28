# Build Message System Bridge

## Context

You are implementing the message system bridge that connects Plue's C FFI message API to OpenCode's message and streaming endpoints. This is crucial for handling conversations between users and AI assistants.

### Project State

From previous tasks, you have:
- OpenCode API client with message endpoints (`src/opencode/api.zig`)
- Session management bridge (`src/session/ffi.zig`)
- HTTP client with SSE support (`src/http/sse.zig`)

Now you need to implement message sending, retrieval, and streaming responses.

### Message API Requirements (from PLUE_CORE_API.md)

```c
// Send a user message to a session
export fn plue_message_send(
    session: ?*anyopaque,
    provider_id: [*:0]const u8,
    model_id: [*:0]const u8,
    message_json: [*:0]const u8
) [*c]u8;

// Get all messages for a session as JSON array
export fn plue_message_list(session: ?*anyopaque) [*c]u8;

// Get a specific message by ID as JSON
export fn plue_message_get(session: ?*anyopaque, message_id: [*:0]const u8) [*c]u8;

// Stream response for a message
typedef fn(*const u8, usize, *anyopaque) void plue_stream_callback;
export fn plue_message_stream_response(
    session: ?*anyopaque,
    message_id: [*:0]const u8,
    provider_id: [*:0]const u8,
    model_id: [*:0]const u8,
    callback: plue_stream_callback,
    user_data: ?*anyopaque
) c_int;
```

### OpenCode Message Model

```typescript
// Message.Info structure from OpenCode
interface MessageInfo {
  id: string;
  role: "user" | "assistant";
  parts: MessagePart[];
  metadata: {
    time: {
      created: number;       // Unix timestamp (ms)
      completed?: number;    // When assistant finished
    };
    error?: NamedError;      // Provider errors
    sessionID: string;
    tool?: Record<string, any>; // Tool metadata
    providerID?: string;
    modelID?: string;
    usage?: {                // Token usage
      inputTokens: number;
      outputTokens: number;
      totalTokens: number;
    };
  };
}

// Message parts (actual types from OpenCode)
type MessagePart = 
  | { type: "text", text: string }
  | { type: "reasoning", text: string, providerMetadata?: any }
  | { type: "tool-invocation", toolInvocation: ToolInvocation }
  | { type: "source-url", sourceId: string, url: string, title?: string }
  | { type: "file", name: string, data: string, mimeType: string }
  | { type: "step-start", name: string, timestamp: number };

// Tool invocation states
type ToolInvocation =
  | { state: "call", toolCallId: string, toolName: string, args: any }
  | { state: "partial-call", toolCallId: string, toolName: string, args: any }
  | { state: "result", toolCallId: string, toolName: string, args: any, result: string };

// Event stream from Bus (not direct streaming)
type BusEvent =
  | { type: "message.created", message: MessageInfo }
  | { type: "message.part.created", sessionID: string, messageID: string, part: MessagePart }
  | { type: "message.part.updated", sessionID: string, messageID: string, partIndex: number }
  | { type: "message.completed", sessionID: string, messageID: string }
  | { type: "message.error", sessionID: string, error: any };
```

**Important Details**:
- Messages are sent via `/session_chat` endpoint, not `/message/*`
- Streaming happens through the global event bus at `/event`
- Message parts support various types including reasoning and tool invocations
- Tool calls have three states: call, partial-call, and result
- Metadata includes provider info and token usage

## Requirements

### 1. Message Types (`src/message/types.zig`)

Define message-related types:

```zig
const std = @import("std");
const opencode = @import("../opencode/types.zig");

pub const MessageRequest = struct {
    text: []const u8,
    attachments: []const Attachment = &.{},
};

pub const Attachment = struct {
    path: []const u8,
    content: ?[]const u8 = null,
    mime_type: ?[]const u8 = null,
};

pub const StreamState = struct {
    /// Current message being streamed
    message_id: []const u8,
    
    /// Provider and model
    provider_id: []const u8,
    model_id: []const u8,
    
    /// Accumulated content
    content_buffer: std.ArrayList(u8),
    
    /// Current tool invocation if any
    current_tool: ?struct {
        name: []const u8,
        params: std.json.Value,
    },
    
    /// Abort signal from session
    abort_signal: *std.atomic.Value(bool),
    
    /// Statistics
    stats: struct {
        tokens_received: u32 = 0,
        tool_calls: u32 = 0,
        start_time: i64,
    },
};

pub const StreamCallback = struct {
    /// C function pointer
    fn_ptr: *const fn ([*c]const u8, usize, ?*anyopaque) callconv(.C) void,
    
    /// User data
    user_data: ?*anyopaque,
    
    /// Call the callback
    pub fn call(self: StreamCallback, data: []const u8) void {
        self.fn_ptr(data.ptr, data.len, self.user_data);
    }
};
```

### 2. Message Manager (`src/message/manager.zig`)

Core message handling logic:

```zig
pub const MessageManager = struct {
    allocator: std.mem.Allocator,
    api: *opencode.OpenCodeApi,
    active_streams: std.AutoHashMap([]const u8, *StreamState),
    mutex: std.Thread.Mutex,
    
    /// Send a message via chat endpoint
    pub fn sendMessage(
        self: *MessageManager,
        session_id: []const u8,
        provider_id: []const u8,
        model_id: []const u8,
        request: MessageRequest,
    ) !opencode.MessageInfo {
        // Build message parts
        var parts = std.ArrayList(opencode.MessagePart).init(self.allocator);
        defer parts.deinit();
        
        // Add text part
        try parts.append(.{
            .text = .{ .text = request.text },
        });
        
        // Add file parts for attachments
        for (request.attachments) |attachment| {
            const file_data = if (attachment.content) |content|
                content
            else
                try std.fs.cwd().readFileAlloc(self.allocator, attachment.path, 1024 * 1024 * 10); // 10MB max
            
            defer if (attachment.content == null) self.allocator.free(file_data);
            
            const base64_data = try std.base64.standard.Encoder.encode(
                self.allocator,
                file_data,
            );
            defer self.allocator.free(base64_data);
            
            try parts.append(.{
                .file = .{
                    .name = std.fs.path.basename(attachment.path),
                    .data = base64_data,
                    .mimeType = attachment.mime_type orelse "application/octet-stream",
                },
            });
        }
        
        // Send via OpenCode chat endpoint
        const message = try self.api.message.chat(
            session_id,
            provider_id,
            model_id,
            parts.items,
        );
        
        // No need to emit event - OpenCode publishes to Bus automatically
        
        return message;
    }
    
    /// List messages
    pub fn listMessages(self: *MessageManager, session_id: []const u8) ![]opencode.MessageInfo {
        return self.api.session.getMessages(session_id);
    }
    
    /// Get specific message
    pub fn getMessage(
        self: *MessageManager,
        session_id: []const u8,
        message_id: []const u8,
    ) !?opencode.Message {
        const messages = try self.listMessages(session_id);
        for (messages) |msg| {
            if (std.mem.eql(u8, msg.id, message_id)) {
                return msg;
            }
        }
        return null;
    }
    
    /// Monitor event stream for message updates
    pub fn streamResponse(
        self: *MessageManager,
        session_id: []const u8,
        message_id: []const u8,
        callback: StreamCallback,
        abort_signal: *std.atomic.Value(bool),
    ) !void {
        // Create stream state
        const state = try self.allocator.create(StreamState);
        state.* = .{
            .message_id = try self.allocator.dupe(u8, message_id),
            .session_id = try self.allocator.dupe(u8, session_id),
            .content_buffer = std.ArrayList(u8).init(self.allocator),
            .current_tool = null,
            .abort_signal = abort_signal,
            .stats = .{
                .start_time = std.time.milliTimestamp(),
            },
        };
        
        // Track active stream
        self.mutex.lock();
        try self.active_streams.put(message_id, state);
        self.mutex.unlock();
        
        defer {
            self.mutex.lock();
            _ = self.active_streams.remove(message_id);
            self.mutex.unlock();
            self.cleanupStreamState(state);
        }
        
        // Monitor global event stream for this message
        // OpenCode doesn't have per-message streaming - uses global event bus
        try self.api.message.streamEvents(
            StreamHandler{
                .manager = self,
                .state = state,
                .callback = callback,
            }.handleBusEvent,
            state,
        );
    }
    
    /// Check if streaming is active
    pub fn isStreaming(self: *MessageManager, message_id: []const u8) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.active_streams.contains(message_id);
    }
    
    /// Cleanup stream state
    fn cleanupStreamState(self: *MessageManager, state: *StreamState) void {
        self.allocator.free(state.message_id);
        self.allocator.free(state.provider_id);
        self.allocator.free(state.model_id);
        state.content_buffer.deinit();
        if (state.current_tool) |tool| {
            self.allocator.free(tool.name);
        }
        self.allocator.destroy(state);
    }
};

const StreamHandler = struct {
    manager: *MessageManager,
    state: *StreamState,
    callback: StreamCallback,
    
    fn handleEvent(event: opencode.StreamEvent, context: *anyopaque) !void {
        const state = @ptrCast(*StreamState, @alignCast(@alignOf(StreamState), context));
        
        // Check abort signal
        if (state.abort_signal.load(.acquire)) {
            return error.Aborted;
        }
        
        const self = @fieldParentPtr(StreamHandler, "state", state);
        
        switch (event) {
            .content => |text| {
                // Accumulate content
                try state.content_buffer.appendSlice(text);
                state.stats.tokens_received += @intCast(u32, text.len);
                
                // Send to callback
                self.callback.call(text);
                
                // Emit update event
                try emitMessageEvent(.{
                    .part_updated = .{
                        .session_id = "TODO",
                        .message_id = state.message_id,
                        .part_index = 0,
                    },
                });
            },
            
            .tool_call => |tool| {
                state.current_tool = .{
                    .name = try self.manager.allocator.dupe(u8, tool.name),
                    .params = tool.params,
                };
                state.stats.tool_calls += 1;
                
                // Format tool call for callback
                const formatted = try std.fmt.allocPrint(
                    self.manager.allocator,
                    "\n🔧 Calling tool: {s}\n",
                    .{tool.name},
                );
                defer self.manager.allocator.free(formatted);
                
                self.callback.call(formatted);
            },
            
            .tool_result => |result| {
                // Format tool result
                const formatted = try std.fmt.allocPrint(
                    self.manager.allocator,
                    "\n✅ Tool result: {}\n",
                    .{result},
                );
                defer self.manager.allocator.free(formatted);
                
                self.callback.call(formatted);
                
                // Clear current tool
                if (state.current_tool) |tool| {
                    self.manager.allocator.free(tool.name);
                    state.current_tool = null;
                }
            },
            
            .error => |err| {
                // Send error to callback
                const formatted = try std.fmt.allocPrint(
                    self.manager.allocator,
                    "\n❌ Error: {s}\n",
                    .{err},
                );
                defer self.manager.allocator.free(formatted);
                
                self.callback.call(formatted);
                
                // Emit error event
                try emitMessageEvent(.{
                    .error = .{
                        .session_id = "TODO",
                        .message_id = state.message_id,
                        .error = err,
                    },
                });
            },
            
            .done => {
                // Calculate statistics
                const duration = std.time.milliTimestamp() - state.stats.start_time;
                const stats_formatted = try std.fmt.allocPrint(
                    self.manager.allocator,
                    "\n\n📊 Stats: {} tokens, {} tool calls, {}ms\n",
                    .{ state.stats.tokens_received, state.stats.tool_calls, duration },
                );
                defer self.manager.allocator.free(stats_formatted);
                
                self.callback.call(stats_formatted);
                
                // Emit completion event
                try emitMessageEvent(.{
                    .completed = .{
                        .session_id = "TODO",
                        .message_id = state.message_id,
                        .stats = state.stats,
                    },
                });
            },
        }
    }
};
```

### 3. FFI Implementation (`src/message/ffi.zig`)

Implement C FFI functions:

```zig
const std = @import("std");
const c = @cImport({});
const SessionHandle = @import("../session/handle.zig").SessionHandle;
const MessageManager = @import("manager.zig").MessageManager;
const error_handling = @import("../error/handling.zig");
const types = @import("types.zig");

/// Global message manager
var message_manager: ?MessageManager = null;

/// Initialize message manager
pub fn init(allocator: std.mem.Allocator, api: *opencode.OpenCodeApi) !void {
    message_manager = MessageManager{
        .allocator = allocator,
        .api = api,
        .active_streams = std.AutoHashMap([]const u8, *types.StreamState).init(allocator),
        .mutex = .{},
    };
}

/// Send a user message to a session with provider/model
export fn plue_message_send(
    session: ?*anyopaque,
    provider_id: [*:0]const u8,
    model_id: [*:0]const u8,
    message_json: [*:0]const u8,
) [*c]u8 {
    if (session == null or message_json == null) {
        error_handling.setLastError(error.InvalidParam, "Invalid parameters");
        return null;
    }
    
    const handle = @ptrCast(*SessionHandle, @alignCast(@alignOf(SessionHandle), session));
    const manager = message_manager orelse {
        error_handling.setLastError(error.NotInitialized, "Message manager not initialized");
        return null;
    };
    
    // Parse request
    const json_slice = std.mem.span(message_json);
    const request = std.json.parseFromSlice(
        types.MessageRequest,
        manager.allocator,
        json_slice,
        .{ .ignore_unknown_fields = true },
    ) catch |err| {
        error_handling.setLastError(err, "Failed to parse message request");
        return null;
    };
    defer request.deinit();
    
    const provider_id_slice = std.mem.span(provider_id);
    const model_id_slice = std.mem.span(model_id);
    
    // Send message via chat endpoint
    const message = manager.sendMessage(
        handle.id,
        provider_id_slice,
        model_id_slice,
        request.value,
    ) catch |err| {
        error_handling.setLastError(err, "Failed to send message");
        return null;
    };
    
    // Return message info as JSON
    const json_string = std.json.stringifyAlloc(manager.allocator, message, .{}) catch |err| {
        error_handling.setLastError(err, "Failed to serialize message info");
        return null;
    };
    
    return json_string.ptr;
}

/// Get all messages for a session as JSON array
export fn plue_message_list(session: ?*anyopaque) [*c]u8 {
    if (session == null) {
        error_handling.setLastError(error.InvalidParam, "Session handle is null");
        return null;
    }
    
    const handle = @ptrCast(*SessionHandle, @alignCast(@alignOf(SessionHandle), session));
    const manager = message_manager orelse {
        error_handling.setLastError(error.NotInitialized, "Message manager not initialized");
        return null;
    };
    
    // Get messages
    const messages = manager.listMessages(handle.id) catch |err| {
        error_handling.setLastError(err, "Failed to list messages");
        return null;
    };
    
    // Convert to JSON
    const json_string = std.json.stringifyAlloc(manager.allocator, messages, .{}) catch |err| {
        error_handling.setLastError(err, "Failed to serialize messages");
        return null;
    };
    
    return json_string.ptr;
}

/// Get a specific message by ID as JSON
export fn plue_message_get(session: ?*anyopaque, message_id: [*:0]const u8) [*c]u8 {
    if (session == null or message_id == null) {
        error_handling.setLastError(error.InvalidParam, "Invalid parameters");
        return null;
    }
    
    const handle = @ptrCast(*SessionHandle, @alignCast(@alignOf(SessionHandle), session));
    const manager = message_manager orelse {
        error_handling.setLastError(error.NotInitialized, "Message manager not initialized");
        return null;
    };
    
    const message_id_slice = std.mem.span(message_id);
    
    // Get message
    const message = manager.getMessage(handle.id, message_id_slice) catch |err| {
        error_handling.setLastError(err, "Failed to get message");
        return null;
    };
    
    if (message == null) {
        error_handling.setLastError(error.NotFound, "Message not found");
        return null;
    }
    
    // Convert to JSON
    const json_string = std.json.stringifyAlloc(manager.allocator, message.?, .{}) catch |err| {
        error_handling.setLastError(err, "Failed to serialize message");
        return null;
    };
    
    return json_string.ptr;
}

/// Stream response for a message
export fn plue_message_stream_response(
    session: ?*anyopaque,
    message_id: [*:0]const u8,
    provider_id: [*:0]const u8,
    model_id: [*:0]const u8,
    callback: ?*const fn ([*c]const u8, usize, ?*anyopaque) callconv(.C) void,
    user_data: ?*anyopaque,
) c_int {
    if (session == null or message_id == null or provider_id == null or model_id == null or callback == null) {
        error_handling.setLastError(error.InvalidParam, "Invalid parameters");
        return -1;
    }
    
    const handle = @ptrCast(*SessionHandle, @alignCast(@alignOf(SessionHandle), session));
    const manager = message_manager orelse {
        error_handling.setLastError(error.NotInitialized, "Message manager not initialized");
        return -1;
    };
    
    const message_id_slice = std.mem.span(message_id);
    const provider_id_slice = std.mem.span(provider_id);
    const model_id_slice = std.mem.span(model_id);
    
    // Create callback wrapper
    const stream_callback = types.StreamCallback{
        .fn_ptr = callback,
        .user_data = user_data,
    };
    
    // Start streaming
    manager.streamResponse(
        handle.id,
        message_id_slice,
        provider_id_slice,
        model_id_slice,
        stream_callback,
        &handle.abort_signal,
    ) catch |err| {
        error_handling.setLastError(err, "Failed to stream response");
        return -1;
    };
    
    return 0;
}
```

### 4. Message Events (`src/message/events.zig`)

Event system for message updates:

```zig
const event_bus = @import("../event/bus.zig");

pub const MessageEvent = union(enum) {
    created: struct {
        session_id: []const u8,
        message_id: []const u8,
        role: opencode.MessageRole,
    },
    part_updated: struct {
        session_id: []const u8,
        message_id: []const u8,
        part_index: u32,
    },
    completed: struct {
        session_id: []const u8,
        message_id: []const u8,
        stats: anytype,
    },
    error: struct {
        session_id: []const u8,
        message_id: []const u8,
        error: []const u8,
    },
};

pub fn emitMessageEvent(event: MessageEvent) !void {
    const bus = event_bus.getInstance();
    try bus.emit("message", event);
}
```

### 5. Message Cache (`src/message/cache.zig`)

Cache messages for performance:

```zig
pub const MessageCache = struct {
    allocator: std.mem.Allocator,
    cache: std.StringHashMap(CachedSession),
    max_age_ms: i64 = 60000, // 1 minute
    
    const CachedSession = struct {
        messages: []opencode.Message,
        last_update: i64,
    };
    
    /// Get cached messages
    pub fn get(self: *MessageCache, session_id: []const u8) ?[]opencode.Message {
        if (self.cache.get(session_id)) |cached| {
            const age = std.time.milliTimestamp() - cached.last_update;
            if (age < self.max_age_ms) {
                return cached.messages;
            }
        }
        return null;
    }
    
    /// Update cache
    pub fn put(self: *MessageCache, session_id: []const u8, messages: []opencode.Message) !void {
        const cached = CachedSession{
            .messages = try self.allocator.dupe(opencode.Message, messages),
            .last_update = std.time.milliTimestamp(),
        };
        try self.cache.put(session_id, cached);
    }
    
    /// Invalidate cache
    pub fn invalidate(self: *MessageCache, session_id: []const u8) void {
        if (self.cache.fetchRemove(session_id)) |entry| {
            self.allocator.free(entry.value.messages);
        }
    }
};
```

### 6. Streaming Utilities (`src/message/streaming.zig`)

Helper utilities for streaming:

```zig
pub const StreamBuffer = struct {
    allocator: std.mem.Allocator,
    chunks: std.ArrayList([]const u8),
    total_size: usize = 0,
    
    /// Add chunk
    pub fn addChunk(self: *StreamBuffer, chunk: []const u8) !void {
        const copy = try self.allocator.dupe(u8, chunk);
        try self.chunks.append(copy);
        self.total_size += chunk.len;
    }
    
    /// Get complete content
    pub fn getContent(self: *StreamBuffer) ![]const u8 {
        var result = try self.allocator.alloc(u8, self.total_size);
        var offset: usize = 0;
        
        for (self.chunks.items) |chunk| {
            @memcpy(result[offset..][0..chunk.len], chunk);
            offset += chunk.len;
        }
        
        return result;
    }
    
    /// Cleanup
    pub fn deinit(self: *StreamBuffer) void {
        for (self.chunks.items) |chunk| {
            self.allocator.free(chunk);
        }
        self.chunks.deinit();
    }
};

/// Parse streaming format
pub fn parseStreamingFormat(text: []const u8) StreamFormat {
    // Detect markdown code blocks
    if (std.mem.indexOf(u8, text, "```")) |_| {
        return .markdown;
    }
    
    // Detect tool invocations
    if (std.mem.startsWith(u8, text, "🔧")) {
        return .tool_call;
    }
    
    return .plain_text;
}

pub const StreamFormat = enum {
    plain_text,
    markdown,
    tool_call,
    tool_result,
};
```

## Implementation Steps

### Step 1: Define Message Types
1. Create `src/message/types.zig`
2. Define request/response structures
3. Add streaming state types
4. Write type tests

### Step 2: Implement Message Manager
1. Create `src/message/manager.zig`
2. Add message sending logic
3. Implement streaming handler
4. Add abort support

### Step 3: Create FFI Functions
1. Create `src/message/ffi.zig`
2. Implement all exports
3. Add parameter validation
4. Test with C client

### Step 4: Add Event System
1. Create `src/message/events.zig`
2. Define event types
3. Integrate with streaming
4. Test event delivery

### Step 5: Implement Caching
1. Create `src/message/cache.zig`
2. Add LRU cache logic
3. Handle invalidation
4. Test cache performance

### Step 6: Add Streaming Utilities
1. Create `src/message/streaming.zig`
2. Implement buffer management
3. Add format detection
4. Test streaming scenarios

## Testing Requirements

1. **Unit Tests** (>95% coverage):
   - Message sending
   - Streaming logic
   - Cache behavior
   - Event emission

2. **Integration Tests**:
   - Full conversation flows
   - Streaming interruption
   - Tool invocations
   - Error handling

3. **Performance Tests**:
   - Streaming throughput
   - Cache hit rates
   - Memory usage
   - Concurrent streams

## Example Usage (from C)

```c
// Send a message with provider and model
const char* request = "{\"text\": \"Help me write a sorting algorithm\", \"attachments\": []}";
char* message_json = plue_message_send(session, "anthropic", "claude-3-opus-20240229", request);
if (!message_json) {
    printf("Failed to send: %s\n", plue_get_last_error());
    return;
}

// Parse message info to get ID
// In real code, you'd parse the JSON to extract the message ID
const char* message_id = "msg_12345"; // Extracted from message_json

// Define streaming callback
void on_stream_chunk(const char* data, size_t len, void* user_data) {
    printf("%.*s", (int)len, data);
    fflush(stdout);
}

// Stream the response
int result = plue_message_stream_response(
    session,
    message_id,
    "anthropic",
    "claude-3-opus-20240229",
    on_stream_chunk,
    NULL
);

if (result != 0) {
    printf("\nStreaming failed: %s\n", plue_get_last_error());
}

// Clean up
plue_free_string(message_id);
```

## Corner Cases and Implementation Details

Based on OpenCode's implementation, handle these critical scenarios:

### Message API Architecture
1. **Chat Endpoint Only**: Messages are sent via `/session_chat`, not separate message endpoints
2. **Event Bus Streaming**: All streaming happens through global `/event` endpoint, not per-message
3. **Message Storage**: Messages stored in `session/{id}/messages.json` file
4. **Part Types**: Support text, file, tool-invocation, reasoning, source-url, step-start
5. **No Update Endpoint**: Messages are immutable once created

### Message Lifecycle Edge Cases  
1. **ID Generation**: Message IDs are UUIDs, not timestamps like sessions
2. **Role Assignment**: Only "user" and "assistant" roles supported
3. **Provider Binding**: Messages track providerID and modelID in metadata
4. **Token Usage**: Usage statistics added to metadata after completion
5. **Error Handling**: Errors stored in metadata.error field

### Streaming Implementation Details
1. **Bus Events**: Listen for message.part.created, message.part.updated events
2. **No Direct Stream**: OpenCode doesn't provide direct SSE for individual messages
3. **Event Filtering**: Must filter global events by sessionID and messageID
4. **Part Updates**: Parts can be updated incrementally (for streaming text)
5. **Completion Event**: message.completed signals end of streaming

### Tool Invocation Specifics
1. **Three States**: call → partial-call → result progression
2. **Tool Call IDs**: Each invocation has unique toolCallId
3. **Args Serialization**: Tool args stored as JSON in message parts
4. **Result Format**: Tool results always returned as strings
5. **Step Tracking**: Optional step number for multi-tool sequences

### File Attachment Handling
1. **Base64 Encoding**: Files must be base64 encoded in data field
2. **MIME Types**: Explicit mimeType required for each file
3. **Size Limits**: Consider implementing client-side file size limits
4. **Name Field**: File name stored separately from path
5. **Memory Usage**: Large files can cause memory issues

### Event Bus Integration
1. **Connection Required**: Must have active SSE connection to /event
2. **Initial Empty Event**: Wait for {} before considering connected
3. **Event Parsing**: Events arrive as JSON in SSE data field
4. **Multiplexing**: Single stream for all sessions and messages
5. **Reconnection**: Must reestablish on disconnect

### Cache Considerations
1. **Message Immutability**: Can cache aggressively since messages don't change
2. **Part Updates**: Must invalidate when parts are updated
3. **Session Scope**: Cache per session to avoid cross-session leaks
4. **Memory Limits**: Implement LRU eviction for large conversations
5. **Startup Load**: Consider lazy loading old messages

### UX Improvements
1. **Streaming Indicators**: Show "typing" indicator during streaming
2. **Part Type Icons**: Visual indicators for different part types
3. **Tool Progress**: Show tool execution progress
4. **Error Recovery**: Retry failed messages automatically
5. **Offline Queue**: Queue messages when server unavailable

### Potential Bugs to Watch Out For
1. **Event Order**: Message parts may arrive out of order
2. **Duplicate Events**: Same event may be delivered multiple times
3. **Memory Leaks**: Ensure all event listeners are cleaned up
4. **Large Messages**: Very long messages may exceed buffer sizes
5. **Unicode Handling**: Ensure proper UTF-8 handling in streaming
6. **Tool Timeouts**: Long-running tools may timeout silently
7. **Concurrent Sends**: Multiple messages sent quickly may interleave
8. **Session State**: Messages sent to deleted sessions should fail
9. **Provider Errors**: Handle provider-specific error formats
10. **Partial Writes**: Network interruption during send may leave partial state

## Success Criteria

The implementation is complete when:
- [ ] Messages can be sent via chat endpoint with provider/model
- [ ] Event bus streaming works with proper filtering
- [ ] Tool invocations progress through all three states
- [ ] File attachments are properly base64 encoded
- [ ] Abort signals interrupt event stream monitoring
- [ ] Events are properly filtered by session and message ID
- [ ] Cache improves performance without memory leaks
- [ ] Memory usage is stable during long conversations
- [ ] All tests pass with >95% coverage
- [ ] Error messages provide actionable feedback

## Git Workflow

Continue in the same worktree:
```bash
cd ../plue-server-management
```

Commit with conventional commits:
- `feat: implement message types and structures`
- `feat: add message manager with streaming`
- `feat: implement message FFI functions`
- `feat: add message event system`
- `feat: implement message caching`
- `test: add message bridge tests`

The branch remains: `feat_add_opencode_server_management`