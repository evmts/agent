"""
Send message endpoint with streaming.
"""

import json
import logging
from typing import AsyncGenerator

from fastapi import APIRouter, HTTPException, Query
from sse_starlette.sse import EventSourceResponse

from core import NotFoundError, send_message

from ...event_bus import get_event_bus
from ...requests import PromptRequest
from ...state import get_agent

logger = logging.getLogger(__name__)


router = APIRouter()


@router.post("/session/{sessionID}/message")
async def send_message_route(
    sessionID: str, request: PromptRequest, directory: str | None = Query(None)
) -> EventSourceResponse:
    """Send a prompt and stream the response via SSE."""

    async def stream_response() -> AsyncGenerator[dict, None]:
        try:
            async for event in send_message(
                session_id=sessionID,
                parts=request.parts,
                agent=get_agent(),
                event_bus=get_event_bus(),
                message_id=request.messageID,
                agent_name=request.agent or "default",
                model_id=request.model.modelID if request.model else "default",
                provider_id=request.model.providerID if request.model else "default",
            ):
                yield {
                    "event": event.type,
                    "data": json.dumps(
                        {"type": event.type, "properties": event.properties}
                    ),
                }
        except NotFoundError:
            # Can't raise HTTPException in generator, yield error event
            logger.warning("Session not found during streaming: %s", sessionID)
            yield {
                "event": "error",
                "data": json.dumps({"error": "Session not found"}),
            }
        except Exception as e:
            # Log unexpected errors during streaming
            logger.exception("Error during message streaming for session %s", sessionID)
            yield {
                "event": "error",
                "data": json.dumps({"error": str(e)}),
            }

    return EventSourceResponse(stream_response())
