# Client

HTTP and SSE client for communicating with the Plue API server.

## Architecture

```
┌──────────────────────────────────────┐
│         PlueClient (client.zig)      │
│   High-level API client interface    │
└────────────┬──────────────┬──────────┘
             │              │
             │              │
      ┌──────▼──────┐  ┌───▼────────┐
      │ HttpClient  │  │ SseClient  │
      │  (http.zig) │  │ (sse.zig)  │
      │             │  │            │
      │ GET/POST    │  │ Streaming  │
      │ PATCH/DEL   │  │ Events     │
      └─────────────┘  └────────────┘
             │              │
             └──────┬───────┘
                    │
         ┌──────────▼──────────┐
         │  Protocol Types     │
         │  (protocol.zig)     │
         │                     │
         │  - Session          │
         │  - Message          │
         │  - StreamEvent      │
         │  - ToolUse          │
         └─────────────────────┘
```

## Files

| File | Purpose |
|------|---------|
| `client.zig` | High-level PlueClient with typed API methods |
| `http.zig` | Simple HTTP client (GET, POST, PATCH, DELETE) |
| `sse.zig` | Server-Sent Events streaming client |
| `protocol.zig` | Protocol types and JSON parsing |

## Usage

```zig
const PlueClient = @import("client/client.zig").PlueClient;

var client = PlueClient.init(allocator, "http://localhost:4000");
defer client.deinit();

// Create session
const session = try client.createSession("/path/to/repo", "claude-sonnet-4");

// List sessions
const sessions = try client.listSessions();

// Stream message
try client.stream(session.id, "Hello", null, eventCallback);
```

## Protocol

All requests/responses use JSON. Key types:

- **Session**: Agent session with ID, directory, model
- **Message**: Chat message (user or assistant)
- **StreamEvent**: Real-time event during streaming
- **ToolUse**: Tool invocation by agent
- **TokenUsage**: Token consumption tracking

## Event Queue

SSE events are buffered in `EventQueue` for async processing:

```zig
const EventQueue = @import("client/sse.zig").EventQueue;

var queue = EventQueue.init(allocator);
defer queue.deinit();

// Push events from callback
queue.push(event);

// Pop in main loop
while (queue.pop()) |event| {
    // Handle event
}
```
