"""
Wrapper that adapts Pydantic AI streaming to the server.py expected interface.

Uses run_stream_events() to get proper tool call events during streaming.
Supports MCP-based agents with proper lifecycle management.
"""
import logging
from contextlib import asynccontextmanager
from dataclasses import dataclass, field
from typing import Any, AsyncIterator

from pydantic_ai import Agent, AgentRunResultEvent
from pydantic_ai.messages import (
    FunctionToolCallEvent,
    FunctionToolResultEvent,
    ModelMessage,
    PartDeltaEvent,
    PartStartEvent,
    TextPartDelta,
    ToolCallPartDelta,
)

from config import DEFAULT_MODEL
from .agent import create_agent_with_mcp, create_agent, get_anthropic_model_settings
from .tools.filesystem import set_current_session_id, mark_file_read, check_file_writable

logger = logging.getLogger(__name__)


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
    _message_history: list[ModelMessage] = field(default_factory=list)

    async def stream_async(
        self,
        user_text: str,
        session_id: str | None = None,
        enable_thinking: bool = True,
        model_id: str | None = None,
        reasoning_effort: str | None = None,
    ) -> AsyncIterator[StreamEvent]:
        """
        Stream agent response, yielding events compatible with server.py.

        Uses run_stream_events() to get proper tool call events including
        FunctionToolCallEvent and FunctionToolResultEvent.

        Args:
            user_text: The user's input message
            session_id: Optional session ID for context
            enable_thinking: Enable extended thinking for better reasoning (default True)
            model_id: Optional model ID to override the agent's default model
            reasoning_effort: Optional reasoning effort level (minimal, low, medium, high)

        Yields:
            StreamEvent objects with text deltas, tool calls, and tool results
        """
        final_result = None
        tool_call_count = 0

        logger.debug("Starting agent stream for session %s with model=%s, reasoning_effort=%s",
                    session_id, model_id, reasoning_effort)

        # Set session ID for file safety tracking
        if session_id:
            set_current_session_id(session_id)

        # Build model settings
        model_settings = get_anthropic_model_settings(enable_thinking=enable_thinking)

        # Add reasoning effort if specified
        if reasoning_effort:
            # Map reasoning_effort to thinking budget
            # Max output tokens for Claude models
            MAX_OUTPUT_TOKENS = 64000
            reasoning_budgets = {
                "minimal": 10000,
                "low": 30000,
                "medium": 50000,  # Leave room for output within 64k limit
                "high": 54000,    # Max thinking budget (64k - 10k buffer)
            }
            budget = reasoning_budgets.get(reasoning_effort, 50000)
            model_settings['anthropic_thinking'] = {
                'type': 'enabled',
                'budget_tokens': budget,
            }
            # Ensure max_tokens is always greater than thinking budget, but capped at model limit
            model_settings['max_tokens'] = min(max(budget + 10000, 64000), MAX_OUTPUT_TOKENS)

        # Prepare run_stream_events kwargs
        run_kwargs = {
            'message_history': self._message_history,
            'model_settings': model_settings,
        }

        # Override model if specified
        if model_id:
            run_kwargs['model'] = f'anthropic:{model_id}'

        async for event in self.agent.run_stream_events(user_text, **run_kwargs):
            if isinstance(event, PartStartEvent):
                # A new part is starting - could be text or tool call
                pass

            elif isinstance(event, PartDeltaEvent):
                # Streaming delta for a part
                if isinstance(event.delta, TextPartDelta):
                    # Text content streaming
                    if event.delta.content_delta:
                        yield StreamEvent(
                            data=event.delta.content_delta,
                            event_type="text"
                        )
                elif isinstance(event.delta, ToolCallPartDelta):
                    # Tool call arguments streaming (optional to handle)
                    pass

            elif isinstance(event, FunctionToolCallEvent):
                # Tool is being called
                tool_name = event.part.tool_name
                # Args can be dict or object, convert to dict
                try:
                    if hasattr(event.part.args, 'model_dump'):
                        args = event.part.args.model_dump()
                    elif isinstance(event.part.args, dict):
                        args = event.part.args
                    else:
                        args = dict(event.part.args) if event.part.args else {}
                except Exception:
                    args = {}

                # Enforce read-before-write for write_file tool
                if tool_name == "write_file" and session_id:
                    path = args.get("path")
                    if path:
                        try:
                            check_file_writable(path)
                        except ValueError as e:
                            logger.warning("File safety check failed for %s: %s", path, e)

                tool_call_count += 1
                logger.debug("Tool call: %s", tool_name)

                yield StreamEvent(
                    event_type="tool_call",
                    tool_name=tool_name,
                    tool_input=args,
                    tool_id=event.part.tool_call_id,
                )

            elif isinstance(event, FunctionToolResultEvent):
                # Tool has returned a result
                # result is ToolReturnPart with tool_call_id and content
                try:
                    content = event.result.content
                    if isinstance(content, str):
                        output = content
                    elif hasattr(content, 'model_dump_json'):
                        output = content.model_dump_json()
                    else:
                        output = str(content)
                except Exception as e:
                    output = f"Error formatting result: {e}"

                yield StreamEvent(
                    event_type="tool_result",
                    tool_id=event.result.tool_call_id,
                    tool_output=output,
                    tool_name=event.result.tool_name,
                )

            elif isinstance(event, AgentRunResultEvent):
                # Final result - save for history update
                final_result = event

        # Update message history after completion
        if final_result:
            self._message_history = list(final_result.result.all_messages())

        logger.debug("Agent stream complete: %d tool calls", tool_call_count)

    def reset_history(self) -> None:
        """Clear conversation history for new session."""
        self._message_history = []

    def get_history(self) -> list[ModelMessage]:
        """Get the current message history."""
        return self._message_history.copy()


@asynccontextmanager
async def create_mcp_wrapper(
    model_id: str = DEFAULT_MODEL,
    agent_name: str = "build",
    working_dir: str | None = None,
) -> AsyncIterator[AgentWrapper]:
    """
    Create an AgentWrapper with MCP tools enabled.

    This is an async context manager that properly manages MCP server lifecycles.

    Args:
        model_id: Anthropic model identifier
        agent_name: Name of the agent configuration to use
        working_dir: Working directory for filesystem operations

    Yields:
        AgentWrapper with MCP-enabled agent

    Example:
        async with create_mcp_wrapper() as wrapper:
            async for event in wrapper.stream_async("Hello"):
                print(event)
    """
    async with create_agent_with_mcp(
        model_id=model_id,
        agent_name=agent_name,
        working_dir=working_dir,
    ) as agent:
        yield AgentWrapper(agent=agent)


def create_simple_wrapper(
    model_id: str = DEFAULT_MODEL,
    agent_name: str = "build",
) -> AgentWrapper:
    """
    Create an AgentWrapper WITHOUT MCP tools (for backwards compatibility).

    Note: This creates a wrapper without MCP tools. For full functionality,
    use create_mcp_wrapper() as an async context manager instead.

    Args:
        model_id: Anthropic model identifier
        agent_name: Name of the agent configuration to use

    Returns:
        AgentWrapper with basic agent (no MCP tools)
    """
    agent = create_agent(model_id=model_id, agent_name=agent_name)
    return AgentWrapper(agent=agent)
