"""
List sessions endpoint.
"""

from fastapi import APIRouter, Query

from core import Session, list_sessions


router = APIRouter()


@router.get("/session")
async def list_sessions_route(directory: str | None = Query(None)) -> list[Session]:
    """List all sessions sorted by most recently updated."""
    return list_sessions()
