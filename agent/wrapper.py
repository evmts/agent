"""
Wrapper that adapts Pydantic AI streaming to the server.py expected interface.
"""
from dataclasses import dataclass, field
from typing import Any, AsyncIterator

from pydantic_ai import Agent
from pydantic_ai.messages import (
    ModelRequest,
    ModelResponse,
    TextPart,
    ToolCallPart,
    ToolReturnPart,
)


@dataclass
class StreamEvent:
    """Event emitted during streaming, compatible with server.py expectations."""

    data: str | None = None
    event_type: str = "text"
    tool_name: str | None = None
    tool_input: dict[str, Any] | None = None
    tool_output: str | None = None
    tool_id: str | None = None
    reasoning: str | None = None


@dataclass
class AgentWrapper:
    """
    Wraps a Pydantic AI Agent to provide a stream_async interface
    compatible with server.py.
    """

    agent: Agent
    _message_history: list = field(default_factory=list)

    async def stream_async(
        self,
        user_text: str,
        session_id: str | None = None,
    ) -> AsyncIterator[StreamEvent]:
        """
        Stream agent response, yielding events compatible with server.py.

        The server expects events with a 'data' attribute containing text chunks.
        We also yield tool events for richer UI updates.

        Args:
            user_text: The user's input message
            session_id: Optional session ID for context

        Yields:
            StreamEvent objects with text deltas and tool events
        """
        async with self.agent.run_stream(
            user_text, message_history=self._message_history
        ) as result:
            # Track tool calls for proper event emission
            pending_tool_calls: dict[str, str] = {}  # tool_call_id -> tool_name

            async for text in result.stream_text(delta=True):
                yield StreamEvent(data=text, event_type="text")

            # After streaming completes, update message history
            self._message_history = result.all_messages()

    async def stream_async_with_tools(
        self,
        user_text: str,
        session_id: str | None = None,
    ) -> AsyncIterator[StreamEvent]:
        """
        Stream agent response with full tool event handling.

        This version provides more detailed events including tool calls and results.
        Use this when you need to display tool execution in the UI.

        Args:
            user_text: The user's input message
            session_id: Optional session ID for context

        Yields:
            StreamEvent objects with text, tool calls, and tool results
        """
        async with self.agent.run_stream(
            user_text, message_history=self._message_history
        ) as result:
            current_text = ""

            async for message in result.stream():
                # Handle different message/part types
                if hasattr(message, "content"):
                    # This is the accumulated response
                    new_text = ""
                    for part in message.content:
                        if isinstance(part, str):
                            new_text = part
                        elif hasattr(part, "content"):
                            new_text = part.content

                    if new_text and new_text != current_text:
                        # Emit the delta
                        delta = new_text[len(current_text) :]
                        if delta:
                            yield StreamEvent(data=delta, event_type="text")
                            current_text = new_text

            # Update message history after completion
            self._message_history = result.all_messages()

    def reset_history(self) -> None:
        """Clear conversation history for new session."""
        self._message_history = []

    def get_history(self) -> list:
        """Get the current message history."""
        return self._message_history.copy()
