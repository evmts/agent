"""
Get message endpoint.
"""

from fastapi import APIRouter, HTTPException, Query

from core import NotFoundError, get_message


router = APIRouter()


@router.get("/session/{sessionID}/message/{messageID}")
async def get_message_route(
    sessionID: str, messageID: str, directory: str | None = Query(None)
) -> dict:
    """Get a specific message."""
    try:
        return get_message(sessionID, messageID)
    except NotFoundError as e:
        if e.resource == "Session":
            raise HTTPException(status_code=404, detail="Session not found")
        raise HTTPException(status_code=404, detail="Message not found")
