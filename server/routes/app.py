"""
Application-level endpoints (providers, settings, etc.).
"""

import os
from typing import Dict, List

from fastapi import APIRouter, Query
from pydantic import BaseModel


router = APIRouter()


# =============================================================================
# Constants
# =============================================================================

DEFAULT_ANTHROPIC_MODEL_INDEX = 0


# =============================================================================
# Response Models
# =============================================================================


class Model(BaseModel):
    """AI model information."""

    id: str
    name: str


class Provider(BaseModel):
    """AI provider with available models."""

    id: str
    name: str
    models: List[Model]


class ProvidersResponse(BaseModel):
    """Response for providers endpoint."""

    providers: List[Provider]
    default: Dict[str, int]


# =============================================================================
# Available Models
# =============================================================================

ANTHROPIC_MODELS = [
    Model(id="claude-opus-4-5-20251101", name="Claude Opus 4.5"),
    Model(id="claude-sonnet-4-20250514", name="Claude Sonnet 4"),
    Model(id="claude-3-5-sonnet-20241022", name="Claude 3.5 Sonnet"),
    Model(id="claude-3-5-haiku-20241022", name="Claude 3.5 Haiku"),
]


# =============================================================================
# Routes
# =============================================================================


@router.get("/app/providers")
async def list_providers(directory: str = Query(None)) -> ProvidersResponse:
    """
    List available AI providers and their models.

    Args:
        directory: Optional working directory (currently unused, reserved for future use)

    Returns:
        ProvidersResponse with available providers and default model indices
    """
    providers = []
    default = {}

    # Add Anthropic if API key is available
    if os.environ.get("ANTHROPIC_API_KEY"):
        providers.append(
            Provider(id="anthropic", name="Anthropic", models=ANTHROPIC_MODELS)
        )
        # Default to first model (Opus 4.5)
        default["anthropic"] = DEFAULT_ANTHROPIC_MODEL_INDEX

    return ProvidersResponse(providers=providers, default=default)
