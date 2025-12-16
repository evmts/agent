"""
Delete session endpoint.
"""

from fastapi import APIRouter, HTTPException, Query

from core import NotFoundError, delete_session

from ...event_bus import get_event_bus


router = APIRouter()


@router.delete("/session/{sessionID}")
async def delete_session_route(
    sessionID: str, directory: str | None = Query(None)
) -> bool:
    """Delete a session."""
    try:
        return await delete_session(sessionID, get_event_bus())
    except NotFoundError:
        raise HTTPException(status_code=404, detail="Session not found")
