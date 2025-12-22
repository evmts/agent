"""
Streaming client for sending events back to the Zig API server.

Uses HTTP POST with chunked transfer encoding for real-time streaming.
"""

import json
import logging
from typing import Optional, Any

import httpx

logger = logging.getLogger(__name__)


class StreamingClient:
    """Client for streaming events back to the Zig API server."""

    def __init__(self, callback_url: str, task_id: str):
        self.callback_url = callback_url
        self.task_id = task_id
        self.client = httpx.Client(timeout=30.0)
        self.token_index = 0
        self.message_id: Optional[str] = None

    def close(self):
        """Close the HTTP client."""
        self.client.close()

    def _send_event(self, event: dict) -> bool:
        """Send an event to the callback URL."""
        try:
            response = self.client.post(
                self.callback_url,
                json=event,
                headers={"Content-Type": "application/json"},
            )
            return response.status_code == 200
        except Exception as e:
            logger.error(f"Failed to send event: {e}")
            return False

    def set_message_id(self, message_id: str):
        """Set the current message ID for token events."""
        self.message_id = message_id
        self.token_index = 0

    def send_token(self, text: str) -> bool:
        """Send a token event (text delta)."""
        event = {
            "type": "token",
            "task_id": self.task_id,
            "message_id": self.message_id,
            "text": text,
            "token_index": self.token_index,
        }
        self.token_index += 1
        return self._send_event(event)

    def send_tool_start(
        self,
        tool_id: str,
        tool_name: str,
        args: Optional[dict] = None,
    ) -> bool:
        """Send a tool start event."""
        event = {
            "type": "tool_start",
            "task_id": self.task_id,
            "message_id": self.message_id,
            "tool_id": tool_id,
            "tool_name": tool_name,
        }
        if args:
            event["args"] = args
        return self._send_event(event)

    def send_tool_end(
        self,
        tool_id: str,
        state: str,  # "success" or "error"
        output: Optional[str] = None,
    ) -> bool:
        """Send a tool end event."""
        event = {
            "type": "tool_end",
            "task_id": self.task_id,
            "tool_id": tool_id,
            "tool_state": state,
        }
        if output:
            event["output"] = output
        return self._send_event(event)

    def send_done(self) -> bool:
        """Send a done event."""
        return self._send_event({
            "type": "done",
            "task_id": self.task_id,
        })

    def send_error(self, message: str) -> bool:
        """Send an error event."""
        return self._send_event({
            "type": "error",
            "task_id": self.task_id,
            "message": message,
        })

    def send_step_start(self, step_name: str, step_index: int) -> bool:
        """Send a workflow step start event."""
        return self._send_event({
            "type": "step_start",
            "task_id": self.task_id,
            "step_name": step_name,
            "step_index": step_index,
        })

    def send_step_end(
        self,
        step_name: str,
        step_index: int,
        state: str,
        output: Optional[str] = None,
    ) -> bool:
        """Send a workflow step end event."""
        event = {
            "type": "step_end",
            "task_id": self.task_id,
            "step_name": step_name,
            "step_index": step_index,
            "step_state": state,
        }
        if output:
            event["output"] = output
        return self._send_event(event)

    def send_log(self, level: str, message: str) -> bool:
        """Send a log event."""
        return self._send_event({
            "type": "log",
            "task_id": self.task_id,
            "level": level,
            "message": message,
        })
