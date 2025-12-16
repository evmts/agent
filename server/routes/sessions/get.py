"""
Get session endpoint.
"""

from fastapi import APIRouter, HTTPException, Query

from core import NotFoundError, Session, get_session


router = APIRouter()


@router.get("/session/{sessionID}")
async def get_session_route(
    sessionID: str, directory: str | None = Query(None)
) -> Session:
    """Get session details."""
    try:
        return get_session(sessionID)
    except NotFoundError:
        raise HTTPException(status_code=404, detail="Session not found")
