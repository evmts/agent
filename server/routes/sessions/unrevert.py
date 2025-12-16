"""
Unrevert session endpoint.
"""

from fastapi import APIRouter, HTTPException, Query

from core import NotFoundError, Session, unrevert_session

from ...event_bus import get_event_bus


router = APIRouter()


@router.post("/session/{sessionID}/unrevert")
async def unrevert_session_route(
    sessionID: str, directory: str | None = Query(None)
) -> Session:
    """Undo revert on a session."""
    try:
        return await unrevert_session(sessionID, get_event_bus())
    except NotFoundError:
        raise HTTPException(status_code=404, detail="Session not found")
