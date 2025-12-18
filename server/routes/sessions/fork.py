"""
Fork session endpoint.
"""

from fastapi import APIRouter, HTTPException, Query

from core import NotFoundError, Session, fork_session

from ...event_bus import get_event_bus
from ...requests import ForkRequest


router = APIRouter()


@router.post("/session/{sessionID}/fork")
async def fork_session_route(
    sessionID: str, request: ForkRequest, directory: str | None = Query(None)
) -> Session:
    """Fork a session at a specific message."""
    try:
        return await fork_session(
            session_id=sessionID,
            event_bus=get_event_bus(),
            message_id=request.messageID,
            title=request.title,
        )
    except NotFoundError:
        raise HTTPException(status_code=404, detail="Session not found")
