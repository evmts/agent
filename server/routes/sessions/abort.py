"""
Abort session endpoint.
"""

from fastapi import APIRouter, HTTPException, Query

from core import NotFoundError, abort_session


router = APIRouter()


@router.post("/session/{sessionID}/abort")
async def abort_session_route(
    sessionID: str, directory: str | None = Query(None)
) -> bool:
    """Abort an active session."""
    try:
        return abort_session(sessionID)
    except NotFoundError:
        raise HTTPException(status_code=404, detail="Session not found")
