"""
Streaming client for sending events back to the Zig API server.

Uses HTTP POST with chunked transfer encoding for real-time streaming.
"""

import json
import random
import time
from typing import Optional, Any

import httpx

from .logger import get_logger

logger = get_logger(__name__)

# Events that are critical and require more retries
CRITICAL_EVENTS = {'done', 'error', 'tool_end'}


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

    def _should_retry(self, error: Exception, status_code: Optional[int] = None) -> bool:
        """Determine if a request should be retried based on the error or status code."""
        # Retry on 5xx server errors
        if status_code is not None and 500 <= status_code < 600:
            return True

        # Don't retry on 4xx client errors
        if status_code is not None and 400 <= status_code < 500:
            return False

        # Retry on network/timeout errors
        if isinstance(error, (httpx.TimeoutException, httpx.NetworkError, httpx.ConnectError)):
            return True

        # Don't retry on other errors
        return False

    def _send_event_with_retry(self, event: dict) -> bool:
        """
        Send an event with exponential backoff retry logic.

        Critical events (done, error, tool_end) get 10 retries.
        Normal events get 5 retries.
        """
        event_type = event.get("type", "unknown")
        is_critical = event_type in CRITICAL_EVENTS
        max_retries = 10 if is_critical else 5
        base_delay = 0.5  # seconds
        max_delay = 30.0  # seconds

        for attempt in range(max_retries + 1):
            try:
                response = self.client.post(
                    self.callback_url,
                    json=event,
                    headers={"Content-Type": "application/json"},
                )

                if response.status_code == 200:
                    if attempt > 0:
                        logger.info(
                            f"Event {event_type} succeeded on attempt {attempt + 1}/{max_retries + 1}"
                        )
                    return True

                # Check if we should retry
                if not self._should_retry(None, response.status_code):
                    logger.error(
                        f"Event {event_type} failed with status {response.status_code} (non-retryable)"
                    )
                    return False

                # Log retry for 5xx errors
                if attempt < max_retries:
                    logger.warning(
                        f"Event {event_type} failed with status {response.status_code}, "
                        f"attempt {attempt + 1}/{max_retries + 1}, retrying..."
                    )
                else:
                    logger.error(
                        f"Event {event_type} failed with status {response.status_code} "
                        f"after {max_retries + 1} attempts"
                    )
                    return False

            except Exception as e:
                # Check if we should retry this exception
                if not self._should_retry(e):
                    logger.error(f"Event {event_type} failed with non-retryable error: {e}")
                    return False

                # Log retry for retryable errors
                if attempt < max_retries:
                    logger.warning(
                        f"Event {event_type} failed with error: {e}, "
                        f"attempt {attempt + 1}/{max_retries + 1}, retrying..."
                    )
                else:
                    logger.error(
                        f"Event {event_type} failed after {max_retries + 1} attempts: {e}"
                    )
                    return False

            # Calculate exponential backoff with jitter
            if attempt < max_retries:
                delay = min(base_delay * (2 ** attempt), max_delay)
                # Add jitter: random value between 0 and 25% of delay
                jitter = delay * 0.25 * random.random()
                time.sleep(delay + jitter)

        return False

    def _send_event(self, event: dict) -> bool:
        """Send an event to the callback URL with retry logic."""
        return self._send_event_with_retry(event)

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
