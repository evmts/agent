"""
Get tool endpoint.
"""

from fastapi import APIRouter, HTTPException

from .schemas import get_tool_info


router = APIRouter()


@router.get("/tools/{toolId}")
async def get_tool(toolId: str) -> dict:
    """Get a specific tool's schema."""
    tools = get_tool_info()
    for tool in tools:
        if tool["id"] == toolId:
            return tool
    raise HTTPException(status_code=404, detail="Tool not found")
