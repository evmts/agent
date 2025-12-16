"""
Health check endpoint.
"""

from fastapi import APIRouter

from ..state import get_agent


router = APIRouter()


@router.get("/health")
async def health() -> dict:
    """Health check endpoint."""
    return {"status": "ok", "agent_configured": get_agent() is not None}
