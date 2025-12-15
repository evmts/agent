"""
OpenCode-compatible API server.

Implements the OpenCode API specification for use with OpenCode clients
(including Go Bubbletea TUI).
"""

import asyncio
import json
import os
import secrets
import time
from typing import Any, AsyncGenerator, Literal

from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from sse_starlette.sse import EventSourceResponse

from snapshot import Snapshot

# =============================================================================
# Pydantic Models
# =============================================================================


def gen_id(prefix: str) -> str:
    """Generate IDs matching OpenCode format: ses_xxx, msg_xxx, prt_xxx"""
    return f"{prefix}{secrets.token_urlsafe(12)}"


# --- Time Models ---
class SessionTime(BaseModel):
    created: float
    updated: float
    archived: float | None = None


class MessageTime(BaseModel):
    created: float
    completed: float | None = None


class PartTime(BaseModel):
    start: float
    end: float | None = None


# --- Session Models ---
class FileDiff(BaseModel):
    file: str
    before: str
    after: str
    additions: int
    deletions: int


class SessionSummary(BaseModel):
    additions: int
    deletions: int
    files: int
    diffs: list[FileDiff] | None = None


class RevertInfo(BaseModel):
    messageID: str
    partID: str | None = None
    snapshot: str | None = None
    diff: str | None = None


class Session(BaseModel):
    id: str
    projectID: str
    directory: str
    title: str
    version: str
    time: SessionTime
    parentID: str | None = None
    summary: SessionSummary | None = None
    revert: RevertInfo | None = None


# --- Model/Provider Info ---
class ModelInfo(BaseModel):
    providerID: str
    modelID: str


class TokenInfo(BaseModel):
    input: int
    output: int
    reasoning: int = 0
    cache: dict[str, int] | None = None


class PathInfo(BaseModel):
    cwd: str
    root: str


# --- Message Models ---
class UserMessage(BaseModel):
    id: str
    sessionID: str
    role: Literal["user"] = "user"
    time: MessageTime
    agent: str
    model: ModelInfo
    system: str | None = None
    tools: dict[str, bool] | None = None


class AssistantMessage(BaseModel):
    id: str
    sessionID: str
    role: Literal["assistant"] = "assistant"
    time: MessageTime
    parentID: str
    modelID: str
    providerID: str
    mode: str
    path: PathInfo
    cost: float
    tokens: TokenInfo
    finish: str | None = None
    summary: bool | None = None
    error: dict | None = None


Message = UserMessage | AssistantMessage


# --- Part Models ---
class TextPart(BaseModel):
    id: str
    sessionID: str
    messageID: str
    type: Literal["text"] = "text"
    text: str
    time: PartTime | None = None


class ReasoningPart(BaseModel):
    id: str
    sessionID: str
    messageID: str
    type: Literal["reasoning"] = "reasoning"
    text: str
    time: PartTime


class ToolStatePending(BaseModel):
    status: Literal["pending"] = "pending"
    input: dict[str, Any]
    raw: str


class ToolStateRunning(BaseModel):
    status: Literal["running"] = "running"
    input: dict[str, Any]
    title: str | None = None
    metadata: dict[str, Any] | None = None
    time: PartTime


class ToolStateCompleted(BaseModel):
    status: Literal["completed"] = "completed"
    input: dict[str, Any]
    output: str
    title: str | None = None
    metadata: dict[str, Any] | None = None
    time: PartTime


ToolState = ToolStatePending | ToolStateRunning | ToolStateCompleted


class ToolPart(BaseModel):
    id: str
    sessionID: str
    messageID: str
    type: Literal["tool"] = "tool"
    tool: str
    state: ToolState


class FilePart(BaseModel):
    id: str
    sessionID: str
    messageID: str
    type: Literal["file"] = "file"
    mime: str
    url: str
    filename: str | None = None


Part = TextPart | ReasoningPart | ToolPart | FilePart


# --- Request/Response Models ---
class CreateSessionRequest(BaseModel):
    parentID: str | None = None
    title: str | None = None


class UpdateSessionRequest(BaseModel):
    title: str | None = None
    time: dict | None = None  # { archived: number }


class TextPartInput(BaseModel):
    type: Literal["text"] = "text"
    text: str


class FilePartInput(BaseModel):
    type: Literal["file"] = "file"
    mime: str
    url: str
    filename: str | None = None


PartInput = TextPartInput | FilePartInput


class PromptRequest(BaseModel):
    parts: list[dict]  # TextPartInput | FilePartInput
    messageID: str | None = None
    model: ModelInfo | None = None
    agent: str | None = None
    noReply: bool | None = None
    system: str | None = None
    tools: dict[str, bool] | None = None


class ForkRequest(BaseModel):
    messageID: str | None = None


class RevertRequest(BaseModel):
    messageID: str
    partID: str | None = None


# --- Event Models ---
class Event(BaseModel):
    type: str
    properties: dict


# --- Error Models ---
class BadRequestError(BaseModel):
    error: str = "Bad request"
    message: str


class NotFoundError(BaseModel):
    error: str = "Not found"
    message: str


# =============================================================================
# In-Memory Storage & Event Bus
# =============================================================================

# Storage
sessions: dict[str, Session] = {}
session_messages: dict[str, list[dict]] = {}  # sessionID -> [{info, parts}]
active_tasks: dict[str, asyncio.Task] = {}  # sessionID -> running task
session_snapshots: dict[str, Snapshot] = {}  # sessionID -> Snapshot instance
session_snapshot_history: dict[str, list[str]] = {}  # sessionID -> [tree SHA hashes]

# Event bus for SSE
event_subscribers: list[asyncio.Queue] = []


async def broadcast_event(event: Event):
    """Broadcast event to all SSE subscribers."""
    data = event.model_dump()
    for queue in event_subscribers:
        await queue.put(data)


# Placeholder for agent
agent = None


def set_agent(new_agent):
    """Set the agent instance. Called by agent configuration module."""
    global agent
    agent = new_agent


# =============================================================================
# FastAPI App
# =============================================================================

app = FastAPI(title="OpenCode API", version="1.0.0")

# CORS Configuration
# SECURITY NOTE: allow_origins=["*"] is insecure for production environments.
# It allows any origin to make requests, which can lead to CSRF attacks.
# For production, set CORS_ORIGINS environment variable to specific allowed origins:
# Example: CORS_ORIGINS="https://example.com,https://app.example.com"
cors_origins_env = os.environ.get("CORS_ORIGINS", "*")
cors_origins = [origin.strip() for origin in cors_origins_env.split(",")] if cors_origins_env != "*" else ["*"]

app.add_middleware(
    CORSMiddleware,
    allow_origins=cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# =============================================================================
# Global Event SSE Endpoint
# =============================================================================


@app.get("/global/event")
async def global_event(directory: str | None = Query(None)):
    """Subscribe to global events via SSE."""

    async def event_generator() -> AsyncGenerator[dict, None]:
        queue: asyncio.Queue = asyncio.Queue()
        event_subscribers.append(queue)
        try:
            while True:
                event = await queue.get()
                yield {"event": event["type"], "data": json.dumps(event)}
        finally:
            event_subscribers.remove(queue)

    return EventSourceResponse(event_generator())


# =============================================================================
# Session Endpoints
# =============================================================================


@app.get("/session")
async def list_sessions(directory: str | None = Query(None)) -> list[Session]:
    """List all sessions sorted by most recently updated."""
    return sorted(sessions.values(), key=lambda s: s.time.updated, reverse=True)


@app.post("/session")
async def create_session(
    request: CreateSessionRequest, directory: str | None = Query(None)
) -> Session:
    """Create a new session."""
    now = time.time()
    session = Session(
        id=gen_id("ses_"),
        projectID="default",
        directory=directory or os.getcwd(),
        title=request.title or "New Session",
        version="1.0.0",
        time=SessionTime(created=now, updated=now),
        parentID=request.parentID,
    )
    sessions[session.id] = session
    session_messages[session.id] = []

    # Initialize snapshot system
    snapshot = Snapshot(directory or os.getcwd())
    session_snapshots[session.id] = snapshot
    try:
        initial_hash = snapshot.track()
        session_snapshot_history[session.id] = [initial_hash]
    except Exception:
        # Snapshot initialization failed (e.g., not a valid directory)
        session_snapshot_history[session.id] = []

    await broadcast_event(
        Event(type="session.created", properties={"info": session.model_dump()})
    )
    return session


@app.get("/session/{sessionID}")
async def get_session(sessionID: str, directory: str | None = Query(None)) -> Session:
    """Get session details."""
    if sessionID not in sessions:
        raise HTTPException(status_code=404, detail="Session not found")
    return sessions[sessionID]


@app.delete("/session/{sessionID}")
async def delete_session(sessionID: str, directory: str | None = Query(None)) -> bool:
    """Delete a session."""
    if sessionID not in sessions:
        raise HTTPException(status_code=404, detail="Session not found")

    session = sessions.pop(sessionID)
    session_messages.pop(sessionID, None)
    session_snapshots.pop(sessionID, None)
    session_snapshot_history.pop(sessionID, None)

    await broadcast_event(
        Event(type="session.deleted", properties={"info": session.model_dump()})
    )
    return True


@app.patch("/session/{sessionID}")
async def update_session(
    sessionID: str, request: UpdateSessionRequest, directory: str | None = Query(None)
) -> Session:
    """Update session title or archived status."""
    if sessionID not in sessions:
        raise HTTPException(status_code=404, detail="Session not found")

    session = sessions[sessionID]
    if request.title is not None:
        session.title = request.title
    if request.time and "archived" in request.time:
        session.time.archived = request.time["archived"]
    session.time.updated = time.time()
    sessions[sessionID] = session

    await broadcast_event(
        Event(type="session.updated", properties={"info": session.model_dump()})
    )
    return session


# =============================================================================
# Message Endpoints
# =============================================================================


@app.get("/session/{sessionID}/message")
async def list_messages(
    sessionID: str, limit: int | None = Query(None), directory: str | None = Query(None)
) -> list[dict]:
    """List messages in a session."""
    if sessionID not in sessions:
        raise HTTPException(status_code=404, detail="Session not found")

    messages = session_messages.get(sessionID, [])
    if limit:
        messages = messages[-limit:]
    return messages


@app.get("/session/{sessionID}/message/{messageID}")
async def get_message(
    sessionID: str, messageID: str, directory: str | None = Query(None)
) -> dict:
    """Get a specific message."""
    if sessionID not in sessions:
        raise HTTPException(status_code=404, detail="Session not found")

    for msg in session_messages.get(sessionID, []):
        if msg["info"]["id"] == messageID:
            return msg

    raise HTTPException(status_code=404, detail="Message not found")


@app.post("/session/{sessionID}/message")
async def send_message(
    sessionID: str, request: PromptRequest, directory: str | None = Query(None)
):
    """Send a prompt and stream the response via SSE."""
    if sessionID not in sessions:
        raise HTTPException(status_code=404, detail="Session not found")

    async def stream_response() -> AsyncGenerator[dict, None]:
        now = time.time()

        # Create user message
        user_msg_id = request.messageID or gen_id("msg_")
        user_msg = {
            "info": {
                "id": user_msg_id,
                "sessionID": sessionID,
                "role": "user",
                "time": {"created": now},
                "agent": request.agent or "default",
                "model": (request.model.model_dump() if request.model else {"providerID": "default", "modelID": "default"}),
            },
            "parts": [],
        }

        # Add text parts from request
        for part in request.parts:
            if part.get("type") == "text":
                part_id = gen_id("prt_")
                user_msg["parts"].append({
                    "id": part_id,
                    "sessionID": sessionID,
                    "messageID": user_msg_id,
                    "type": "text",
                    "text": part.get("text", ""),
                })

        session_messages[sessionID].append(user_msg)
        await broadcast_event(Event(type="message.updated", properties={"info": user_msg["info"]}))

        # Create assistant message
        asst_msg_id = gen_id("msg_")
        asst_msg = {
            "info": {
                "id": asst_msg_id,
                "sessionID": sessionID,
                "role": "assistant",
                "time": {"created": time.time()},
                "parentID": user_msg_id,
                "modelID": request.model.modelID if request.model else "default",
                "providerID": request.model.providerID if request.model else "default",
                "mode": "normal",
                "path": {"cwd": os.getcwd(), "root": os.getcwd()},
                "cost": 0.0,
                "tokens": {"input": 0, "output": 0, "reasoning": 0, "cache": {"read": 0, "write": 0}},
            },
            "parts": [],
        }

        # Broadcast assistant message creation
        yield {"event": "message.updated", "data": json.dumps({"type": "message.updated", "properties": {"info": asst_msg["info"]}})}

        # Capture step start snapshot
        snapshot = session_snapshots.get(sessionID)
        step_start_hash: str | None = None
        if snapshot:
            try:
                step_start_hash = snapshot.track()
            except Exception:
                pass

        if agent is None:
            # No agent configured - return error part
            error_part_id = gen_id("prt_")
            error_part = {
                "id": error_part_id,
                "sessionID": sessionID,
                "messageID": asst_msg_id,
                "type": "text",
                "text": "Agent not configured. Please set up an agent using set_agent().",
            }
            asst_msg["parts"].append(error_part)
            yield {"event": "part.updated", "data": json.dumps({"type": "part.updated", "properties": error_part})}
        else:
            # Stream from agent
            text_part_id = gen_id("prt_")
            text_content = ""
            reasoning_part_id: str | None = None
            reasoning_content = ""
            tool_parts: dict[str, dict] = {}  # tool_id -> tool_part

            try:
                # Extract text from user message
                user_text = ""
                for part in request.parts:
                    if part.get("type") == "text":
                        user_text += part.get("text", "")

                async for event in agent.stream_async(user_text):
                    event_type = getattr(event, "event_type", "text")

                    if event_type == "text" and hasattr(event, "data") and event.data:
                        # Text content
                        text_content += event.data
                        text_part = {
                            "id": text_part_id,
                            "sessionID": sessionID,
                            "messageID": asst_msg_id,
                            "type": "text",
                            "text": text_content,
                        }
                        yield {"event": "part.updated", "data": json.dumps({"type": "part.updated", "properties": text_part})}

                    elif event_type == "reasoning" and hasattr(event, "reasoning") and event.reasoning:
                        # Reasoning/thinking content
                        if reasoning_part_id is None:
                            reasoning_part_id = gen_id("prt_")
                        reasoning_content += event.reasoning
                        reasoning_part = {
                            "id": reasoning_part_id,
                            "sessionID": sessionID,
                            "messageID": asst_msg_id,
                            "type": "reasoning",
                            "text": reasoning_content,
                            "time": {"start": time.time()},
                        }
                        yield {"event": "part.updated", "data": json.dumps({"type": "part.updated", "properties": reasoning_part})}

                    elif event_type == "tool_call":
                        # Tool invocation started
                        tool_part_id = gen_id("prt_")
                        tool_part = {
                            "id": tool_part_id,
                            "sessionID": sessionID,
                            "messageID": asst_msg_id,
                            "type": "tool",
                            "tool": event.tool_name,
                            "state": {
                                "status": "running",
                                "input": event.tool_input or {},
                                "title": event.tool_name,
                                "time": {"start": time.time()},
                            },
                        }
                        if event.tool_id:
                            tool_parts[event.tool_id] = tool_part
                        yield {"event": "part.updated", "data": json.dumps({"type": "part.updated", "properties": tool_part})}

                    elif event_type == "tool_result":
                        # Tool execution completed
                        if event.tool_id and event.tool_id in tool_parts:
                            tool_part = tool_parts[event.tool_id]
                            tool_part["state"]["status"] = "completed"
                            tool_part["state"]["output"] = event.tool_output
                            tool_part["state"]["time"]["end"] = time.time()
                            yield {"event": "part.updated", "data": json.dumps({"type": "part.updated", "properties": tool_part})}

                # Final text part
                if text_content:
                    asst_msg["parts"].append({
                        "id": text_part_id,
                        "sessionID": sessionID,
                        "messageID": asst_msg_id,
                        "type": "text",
                        "text": text_content,
                    })

                # Final reasoning part
                if reasoning_content and reasoning_part_id:
                    asst_msg["parts"].append({
                        "id": reasoning_part_id,
                        "sessionID": sessionID,
                        "messageID": asst_msg_id,
                        "type": "reasoning",
                        "text": reasoning_content,
                    })

                # Final tool parts
                for tool_part in tool_parts.values():
                    asst_msg["parts"].append(tool_part)

            except Exception as e:
                error_part_id = gen_id("prt_")
                error_part = {
                    "id": error_part_id,
                    "sessionID": sessionID,
                    "messageID": asst_msg_id,
                    "type": "text",
                    "text": f"Error: {str(e)}",
                }
                asst_msg["parts"].append(error_part)
                yield {"event": "part.updated", "data": json.dumps({"type": "part.updated", "properties": error_part})}

        # Complete assistant message
        asst_msg["info"]["time"]["completed"] = time.time()
        session_messages[sessionID].append(asst_msg)

        # Capture step finish snapshot and compute diff
        if snapshot and step_start_hash:
            try:
                step_finish_hash = snapshot.track()
                session_snapshot_history[sessionID].append(step_finish_hash)

                # Compute diff and update session summary
                changed_files = snapshot.patch(step_start_hash, step_finish_hash)
                if changed_files:
                    diffs = snapshot.diff_full(step_start_hash, step_finish_hash)
                    sessions[sessionID].summary = SessionSummary(
                        additions=sum(d.additions for d in diffs),
                        deletions=sum(d.deletions for d in diffs),
                        files=len(diffs),
                        diffs=[
                            FileDiff(
                                file=d.file,
                                before=d.before,
                                after=d.after,
                                additions=d.additions,
                                deletions=d.deletions,
                            )
                            for d in diffs
                        ],
                    )
            except Exception:
                pass

        # Update session timestamp
        sessions[sessionID].time.updated = time.time()

        yield {"event": "message.updated", "data": json.dumps({"type": "message.updated", "properties": {"info": asst_msg["info"]}})}

    return EventSourceResponse(stream_response())


# =============================================================================
# Session Action Endpoints
# =============================================================================


@app.post("/session/{sessionID}/abort")
async def abort_session(sessionID: str, directory: str | None = Query(None)) -> bool:
    """Abort an active session."""
    if sessionID not in sessions:
        raise HTTPException(status_code=404, detail="Session not found")

    if sessionID in active_tasks:
        active_tasks[sessionID].cancel()
        del active_tasks[sessionID]

    return True


@app.get("/session/{sessionID}/diff")
async def get_session_diff(
    sessionID: str, messageID: str | None = Query(None), directory: str | None = Query(None)
) -> list[FileDiff]:
    """Get file diffs for a session."""
    if sessionID not in sessions:
        raise HTTPException(status_code=404, detail="Session not found")

    snapshot = session_snapshots.get(sessionID)
    history = session_snapshot_history.get(sessionID, [])

    # If we have snapshots, compute real diffs
    if snapshot and len(history) >= 2:
        try:
            # Determine the range based on messageID
            if messageID:
                messages = session_messages.get(sessionID, [])
                target_index = None
                for i, msg in enumerate(messages):
                    if msg["info"]["id"] == messageID:
                        target_index = i
                        break
                if target_index is not None and target_index < len(history):
                    diffs = snapshot.diff_full(history[0], history[target_index])
                else:
                    diffs = snapshot.diff_full(history[0], history[-1])
            else:
                # Default: diff from session start to current
                diffs = snapshot.diff_full(history[0], history[-1])

            return [
                FileDiff(
                    file=d.file,
                    before=d.before,
                    after=d.after,
                    additions=d.additions,
                    deletions=d.deletions,
                )
                for d in diffs
            ]
        except Exception:
            pass

    # Fallback to cached summary diffs
    session = sessions[sessionID]
    if session.summary and session.summary.diffs:
        return session.summary.diffs
    return []


@app.post("/session/{sessionID}/fork")
async def fork_session(
    sessionID: str, request: ForkRequest, directory: str | None = Query(None)
) -> Session:
    """Fork a session at a specific message."""
    if sessionID not in sessions:
        raise HTTPException(status_code=404, detail="Session not found")

    parent = sessions[sessionID]
    now = time.time()

    new_session = Session(
        id=gen_id("ses_"),
        projectID=parent.projectID,
        directory=parent.directory,
        title=f"{parent.title} (fork)",
        version=parent.version,
        time=SessionTime(created=now, updated=now),
        parentID=sessionID,
    )
    sessions[new_session.id] = new_session

    # Copy messages up to the fork point
    messages_to_copy = []
    for msg in session_messages.get(sessionID, []):
        messages_to_copy.append(msg)
        if request.messageID and msg["info"]["id"] == request.messageID:
            break
    session_messages[new_session.id] = messages_to_copy.copy()

    await broadcast_event(
        Event(type="session.created", properties={"info": new_session.model_dump()})
    )
    return new_session


@app.post("/session/{sessionID}/revert")
async def revert_session(
    sessionID: str, request: RevertRequest, directory: str | None = Query(None)
) -> Session:
    """Revert session to a specific message, restoring files to that state."""
    if sessionID not in sessions:
        raise HTTPException(status_code=404, detail="Session not found")

    snapshot = session_snapshots.get(sessionID)
    history = session_snapshot_history.get(sessionID, [])

    # Find the snapshot hash corresponding to the target message
    messages = session_messages.get(sessionID, [])
    target_index: int | None = None
    for i, msg in enumerate(messages):
        if msg["info"]["id"] == request.messageID:
            target_index = i
            break

    target_hash: str | None = None
    if target_index is not None and target_index < len(history):
        target_hash = history[target_index]

    # Restore files if we have a valid snapshot
    if snapshot and target_hash:
        try:
            snapshot.restore(target_hash)
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Failed to restore snapshot: {e}")

    session = sessions[sessionID]
    session.revert = RevertInfo(
        messageID=request.messageID,
        partID=request.partID,
        snapshot=target_hash,
    )
    session.time.updated = time.time()
    sessions[sessionID] = session

    await broadcast_event(
        Event(type="session.updated", properties={"info": session.model_dump()})
    )
    return session


@app.post("/session/{sessionID}/unrevert")
async def unrevert_session(sessionID: str, directory: str | None = Query(None)) -> Session:
    """Undo revert on a session."""
    if sessionID not in sessions:
        raise HTTPException(status_code=404, detail="Session not found")

    session = sessions[sessionID]
    session.revert = None
    session.time.updated = time.time()
    sessions[sessionID] = session

    await broadcast_event(
        Event(type="session.updated", properties={"info": session.model_dump()})
    )
    return session


# =============================================================================
# Tools Endpoints
# =============================================================================


def get_tool_info() -> list[dict]:
    """Get information about all available tools with their schemas."""
    tools = [
        {
            "id": "python",
            "description": "Execute Python code in a sandboxed subprocess",
            "parameters": {
                "code": {"type": "string", "description": "Python code to execute"},
                "timeout": {"type": "integer", "description": "Max execution time in seconds", "default": 30}
            }
        },
        {
            "id": "shell",
            "description": "Execute shell commands in a subprocess",
            "parameters": {
                "command": {"type": "string", "description": "Shell command to execute"},
                "timeout": {"type": "integer", "description": "Max execution time in seconds", "default": 30}
            }
        },
        {
            "id": "read",
            "description": "Read the contents of a file",
            "parameters": {
                "file_path": {"type": "string", "description": "Absolute path to the file to read"},
                "limit": {"type": "integer", "description": "Maximum number of lines to read", "optional": True},
                "offset": {"type": "integer", "description": "Line number to start reading from", "optional": True}
            }
        },
        {
            "id": "write",
            "description": "Write content to a file, overwriting if it exists",
            "parameters": {
                "file_path": {"type": "string", "description": "Absolute path to the file to write"},
                "content": {"type": "string", "description": "Content to write to the file"}
            }
        },
        {
            "id": "edit",
            "description": "Perform exact string replacements in files",
            "parameters": {
                "file_path": {"type": "string", "description": "Absolute path to the file to modify"},
                "old_string": {"type": "string", "description": "The text to replace"},
                "new_string": {"type": "string", "description": "The text to replace it with"},
                "replace_all": {"type": "boolean", "description": "Replace all occurrences of old_string", "default": False}
            }
        },
        {
            "id": "search",
            "description": "Search for files matching a glob pattern",
            "parameters": {
                "pattern": {"type": "string", "description": "Glob pattern to match files against (e.g., '**/*.js')"},
                "path": {"type": "string", "description": "Directory to search in", "optional": True}
            }
        },
        {
            "id": "grep",
            "description": "Search for content within files using regex patterns",
            "parameters": {
                "pattern": {"type": "string", "description": "Regular expression pattern to search for"},
                "path": {"type": "string", "description": "File or directory to search in", "optional": True},
                "glob": {"type": "string", "description": "Glob pattern to filter files (e.g., '*.js')", "optional": True},
                "type": {"type": "string", "description": "File type to search (e.g., 'js', 'py', 'rust')", "optional": True},
                "output_mode": {"type": "string", "description": "Output mode: 'content', 'files_with_matches', or 'count'", "default": "files_with_matches"},
                "case_insensitive": {"type": "boolean", "description": "Case insensitive search", "default": False}
            }
        },
        {
            "id": "ls",
            "description": "List directory contents",
            "parameters": {
                "path": {"type": "string", "description": "Directory path to list", "optional": True},
                "all": {"type": "boolean", "description": "Show hidden files", "default": False},
                "long": {"type": "boolean", "description": "Use long listing format", "default": False}
            }
        },
        {
            "id": "fetch",
            "description": "Fetch content from a URL",
            "parameters": {
                "url": {"type": "string", "description": "URL to fetch content from"},
                "method": {"type": "string", "description": "HTTP method to use", "default": "GET"},
                "headers": {"type": "object", "description": "HTTP headers to include", "optional": True},
                "body": {"type": "string", "description": "Request body for POST/PUT", "optional": True}
            }
        },
        {
            "id": "web",
            "description": "Search the web and return results",
            "parameters": {
                "query": {"type": "string", "description": "Search query"},
                "max_results": {"type": "integer", "description": "Maximum number of results to return", "default": 10}
            }
        },
        {
            "id": "todowrite",
            "description": "Create or update a structured task list",
            "parameters": {
                "todos": {
                    "type": "array",
                    "description": "List of todo items",
                    "items": {
                        "type": "object",
                        "properties": {
                            "content": {"type": "string", "description": "Task description"},
                            "status": {"type": "string", "description": "Task status: 'pending', 'in_progress', or 'completed'"},
                            "activeForm": {"type": "string", "description": "Present continuous form of the task"}
                        }
                    }
                }
            }
        },
        {
            "id": "todoread",
            "description": "Read the current task list",
            "parameters": {}
        }
    ]
    return tools


@app.get("/tools")
async def list_tools() -> list[dict]:
    """List all available tools with their schemas."""
    return get_tool_info()


@app.get("/tools/{toolId}")
async def get_tool(toolId: str) -> dict:
    """Get a specific tool's schema."""
    tools = get_tool_info()
    for tool in tools:
        if tool["id"] == toolId:
            return tool
    raise HTTPException(status_code=404, detail="Tool not found")


# =============================================================================
# Health Endpoint
# =============================================================================


@app.get("/health")
async def health():
    """Health check endpoint."""
    return {"status": "ok", "agent_configured": agent is not None}


# =============================================================================
# Main
# =============================================================================

if __name__ == "__main__":
    import uvicorn

    port = int(os.environ.get("PORT", 8000))
    uvicorn.run(app, host="0.0.0.0", port=port)
