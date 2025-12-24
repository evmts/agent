"""
Tool implementations for the agent runner.

These tools run inside the sandboxed container and provide
file system, shell, and git operations.
"""

from typing import List, Dict, Any

from .grep import grep_tool, GREP_DEFINITION
from .read_file import read_file_tool, READ_FILE_DEFINITION
from .write_file import write_file_tool, WRITE_FILE_DEFINITION
from .shell import shell_tool, SHELL_DEFINITION
from .list_files import list_files_tool, LIST_FILES_DEFINITION

# Map of tool name to implementation
TOOL_IMPLEMENTATIONS = {
    "grep": grep_tool,
    "read_file": read_file_tool,
    "write_file": write_file_tool,
    "shell": shell_tool,
    "list_files": list_files_tool,
}

# Map of tool name to definition
TOOL_DEFINITIONS = {
    "grep": GREP_DEFINITION,
    "read_file": READ_FILE_DEFINITION,
    "write_file": WRITE_FILE_DEFINITION,
    "shell": SHELL_DEFINITION,
    "list_files": LIST_FILES_DEFINITION,
}


def get_tool_definitions(enabled_tools: List[str]) -> List[Dict[str, Any]]:
    """
    Get tool definitions for enabled tools.

    Args:
        enabled_tools: List of tool names to enable

    Returns:
        List of Anthropic tool definitions
    """
    definitions = []
    for tool_name in enabled_tools:
        if tool_name in TOOL_DEFINITIONS:
            definitions.append(TOOL_DEFINITIONS[tool_name])
    return definitions


def execute_tool(tool_name: str, input_data: Dict[str, Any]) -> str:
    """
    Execute a tool with the given input.

    Args:
        tool_name: Name of the tool to execute
        input_data: Tool input parameters

    Returns:
        Tool output as string

    Raises:
        ValueError: If tool is not found
    """
    if tool_name not in TOOL_IMPLEMENTATIONS:
        raise ValueError(f"Unknown tool: {tool_name}")

    return TOOL_IMPLEMENTATIONS[tool_name](input_data)
