"""
Agent runner for executing Claude-powered agents with tool use.

Supports streaming responses and tool execution in sandboxed environments.
"""

import json
import logging
import uuid
from typing import List, Dict, Any, Optional, Callable

from anthropic import Anthropic

from .streaming import StreamingClient
from .tools import get_tool_definitions, execute_tool

logger = logging.getLogger(__name__)


class AgentRunner:
    """Runs a Claude-powered agent with tool support."""

    def __init__(
        self,
        api_key: str,
        model: str,
        system_prompt: str,
        tools: List[str],
        max_turns: int,
        streaming: StreamingClient,
    ):
        self.client = Anthropic(api_key=api_key)
        self.model = model
        self.system_prompt = system_prompt
        self.enabled_tools = tools
        self.max_turns = max_turns
        self.streaming = streaming

        # Get tool definitions for enabled tools
        self.tool_definitions = get_tool_definitions(tools)

    def run(
        self,
        messages: List[Dict[str, Any]],
        abort_check: Optional[Callable[[], bool]] = None,
    ) -> bool:
        """
        Run the agent loop until completion or max turns.

        Args:
            messages: Initial conversation messages
            abort_check: Callable that returns True if execution should abort

        Returns:
            True if completed successfully, False otherwise
        """
        current_messages = list(messages)
        turns = 0

        while turns < self.max_turns:
            # Check for abort
            if abort_check and abort_check():
                logger.info("Agent execution aborted")
                return False

            # Generate message ID for this turn
            message_id = f"msg_{uuid.uuid4().hex[:12]}"
            self.streaming.set_message_id(message_id)

            try:
                # Call Claude with streaming
                with self.client.messages.stream(
                    model=self.model,
                    max_tokens=4096,
                    system=self.system_prompt,
                    messages=current_messages,
                    tools=self.tool_definitions if self.tool_definitions else None,
                ) as stream:
                    response = self._process_stream(stream, message_id, abort_check)

                if response is None:
                    # Aborted during stream
                    return False

            except Exception as e:
                logger.exception("Error calling Claude API")
                self.streaming.send_error(f"Claude API error: {str(e)}")
                return False

            # Check stop reason
            stop_reason = response.stop_reason

            if stop_reason == "end_turn":
                # Agent completed normally
                logger.info("Agent completed")
                return True

            elif stop_reason == "tool_use":
                # Process tool calls
                tool_results = self._process_tool_calls(
                    response.content,
                    abort_check,
                )

                if tool_results is None:
                    # Aborted during tool execution
                    return False

                # Add assistant message and tool results
                current_messages.append({
                    "role": "assistant",
                    "content": response.content,
                })
                current_messages.append({
                    "role": "user",
                    "content": tool_results,
                })

            else:
                logger.warning(f"Unexpected stop reason: {stop_reason}")
                return False

            turns += 1

        logger.warning("Max turns reached")
        self.streaming.send_error("Max turns reached")
        return False

    def _process_stream(
        self,
        stream,
        message_id: str,
        abort_check: Optional[Callable[[], bool]],
    ) -> Optional[Any]:
        """
        Process a streaming response, sending tokens as they arrive.

        Returns the final message or None if aborted.
        """
        current_tool_id = None
        current_tool_name = None
        tool_input_json = ""

        for event in stream:
            # Check for abort
            if abort_check and abort_check():
                return None

            if event.type == "content_block_start":
                if event.content_block.type == "text":
                    pass  # Text block starting
                elif event.content_block.type == "tool_use":
                    current_tool_id = event.content_block.id
                    current_tool_name = event.content_block.name
                    tool_input_json = ""
                    self.streaming.send_tool_start(
                        current_tool_id,
                        current_tool_name,
                    )

            elif event.type == "content_block_delta":
                if event.delta.type == "text_delta":
                    # Stream text token
                    self.streaming.send_token(event.delta.text)
                elif event.delta.type == "input_json_delta":
                    # Accumulate tool input JSON
                    tool_input_json += event.delta.partial_json

            elif event.type == "content_block_stop":
                if current_tool_id:
                    current_tool_id = None
                    current_tool_name = None
                    tool_input_json = ""

        return stream.get_final_message()

    def _process_tool_calls(
        self,
        content: List[Any],
        abort_check: Optional[Callable[[], bool]],
    ) -> Optional[List[Dict[str, Any]]]:
        """
        Execute tool calls and return results.

        Returns tool results or None if aborted.
        """
        results = []

        for block in content:
            if block.type != "tool_use":
                continue

            # Check for abort
            if abort_check and abort_check():
                return None

            tool_id = block.id
            tool_name = block.name
            tool_input = block.input

            logger.info(f"Executing tool: {tool_name}")
            self.streaming.send_tool_start(tool_id, tool_name, tool_input)

            try:
                output = execute_tool(tool_name, tool_input)
                self.streaming.send_tool_end(tool_id, "success", output)

                results.append({
                    "type": "tool_result",
                    "tool_use_id": tool_id,
                    "content": output,
                })

            except Exception as e:
                error_msg = f"Tool execution error: {str(e)}"
                logger.exception(error_msg)
                self.streaming.send_tool_end(tool_id, "error", error_msg)

                results.append({
                    "type": "tool_result",
                    "tool_use_id": tool_id,
                    "content": error_msg,
                    "is_error": True,
                })

        return results
