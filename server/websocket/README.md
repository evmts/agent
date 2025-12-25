# WebSocket Handlers

WebSocket connection handlers for real-time agent streaming. Provides Server-Sent Events (SSE) and bidirectional communication for agent interactions.

## Key Files

| File | Purpose |
|------|---------|
| `agent_handler.zig` | Agent streaming via SSE/WebSocket |

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                  WebSocket Handlers                         │
│                                                             │
│  ┌───────────────────────────────────────────────────────┐ │
│  │              agent_handler.zig                        │ │
│  │                                                       │ │
│  │  ┌─────────────┐         ┌──────────────────────┐    │ │
│  │  │   Client    │◀───────▶│   SSE/WebSocket      │    │ │
│  │  │   Browser   │         │   Connection         │    │ │
│  │  └─────────────┘         └──────────┬───────────┘    │ │
│  │                                     │                │ │
│  │                                     ▼                │ │
│  │                          ┌──────────────────────┐    │ │
│  │                          │   Agent Executor     │    │ │
│  │                          │                      │    │ │
│  │                          │ • Stream tokens      │    │ │
│  │                          │ • Stream tool calls  │    │ │
│  │                          │ • Stream results     │    │ │
│  │                          └──────────┬───────────┘    │ │
│  │                                     │                │ │
│  │                                     ▼                │ │
│  │                          ┌──────────────────────┐    │ │
│  │                          │  Anthropic API       │    │ │
│  │                          │  (Claude)            │    │ │
│  │                          └──────────────────────┘    │ │
│  └───────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

## Event Flow

```
Client connects to /api/agent/stream
         │
         ▼
┌────────────────────┐
│  Authenticate      │  Validate session/token
└────────┬───────────┘
         │
         ▼
┌────────────────────┐
│  Create SSE conn   │  Setup Server-Sent Events stream
└────────┬───────────┘
         │
         ▼
┌────────────────────┐
│  Start Agent       │  Initialize agent with callbacks
└────────┬───────────┘
         │
         ▼
┌────────────────────────────────────────┐
│  Stream Events:                        │
│                                        │
│  1. token           → Send to client   │
│  2. tool_call       → Send to client   │
│  3. tool_result     → Send to client   │
│  4. error           → Send to client   │
│  5. done            → Close connection │
└────────────────────────────────────────┘
```

## SSE Event Types

| Event | Payload | Description |
|-------|---------|-------------|
| `token` | `{ text: string }` | Streaming token from LLM |
| `tool_call` | `{ name: string, args: any }` | Agent invoking a tool |
| `tool_result` | `{ result: any }` | Tool execution result |
| `error` | `{ error: string }` | Error during execution |
| `done` | `{ usage: {...} }` | Stream complete, token usage |

## Usage Pattern

Client-side:

```typescript
const eventSource = new EventSource('/api/agent/stream?session_id=123');

eventSource.addEventListener('token', (e) => {
  const { text } = JSON.parse(e.data);
  appendToUI(text);
});

eventSource.addEventListener('tool_call', (e) => {
  const { name, args } = JSON.parse(e.data);
  showToolExecution(name, args);
});

eventSource.addEventListener('done', (e) => {
  eventSource.close();
});
```

Server-side:

```zig
const websocket = @import("websocket/agent_handler.zig");

// Setup SSE stream with callbacks
const callbacks = .{
    .onToken = sendToken,
    .onToolCall = sendToolCall,
    .onToolResult = sendToolResult,
};

try websocket.handleAgentStream(req, res, callbacks);
```

## Connection Management

- Connections are authenticated via session cookie or bearer token
- Each connection mapped to agent session
- Automatic cleanup on disconnect
- Heartbeat to detect dead connections
- Graceful shutdown on server restart
