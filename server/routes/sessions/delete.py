"""
Delete session endpoint.
"""

import logging

from fastapi import APIRouter, HTTPException, Query

from core import NotFoundError, delete_session

from ...event_bus import get_event_bus

logger = logging.getLogger(__name__)

router = APIRouter()


@router.delete("/session/{sessionID}")
async def delete_session_route(
    sessionID: str, directory: str | None = Query(None)
) -> bool:
    """Delete a session."""
    try:
        return await delete_session(sessionID, get_event_bus())
    except NotFoundError:
        logger.debug("Session not found for deletion: %s", sessionID)
        raise HTTPException(status_code=404, detail="Session not found")
