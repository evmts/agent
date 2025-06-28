# Build HTTP Client Infrastructure in Zig

## Context

You are implementing the HTTP client infrastructure for Plue's communication with the OpenCode server. This is the second component of the MVP2 architecture and is critical for all subsequent features.

### Project State

From the previous task, you have:
- Process management utilities in `src/util/process.zig`
- Server configuration in `src/server/config.zig`
- Server manager in `src/server/manager.zig` that spawns OpenCode

Now you need to build the HTTP client layer that will communicate with the running OpenCode server.

### OpenCode API Overview

OpenCode exposes a REST API with the following characteristics:
- JSON request/response bodies
- Server-Sent Events (SSE) for streaming responses
- Standard HTTP status codes
- Consistent error response format
- No dedicated health endpoint - use `/event` SSE connection as health indicator

Example endpoints:
```
GET  /event                    # Event stream (SSE) - also serves as health check
POST /app_info                 # Get app information
POST /config_get               # Get configuration
POST /session_create           # Create session
POST /session_messages         # Get session messages
POST /session_chat             # Send chat message
POST /provider_list            # List providers
```

### Reference Implementations

OpenCode's server implementation uses standard HTTP patterns:
```typescript
// From packages/opencode/src/server/server.ts
// SSE event stream - critical for health monitoring
.get("/event", async (c) => {
  log.info("event connected");
  return streamSSE(c, async (stream) => {
    // Initial empty message confirms connection
    stream.writeSSE({
      data: JSON.stringify({}),
    });
    const unsub = Bus.subscribeAll(async (event) => {
      await stream.writeSSE({
        data: JSON.stringify(event),
      });
    });
    await new Promise<void>((resolve) => {
      stream.onAbort(() => {
        unsub();
        resolve();
        log.info("event disconnected");
      });
    });
  });
})

// Error handling pattern
.onError((err, c) => {
  if (err instanceof NamedError) {
    return c.json(err.toObject(), {
      status: 400,
    });
  }
  return c.json(
    new NamedError.Unknown({ message: err.toString() }).toObject(),
    { status: 400 },
  );
})
```

The Bubble Tea TUI client provides a clean SSE implementation pattern:
```go
// From packages/tui/pkg/client/event.go
func (c *Client) Event(ctx context.Context) (<-chan any, error) {
    events := make(chan any)
    req, err := http.NewRequestWithContext(ctx, "GET", c.Server+"event", nil)
    if err != nil {
        return nil, err
    }

    resp, err := http.DefaultClient.Do(req)
    if err != nil {
        return nil, err
    }

    go func() {
        defer close(events)
        defer resp.Body.Close()

        scanner := bufio.NewScanner(resp.Body)
        // Important: Set large buffer for SSE events
        scanner.Buffer(make([]byte, 1024*1024), 10*1024*1024)
        for scanner.Scan() {
            line := scanner.Text()
            if strings.HasPrefix(line, "data: ") {
                data := strings.TrimPrefix(line, "data: ")
                // Parse and send event...
            }
        }
    }()

    return events, nil
}
```

## Requirements

### 1. Core HTTP Types (`src/http/types.zig`)

Define fundamental HTTP types:
```zig
pub const Method = enum {
    GET,
    POST,
    PUT,
    DELETE,
    PATCH,
    HEAD,
    OPTIONS,
};

pub const Header = struct {
    name: []const u8,
    value: []const u8,
};

pub const Request = struct {
    method: Method,
    url: []const u8,
    headers: []Header,
    body: ?[]const u8 = null,
};

pub const Response = struct {
    status: u16,
    headers: []Header,
    body: []const u8,
    
    pub fn isSuccess(self: *const Response) bool {
        return self.status >= 200 and self.status < 300;
    }
    
    pub fn getHeader(self: *const Response, name: []const u8) ?[]const u8
};

pub const HttpError = error{
    ConnectionFailed,
    Timeout,
    InvalidResponse,
    TooManyRedirects,
    NetworkError,
    InvalidUrl,
};
```

### 2. HTTP Client (`src/http/client.zig`)

Create a robust HTTP client with connection pooling:

```zig
pub const ClientOptions = struct {
    /// Base URL for all requests
    base_url: ?[]const u8 = null,
    
    /// Request timeout in milliseconds
    timeout_ms: u32 = 30000,
    
    /// Maximum number of retries
    max_retries: u32 = 3,
    
    /// Retry delay in milliseconds
    retry_delay_ms: u32 = 1000,
    
    /// User agent string
    user_agent: []const u8 = "Plue/1.0",
    
    /// Connection pool size
    pool_size: u32 = 10,
};

pub const Client = struct {
    allocator: std.mem.Allocator,
    options: ClientOptions,
    pool: ConnectionPool,
    
    /// Initialize a new HTTP client
    pub fn init(allocator: std.mem.Allocator, options: ClientOptions) !Client
    
    /// Make an HTTP request
    pub fn request(self: *Client, req: Request) !Response
    
    /// Convenience methods
    pub fn get(self: *Client, url: []const u8) !Response
    pub fn post(self: *Client, url: []const u8, body: []const u8) !Response
    pub fn put(self: *Client, url: []const u8, body: []const u8) !Response
    pub fn delete(self: *Client, url: []const u8) !Response
    
    /// Make request with automatic JSON encoding/decoding
    pub fn requestJson(self: *Client, comptime T: type, req: Request) !T
    
    /// Stream Server-Sent Events
    pub fn streamSSE(self: *Client, url: []const u8, callback: SseCallback, context: *anyopaque) !void
    
    /// Cleanup resources
    pub fn deinit(self: *Client) void
};
```

### 3. Connection Pool (`src/http/pool.zig`)

Implement connection pooling for performance:

```zig
pub const Connection = struct {
    stream: std.net.Stream,
    last_used: i64,
    in_use: bool,
};

pub const ConnectionPool = struct {
    allocator: std.mem.Allocator,
    connections: std.ArrayList(Connection),
    max_connections: u32,
    mutex: std.Thread.Mutex,
    
    /// Get a connection from the pool
    pub fn acquire(self: *ConnectionPool, host: []const u8, port: u16) !*Connection
    
    /// Return a connection to the pool
    pub fn release(self: *ConnectionPool, conn: *Connection) void
    
    /// Clean up idle connections
    pub fn cleanup(self: *ConnectionPool) void
};
```

### 4. JSON Integration (`src/http/json.zig`)

Create JSON request/response helpers:

```zig
pub const JsonOptions = struct {
    /// Whether to allow unknown fields
    ignore_unknown_fields: bool = true,
    
    /// Maximum nesting depth
    max_depth: u32 = 128,
    
    /// Custom allocator for parsing
    allocator: ?std.mem.Allocator = null,
};

/// Send JSON request and parse response
pub fn requestJson(
    client: *Client,
    comptime T: type,
    method: Method,
    url: []const u8,
    payload: anytype,
    options: JsonOptions,
) !T

/// Parse JSON response with error handling
pub fn parseResponse(comptime T: type, response: Response, options: JsonOptions) !T

/// Standard error response format
pub const ErrorResponse = struct {
    error: struct {
        code: []const u8,
        message: []const u8,
        details: ?std.json.Value = null,
    },
};
```

### 5. Server-Sent Events (`src/http/sse.zig`)

Implement SSE streaming for real-time updates:

```zig
pub const SseEvent = struct {
    id: ?[]const u8 = null,
    event: ?[]const u8 = null,
    data: []const u8,
    retry: ?u32 = null,
};

pub const SseCallback = *const fn (event: SseEvent, context: *anyopaque) anyerror!void;

pub const SseStream = struct {
    client: *Client,
    url: []const u8,
    connection: *Connection,
    parser: SseParser,
    abort_controller: *AbortController,
    reconnect_delay_ms: u32,
    max_reconnect_attempts: u32,
    
    /// Start streaming SSE
    pub fn start(client: *Client, url: []const u8) !SseStream
    
    /// Read next event with timeout
    pub fn next(self: *SseStream) !?SseEvent
    
    /// Stream with callback and auto-reconnect
    pub fn stream(self: *SseStream, callback: SseCallback, context: *anyopaque) !void
    
    /// Handle disconnection and reconnection
    pub fn handleDisconnect(self: *SseStream) !void
    
    /// Abort the stream gracefully
    pub fn abort(self: *SseStream) void
    
    /// Close the stream
    pub fn close(self: *SseStream) void
};

pub const SseParser = struct {
    buffer: std.ArrayList(u8),
    line_buffer: std.ArrayList(u8),
    incomplete_line: bool,
    
    /// Parse SSE data chunk by chunk
    pub fn parseChunk(self: *SseParser, data: []const u8) ![]SseEvent
    
    /// Handle partial lines across chunks
    pub fn handlePartialLine(self: *SseParser, data: []const u8) !void
};

/// Abort controller for graceful SSE shutdown
pub const AbortController = struct {
    aborted: std.atomic.Value(bool),
    listeners: std.ArrayList(*const fn() void),
    
    pub fn abort(self: *AbortController) void
    pub fn onAbort(self: *AbortController, callback: *const fn() void) void
};
```

### 6. Retry Logic (`src/http/retry.zig`)

Implement intelligent retry with exponential backoff:

```zig
pub const RetryPolicy = struct {
    max_attempts: u32 = 3,
    base_delay_ms: u32 = 1000,
    max_delay_ms: u32 = 30000,
    exponential_base: f32 = 2.0,
    jitter: bool = true,
    
    /// Determine if request should be retried
    pub fn shouldRetry(self: *const RetryPolicy, response: ?Response, err: ?anyerror, attempt: u32) bool
    
    /// Calculate delay before next retry
    pub fn getDelay(self: *const RetryPolicy, attempt: u32) u32
};

/// Execute request with retry
pub fn withRetry(
    client: *Client,
    request: Request,
    policy: RetryPolicy,
) !Response
```

### 7. Request Builder (`src/http/builder.zig`)

Create a fluent API for building requests:

```zig
pub const RequestBuilder = struct {
    allocator: std.mem.Allocator,
    method: Method,
    url: std.ArrayList(u8),
    headers: std.ArrayList(Header),
    body: ?[]const u8,
    
    /// Create new request builder
    pub fn init(allocator: std.mem.Allocator, method: Method) RequestBuilder
    
    /// Set URL
    pub fn url(self: *RequestBuilder, url_str: []const u8) *RequestBuilder
    
    /// Add header
    pub fn header(self: *RequestBuilder, name: []const u8, value: []const u8) *RequestBuilder
    
    /// Set JSON body
    pub fn json(self: *RequestBuilder, value: anytype) !*RequestBuilder
    
    /// Set form data
    pub fn form(self: *RequestBuilder, data: anytype) !*RequestBuilder
    
    /// Add query parameters
    pub fn query(self: *RequestBuilder, key: []const u8, value: []const u8) *RequestBuilder
    
    /// Build the request
    pub fn build(self: *RequestBuilder) !Request
};
```

## Implementation Steps

### Step 1: Create HTTP Types
1. Create `src/http/types.zig` with core types
2. Define error types and response structures
3. Add helper methods for common operations

### Step 2: Implement Basic Client
1. Create `src/http/client.zig`
2. Implement TCP connection handling
3. Add HTTP/1.1 protocol support
4. Handle request/response cycle

### Step 3: Add Connection Pooling
1. Create `src/http/pool.zig`
2. Implement thread-safe connection management
3. Add connection health checks
4. Handle connection lifecycle

### Step 4: Integrate JSON Support
1. Create `src/http/json.zig`
2. Add automatic serialization/deserialization
3. Handle error responses
4. Support custom types

### Step 5: Implement SSE Streaming
1. Create `src/http/sse.zig`
2. Parse SSE protocol
3. Handle reconnection
4. Support event callbacks

### Step 6: Add Retry Logic
1. Create `src/http/retry.zig`
2. Implement exponential backoff
3. Add jitter for distributed systems
4. Handle different error types

### Step 7: Create Request Builder
1. Create `src/http/builder.zig`
2. Implement fluent API
3. Add validation
4. Support all HTTP methods

## Testing Requirements

1. **Unit Tests** (>95% coverage):
   - HTTP protocol parsing
   - Connection pool management
   - JSON serialization
   - SSE parsing with partial chunks
   - Retry logic with exponential backoff
   - Abort controller functionality

2. **Integration Tests**:
   - Real requests to OpenCode
   - Streaming responses
   - Error handling
   - Timeout scenarios

3. **Performance Tests**:
   - Connection pool efficiency
   - Request throughput
   - Memory usage
   - Concurrent requests

## Example Usage

```zig
// Initialize client
const client = try Client.init(allocator, .{
    .base_url = "http://localhost:3000",
    .timeout_ms = 10000,
    .pool_size = 5,
});
defer client.deinit();

// Connect to event stream for health monitoring
var event_stream = try client.streamSSE("/event");
defer event_stream.close();

// Wait for initial empty message confirming connection
const initial_event = try event_stream.next();
if (!std.mem.eql(u8, initial_event.?.data, "{}")) {
    return error.InvalidHealthResponse;
}

// JSON request/response with OpenCode endpoints
const session = try client.requestJson(
    Session,
    .POST,
    "/session_create",
    {},  // Empty body for session creation
    .{},
);

// Send chat message
const message_response = try client.requestJson(
    MessageInfo,
    .POST,
    "/session_chat",
    .{
        .sessionID = session.id,
        .providerID = "openai",
        .modelID = "gpt-4",
        .parts = &[_]MessagePart{.{ .text = "Hello!" }},
    },
    .{},
);

// Stream with abort handling
var abort_controller = AbortController.init(allocator);
try client.streamSSE("/event", struct {
    fn onEvent(event: SseEvent, ctx: *anyopaque) !void {
        const controller = @ptrCast(*AbortController, @alignCast(@alignOf(AbortController), ctx));
        if (controller.aborted.load(.acquire)) return error.Aborted;
        
        const data = try std.json.parseFromSlice(EventData, allocator, event.data, .{});
        defer data.deinit();
        
        std.log.info("Event: {s}", .{data.value.type});
    }
}.onEvent, &abort_controller);

// Graceful shutdown
abort_controller.abort();
```

## Security Considerations

1. **TLS Support**: Prepare for HTTPS in future versions
2. **Header Validation**: Sanitize header values
3. **URL Validation**: Prevent injection attacks
4. **Timeout Enforcement**: Prevent resource exhaustion
5. **Certificate Pinning**: Consider for production

## Corner Cases and Implementation Details

Based on OpenCode's implementation, handle these critical scenarios:

### SSE Connection Management
1. **Initial Empty Message**: The `/event` endpoint sends `data: {}` immediately upon connection - use this as health confirmation
2. **Abort Handling**: Implement proper `onAbort` callbacks to clean up subscriptions and resources
3. **Partial Line Buffering**: SSE data may arrive in chunks mid-line - buffer incomplete lines
4. **Event Bus Integration**: Events are published through a global Bus system - expect various event types
5. **Connection State Tracking**: Log "event connected" and "event disconnected" for debugging

### HTTP Client Specifics  
1. **No Health Endpoint**: Don't look for `/health` - use `/event` SSE connection instead
2. **POST-Only API**: Most endpoints are POST, even for queries like `/provider_list`
3. **Empty Body Handling**: Some endpoints like `/session_create` accept empty JSON bodies
4. **Consistent Error Format**: All errors return `NamedError` objects with `toObject()` structure
5. **Request Logging**: Log method, path, and duration for all requests

### Connection Pool Optimization
1. **Keep-Alive for SSE**: Don't pool SSE connections - they're long-lived
2. **Idle Timeout**: Set `idleTimeout: 0` for SSE connections to prevent premature closure  
3. **Connection Reuse**: Aggressively reuse connections for regular requests
4. **DNS Caching**: Cache resolved addresses to avoid repeated lookups
5. **Pipeline Requests**: Support HTTP/1.1 pipelining for bulk operations

### Error Recovery Patterns
1. **SSE Auto-Reconnect**: Implement exponential backoff (1s, 2s, 4s...) with jitter
2. **Partial Response Handling**: If SSE disconnects mid-event, discard partial data
3. **Network Change Detection**: Monitor for network interface changes and reconnect
4. **Server Restart Detection**: Detect ECONNREFUSED and trigger reconnection flow
5. **Memory Pressure**: Release idle connections under memory pressure

### Performance Optimizations
1. **Buffer Pooling**: Reuse read/write buffers to reduce allocations
2. **Zero-Copy Parsing**: Parse JSON directly from network buffers when possible
3. **Selective Field Parsing**: Use streaming JSON parser for large responses
4. **Compression Support**: Prepare for gzip/deflate support (not currently used)
5. **Request Batching**: Batch multiple requests to reduce round trips

### UX Improvements
1. **Connection Progress**: Show "Connecting to OpenCode server..." with spinner
2. **Retry Feedback**: Display "Connection lost. Reconnecting... (attempt 2/3)"
3. **Latency Display**: Show request duration in debug mode: "Provider list fetched (124ms)"
4. **Error Context**: Include last successful operation in error messages
5. **Graceful Degradation**: Queue requests during reconnection instead of failing immediately

### Potential Bugs to Watch Out For
1. **SSE Line Splitting**: Events can be split across TCP packets - must buffer partial lines
2. **Large Event Handling**: Set scanner buffer to 10MB (like TUI client) to handle large events
3. **Context Cancellation**: Properly handle context.Done() to avoid goroutine leaks
4. **Connection String**: Ensure trailing slash handling - `c.Server+"event"` vs `c.Server+"/event"`
5. **Empty Data Lines**: SSE spec allows empty data - don't crash on `data: \n`
6. **Race on Close**: Avoid closing channels multiple times in error paths
7. **HTTP/2 Compatibility**: SSE may behave differently with HTTP/2 - test both protocols
8. **Memory Leaks**: Ensure all event subscriptions are cleaned up on disconnect
9. **Concurrent Writes**: Protect shared state with mutexes when handling events
10. **Timeout vs Cancellation**: Distinguish between timeout errors and user cancellation

## Platform Considerations  

### macOS
- Use kqueue for efficient I/O
- Handle BSD socket quirks
- Consider Network.framework integration
- Support system proxy configuration
- Handle App Transport Security (ATS) for future HTTPS

### iOS (Future)
- Prepare for background task limitations
- Consider URLSession for system integration
- Handle network permission requirements
- Support low data mode

### Cross-Platform
- Abstract socket operations
- Handle platform-specific errors
- Test on different architectures

## Success Criteria

The implementation is complete when:
- [ ] HTTP client makes successful requests to OpenCode
- [ ] Connection pooling reduces latency by >50%
- [ ] JSON serialization works for all OpenCode types
- [ ] SSE streaming handles large responses and partial chunks
- [ ] Event stream connection serves as reliable health indicator
- [ ] Abort handling allows graceful stream shutdown
- [ ] Retry logic recovers from transient failures with exponential backoff
- [ ] All tests pass with >95% coverage
- [ ] Memory usage is stable under load
- [ ] Concurrent requests work reliably
- [ ] SSE reconnection works automatically on disconnect

## Git Workflow

Continue in the same worktree:
```bash
cd ../plue-server-management
```

Commit with conventional commits:
- `feat: add core HTTP types and errors`
- `feat: implement basic HTTP client`
- `feat: add connection pooling`
- `feat: integrate JSON support`
- `feat: implement SSE streaming`
- `test: add HTTP client tests`
- `perf: optimize connection reuse`

The branch remains: `feat_add_opencode_server_management`

## Integration with Server Manager

**IMPORTANT**: This task includes completing the health monitoring left unfinished from Task 01:

1. **Update EventStreamConnection** in `src/server/manager.zig`:
   - Replace the stub implementation with actual HTTP/SSE client
   - Connect to `/event` endpoint for health monitoring
   - Parse initial empty message `data: {}` as connection confirmation
   - Implement reconnection logic with exponential backoff
   - Track consecutive failures for server restart decisions

2. **Health Monitoring Pattern**:
   ```zig
   // In ServerManager, update the stub EventStreamConnection
   pub fn connectEventStream(self: *ServerManager) !void {
       const event_url = try std.fmt.allocPrint(self.allocator, "{s}/event", .{self.server_url});
       defer self.allocator.free(event_url);
       
       // Use the HTTP client from this task
       var client = try HttpClient.init(self.allocator);
       self.event_stream = try client.streamSse(event_url, .{
           .on_event = handleHealthEvent,
           .on_disconnect = handleDisconnection,
           .reconnect_delay_ms = self.config.event_stream_reconnect_ms,
       });
   }
   ```

3. **Testing Requirements**:
   - Verify `/event` connection establishes within 5 seconds of server start
   - Test automatic reconnection after network interruption
   - Confirm server restart triggers after max_connection_failures
   - Validate memory cleanup on shutdown