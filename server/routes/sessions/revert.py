"""
Revert session endpoint.
"""

from fastapi import APIRouter, HTTPException, Query

from core import InvalidOperationError, NotFoundError, Session, revert_session

from ...event_bus import get_event_bus
from ...requests import RevertRequest


router = APIRouter()


@router.post("/session/{sessionID}/revert")
async def revert_session_route(
    sessionID: str, request: RevertRequest, directory: str | None = Query(None)
) -> Session:
    """Revert session to a specific message, restoring files to that state."""
    try:
        return await revert_session(
            session_id=sessionID,
            message_id=request.messageID,
            event_bus=get_event_bus(),
            part_id=request.partID,
        )
    except NotFoundError:
        raise HTTPException(status_code=404, detail="Session not found")
    except InvalidOperationError as e:
        raise HTTPException(status_code=500, detail=str(e))
