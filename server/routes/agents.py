"""
Agent listing endpoint.
"""

import os
from pathlib import Path
from typing import Optional

from fastapi import APIRouter, Query
from pydantic import BaseModel

from agent.registry import AgentRegistry, AgentMode
from config.defaults import DEFAULT_MODEL


# =============================================================================
# Constants
# =============================================================================

DEFAULT_PROVIDER_ID = "anthropic"


# =============================================================================
# Models
# =============================================================================


class ModelInfo(BaseModel):
    """Model configuration information."""

    providerID: str
    modelID: str


class Agent(BaseModel):
    """Agent configuration returned by the API."""

    name: str
    description: str
    mode: str  # "normal" or "subagent"
    model: ModelInfo


# =============================================================================
# Router
# =============================================================================

router = APIRouter()


@router.get("/agent")
async def list_agents(directory: Optional[str] = Query(None)) -> list[Agent]:
    """
    List all available agents.

    Args:
        directory: Optional working directory for loading custom agent configs

    Returns:
        List of available agents with their configurations
    """
    # Load agent registry with custom configs if directory specified
    project_root = Path(directory) if directory else None
    registry = AgentRegistry(project_root=project_root)

    # Get model from environment
    model_id = os.environ.get("ANTHROPIC_MODEL", DEFAULT_MODEL)

    # Convert registry agents to API format
    agents = []
    for agent_config in registry.list():
        # Map AgentMode to API mode format
        mode = "subagent" if agent_config.mode == AgentMode.SUBAGENT else "normal"

        agents.append(
            Agent(
                name=agent_config.name,
                description=agent_config.description,
                mode=mode,
                model=ModelInfo(
                    providerID=DEFAULT_PROVIDER_ID,
                    modelID=model_id,
                ),
            )
        )

    return agents
