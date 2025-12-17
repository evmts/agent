"""
Get session endpoint.
"""

import logging

from fastapi import APIRouter, HTTPException, Query

from core import NotFoundError, Session, get_session

logger = logging.getLogger(__name__)

router = APIRouter()


@router.get("/session/{sessionID}")
async def get_session_route(
    sessionID: str, directory: str | None = Query(None)
) -> Session:
    """Get session details."""
    try:
        return get_session(sessionID)
    except NotFoundError:
        logger.debug("Session not found: %s", sessionID)
        raise HTTPException(status_code=404, detail="Session not found")
