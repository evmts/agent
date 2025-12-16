"""
Global event SSE endpoint.
"""

import json
from typing import AsyncGenerator

from fastapi import APIRouter, Query
from sse_starlette.sse import EventSourceResponse

from ..event_bus import get_event_bus


router = APIRouter()


@router.get("/global/event")
async def global_event(directory: str | None = Query(None)) -> EventSourceResponse:
    """Subscribe to global events via SSE."""
    event_bus = get_event_bus()

    async def event_generator() -> AsyncGenerator[dict, None]:
        queue = event_bus.subscribe()
        try:
            while True:
                event = await queue.get()
                yield {"event": event["type"], "data": json.dumps(event)}
        finally:
            event_bus.unsubscribe(queue)

    return EventSourceResponse(event_generator())
