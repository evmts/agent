# Create OpenCode API Client in Zig

## Context

You are implementing a type-safe API client for OpenCode's HTTP endpoints. This builds on the HTTP client infrastructure from the previous task to provide a clean, strongly-typed interface for all OpenCode operations.

### Project State

From previous tasks, you have:
- Server manager that spawns OpenCode (`src/server/manager.zig`)
- HTTP client with JSON and SSE support (`src/http/client.zig`)
- Connection pooling and retry logic (`src/http/pool.zig`, `src/http/retry.zig`)

Now you need to create a comprehensive API client that maps OpenCode's endpoints to Zig functions.

### OpenCode API Reference

The actual OpenCode API from `packages/opencode/src/server/server.ts`:

```typescript
// Event stream (SSE) - also serves as health check
GET  /event

// App management
POST /app_info                 // Get app information
POST /app_initialize           // Initialize the app
POST /path_get                 // Get paths (root, data, cwd, config)

// Configuration
POST /config_get               // Get configuration info

// Session management 
POST /session_create           // Create new session
POST /session_initialize       // Initialize session with provider/model
POST /session_list             // List all sessions
POST /session_messages         // Get messages for a session
POST /session_chat             // Send chat message
POST /session_abort            // Abort a session
POST /session_delete           // Delete a session
POST /session_summarize        // Summarize the session
POST /session_share            // Share a session
POST /session_unshare          // Unshare a session

// Provider management
POST /provider_list            // List all providers and default models

// File operations
POST /file_search              // Search for files using ripgrep

// Installation info
POST /installation_info        // Get installation information
```

**Important:** Note that most endpoints are POST, even for read operations!

### OpenCode Type Definitions

Key types from OpenCode that need Zig equivalents:

```typescript
// From OpenCode's actual implementation
// Session types
interface SessionInfo {
  id: string;
  title?: string;
  time: { created: number; updated: number };
  parentId?: string;
  shared?: boolean;
  shareID?: string;
}

// Message types  
interface MessageInfo {
  id: string;
  sessionID: string;
  role: "user" | "assistant";
  parts: MessagePart[];
  time: { created: number; updated: number };
  providerID?: string;
  modelID?: string;
}

interface MessagePart {
  type: "text" | "image" | "tool-use" | "tool-result";
  // Content varies by type
}

// Provider types from ModelsDev
interface Provider {
  id: string;
  name: string;
  models: Model[];
}

interface Model {
  id: string;
  name: string;
  providerID: string;
  // Additional fields from ModelsDev
}

// App info
interface AppInfo {
  path: {
    root: string;
    data: string;
    cwd: string;
  };
  installation: string;
}

// Installation info
interface InstallationInfo {
  version: string;
  method: "npm" | "binary" | "unknown";
  target: string;
}

## Requirements

### 1. OpenCode Types (`src/opencode/types.zig`)

Define Zig equivalents for all OpenCode types:

```zig
pub const SessionId = []const u8;
pub const MessageId = []const u8;
pub const ProviderId = []const u8;
pub const ModelId = []const u8;

pub const SessionInfo = struct {
    id: SessionId,
    title: ?[]const u8 = null,
    time: struct {
        created: i64,
        updated: i64,
    },
    parent_id: ?SessionId = null,
};

pub const MessageRole = enum {
    user,
    assistant,
    
    pub fn jsonStringify(self: MessageRole, writer: anytype) !void {
        try writer.writeAll(switch (self) {
            .user => "user",
            .assistant => "assistant",
        });
    }
};

pub const MessagePartType = enum {
    text,
    file,
    tool,
    reasoning,
};

pub const MessagePart = union(MessagePartType) {
    text: struct {
        content: []const u8,
    },
    file: struct {
        path: []const u8,
        content: ?[]const u8 = null,
    },
    tool: struct {
        name: []const u8,
        params: std.json.Value,
        result: ?std.json.Value = null,
    },
    reasoning: struct {
        content: []const u8,
    },
};

pub const Message = struct {
    id: MessageId,
    role: MessageRole,
    parts: []MessagePart,
    time: struct {
        created: i64,
        updated: i64,
    },
};

pub const Model = struct {
    id: ModelId,
    name: []const u8,
    context_length: u32,
    input_cost: ?f64 = null,
    output_cost: ?f64 = null,
};

pub const ProviderInfo = struct {
    id: ProviderId,
    enabled: bool,
    models: []Model,
    config: ?std.json.Value = null,
};

pub const Tool = struct {
    name: []const u8,
    description: []const u8,
    parameters: std.json.Value, // JSON Schema
};

pub const ToolResult = struct {
    success: bool,
    output: ?[]const u8 = null,
    error: ?[]const u8 = null,
    metadata: ?std.json.Value = null,
};
```

### 2. API Client Core (`src/opencode/client.zig`)

Create the main API client:

```zig
pub const ApiClient = struct {
    allocator: std.mem.Allocator,
    http_client: *http.Client,
    base_url: []const u8,
    event_stream: ?*http.SseStream = null,
    
    /// Initialize API client
    pub fn init(allocator: std.mem.Allocator, base_url: []const u8) !ApiClient {
        const http_client = try allocator.create(http.Client);
        http_client.* = try http.Client.init(allocator, .{
            .base_url = base_url,
            .timeout_ms = 30000,
        });
        
        return ApiClient{
            .allocator = allocator,
            .http_client = http_client,
            .base_url = base_url,
        };
    }
    
    /// Connect to event stream (health check)
    pub fn connectEventStream(self: *ApiClient) !void {
        self.event_stream = try self.http_client.streamSSE("/event");
        // Wait for initial empty message
        const initial = try self.event_stream.?.next();
        if (!std.mem.eql(u8, initial.?.data, "{}")) {
            return error.InvalidHealthResponse;
        }
    }
    
    /// Get app information
    pub fn getAppInfo(self: *ApiClient) !AppInfo {
        return self.http_client.requestJson(
            AppInfo,
            .{ .method = .POST, .url = "/app_info" },
        );
    }
    
    /// Get paths
    pub fn getPaths(self: *ApiClient) !PathInfo {
        return self.http_client.requestJson(
            PathInfo,
            .{ .method = .POST, .url = "/path_get" },
        );
    }
    
    /// Initialize app
    pub fn initializeApp(self: *ApiClient) !bool {
        return self.http_client.requestJson(
            bool,
            .{ .method = .POST, .url = "/app_initialize" },
        );
    }
    
    /// Cleanup
    pub fn deinit(self: *ApiClient) void {
        if (self.event_stream) |stream| {
            stream.close();
        }
        self.http_client.deinit();
        self.allocator.destroy(self.http_client);
    }
};

pub const AppInfo = struct {
    path: struct {
        root: []const u8,
        data: []const u8,
        cwd: []const u8,
    },
    installation: []const u8,
};

pub const PathInfo = struct {
    root: []const u8,
    data: []const u8,
    cwd: []const u8,
    config: []const u8,
};
```

### 3. Session API (`src/opencode/session_api.zig`)

Implement session-related endpoints:

```zig
pub const SessionApi = struct {
    client: *ApiClient,
    
    /// Create a new session
    pub fn create(self: *SessionApi) !SessionInfo {
        return self.client.http_client.requestJson(
            SessionInfo,
            .{ .method = .POST, .url = "/session_create" },
        );
    }
    
    /// Initialize session with provider and model
    pub fn initialize(self: *SessionApi, session_id: SessionId, provider_id: ProviderId, model_id: ModelId) !bool {
        const body = .{
            .sessionID = session_id,
            .providerID = provider_id,
            .modelID = model_id,
        };
        
        return self.client.http_client.requestJson(
            bool,
            http.RequestBuilder.init(self.client.allocator, .POST)
                .url("/session_initialize")
                .json(body)
                .build(),
        );
    }
    
    /// List all sessions
    pub fn list(self: *SessionApi) ![]SessionInfo {
        return self.client.http_client.requestJson(
            []SessionInfo,
            .{ .method = .POST, .url = "/session_list" },
        );
    }
    
    /// Get messages for a session
    pub fn getMessages(self: *SessionApi, session_id: SessionId) ![]MessageInfo {
        const body = .{ .sessionID = session_id };
        
        return self.client.http_client.requestJson(
            []MessageInfo,
            http.RequestBuilder.init(self.client.allocator, .POST)
                .url("/session_messages")
                .json(body)
                .build(),
        );
    }
    
    /// Delete a session
    pub fn delete(self: *SessionApi, session_id: SessionId) !bool {
        const body = .{ .sessionID = session_id };
        
        return self.client.http_client.requestJson(
            bool,
            http.RequestBuilder.init(self.client.allocator, .POST)
                .url("/session_delete")
                .json(body)
                .build(),
        );
    }
    
    /// Abort a session
    pub fn abort(self: *SessionApi, session_id: SessionId) !bool {
        const body = .{ .sessionID = session_id };
        
        return self.client.http_client.requestJson(
            bool,
            http.RequestBuilder.init(self.client.allocator, .POST)
                .url("/session_abort")
                .json(body)
                .build(),
        );
    }
    
    /// Share a session
    pub fn share(self: *SessionApi, session_id: SessionId) !SessionInfo {
        const body = .{ .sessionID = session_id };
        
        return self.client.http_client.requestJson(
            SessionInfo,
            http.RequestBuilder.init(self.client.allocator, .POST)
                .url("/session_share")
                .json(body)
                .build(),
        );
    }
    
    /// Unshare a session
    pub fn unshare(self: *SessionApi, session_id: SessionId) !SessionInfo {
        const body = .{ .sessionID = session_id };
        
        return self.client.http_client.requestJson(
            SessionInfo,
            http.RequestBuilder.init(self.client.allocator, .POST)
                .url("/session_unshare")
                .json(body)
                .build(),
        );
    }
    
    /// Summarize a session
    pub fn summarize(self: *SessionApi, session_id: SessionId, provider_id: ProviderId, model_id: ModelId) !bool {
        const body = .{
            .sessionID = session_id,
            .providerID = provider_id,
            .modelID = model_id,
        };
        
        return self.client.http_client.requestJson(
            bool,
            http.RequestBuilder.init(self.client.allocator, .POST)
                .url("/session_summarize")
                .json(body)
                .build(),
        );
    }
};
```

### 4. Message API (`src/opencode/message_api.zig`)

Handle message operations:

```zig
pub const MessageApi = struct {
    client: *ApiClient,
    
    /// Send a chat message
    pub fn chat(
        self: *MessageApi,
        session_id: SessionId,
        provider_id: ProviderId,
        model_id: ModelId,
        parts: []const MessagePart,
    ) !MessageInfo {
        const body = .{
            .sessionID = session_id,
            .providerID = provider_id,
            .modelID = model_id,
            .parts = parts,
        };
        
        return self.client.http_client.requestJson(
            MessageInfo,
            http.RequestBuilder.init(self.client.allocator, .POST)
                .url("/session_chat")
                .json(body)
                .build(),
        );
    }
    
    /// Create text message part
    pub fn textPart(allocator: std.mem.Allocator, text: []const u8) !MessagePart {
        return MessagePart{
            .text = .{ .text = try allocator.dupe(u8, text) },
        };
    }
    
    /// Create image message part
    pub fn imagePart(allocator: std.mem.Allocator, media_type: []const u8, data: []const u8) !MessagePart {
        return MessagePart{
            .image = .{
                .media_type = try allocator.dupe(u8, media_type),
                .data = try allocator.dupe(u8, data),
            },
        };
    }
    
    /// Stream events from event bus
    pub fn streamEvents(
        self: *MessageApi,
        callback: EventCallback,
        context: *anyopaque,
    ) !void {
        // Use the global event stream from ApiClient
        if (self.client.event_stream == null) {
            return error.EventStreamNotConnected;
        }
        
        while (true) {
            const event = try self.client.event_stream.?.next();
            if (event) |e| {
                const parsed = try parseEventData(e.data);
                try callback(parsed, context);
            }
        }
    }
};

pub const StreamEvent = union(enum) {
    content: []const u8,
    tool_call: struct {
        name: []const u8,
        params: std.json.Value,
    },
    tool_result: ToolResult,
    error: []const u8,
    done: void,
};

pub const StreamCallback = *const fn (event: StreamEvent, context: *anyopaque) anyerror!void;
```

### 5. Provider API (`src/opencode/provider_api.zig`)

Manage AI providers:

```zig
pub const ProviderApi = struct {
    client: *ApiClient,
    
    /// List all providers with default models
    pub fn list(self: *ProviderApi) !ProviderListResponse {
        return self.client.http_client.requestJson(
            ProviderListResponse,
            .{ .method = .POST, .url = "/provider_list" },
        );
    }
    
    /// Get default model for a provider
    pub fn getDefaultModel(self: *ProviderApi, provider_id: ProviderId) !?ModelId {
        const response = try self.list();
        
        if (response.default.get(provider_id)) |model_id| {
            return model_id;
        }
        return null;
    }
    
    /// Get all models for a provider
    pub fn getProviderModels(self: *ProviderApi, provider_id: ProviderId) ![]Model {
        const response = try self.list();
        
        for (response.providers) |provider| {
            if (std.mem.eql(u8, provider.id, provider_id)) {
                return provider.models;
            }
        }
        
        return error.ProviderNotFound;
    }
};

pub const ProviderListResponse = struct {
    providers: []Provider,
    default: std.StringHashMap(ModelId),
};
```

### 6. File API (`src/opencode/file_api.zig`)

File search operations:

```zig
pub const FileApi = struct {
    client: *ApiClient,
    
    /// Search for files using ripgrep
    pub fn search(self: *FileApi, query: []const u8) ![][]const u8 {
        const body = .{ .query = query };
        
        return self.client.http_client.requestJson(
            [][]const u8,
            http.RequestBuilder.init(self.client.allocator, .POST)
                .url("/file_search")
                .json(body)
                .build(),
        );
    }
};
```

### 7. Configuration API (`src/opencode/config_api.zig`)

Configuration management:

```zig
pub const ConfigApi = struct {
    client: *ApiClient,
    
    /// Get configuration info
    pub fn get(self: *ConfigApi) !ConfigInfo {
        return self.client.http_client.requestJson(
            ConfigInfo,
            .{ .method = .POST, .url = "/config_get" },
        );
    }
};

pub const ConfigInfo = struct {
    // Fields defined by Config.Info in OpenCode
    autoupdate: ?bool = null,
    // Add other config fields as needed
};
```

### 8. Installation API (`src/opencode/installation_api.zig`)

Installation information:

```zig
pub const InstallationApi = struct {
    client: *ApiClient,
    
    /// Get installation info
    pub fn getInfo(self: *InstallationApi) !InstallationInfo {
        return self.client.http_client.requestJson(
            InstallationInfo,
            .{ .method = .POST, .url = "/installation_info" },
        );
    }
};

pub const ToolStreamEvent = union(enum) {
    output: []const u8,
    metadata: std.json.Value,
    done: ToolResult,
};

pub const ToolStreamCallback = *const fn (event: ToolStreamEvent, context: *anyopaque) anyerror!void;
```

### 9. Complete API Client (`src/opencode/api.zig`)

Combine all APIs into a single client:

```zig
pub const OpenCodeApi = struct {
    allocator: std.mem.Allocator,
    client: ApiClient,
    session: SessionApi,
    message: MessageApi,
    provider: ProviderApi,
    file: FileApi,
    config: ConfigApi,
    installation: InstallationApi,
    
    /// Initialize the complete API
    pub fn init(allocator: std.mem.Allocator, base_url: []const u8) !OpenCodeApi {
        var client = try ApiClient.init(allocator, base_url);
        
        return OpenCodeApi{
            .allocator = allocator,
            .client = client,
            .session = SessionApi{ .client = &client },
            .message = MessageApi{ .client = &client },
            .provider = ProviderApi{ .client = &client },
            .file = FileApi{ .client = &client },
            .config = ConfigApi{ .client = &client },
            .installation = InstallationApi{ .client = &client },
        };
    }
    
    /// Connect to server and wait for ready
    pub fn connect(self: *OpenCodeApi, timeout_ms: u32) !void {
        const start = std.time.milliTimestamp();
        
        // Try to connect to event stream
        while (std.time.milliTimestamp() - start < timeout_ms) {
            if (self.client.connectEventStream()) |_| {
                // Also initialize the app
                _ = try self.client.initializeApp();
                return;
            } else |_| {
                std.time.sleep(100 * std.time.ns_per_ms);
            }
        }
        
        return error.ServerNotReady;
    }
    
    /// Cleanup
    pub fn deinit(self: *OpenCodeApi) void {
        self.client.deinit();
    }
};
```

### 10. Error Handling (`src/opencode/errors.zig`)

Define OpenCode-specific errors:

```zig
pub const OpenCodeError = error{
    ServerNotReady,
    InvalidSession,
    InvalidMessage,
    ProviderNotConfigured,
    ToolNotFound,
    StreamInterrupted,
    RateLimitExceeded,
    AuthenticationFailed,
};

/// Parse error response from OpenCode
pub fn parseErrorResponse(response: http.Response) !OpenCodeError {
    const error_data = try std.json.parseFromSlice(
        struct {
            error: struct {
                code: []const u8,
                message: []const u8,
            },
        },
        response.allocator,
        response.body,
        .{},
    );
    defer error_data.deinit();
    
    // Map OpenCode error codes to Zig errors
    const code = error_data.value.error.code;
    if (std.mem.eql(u8, code, "SESSION_NOT_FOUND")) {
        return error.InvalidSession;
    } else if (std.mem.eql(u8, code, "TOOL_NOT_FOUND")) {
        return error.ToolNotFound;
    }
    // ... more mappings
    
    return error.UnknownError;
}
```

## Implementation Steps

### Step 1: Define OpenCode Types
1. Create `src/opencode/types.zig`
2. Define all data structures
3. Add JSON serialization support
4. Write type conversion utilities

### Step 2: Implement Base API Client
1. Create `src/opencode/client.zig`
2. Add health and version endpoints
3. Implement error handling
4. Add request/response logging

### Step 3: Add Session API
1. Create `src/opencode/session_api.zig`
2. Implement CRUD operations
3. Add session branching support
4. Write comprehensive tests

### Step 4: Implement Message API
1. Create `src/opencode/message_api.zig`
2. Add message sending
3. Implement SSE streaming
4. Handle stream interruptions

### Step 5: Add Provider API
1. Create `src/opencode/provider_api.zig`
2. Implement configuration
3. Add model discovery
4. Handle authentication

### Step 6: Implement Tool API
1. Create `src/opencode/tool_api.zig`
2. Add tool execution
3. Implement streaming output
4. Handle abort signals

### Step 7: Create Unified API
1. Create `src/opencode/api.zig`
2. Combine all sub-APIs
3. Add convenience methods
4. Implement initialization

## Testing Requirements

1. **Unit Tests** (>95% coverage):
   - Type serialization/deserialization
   - Error mapping
   - URL construction
   - Response parsing

2. **Integration Tests**:
   - Full API workflows
   - Error scenarios
   - Streaming operations
   - Concurrent requests

3. **Mock Server Tests**:
   - Test against mock OpenCode responses
   - Simulate error conditions
   - Test timeout handling

## Example Usage

```zig
// Initialize API
var api = try OpenCodeApi.init(allocator, "http://localhost:3000");
defer api.deinit();

// Connect to server and initialize
try api.connect(5000);

// Get app info
const app_info = try api.client.getAppInfo();
std.log.info("App data path: {s}", .{app_info.path.data});

// List providers
const providers = try api.provider.list();
std.log.info("Found {} providers", .{providers.providers.len});

// Create a session
const session = try api.session.create();
std.log.info("Created session: {s}", .{session.id});

// Initialize session with provider and model
const provider_id = "anthropic";
const model_id = providers.default.get(provider_id) orelse "claude-3-opus-20240229";
_ = try api.session.initialize(session.id, provider_id, model_id);

// Send a chat message
const text_part = try api.message.textPart(allocator, "Help me write a hello world program");
defer allocator.free(text_part.text.text);

const message = try api.message.chat(
    session.id,
    provider_id,
    model_id,
    &[_]MessagePart{text_part},
);
std.log.info("Sent message: {s}", .{message.id});

// Stream events from the event bus
try api.message.streamEvents(struct {
    fn onEvent(event: Event, ctx: *anyopaque) !void {
        switch (event.type) {
            .message_chunk => |chunk| std.debug.print("{s}", .{chunk.text}),
            .message_complete => std.debug.print("\n", .{}),
            else => {},
        }
    }
}.onEvent, null);

// Search for files
const files = try api.file.search("*.zig");
std.log.info("Found {} Zig files", .{files.len});

// Share the session
const shared = try api.session.share(session.id);
std.log.info("Share URL: {s}", .{shared.shareID});
```

## Corner Cases and Implementation Details

Based on OpenCode's implementation, handle these critical scenarios:

### API Design Patterns
1. **POST for Everything**: Unlike typical REST, OpenCode uses POST for all operations including queries
2. **Empty Bodies**: Many endpoints accept empty JSON bodies `{}` - don't send null
3. **Consistent Naming**: Endpoints use snake_case (e.g., `/session_create` not `/session/create`)
4. **No URL Parameters**: All parameters go in the request body, not URL path
5. **Boolean Returns**: Many operations return just `true` on success

### Event Stream Integration
1. **Single Event Stream**: All events flow through `/event`, not endpoint-specific streams
2. **Event Types**: Events include session updates, message chunks, tool outputs, etc.
3. **Initial Connection**: Must wait for empty `{}` message before considering connected
4. **Multiplexing**: Single stream serves all sessions - filter by sessionID
5. **Reconnection**: On disconnect, must re-establish and potentially replay missed events

### Session Management Edge Cases
1. **Session Initialization**: Create and initialize are separate steps - don't skip initialization
2. **Provider Binding**: Once initialized with a provider/model, it's fixed for that session
3. **Parent Sessions**: Support branching conversations via parentId
4. **Shared Sessions**: Share/unshare changes the session object - refetch after
5. **Abort vs Delete**: Abort cancels in-progress operations, delete removes history

### Message Handling Specifics
1. **Part Types**: Support text, image, tool-use, tool-result parts
2. **Image Encoding**: Images must be base64 encoded with media type
3. **Tool Integration**: Tool calls flow through message parts, not separate endpoints
4. **Streaming**: Response streaming happens via global event bus, not dedicated endpoint
5. **Message Ordering**: Messages have created/updated timestamps for proper ordering

### Provider Integration Details
1. **Default Models**: Each provider has a preferred default model
2. **Model Sorting**: Models are pre-sorted by capability/cost in the response
3. **Configuration**: Provider config is stored separately from listing
4. **Validation**: Invalid provider/model combinations fail at chat time
5. **Rate Limits**: Handle provider-specific rate limit errors gracefully

### Performance Considerations
1. **Connection Pooling**: Reuse HTTP connections except for SSE
2. **JSON Parsing**: Use streaming parser for large message histories
3. **Event Buffering**: Buffer events during processing to avoid backpressure
4. **Batch Operations**: No batch endpoints - implement client-side batching
5. **Caching**: Cache provider list and app info - they rarely change

### Error Handling Patterns
1. **NamedError Format**: All errors follow `{ data: { ... }, message: string }` format
2. **Network Errors**: Distinguish between connection failures and API errors
3. **Validation Errors**: Server validates all inputs - handle 400s gracefully
4. **State Errors**: Operations on deleted sessions return specific errors
5. **Async Errors**: Event stream errors arrive as error events, not exceptions

### UX Improvements
1. **Progress Tracking**: Expose message progress through event stream (tokens, elapsed time)
2. **Auto-Retry**: Implement automatic retry for transient failures with backoff
3. **Graceful Degradation**: Queue operations during connection loss
4. **Timeout Hints**: Suggest appropriate timeouts based on operation type
5. **Debug Mode**: Optional request/response logging for troubleshooting

### Potential Bugs to Watch Out For
1. **Event Stream Blocking**: Don't block event processing - buffer and process async
2. **JSON Number Precision**: JavaScript numbers may lose precision - use strings for IDs
3. **Memory Leaks**: Ensure all event subscriptions are cleaned up properly
4. **Race Conditions**: Session operations may race with event updates
5. **Large Payloads**: File search results can be huge - implement pagination
6. **Type Mismatches**: TypeScript anys may not match Zig types perfectly
7. **Timezone Issues**: Timestamps are in milliseconds, handle timezone correctly
8. **Path Encoding**: File paths may contain special characters - encode properly
9. **Concurrent Modifications**: Two clients modifying same session causes conflicts
10. **SSE Reconnect Loops**: Prevent infinite reconnection on auth failures

## Success Criteria

The implementation is complete when:
- [ ] All OpenCode endpoints have type-safe wrappers
- [ ] JSON serialization works for all types
- [ ] SSE streaming handles large responses and reconnections
- [ ] Error responses are properly mapped to NamedError format
- [ ] Concurrent API calls work correctly with connection pooling
- [ ] Event stream multiplexing works for multiple sessions
- [ ] All tests pass with >95% coverage
- [ ] API is intuitive and well-documented
- [ ] Performance meets requirements (<10ms overhead per call)
- [ ] Memory usage is stable during long streaming sessions

## Git Workflow

Continue in the same worktree:
```bash
cd ../plue-server-management
```

Commit with conventional commits:
- `feat: define OpenCode type system`
- `feat: implement base API client`
- `feat: add session management API`
- `feat: implement message streaming`
- `feat: add provider configuration`
- `feat: implement tool execution`
- `test: add API client tests`

The branch remains: `feat_add_opencode_server_management`