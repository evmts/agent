"""
Conversation compaction logic.

Provides functions for compacting conversation history by summarizing
older messages to reduce token count while preserving key information.
"""

import json
import logging
import time
from typing import Any

from anthropic import Anthropic

from config.defaults import (
    DEFAULT_AUTO_COMPACT_TOKEN_LIMIT,
    DEFAULT_COMPACTION_MODEL,
    DEFAULT_PRESERVE_MESSAGES,
)

from .events import Event, EventBus
from .exceptions import CoreError, NotFoundError
from .models import CompactionInfo, CompactionResult, gen_id
from .state import session_messages, sessions

logger = logging.getLogger(__name__)


# Compaction prompt for summarization
COMPACTION_PROMPT = """You are summarizing a conversation between a user and an AI coding assistant.
Create a concise summary that preserves:

1. KEY DECISIONS: Important choices made during the conversation
2. FILE CONTEXT: Files that were read, edited, or created (with absolute paths)
3. CODE CHANGES: Summary of code modifications made
4. ERRORS & SOLUTIONS: Any errors encountered and how they were resolved
5. CURRENT STATE: What the user is currently working on

Format as structured bullet points under these headings. Be concise but complete.
Focus on information that would be useful for continuing the conversation.

CONVERSATION TO SUMMARIZE:
{messages}

Provide your summary now:"""


def estimate_tokens(text: str) -> int:
    """
    Estimate token count for text.

    Uses a simple heuristic of ~4 characters per token.
    This is approximate but sufficient for compaction triggering.

    Args:
        text: Text to estimate tokens for

    Returns:
        Estimated token count
    """
    return len(text) // 4


def count_message_tokens(messages: list[dict[str, Any]]) -> int:
    """
    Count tokens in a list of messages.

    Args:
        messages: List of message dictionaries

    Returns:
        Estimated total token count
    """
    total = 0
    for msg in messages:
        # Count info metadata
        total += estimate_tokens(json.dumps(msg.get("info", {})))

        # Count parts
        for part in msg.get("parts", []):
            if part.get("type") == "text":
                total += estimate_tokens(part.get("text", ""))
            elif part.get("type") == "tool":
                # Count tool name and state
                total += estimate_tokens(part.get("tool", ""))
                state = part.get("state", {})
                total += estimate_tokens(state.get("output", ""))
            # Other part types typically don't contribute much to token count

    return total


def format_messages_for_summary(messages: list[dict[str, Any]]) -> str:
    """
    Format messages as text for summarization.

    Args:
        messages: List of message dictionaries

    Returns:
        Formatted text representation
    """
    lines = []
    for msg in messages:
        role = msg.get("info", {}).get("role", "unknown")
        lines.append(f"\n{role.upper()}:")

        for part in msg.get("parts", []):
            if part.get("type") == "text":
                text = part.get("text", "")
                lines.append(f"  {text}")
            elif part.get("type") == "tool":
                tool = part.get("tool", "unknown")
                state = part.get("state", {})
                output = state.get("output", "")
                if len(output) > 200:
                    output = output[:200] + "..."
                lines.append(f"  [Tool: {tool}]")
                if output:
                    lines.append(f"  Output: {output}")

    return "\n".join(lines)


async def generate_summary(
    messages: list[dict[str, Any]],
    model_id: str = DEFAULT_COMPACTION_MODEL,
) -> str:
    """
    Generate a summary of messages using Claude.

    Args:
        messages: Messages to summarize
        model_id: Model to use for summarization

    Returns:
        Generated summary text

    Raises:
        CoreError: If summarization fails
    """
    try:
        client = Anthropic()
        formatted = format_messages_for_summary(messages)
        prompt = COMPACTION_PROMPT.format(messages=formatted)

        response = client.messages.create(
            model=model_id,
            max_tokens=4096,
            messages=[{"role": "user", "content": prompt}],
        )

        # Extract text from response
        summary = ""
        for block in response.content:
            if hasattr(block, "text"):
                summary += block.text

        if not summary:
            raise CoreError("No summary generated")

        return summary.strip()

    except Exception as e:
        logger.error("Failed to generate summary: %s", str(e))
        raise CoreError(f"Summarization failed: {str(e)}") from e


async def compact_conversation(
    session_id: str,
    event_bus: EventBus,
    preserve_count: int = DEFAULT_PRESERVE_MESSAGES,
    model_id: str = DEFAULT_COMPACTION_MODEL,
) -> CompactionResult:
    """
    Compact conversation history by summarizing older messages.

    Args:
        session_id: Session to compact
        event_bus: EventBus for publishing events
        preserve_count: Number of recent messages to keep intact
        model_id: Model to use for summarization

    Returns:
        CompactionResult with summary and token counts

    Raises:
        NotFoundError: If session not found
        CoreError: If compaction fails
    """
    if session_id not in sessions:
        raise NotFoundError("Session", session_id)

    messages = session_messages.get(session_id, [])

    # Check if we have enough messages to compact
    if len(messages) <= preserve_count + 1:
        return CompactionResult(
            compacted=False,
            reason=f"Not enough messages to compact (have {len(messages)}, need >{preserve_count + 1})",
        )

    # Split messages
    to_summarize = messages[:-preserve_count]
    to_preserve = messages[-preserve_count:]

    # Calculate tokens before
    tokens_before = count_message_tokens(messages)

    logger.info(
        "Compacting session %s: %d messages -> summary + %d preserved",
        session_id,
        len(to_summarize),
        len(to_preserve),
    )

    # Generate summary
    summary = await generate_summary(to_summarize, model_id)

    # Create summary message
    now = time.time()
    summary_msg: dict[str, Any] = {
        "info": {
            "id": gen_id("msg_"),
            "sessionID": session_id,
            "role": "system",
            "time": {"created": now},
        },
        "parts": [
            {
                "id": gen_id("prt_"),
                "sessionID": session_id,
                "messageID": gen_id("msg_"),
                "type": "text",
                "text": f"[Conversation Summary]\n{summary}\n\n[End Summary - {len(to_summarize)} messages compacted]",
            }
        ],
    }

    # Replace old messages with summary
    compacted_messages = [summary_msg] + to_preserve
    session_messages[session_id] = compacted_messages

    # Calculate tokens after
    tokens_after = count_message_tokens(compacted_messages)
    tokens_saved = tokens_before - tokens_after

    # Update session compaction info
    session = sessions[session_id]
    if session.compaction is None:
        session.compaction = CompactionInfo()

    session.compaction.last_compacted = now
    session.compaction.total_compactions += 1
    session.compaction.messages_compacted += len(to_summarize)
    session.compaction.tokens_saved += tokens_saved
    session.token_count = tokens_after
    session.time.updated = now

    logger.info(
        "Compaction complete: %d -> %d tokens (saved %d)",
        tokens_before,
        tokens_after,
        tokens_saved,
    )

    # Emit compaction event
    await event_bus.publish(
        Event(
            type="session.compacted",
            properties={
                "session_id": session_id,
                "messages_removed": len(to_summarize),
                "tokens_before": tokens_before,
                "tokens_after": tokens_after,
                "tokens_saved": tokens_saved,
            },
        )
    )

    return CompactionResult(
        compacted=True,
        messages_removed=len(to_summarize),
        tokens_before=tokens_before,
        tokens_after=tokens_after,
        summary=summary,
    )


def should_auto_compact(
    session_id: str,
    threshold: int = DEFAULT_AUTO_COMPACT_TOKEN_LIMIT,
) -> bool:
    """
    Check if a session should be auto-compacted.

    Args:
        session_id: Session to check
        threshold: Token threshold for auto-compaction

    Returns:
        True if session should be compacted

    Raises:
        NotFoundError: If session not found
    """
    if session_id not in sessions:
        raise NotFoundError("Session", session_id)

    messages = session_messages.get(session_id, [])
    if len(messages) <= DEFAULT_PRESERVE_MESSAGES + 1:
        return False

    current_tokens = count_message_tokens(messages)

    # Update session token count
    session = sessions[session_id]
    session.token_count = current_tokens

    return current_tokens > threshold
