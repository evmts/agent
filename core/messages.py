"""
Message operations.

Provides functions for managing messages including listing, retrieving,
and streaming responses from the agent.
"""

import os
import time
from typing import Any, AsyncGenerator, Protocol

from .events import Event, EventBus
from .exceptions import NotFoundError
from .models import FileDiff, SessionSummary, gen_id
from .snapshots import (
    append_snapshot_history,
    compute_diff,
    get_changed_files,
    track_snapshot,
)
from .state import session_messages, sessions


class Agent(Protocol):
    """Protocol for agent implementations."""

    def stream_async(self, prompt: str) -> AsyncGenerator[Any, None]:
        """Stream responses for a prompt."""
        ...


def list_messages(session_id: str, limit: int | None = None) -> list[dict[str, Any]]:
    """
    List messages in a session.

    Args:
        session_id: The session ID
        limit: Maximum number of messages to return

    Returns:
        List of messages

    Raises:
        NotFoundError: If the session is not found
    """
    if session_id not in sessions:
        raise NotFoundError("Session", session_id)

    messages = session_messages.get(session_id, [])
    if limit:
        messages = messages[-limit:]
    return messages


def get_message(session_id: str, message_id: str) -> dict[str, Any]:
    """
    Get a specific message.

    Args:
        session_id: The session ID
        message_id: The message ID

    Returns:
        The message

    Raises:
        NotFoundError: If the session or message is not found
    """
    if session_id not in sessions:
        raise NotFoundError("Session", session_id)

    for msg in session_messages.get(session_id, []):
        if msg["info"]["id"] == message_id:
            return msg

    raise NotFoundError("Message", message_id)


async def send_message(
    session_id: str,
    parts: list[dict[str, Any]],
    agent: Agent | None,
    event_bus: EventBus,
    message_id: str | None = None,
    agent_name: str = "default",
    model_id: str = "default",
    provider_id: str = "default",
) -> AsyncGenerator[Event, None]:
    """
    Send a message and stream the response.

    This is an async generator that yields events as the agent processes the message.

    Args:
        session_id: The session ID
        parts: List of message parts (text, file, etc.)
        agent: The agent to use for generating responses
        event_bus: EventBus for publishing events
        message_id: Optional message ID (generated if not provided)
        agent_name: Agent name for metadata
        model_id: Model ID for metadata
        provider_id: Provider ID for metadata

    Yields:
        Events as the message is processed

    Raises:
        NotFoundError: If the session is not found
    """
    if session_id not in sessions:
        raise NotFoundError("Session", session_id)

    now = time.time()

    # Create user message
    user_msg_id = message_id or gen_id("msg_")
    user_msg: dict[str, Any] = {
        "info": {
            "id": user_msg_id,
            "sessionID": session_id,
            "role": "user",
            "time": {"created": now},
            "agent": agent_name,
            "model": {"providerID": provider_id, "modelID": model_id},
        },
        "parts": [],
    }

    # Add text parts from request
    for part in parts:
        if part.get("type") == "text":
            part_id = gen_id("prt_")
            user_msg["parts"].append(
                {
                    "id": part_id,
                    "sessionID": session_id,
                    "messageID": user_msg_id,
                    "type": "text",
                    "text": part.get("text", ""),
                }
            )

    session_messages[session_id].append(user_msg)
    await event_bus.publish(
        Event(type="message.updated", properties={"info": user_msg["info"]})
    )

    # Create assistant message
    asst_msg_id = gen_id("msg_")
    asst_msg: dict[str, Any] = {
        "info": {
            "id": asst_msg_id,
            "sessionID": session_id,
            "role": "assistant",
            "time": {"created": time.time()},
            "parentID": user_msg_id,
            "modelID": model_id,
            "providerID": provider_id,
            "mode": "normal",
            "path": {"cwd": os.getcwd(), "root": os.getcwd()},
            "cost": 0.0,
            "tokens": {
                "input": 0,
                "output": 0,
                "reasoning": 0,
                "cache": {"read": 0, "write": 0},
            },
        },
        "parts": [],
    }

    # Yield assistant message creation event
    yield Event(type="message.updated", properties={"info": asst_msg["info"]})

    # Capture step start snapshot
    step_start_hash = track_snapshot(session_id)

    if agent is None:
        # No agent configured - return error part
        error_part_id = gen_id("prt_")
        error_part = {
            "id": error_part_id,
            "sessionID": session_id,
            "messageID": asst_msg_id,
            "type": "text",
            "text": "Agent not configured. Please set up an agent using set_agent().",
        }
        asst_msg["parts"].append(error_part)
        yield Event(type="part.updated", properties=error_part)
    else:
        # Stream from agent
        text_part_id = gen_id("prt_")
        text_content = ""
        reasoning_part_id: str | None = None
        reasoning_content = ""
        tool_parts: dict[str, dict[str, Any]] = {}  # tool_id -> tool_part

        try:
            # Extract text from user message
            user_text = ""
            for part in parts:
                if part.get("type") == "text":
                    user_text += part.get("text", "")

            async for event in agent.stream_async(user_text):
                event_type = getattr(event, "event_type", "text")

                if event_type == "text" and hasattr(event, "data") and event.data:
                    # Text content
                    text_content += event.data
                    text_part = {
                        "id": text_part_id,
                        "sessionID": session_id,
                        "messageID": asst_msg_id,
                        "type": "text",
                        "text": text_content,
                    }
                    yield Event(type="part.updated", properties=text_part)

                elif (
                    event_type == "reasoning"
                    and hasattr(event, "reasoning")
                    and event.reasoning
                ):
                    # Reasoning/thinking content
                    if reasoning_part_id is None:
                        reasoning_part_id = gen_id("prt_")
                    reasoning_content += event.reasoning
                    reasoning_part = {
                        "id": reasoning_part_id,
                        "sessionID": session_id,
                        "messageID": asst_msg_id,
                        "type": "reasoning",
                        "text": reasoning_content,
                        "time": {"start": time.time()},
                    }
                    yield Event(type="part.updated", properties=reasoning_part)

                elif event_type == "tool_call":
                    # Tool invocation started
                    tool_part_id = gen_id("prt_")
                    tool_part = {
                        "id": tool_part_id,
                        "sessionID": session_id,
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
                    yield Event(type="part.updated", properties=tool_part)

                elif event_type == "tool_result":
                    # Tool execution completed
                    if event.tool_id and event.tool_id in tool_parts:
                        tool_part = tool_parts[event.tool_id]
                        tool_part["state"]["status"] = "completed"
                        tool_part["state"]["output"] = event.tool_output
                        tool_part["state"]["time"]["end"] = time.time()
                        yield Event(type="part.updated", properties=tool_part)

            # Final text part
            if text_content:
                asst_msg["parts"].append(
                    {
                        "id": text_part_id,
                        "sessionID": session_id,
                        "messageID": asst_msg_id,
                        "type": "text",
                        "text": text_content,
                    }
                )

            # Final reasoning part
            if reasoning_content and reasoning_part_id:
                asst_msg["parts"].append(
                    {
                        "id": reasoning_part_id,
                        "sessionID": session_id,
                        "messageID": asst_msg_id,
                        "type": "reasoning",
                        "text": reasoning_content,
                    }
                )

            # Final tool parts
            for tool_part in tool_parts.values():
                asst_msg["parts"].append(tool_part)

        except Exception as e:
            error_part_id = gen_id("prt_")
            error_part = {
                "id": error_part_id,
                "sessionID": session_id,
                "messageID": asst_msg_id,
                "type": "text",
                "text": f"Error: {str(e)}",
            }
            asst_msg["parts"].append(error_part)
            yield Event(type="part.updated", properties=error_part)

    # Complete assistant message
    asst_msg["info"]["time"]["completed"] = time.time()
    session_messages[session_id].append(asst_msg)

    # Capture step finish snapshot and compute diff
    if step_start_hash:
        step_finish_hash = track_snapshot(session_id)
        if step_finish_hash:
            append_snapshot_history(session_id, step_finish_hash)

            # Compute diff and update session summary
            changed_files = get_changed_files(
                session_id, step_start_hash, step_finish_hash
            )
            if changed_files:
                diffs = compute_diff(session_id, step_start_hash, step_finish_hash)
                sessions[session_id].summary = SessionSummary(
                    additions=sum(d.additions for d in diffs),
                    deletions=sum(d.deletions for d in diffs),
                    files=len(diffs),
                    diffs=diffs,
                )

    # Update session timestamp
    sessions[session_id].time.updated = time.time()

    yield Event(type="message.updated", properties={"info": asst_msg["info"]})
