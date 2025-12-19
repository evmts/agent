"""
Update session endpoint.
"""

from fastapi import APIRouter, HTTPException, Query

from config.defaults import AVAILABLE_MODELS
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
    """Update session title, archived status, model, reasoning effort, or plugins."""
    try:
        archived = None
        if request.time and "archived" in request.time:
            archived = request.time["archived"]

        # Validate model if provided
        if request.model is not None:
            valid_models = [m["id"] for m in AVAILABLE_MODELS]
            if request.model not in valid_models:
                raise HTTPException(
                    status_code=400,
                    detail=f"Invalid model: {request.model}. Available models: {', '.join(valid_models)}"
                )

        # Validate reasoning effort if provided
        if request.reasoning_effort is not None:
            valid_levels = ["minimal", "low", "medium", "high"]
            if request.reasoning_effort not in valid_levels:
                raise HTTPException(
                    status_code=400,
                    detail=f"Invalid reasoning_effort: {request.reasoning_effort}. Valid levels: {', '.join(valid_levels)}"
                )

        # Validate plugins if provided
        if request.plugins is not None:
            from plugins import plugin_exists
            for plugin_name in request.plugins:
                if not plugin_exists(plugin_name):
                    raise HTTPException(
                        status_code=400,
                        detail=f"Plugin not found: {plugin_name}"
                    )

        return await update_session(
            session_id=sessionID,
            event_bus=get_event_bus(),
            title=request.title,
            archived=archived,
            model=request.model,
            reasoning_effort=request.reasoning_effort,
            plugins=request.plugins,
        )
    except NotFoundError:
        raise HTTPException(status_code=404, detail="Session not found")
