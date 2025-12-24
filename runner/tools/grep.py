"""
Grep tool for searching file contents.
"""

import os
import subprocess
from typing import Dict, Any

GREP_DEFINITION = {
    "name": "grep",
    "description": "Search for patterns in files using grep. Returns matching lines with file paths and line numbers.",
    "input_schema": {
        "type": "object",
        "properties": {
            "pattern": {
                "type": "string",
                "description": "The regex pattern to search for",
            },
            "path": {
                "type": "string",
                "description": "The file or directory to search in. Defaults to current directory.",
                "default": ".",
            },
            "include": {
                "type": "string",
                "description": "File pattern to include (e.g., '*.py', '*.ts')",
            },
            "ignore_case": {
                "type": "boolean",
                "description": "Perform case-insensitive search",
                "default": False,
            },
            "max_results": {
                "type": "integer",
                "description": "Maximum number of results to return",
                "default": 100,
            },
        },
        "required": ["pattern"],
    },
}


def grep_tool(input_data: Dict[str, Any]) -> str:
    """Execute grep search."""
    pattern = input_data.get("pattern")
    path = input_data.get("path", ".")
    include = input_data.get("include")
    ignore_case = input_data.get("ignore_case", False)
    max_results = input_data.get("max_results", 100)

    if not pattern:
        return "Error: pattern is required"

    # SECURITY: Prevent path traversal attacks
    # Normalize the path and ensure it stays within /workspace
    full_path = os.path.realpath(os.path.join("/workspace", path))
    if not full_path.startswith("/workspace"):
        return "Error: path traversal not allowed"

    # Use the normalized path relative to workspace
    safe_path = os.path.relpath(full_path, "/workspace")
    if safe_path.startswith(".."):
        return "Error: path traversal not allowed"

    # Build grep command
    cmd = ["grep", "-rn"]

    if ignore_case:
        cmd.append("-i")

    if include:
        cmd.extend(["--include", include])

    # Use the safe normalized path
    cmd.extend([pattern, safe_path])

    try:
        result = subprocess.run(
            cmd,
            cwd="/workspace",
            capture_output=True,
            text=True,
            timeout=30,
        )

        output = result.stdout
        lines = output.split("\n")

        if len(lines) > max_results:
            lines = lines[:max_results]
            lines.append(f"\n... truncated to {max_results} results")

        return "\n".join(lines)

    except subprocess.TimeoutExpired:
        return "Error: search timed out"
    except Exception as e:
        return f"Error: {str(e)}"
