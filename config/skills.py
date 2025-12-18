"""Skills system for reusable instruction sets.

Provides functionality to discover, load, and manage skill files from ~/.agent/skills/
Skills are markdown files with YAML frontmatter that define reusable prompts.
"""

import logging
import re
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import Optional

import yaml

# Constants
SKILLS_DIR_NAME = ".agent"
SKILLS_SUBDIR_NAME = "skills"
MAX_SKILL_NAME_LENGTH = 100
MAX_SKILL_DESCRIPTION_LENGTH = 500
SKILL_CACHE_SIZE = 128

logger = logging.getLogger(__name__)


@dataclass
class Skill:
    """Represents a skill with its metadata and content."""

    name: str
    description: str
    content: str
    file_path: Path


class SkillRegistry:
    """Registry for discovering and managing skill files."""

    def __init__(self, skills_dir: Path | None = None):
        """
        Initialize the skill registry.

        Args:
            skills_dir: Directory containing skill files (defaults to ~/.agent/skills)
        """
        if skills_dir is None:
            skills_dir = Path.home() / SKILLS_DIR_NAME / SKILLS_SUBDIR_NAME
        self.skills_dir = skills_dir
        self._skills: dict[str, Skill] = {}
        self._loaded = False

    def load_skills(self) -> None:
        """Discover and load all skill files from the skills directory."""
        self._skills.clear()

        if not self.skills_dir.exists():
            logger.info(f"Skills directory does not exist: {self.skills_dir}")
            self.skills_dir.mkdir(parents=True, exist_ok=True)
            self._loaded = True
            return

        skill_files = list(self.skills_dir.rglob("*.md"))
        logger.info(f"Found {len(skill_files)} skill file(s) in {self.skills_dir}")

        for skill_file in skill_files:
            try:
                skill = self._parse_skill_file(skill_file)
                if skill:
                    self._skills[skill.name] = skill
                    logger.debug(f"Loaded skill: {skill.name}")
            except Exception as e:
                logger.warning(f"Failed to parse skill {skill_file}: {e}")

        logger.info(f"Loaded {len(self._skills)} skill(s)")
        self._loaded = True

    def _parse_skill_file(self, path: Path) -> Optional[Skill]:
        """
        Parse a skill file with YAML frontmatter.

        Args:
            path: Path to the skill file

        Returns:
            Skill object or None if parsing fails
        """
        try:
            content = path.read_text(encoding="utf-8")
        except OSError as e:
            logger.warning(f"Failed to read skill file {path}: {e}")
            return None

        # Extract YAML frontmatter using regex
        # Matches: ---\n<yaml>\n---\n<body>
        match = re.match(r'^---\n(.*?)\n---\n(.*)$', content, re.DOTALL)
        if not match:
            logger.warning(f"Skill file {path} missing YAML frontmatter")
            return None

        try:
            frontmatter = yaml.safe_load(match.group(1))
        except yaml.YAMLError as e:
            logger.warning(f"Invalid YAML frontmatter in {path}: {e}")
            return None

        body = match.group(2).strip()

        # Validate required fields
        if not isinstance(frontmatter, dict):
            logger.warning(f"Frontmatter in {path} is not a dictionary")
            return None

        name = frontmatter.get("name")
        if not name:
            logger.warning(f"Skill file {path} missing 'name' field")
            return None

        # Validate and normalize fields
        if not isinstance(name, str) or len(name) > MAX_SKILL_NAME_LENGTH:
            logger.warning(f"Invalid skill name in {path}: {name}")
            return None

        description = frontmatter.get("description", "")
        if not isinstance(description, str):
            description = str(description)
        if len(description) > MAX_SKILL_DESCRIPTION_LENGTH:
            description = description[:MAX_SKILL_DESCRIPTION_LENGTH]

        return Skill(
            name=name,
            description=description,
            content=body,
            file_path=path,
        )

    def get_skill(self, name: str) -> Optional[Skill]:
        """
        Get a skill by name.

        Args:
            name: Name of the skill to retrieve

        Returns:
            Skill object or None if not found
        """
        if not self._loaded:
            self.load_skills()
        return self._skills.get(name)

    def list_skills(self) -> list[Skill]:
        """
        Get all available skills.

        Returns:
            List of all loaded skills
        """
        if not self._loaded:
            self.load_skills()
        return list(self._skills.values())

    def search_skills(self, query: str) -> list[Skill]:
        """
        Search skills by name or description.

        Args:
            query: Search query string

        Returns:
            List of matching skills
        """
        query_lower = query.lower()
        return [
            skill for skill in self.list_skills()
            if query_lower in skill.name.lower() or query_lower in skill.description.lower()
        ]

    def reload(self) -> None:
        """Force reload of all skills from disk."""
        logger.info("Reloading skills from disk")
        self._loaded = False
        self.load_skills()


# Global skill registry instance
_skill_registry: Optional[SkillRegistry] = None


def get_skill_registry(skills_dir: Path | None = None) -> SkillRegistry:
    """
    Get or create the global skill registry instance.

    Args:
        skills_dir: Optional custom skills directory

    Returns:
        Global SkillRegistry instance
    """
    global _skill_registry
    if _skill_registry is None or skills_dir is not None:
        _skill_registry = SkillRegistry(skills_dir)
    return _skill_registry


@lru_cache(maxsize=SKILL_CACHE_SIZE)
def expand_skill_reference(skill_name: str, registry: Optional[SkillRegistry] = None) -> str:
    """
    Expand a single skill reference to its content.

    Args:
        skill_name: Name of the skill to expand
        registry: Optional custom registry (defaults to global)

    Returns:
        Expanded skill content or original reference if not found
    """
    if registry is None:
        registry = get_skill_registry()

    skill = registry.get_skill(skill_name)
    if skill:
        return f"\n\n[Skill: {skill.name}]\n{skill.content}\n[End Skill]\n\n"

    logger.warning(f"Skill not found: {skill_name}")
    return f"${skill_name}"  # Return original if not found


def expand_skill_references(
    message: str,
    registry: Optional[SkillRegistry] = None,
) -> tuple[str, list[str]]:
    """
    Expand $skill-name references in a message.

    Finds all $skill-name patterns and replaces them with skill content.
    Skill names can contain letters, numbers, underscores, and hyphens.

    Args:
        message: Message text that may contain skill references
        registry: Optional custom registry (defaults to global)

    Returns:
        Tuple of (expanded_message, list_of_skill_names_used)
    """
    if registry is None:
        registry = get_skill_registry()

    skills_used: list[str] = []
    skill_pattern = re.compile(r'\$([a-zA-Z0-9_-]+)')

    def replace_skill(match: re.Match) -> str:
        skill_name = match.group(1)
        skill = registry.get_skill(skill_name)
        if skill:
            skills_used.append(skill_name)
            return f"\n\n[Skill: {skill.name}]\n{skill.content}\n[End Skill]\n\n"
        return match.group(0)  # Keep original if not found

    expanded = skill_pattern.sub(replace_skill, message)

    if skills_used:
        logger.info(f"Expanded skill references: {skills_used}")

    return expanded, skills_used
