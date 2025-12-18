"""
Create session endpoint.
"""

import os

from fastapi import APIRouter, Query

from core import Session, create_session

from ...event_bus import get_event_bus
from ...requests import CreateSessionRequest


router = APIRouter()


@router.post("/session")
async def create_session_route(
    request: CreateSessionRequest, directory: str | None = Query(None)
) -> Session:
    """Create a new session."""
    return await create_session(
        directory=directory or os.getcwd(),
        event_bus=get_event_bus(),
        title=request.title,
        parent_id=request.parentID,
        bypass_mode=request.bypass_mode,
    )
