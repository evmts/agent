"""
List messages endpoint.
"""

from fastapi import APIRouter, HTTPException, Query

from core import NotFoundError, list_messages


router = APIRouter()


@router.get("/session/{sessionID}/message")
async def list_messages_route(
    sessionID: str,
    limit: int | None = Query(None),
    directory: str | None = Query(None),
) -> list[dict]:
    """List messages in a session."""
    try:
        return list_messages(sessionID, limit)
    except NotFoundError:
        raise HTTPException(status_code=404, detail="Session not found")
