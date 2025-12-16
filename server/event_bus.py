"""
SSE-based EventBus implementation.

This module provides the server-side implementation of the EventBus protocol
using Server-Sent Events for real-time updates to connected clients.
"""

import asyncio
from typing import Any

from core import Event


class SSEEventBus:
    """
    EventBus implementation that broadcasts events to SSE subscribers.

    Each subscriber gets a queue that receives events. The global event
    endpoint consumes from these queues to stream events to clients.
    """

    def __init__(self) -> None:
        self.subscribers: list[asyncio.Queue[dict[str, Any]]] = []

    async def publish(self, event: Event) -> None:
        """Publish an event to all subscribers."""
        data = event.model_dump()
        for queue in self.subscribers:
            await queue.put(data)

    def subscribe(self) -> asyncio.Queue[dict[str, Any]]:
        """
        Create a new subscription queue.

        Returns:
            A queue that will receive all published events
        """
        queue: asyncio.Queue[dict[str, Any]] = asyncio.Queue()
        self.subscribers.append(queue)
        return queue

    def unsubscribe(self, queue: asyncio.Queue[dict[str, Any]]) -> None:
        """
        Remove a subscription queue.

        Args:
            queue: The queue to unsubscribe
        """
        if queue in self.subscribers:
            self.subscribers.remove(queue)


# Global event bus instance
_event_bus: SSEEventBus | None = None


def get_event_bus() -> SSEEventBus:
    """Get the global event bus instance, creating it if necessary."""
    global _event_bus
    if _event_bus is None:
        _event_bus = SSEEventBus()
    return _event_bus
