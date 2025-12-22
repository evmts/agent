"""
Shell command execution tool.
"""

import subprocess
from typing import Dict, Any

SHELL_DEFINITION = {
    "name": "shell",
    "description": "Execute a shell command. Returns stdout, stderr, and exit code.",
    "input_schema": {
        "type": "object",
        "properties": {
            "command": {
                "type": "string",
                "description": "The shell command to execute",
            },
            "working_directory": {
                "type": "string",
                "description": "Working directory for the command (relative to workspace)",
                "default": ".",
            },
            "timeout": {
                "type": "integer",
                "description": "Timeout in seconds",
                "default": 60,
            },
        },
        "required": ["command"],
    },
}


def shell_tool(input_data: Dict[str, Any]) -> str:
    """Execute a shell command."""
    command = input_data.get("command")
    working_dir = input_data.get("working_directory", ".")
    timeout = input_data.get("timeout", 60)

    if not command:
        return "Error: command is required"

    # Construct full working directory
    import os
    full_working_dir = os.path.normpath(os.path.join("/workspace", working_dir))
    if not full_working_dir.startswith("/workspace"):
        return "Error: working_directory must be within workspace"

    try:
        result = subprocess.run(
            command,
            shell=True,
            executable="/bin/sh",
            cwd=full_working_dir,
            capture_output=True,
            text=True,
            timeout=timeout,
        )

        output_parts = []

        if result.stdout:
            output_parts.append(f"STDOUT:\n{result.stdout}")

        if result.stderr:
            output_parts.append(f"STDERR:\n{result.stderr}")

        output_parts.append(f"EXIT CODE: {result.returncode}")

        return "\n\n".join(output_parts)

    except subprocess.TimeoutExpired:
        return f"Error: command timed out after {timeout} seconds"
    except Exception as e:
        return f"Error: {str(e)}"
