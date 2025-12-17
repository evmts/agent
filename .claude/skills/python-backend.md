# Python Backend

This skill covers FastAPI server patterns, route organization, SSE streaming, and server lifecycle management for the Claude Agent platform.

## Overview

The Python backend is built with FastAPI, implementing an OpenCode-compatible REST API with Server-Sent Events (SSE) for real-time streaming. The server manages the agent lifecycle through MCP (Model Context Protocol) integration.

## Key Files

| File | Purpose |
|------|---------|
| `main.py` | Server entry point with MCP lifecycle |
| `server/app.py` | FastAPI app creation and CORS config |
| `server/__init__.py` | Route registration and exports |
| `server/routes/__init__.py` | Route aggregation |
| `server/routes/` | API endpoint handlers |
| `server/event_bus.py` | SSE event broadcasting |
| `server/state.py` | Global agent state |
| `server/requests/` | Pydantic request models |

## Architecture

```
main.py (entry point)
    │
    ├── Lifespan Context Manager
    │   ├── Initialize MCP wrapper
    │   └── Set global agent
    │
    └── uvicorn.run(app)
            │
            └── FastAPI app (server/app.py)
                    │
                    ├── CORS Middleware
                    └── Routes (server/routes/)
```

## Server Entry Point (`main.py`)

### Lifespan Management

The server uses FastAPI's lifespan context manager for MCP initialization:

```python
from contextlib import asynccontextmanager
from fastapi import FastAPI

# Constants
DEFAULT_HOST = "0.0.0.0"
DEFAULT_PORT = 8000
DEFAULT_USE_MCP = True

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Manage MCP wrapper lifecycle."""
    global _wrapper_context, _wrapper

    model_id = os.environ.get("ANTHROPIC_MODEL", DEFAULT_MODEL)
    working_dir = os.environ.get("WORKING_DIR", os.getcwd())
    use_mcp = os.environ.get("USE_MCP", "true").lower() == "true"

    if use_mcp:
        _wrapper_context = create_mcp_wrapper(
            model_id=model_id,
            working_dir=working_dir,
        )
        _wrapper = await _wrapper_context.__aenter__()
        set_agent(_wrapper)
    else:
        _wrapper = create_simple_wrapper(model_id=model_id)
        set_agent(_wrapper)

    yield  # Server runs here

    # Cleanup
    if use_mcp and _wrapper_context:
        await _wrapper_context.__aexit__(None, None, None)

app.router.lifespan_context = lifespan
```

### Running the Server

```python
def main() -> None:
    """Start server."""
    host = os.environ.get("HOST", DEFAULT_HOST)
    port = int(os.environ.get("PORT", str(DEFAULT_PORT)))
    uvicorn.run(app, host=host, port=port)
```

## FastAPI App Setup (`server/app.py`)

### Constants and App Creation

```python
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

# Constants
DEFAULT_CORS_ORIGINS = "*"
API_TITLE = "OpenCode API"
API_VERSION = "1.0.0"

app = FastAPI(title=API_TITLE, version=API_VERSION)
```

### CORS Configuration

```python
# Parse CORS_ORIGINS env var (comma-separated or "*")
cors_origins_env = os.environ.get("CORS_ORIGINS", DEFAULT_CORS_ORIGINS)
cors_origins = (
    [origin.strip() for origin in cors_origins_env.split(",")]
    if cors_origins_env != DEFAULT_CORS_ORIGINS
    else [DEFAULT_CORS_ORIGINS]
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
```

## Route Organization

### Directory Structure

```
server/routes/
├── __init__.py          # Route registration
├── health.py            # Health check endpoint
├── events.py            # Global SSE stream
├── agents.py            # Agent listing
├── config.py            # Config endpoint
├── mcp.py               # MCP server status
├── project.py           # Project info
├── commands.py          # Slash commands
├── app.py               # App/provider info
├── sessions/            # Session CRUD
│   ├── __init__.py      # Sub-router registration
│   ├── create.py
│   ├── list.py
│   ├── get.py
│   ├── update.py
│   ├── delete.py
│   ├── fork.py
│   ├── abort.py
│   ├── revert.py
│   ├── unrevert.py
│   └── diff.py
├── messages/            # Message operations
│   ├── __init__.py
│   ├── send.py          # SSE streaming endpoint
│   ├── list.py
│   └── get.py
└── tools/               # Tool info
    ├── __init__.py
    ├── list.py
    ├── get.py
    └── schemas.py
```

### Route Registration Pattern

In `server/routes/__init__.py`:

```python
from fastapi import FastAPI

from . import agents, config, events, health, mcp, messages, project, sessions, tools

def register_routes(app: FastAPI) -> None:
    """Register all routes with the FastAPI application."""
    # Simple routers
    app.include_router(agents.router)
    app.include_router(config.router)
    app.include_router(events.router)
    app.include_router(health.router)
    app.include_router(mcp.router)
    app.include_router(project.router)

    # Sub-route modules with their own registration
    sessions.register_routes(app)
    messages.register_routes(app)
    tools.register_routes(app)
```

### Individual Route Pattern

```python
# server/routes/health.py
from fastapi import APIRouter

router = APIRouter()

@router.get("/health")
async def health_check() -> dict:
    """Health check endpoint."""
    return {"status": "ok"}
```

### Sub-Router Pattern

For nested routes like sessions:

```python
# server/routes/sessions/__init__.py
from fastapi import FastAPI

from .create import router as create_router
from .list import router as list_router
from .get import router as get_router
# ... more routers

def register_routes(app: FastAPI) -> None:
    """Register session routes."""
    app.include_router(create_router)
    app.include_router(list_router)
    app.include_router(get_router)
    # ...
```

## SSE Streaming

### Event Bus (`server/event_bus.py`)

Singleton event bus for broadcasting events to SSE subscribers:

```python
import asyncio
from typing import Any
from core import Event

class SSEEventBus:
    """Broadcasts events to SSE subscribers."""

    def __init__(self) -> None:
        self.subscribers: list[asyncio.Queue[dict[str, Any]]] = []

    async def publish(self, event: Event) -> None:
        """Publish event to all subscribers."""
        data = event.model_dump()
        for queue in self.subscribers:
            await queue.put(data)

    def subscribe(self) -> asyncio.Queue[dict[str, Any]]:
        """Create a subscription queue."""
        queue: asyncio.Queue[dict[str, Any]] = asyncio.Queue()
        self.subscribers.append(queue)
        return queue

    def unsubscribe(self, queue: asyncio.Queue[dict[str, Any]]) -> None:
        """Remove a subscription queue."""
        if queue in self.subscribers:
            self.subscribers.remove(queue)

# Singleton
_event_bus: SSEEventBus | None = None

def get_event_bus() -> SSEEventBus:
    """Get global event bus instance."""
    global _event_bus
    if _event_bus is None:
        _event_bus = SSEEventBus()
    return _event_bus
```

### SSE Endpoint Pattern

```python
# server/routes/messages/send.py
import json
from typing import AsyncGenerator
from fastapi import APIRouter, Query
from sse_starlette.sse import EventSourceResponse

from core import send_message, NotFoundError
from ...event_bus import get_event_bus
from ...requests import PromptRequest
from ...state import get_agent

router = APIRouter()

@router.post("/session/{sessionID}/message")
async def send_message_route(
    sessionID: str,
    request: PromptRequest,
    directory: str | None = Query(None)
) -> EventSourceResponse:
    """Send prompt and stream response via SSE."""

    async def stream_response() -> AsyncGenerator[dict, None]:
        try:
            async for event in send_message(
                session_id=sessionID,
                parts=request.parts,
                agent=get_agent(),
                event_bus=get_event_bus(),
                message_id=request.messageID,
                agent_name=request.agent or "default",
                model_id=request.model.modelID if request.model else "default",
                provider_id=request.model.providerID if request.model else "default",
            ):
                yield {
                    "event": event.type,
                    "data": json.dumps({
                        "type": event.type,
                        "properties": event.properties
                    }),
                }
        except NotFoundError:
            # Yield error event (can't raise in generator)
            yield {
                "event": "error",
                "data": json.dumps({"error": "Session not found"}),
            }

    return EventSourceResponse(stream_response())
```

## Request Models

Request models are defined in `server/requests/`:

```python
# server/requests/prompt.py
from pydantic import BaseModel, Field

class ModelRequest(BaseModel):
    """Model selection for a request."""
    modelID: str
    providerID: str

class PromptRequest(BaseModel):
    """Request for sending a message."""
    parts: list[dict]
    messageID: str | None = None
    agent: str | None = None
    model: ModelRequest | None = None
```

## Global State (`server/state.py`)

```python
from agent import AgentWrapper

_agent: AgentWrapper | None = None

def set_agent(agent: AgentWrapper) -> None:
    """Set the global agent wrapper."""
    global _agent
    _agent = agent

def get_agent() -> AgentWrapper:
    """Get the global agent wrapper."""
    if _agent is None:
        raise RuntimeError("Agent not initialized")
    return _agent
```

## Common Tasks

### Adding a New Endpoint

1. Create route file in appropriate location:
   ```python
   # server/routes/my_feature.py
   from fastapi import APIRouter

   router = APIRouter()

   @router.get("/my-endpoint")
   async def my_endpoint() -> dict:
       """Endpoint description."""
       return {"result": "data"}
   ```

2. Register in `server/routes/__init__.py`:
   ```python
   from . import my_feature

   def register_routes(app: FastAPI) -> None:
       app.include_router(my_feature.router)
   ```

### Adding SSE Events

1. Define event type in `core/events.py`
2. Publish events via the event bus:
   ```python
   from server.event_bus import get_event_bus
   from core import Event

   event_bus = get_event_bus()
   await event_bus.publish(Event(type="my.event", properties={...}))
   ```

### Error Handling in Routes

```python
from fastapi import HTTPException

@router.get("/resource/{id}")
async def get_resource(id: str) -> dict:
    resource = find_resource(id)
    if resource is None:
        raise HTTPException(status_code=404, detail="Resource not found")
    return resource.model_dump()
```

## Best Practices

1. **Constants at module level** - Define DEFAULT_*, API_* constants at top of file
2. **Type hints** - Always include return type annotations
3. **Async for I/O** - Use `async def` for all route handlers
4. **Pydantic models** - Use for request/response validation
5. **Error events in generators** - Yield error events instead of raising in async generators
6. **Singleton pattern** - Use for global state (event bus, agent)

## Related Skills

- [api-development.md](./api-development.md) - OpenCode API spec details
- [agent-system.md](./agent-system.md) - Agent wrapper creation
- [configuration.md](./configuration.md) - Environment variables
