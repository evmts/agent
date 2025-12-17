# API Development

This skill covers the OpenCode API specification, endpoint implementation, SSE event types, and data models for the Claude Agent platform.

## Overview

The Claude Agent API implements the OpenCode specification, providing a RESTful interface with Server-Sent Events (SSE) for real-time streaming. The API enables session management, message exchange, and tool execution.

## Key Files

| File | Purpose |
|------|---------|
| `server/routes/` | API endpoint implementations |
| `core/models/` | Python data models |
| `sdk/agent/types.go` | Go SDK type definitions |
| `server/requests/` | Request Pydantic models |

## API Endpoints

### Session Management

| Method | Endpoint | Description | Request | Response |
|--------|----------|-------------|---------|----------|
| `POST` | `/session` | Create session | `CreateSessionRequest` | `Session` |
| `GET` | `/session` | List sessions | - | `Session[]` |
| `GET` | `/session/{id}` | Get session | - | `Session` |
| `PATCH` | `/session/{id}` | Update session | `UpdateSessionRequest` | `Session` |
| `DELETE` | `/session/{id}` | Delete session | - | `bool` |

### Session Actions

| Method | Endpoint | Description | Request | Response |
|--------|----------|-------------|---------|----------|
| `POST` | `/session/{id}/abort` | Abort active task | - | `bool` |
| `GET` | `/session/{id}/diff` | Get file diffs | - | `FileDiff[]` |
| `POST` | `/session/{id}/fork` | Fork session | `ForkRequest` | `Session` |
| `POST` | `/session/{id}/revert` | Revert to message | `RevertRequest` | `Session` |
| `POST` | `/session/{id}/unrevert` | Undo revert | - | `Session` |

### Message Operations

| Method | Endpoint | Description | Request | Response |
|--------|----------|-------------|---------|----------|
| `POST` | `/session/{id}/message` | Send message (SSE) | `PromptRequest` | `SSE stream` |
| `GET` | `/session/{id}/message` | List messages | - | `MessageWithParts[]` |
| `GET` | `/session/{id}/message/{msgId}` | Get message | - | `MessageWithParts` |

### Supporting Endpoints

| Method | Endpoint | Description | Response |
|--------|----------|-------------|----------|
| `GET` | `/health` | Health check | `HealthResponse` |
| `GET` | `/global/event` | Global SSE stream | `SSE stream` |
| `GET` | `/mcp/servers` | MCP server status | `MCPServersResponse` |
| `GET` | `/project/current` | Current project | `Project` |
| `GET` | `/agent` | List agents | `Agent[]` |
| `GET` | `/config` | App config | `Config` |
| `GET` | `/app/providers` | AI providers | `ProvidersResponse` |
| `GET` | `/command` | Slash commands | `Command[]` |
| `GET` | `/tool` | List tools | `Tool[]` |
| `GET` | `/tool/{name}/schema` | Tool schema | `ToolSchema` |

## Data Models

### Session

```python
class Session(BaseModel):
    id: str                              # Unique session ID
    projectID: str                       # Project identifier
    directory: str                       # Working directory
    title: str                           # Session title
    version: str                         # Version string
    time: SessionTime                    # Created/updated timestamps
    parentID: str | None = None          # Parent session (for forks)
    summary: SessionSummary | None = None # Change summary
    revert: RevertInfo | None = None     # Revert state

class SessionTime(BaseModel):
    created: float                       # Unix timestamp
    updated: float                       # Unix timestamp
    archived: float | None = None        # Unix timestamp

class SessionSummary(BaseModel):
    additions: int                       # Lines added
    deletions: int                       # Lines deleted
    files: int                           # Files changed
    diffs: list[FileDiff] | None = None
```

### Message

```python
class UserMessage(BaseModel):
    id: str
    sessionID: str
    role: Literal["user"] = "user"
    time: MessageTime
    agent: str                           # Agent name used
    model: ModelInfo                     # Model selection
    system: str | None = None            # System prompt override
    tools: dict[str, bool] | None = None # Tool overrides

class AssistantMessage(BaseModel):
    id: str
    sessionID: str
    role: Literal["assistant"] = "assistant"
    time: MessageTime
    parentID: str                        # Parent user message
    modelID: str
    providerID: str
    mode: str                            # Agent mode
    path: PathInfo                       # Working directory info
    cost: float                          # API cost
    tokens: TokenInfo                    # Token usage
    finish: str | None = None            # Completion reason
    summary: bool | None = None          # Is summary message
    error: dict | None = None            # Error details

Message = UserMessage | AssistantMessage
```

### Part Types

Messages contain parts with different types:

```python
# Text content
class TextPart(BaseModel):
    id: str
    sessionID: str
    messageID: str
    type: Literal["text"] = "text"
    text: str
    time: PartTime | None = None

# Extended thinking/reasoning
class ReasoningPart(BaseModel):
    id: str
    sessionID: str
    messageID: str
    type: Literal["reasoning"] = "reasoning"
    text: str
    time: PartTime

# Tool execution
class ToolPart(BaseModel):
    id: str
    sessionID: str
    messageID: str
    type: Literal["tool"] = "tool"
    tool: str                            # Tool name
    state: ToolState

# File attachment
class FilePart(BaseModel):
    id: str
    sessionID: str
    messageID: str
    type: Literal["file"] = "file"
    mime: str
    url: str
    filename: str | None = None
```

### ToolState

```python
class ToolState(BaseModel):
    status: str                          # "pending", "running", "completed"
    input: dict[str, Any]                # Tool input parameters
    raw: str | None = None               # Raw tool call
    output: str | None = None            # Tool output
    title: str | None = None             # Display title
    metadata: dict | None = None         # Additional metadata
    time: PartTime | None = None         # Timing info
    progress: ToolProgress | None = None # Progress tracking
```

### Supporting Types

```python
class ModelInfo(BaseModel):
    providerID: str
    modelID: str

class TokenInfo(BaseModel):
    input: int
    output: int
    reasoning: int
    cache: dict[str, int] | None = None

class PathInfo(BaseModel):
    cwd: str                             # Current working directory
    root: str                            # Project root

class FileDiff(BaseModel):
    file: str
    before: str
    after: str
    additions: int
    deletions: int
```

## Request Types

### CreateSessionRequest

```python
class CreateSessionRequest(BaseModel):
    parentID: str | None = None          # For forking
    title: str | None = None
```

### PromptRequest

```python
class PromptRequest(BaseModel):
    parts: list[dict]                    # TextPartInput or FilePartInput
    messageID: str | None = None         # Optional message ID
    model: ModelInfo | None = None       # Model override
    agent: str | None = None             # Agent override
    noReply: bool | None = None          # Don't wait for response
    system: str | None = None            # System prompt override
    tools: dict[str, bool] | None = None # Tool enable/disable
```

### Part Inputs

```python
class TextPartInput(BaseModel):
    type: Literal["text"] = "text"
    text: str

class FilePartInput(BaseModel):
    type: Literal["file"] = "file"
    mime: str
    url: str
    filename: str | None = None
```

### ForkRequest / RevertRequest

```python
class ForkRequest(BaseModel):
    messageID: str | None = None         # Fork point (default: latest)

class RevertRequest(BaseModel):
    messageID: str                       # Message to revert to
    partID: str | None = None            # Specific part
```

## SSE Event Types

Events are sent in Server-Sent Events format:

```
event: {event_type}
data: {"type": "{event_type}", "properties": {...}}
```

### Session Events

| Event | Description | Properties |
|-------|-------------|------------|
| `session.created` | New session | `{info: Session}` |
| `session.updated` | Session changed | `{info: Session}` |
| `session.deleted` | Session removed | `{id: string}` |

### Message Events

| Event | Description | Properties |
|-------|-------------|------------|
| `message.updated` | Message metadata | `{info: Message}` |

### Part Events

| Event | Description | Properties |
|-------|-------------|------------|
| `part.updated` | Part content update | `{id, sessionID, messageID, type, ...}` |

Part events include:
- `type: "text"` - Text content with `text` field
- `type: "reasoning"` - Thinking content with `text` field
- `type: "tool"` - Tool execution with `tool`, `state` fields
- `type: "file"` - File attachment with `mime`, `url` fields

### Error Events

```json
{"event": "error", "data": {"error": "Error message"}}
```

## Directory Parameter

Many endpoints accept a `directory` query parameter to scope operations:

```
GET /session?directory=/path/to/project
POST /session/{id}/message?directory=/path/to/project
```

The directory is used for:
- File operations
- Working directory context
- Snapshot tracking

## Example: Creating and Messaging a Session

```python
import httpx

# Create session
session = httpx.post("http://localhost:8000/session", json={
    "title": "My Session"
}).json()

# Send message with SSE streaming
with httpx.stream("POST", f"http://localhost:8000/session/{session['id']}/message",
    json={
        "parts": [{"type": "text", "text": "Hello!"}],
        "agent": "default"
    }
) as response:
    for line in response.iter_lines():
        if line.startswith("data: "):
            event = json.loads(line[6:])
            if event["type"] == "part.updated":
                print(event["properties"].get("text", ""))
```

## Example: Go SDK Usage

```go
client := agent.NewClient("http://localhost:8000")

// Create session
session, _ := client.CreateSession(ctx, &agent.CreateSessionRequest{
    Title: agent.String("My Session"),
})

// Send message with streaming
eventCh, errCh, _ := client.SendMessage(ctx, session.ID, &agent.PromptRequest{
    Parts: []interface{}{
        agent.TextPartInput{Type: "text", Text: "Hello!"},
    },
})

for event := range eventCh {
    // Handle part.updated events for streaming text
}
```

## Implementing New Endpoints

1. Create route file in appropriate `server/routes/` subdirectory
2. Define request model in `server/requests/` if needed
3. Define response model in `core/models/` if needed
4. Add Go types in `sdk/agent/types.go`
5. Register route in `server/routes/__init__.py`

Example endpoint:

```python
# server/routes/my_feature.py
from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel

router = APIRouter()

class MyRequest(BaseModel):
    param: str

class MyResponse(BaseModel):
    result: str

@router.post("/my-endpoint")
async def my_endpoint(
    request: MyRequest,
    directory: str | None = Query(None)
) -> MyResponse:
    """Endpoint description."""
    # Implementation
    return MyResponse(result="success")
```

## Related Skills

- [python-backend.md](./python-backend.md) - Server implementation details
- [go-development.md](./go-development.md) - SDK implementation
- [testing.md](./testing.md) - API testing patterns
