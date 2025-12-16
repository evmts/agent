"""
Get session diff endpoint.
"""

from fastapi import APIRouter, HTTPException, Query

from core import FileDiff, NotFoundError, get_session_diff


router = APIRouter()


@router.get("/session/{sessionID}/diff")
async def get_session_diff_route(
    sessionID: str,
    messageID: str | None = Query(None),
    directory: str | None = Query(None),
) -> list[FileDiff]:
    """Get file diffs for a session."""
    try:
        return get_session_diff(sessionID, messageID)
    except NotFoundError:
        raise HTTPException(status_code=404, detail="Session not found")
