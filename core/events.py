"""
Event types and EventBus protocol.

The EventBus is an abstract interface that core uses to publish events.
The server layer provides an SSE-based implementation.
"""

from typing import Any, Protocol

from pydantic import BaseModel


class Event(BaseModel):
    """Domain event that can be published to subscribers."""

    type: str
    properties: dict[str, Any]


class EventBus(Protocol):
    """Abstract interface for publishing events."""

    async def publish(self, event: Event) -> None:
        """Publish an event to all subscribers."""
        ...


class NullEventBus:
    """No-op EventBus implementation for testing."""

    async def publish(self, event: Event) -> None:
        """Discard the event."""
        pass
