"""
List files tool for exploring directory contents.
"""

import os
import glob as glob_module
from typing import Dict, Any, List

LIST_FILES_DEFINITION = {
    "name": "list_files",
    "description": "List files in a directory. Supports glob patterns.",
    "input_schema": {
        "type": "object",
        "properties": {
            "path": {
                "type": "string",
                "description": "The path or glob pattern (relative to workspace)",
                "default": ".",
            },
            "recursive": {
                "type": "boolean",
                "description": "Include files in subdirectories",
                "default": False,
            },
            "include_hidden": {
                "type": "boolean",
                "description": "Include hidden files (starting with .)",
                "default": False,
            },
            "max_results": {
                "type": "integer",
                "description": "Maximum number of results to return",
                "default": 200,
            },
        },
        "required": [],
    },
}


def list_files_tool(input_data: Dict[str, Any]) -> str:
    """List files in a directory."""
    path = input_data.get("path", ".")
    recursive = input_data.get("recursive", False)
    include_hidden = input_data.get("include_hidden", False)
    max_results = input_data.get("max_results", 200)

    # Security check - prevent path traversal
    full_path = os.path.normpath(os.path.join("/workspace", path))
    if not full_path.startswith("/workspace"):
        return "Error: path traversal not allowed"

    try:
        results: List[str] = []

        if "*" in path or "?" in path:
            # Glob pattern
            pattern = os.path.join("/workspace", path)
            if recursive and "**" not in pattern:
                pattern = os.path.join(os.path.dirname(pattern), "**", os.path.basename(pattern))

            matches = glob_module.glob(pattern, recursive=recursive)

            for match in matches:
                rel_path = os.path.relpath(match, "/workspace")

                if not include_hidden:
                    parts = rel_path.split(os.sep)
                    if any(p.startswith(".") for p in parts):
                        continue

                results.append(rel_path)

        elif os.path.isdir(full_path):
            # Directory listing
            if recursive:
                for root, dirs, files in os.walk(full_path):
                    # Filter hidden directories
                    if not include_hidden:
                        dirs[:] = [d for d in dirs if not d.startswith(".")]

                    for name in files:
                        if not include_hidden and name.startswith("."):
                            continue

                        rel_path = os.path.relpath(os.path.join(root, name), "/workspace")
                        results.append(rel_path)

                        if len(results) >= max_results:
                            break

                    if len(results) >= max_results:
                        break
            else:
                entries = os.listdir(full_path)
                for entry in entries:
                    if not include_hidden and entry.startswith("."):
                        continue

                    entry_path = os.path.join(full_path, entry)
                    rel_path = os.path.relpath(entry_path, "/workspace")

                    if os.path.isdir(entry_path):
                        results.append(rel_path + "/")
                    else:
                        results.append(rel_path)

        else:
            # Single file
            if os.path.exists(full_path):
                results.append(os.path.relpath(full_path, "/workspace"))
            else:
                return f"Error: path not found: {path}"

        # Sort and truncate
        results.sort()
        if len(results) > max_results:
            results = results[:max_results]
            results.append(f"... truncated to {max_results} results")

        return "\n".join(results)

    except Exception as e:
        return f"Error: {str(e)}"
