"""
Read file tool for reading file contents.
"""

import os
from typing import Dict, Any

READ_FILE_DEFINITION = {
    "name": "read_file",
    "description": "Read the contents of a file. Returns the file contents as text.",
    "input_schema": {
        "type": "object",
        "properties": {
            "path": {
                "type": "string",
                "description": "The path to the file to read (relative to workspace)",
            },
            "start_line": {
                "type": "integer",
                "description": "Start reading from this line number (1-indexed)",
            },
            "end_line": {
                "type": "integer",
                "description": "Stop reading at this line number (inclusive)",
            },
        },
        "required": ["path"],
    },
}


def read_file_tool(input_data: Dict[str, Any]) -> str:
    """Read file contents."""
    path = input_data.get("path")
    start_line = input_data.get("start_line")
    end_line = input_data.get("end_line")

    if not path:
        return "Error: path is required"

    # Security check - prevent path traversal
    full_path = os.path.realpath(os.path.join("/workspace", path))
    if not full_path.startswith("/workspace/"):
        return "Error: path traversal not allowed"

    try:
        with open(full_path, "r", encoding="utf-8", errors="replace") as f:
            if start_line or end_line:
                lines = f.readlines()
                start_idx = (start_line - 1) if start_line else 0
                end_idx = end_line if end_line else len(lines)
                content = "".join(lines[start_idx:end_idx])
            else:
                content = f.read()

        # Truncate very large files
        max_size = 100_000
        if len(content) > max_size:
            content = content[:max_size] + f"\n\n... truncated (file is {len(content)} bytes)"

        return content

    except FileNotFoundError:
        return f"Error: file not found: {path}"
    except PermissionError:
        return f"Error: permission denied: {path}"
    except Exception as e:
        return f"Error: {str(e)}"
