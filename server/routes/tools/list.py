"""
List tools endpoint.
"""

from fastapi import APIRouter

from .schemas import get_tool_info


router = APIRouter()


@router.get("/tools")
async def list_tools() -> list[dict]:
    """List all available tools with their schemas."""
    return get_tool_info()
