"""
Skills endpoint for listing and managing reusable instruction sets.

Provides access to skill files from ~/.agent/skills/ that can be injected
into conversations using the $skill-name syntax.
"""

from fastapi import APIRouter, Query
from pydantic import BaseModel

from config.skills import get_skill_registry


router = APIRouter()


class SkillInfo(BaseModel):
    """A skill definition."""

    name: str
    description: str
    file_path: str


# =============================================================================
# Endpoints
# =============================================================================


@router.get("/skill")
async def list_skills(query: str | None = Query(None)) -> list[SkillInfo]:
    """
    List available skills.

    Args:
        query: Optional search query to filter skills by name or description

    Returns:
        List of available skills
    """
    registry = get_skill_registry()

    if query:
        skills = registry.search_skills(query)
    else:
        skills = registry.list_skills()

    return [
        SkillInfo(
            name=skill.name,
            description=skill.description,
            file_path=str(skill.file_path),
        )
        for skill in skills
    ]


@router.get("/skill/{skill_name}")
async def get_skill(skill_name: str) -> SkillInfo | None:
    """
    Get a specific skill by name.

    Args:
        skill_name: Name of the skill to retrieve

    Returns:
        Skill information or None if not found
    """
    registry = get_skill_registry()
    skill = registry.get_skill(skill_name)

    if skill is None:
        return None

    return SkillInfo(
        name=skill.name,
        description=skill.description,
        file_path=str(skill.file_path),
    )


@router.post("/skill/reload")
async def reload_skills() -> dict[str, int]:
    """
    Reload all skills from disk.

    Returns:
        Dictionary with count of loaded skills
    """
    registry = get_skill_registry()
    registry.reload()
    skills = registry.list_skills()

    return {"count": len(skills)}
