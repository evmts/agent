"""
Update session endpoint.
"""

from fastapi import APIRouter, HTTPException, Query

from core import NotFoundError, Session, update_session

from ...event_bus import get_event_bus
from ...requests import UpdateSessionRequest


router = APIRouter()


@router.patch("/session/{sessionID}")
async def update_session_route(
    sessionID: str,
    request: UpdateSessionRequest,
    directory: str | None = Query(None),
) -> Session:
    """Update session title or archived status."""
    try:
        archived = None
        if request.time and "archived" in request.time:
            archived = request.time["archived"]

        return await update_session(
            session_id=sessionID,
            event_bus=get_event_bus(),
            title=request.title,
            archived=archived,
        )
    except NotFoundError:
        raise HTTPException(status_code=404, detail="Session not found")
