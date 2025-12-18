"""
Models endpoint - return available models with their capabilities.
"""

from fastapi import APIRouter
from pydantic import BaseModel

from config.defaults import AVAILABLE_MODELS, DEFAULT_MODEL, DEFAULT_REASONING_EFFORT


router = APIRouter()


class ModelCapabilities(BaseModel):
    """Model capabilities and metadata."""
    id: str
    name: str
    context_window: int
    supports_reasoning: bool
    reasoning_levels: list[str] | None = None


class ModelsResponse(BaseModel):
    """Response for models endpoint."""
    models: list[ModelCapabilities]
    default_model: str
    default_reasoning_effort: str


@router.get("/app/models")
async def list_models() -> ModelsResponse:
    """
    List available AI models with their capabilities.

    Returns:
        ModelsResponse with available models and default settings
    """
    models = [
        ModelCapabilities(
            id=m["id"],
            name=m["name"],
            context_window=m["context_window"],
            supports_reasoning=m["supports_reasoning"],
            reasoning_levels=m.get("reasoning_levels"),
        )
        for m in AVAILABLE_MODELS
    ]

    return ModelsResponse(
        models=models,
        default_model=DEFAULT_MODEL,
        default_reasoning_effort=DEFAULT_REASONING_EFFORT,
    )
