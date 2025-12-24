"""
Write file tool for creating and modifying files.
"""

import os
from typing import Dict, Any

WRITE_FILE_DEFINITION = {
    "name": "write_file",
    "description": "Write content to a file. Creates the file if it doesn't exist, or overwrites if it does.",
    "input_schema": {
        "type": "object",
        "properties": {
            "path": {
                "type": "string",
                "description": "The path to the file to write (relative to workspace)",
            },
            "content": {
                "type": "string",
                "description": "The content to write to the file",
            },
            "append": {
                "type": "boolean",
                "description": "If true, append to the file instead of overwriting",
                "default": False,
            },
        },
        "required": ["path", "content"],
    },
}


def write_file_tool(input_data: Dict[str, Any]) -> str:
    """Write content to a file."""
    path = input_data.get("path")
    content = input_data.get("content")
    append = input_data.get("append", False)

    if not path:
        return "Error: path is required"
    if content is None:
        return "Error: content is required"

    # Security check - prevent path traversal
    full_path = os.path.realpath(os.path.join("/workspace", path))
    if not full_path.startswith("/workspace/"):
        return "Error: path traversal not allowed"

    try:
        # Create parent directories if needed
        parent_dir = os.path.dirname(full_path)
        if parent_dir:
            os.makedirs(parent_dir, exist_ok=True)

        mode = "a" if append else "w"
        with open(full_path, mode, encoding="utf-8") as f:
            f.write(content)

        return f"Successfully wrote {len(content)} bytes to {path}"

    except PermissionError:
        return f"Error: permission denied: {path}"
    except Exception as e:
        return f"Error: {str(e)}"
