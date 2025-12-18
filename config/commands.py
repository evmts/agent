"""
Custom command loading and management.

Loads custom slash commands from ~/.agent/prompts/*.md files.
"""

import logging
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

import yaml

logger = logging.getLogger(__name__)


@dataclass
class CommandArg:
    """Argument definition for a custom command."""

    name: str
    required: bool = False
    description: str = ""
    default: Optional[str] = None


@dataclass
class CustomCommand:
    """A custom slash command loaded from a markdown file."""

    name: str
    description: str
    template: str
    args: list[CommandArg] = field(default_factory=list)
    file_path: Optional[Path] = None


class CommandRegistry:
    """Registry for custom slash commands loaded from markdown files."""

    def __init__(self, prompts_dir: Optional[Path] = None):
        """
        Initialize the command registry.

        Args:
            prompts_dir: Directory containing command markdown files.
                        Defaults to ~/.agent/prompts/
        """
        self.prompts_dir = prompts_dir or Path.home() / ".agent" / "prompts"
        self._commands: dict[str, CustomCommand] = {}
        self._loaded = False

    def load_commands(self) -> None:
        """Load all custom commands from the prompts directory."""
        self._commands.clear()

        if not self.prompts_dir.exists():
            logger.debug(f"Creating prompts directory: {self.prompts_dir}")
            self.prompts_dir.mkdir(parents=True, exist_ok=True)
            self._loaded = True
            return

        logger.debug(f"Loading commands from: {self.prompts_dir}")
        for cmd_file in self.prompts_dir.glob("*.md"):
            try:
                command = self._parse_command_file(cmd_file)
                if command:
                    self._commands[command.name] = command
                    logger.debug(f"Loaded command: {command.name} from {cmd_file.name}")
            except Exception as e:
                logger.warning(f"Failed to parse command {cmd_file}: {e}")

        logger.info(f"Loaded {len(self._commands)} custom commands")
        self._loaded = True

    def _parse_command_file(self, path: Path) -> Optional[CustomCommand]:
        """
        Parse a command file with optional YAML frontmatter.

        Args:
            path: Path to the markdown file

        Returns:
            CustomCommand instance or None if parsing failed
        """
        content = path.read_text()

        # Default name from filename
        name = path.stem

        # Check for YAML frontmatter
        frontmatter: dict = {}
        template = content

        match = re.match(r"^---\n(.*?)\n---\n(.*)$", content, re.DOTALL)
        if match:
            try:
                frontmatter = yaml.safe_load(match.group(1)) or {}
                template = match.group(2).strip()
            except yaml.YAMLError as e:
                logger.warning(f"Failed to parse YAML frontmatter in {path}: {e}")
                # Continue with empty frontmatter

        # Override name if specified
        name = frontmatter.get("name", name)
        description = frontmatter.get("description", "")

        # Parse args
        args = []
        for arg_def in frontmatter.get("args", []):
            args.append(
                CommandArg(
                    name=arg_def.get("name", ""),
                    required=arg_def.get("required", False),
                    description=arg_def.get("description", ""),
                    default=arg_def.get("default"),
                )
            )

        return CustomCommand(
            name=name,
            description=description,
            template=template,
            args=args,
            file_path=path,
        )

    def get_command(self, name: str) -> Optional[CustomCommand]:
        """
        Get command by name.

        Args:
            name: Command name

        Returns:
            CustomCommand instance or None if not found
        """
        if not self._loaded:
            self.load_commands()
        return self._commands.get(name)

    def list_commands(self) -> list[CustomCommand]:
        """
        List all custom commands.

        Returns:
            List of all loaded custom commands
        """
        if not self._loaded:
            self.load_commands()
        return list(self._commands.values())

    def reload(self) -> None:
        """Force reload of all commands from disk."""
        logger.info("Reloading commands from disk")
        self._loaded = False
        self.load_commands()

    def expand_command(
        self,
        name: str,
        args: Optional[list[str]] = None,
        kwargs: Optional[dict[str, str]] = None,
    ) -> Optional[str]:
        """
        Expand command template with arguments.

        Args:
            name: Command name
            args: Positional arguments for $1, $2, etc.
            kwargs: Named arguments for {{name}} placeholders

        Returns:
            Expanded template string or None if command not found

        Raises:
            ValueError: If required arguments are missing
        """
        if not self._loaded:
            self.load_commands()

        command = self.get_command(name)
        if not command:
            return None

        template = command.template
        args = args or []
        kwargs = kwargs or {}

        # Substitute positional args ($1, $2, etc.)
        for i, arg in enumerate(args):
            template = template.replace(f"${i+1}", arg)

        # Substitute named args ({{name}})
        for key, value in kwargs.items():
            template = template.replace(f"{{{{{key}}}}}", value)

        # Substitute from command args with defaults
        for i, arg_def in enumerate(command.args):
            placeholder = f"{{{{{arg_def.name}}}}}"
            if placeholder in template:
                if i < len(args):
                    # Use positional argument
                    template = template.replace(placeholder, args[i])
                elif arg_def.name in kwargs:
                    # Use named argument
                    template = template.replace(placeholder, kwargs[arg_def.name])
                elif arg_def.default:
                    # Use default value
                    template = template.replace(placeholder, arg_def.default)
                elif arg_def.required:
                    # Required argument missing
                    raise ValueError(f"Required argument missing: {arg_def.name}")

        return template


# Global instance
command_registry = CommandRegistry()
