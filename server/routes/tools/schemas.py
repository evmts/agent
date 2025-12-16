"""
Tool schema definitions.
"""


def get_tool_info() -> list[dict]:
    """Get information about all available tools with their schemas."""
    tools = [
        {
            "id": "python",
            "description": "Execute Python code in a sandboxed subprocess",
            "parameters": {
                "code": {"type": "string", "description": "Python code to execute"},
                "timeout": {
                    "type": "integer",
                    "description": "Max execution time in seconds",
                    "default": 30,
                },
            },
        },
        {
            "id": "shell",
            "description": "Execute shell commands in a subprocess",
            "parameters": {
                "command": {"type": "string", "description": "Shell command to execute"},
                "timeout": {
                    "type": "integer",
                    "description": "Max execution time in seconds",
                    "default": 30,
                },
            },
        },
        {
            "id": "read",
            "description": "Read the contents of a file",
            "parameters": {
                "file_path": {
                    "type": "string",
                    "description": "Absolute path to the file to read",
                },
                "limit": {
                    "type": "integer",
                    "description": "Maximum number of lines to read",
                    "optional": True,
                },
                "offset": {
                    "type": "integer",
                    "description": "Line number to start reading from",
                    "optional": True,
                },
            },
        },
        {
            "id": "write",
            "description": "Write content to a file, overwriting if it exists",
            "parameters": {
                "file_path": {
                    "type": "string",
                    "description": "Absolute path to the file to write",
                },
                "content": {
                    "type": "string",
                    "description": "Content to write to the file",
                },
            },
        },
        {
            "id": "edit",
            "description": "Perform exact string replacements in files",
            "parameters": {
                "file_path": {
                    "type": "string",
                    "description": "Absolute path to the file to modify",
                },
                "old_string": {"type": "string", "description": "The text to replace"},
                "new_string": {
                    "type": "string",
                    "description": "The text to replace it with",
                },
                "replace_all": {
                    "type": "boolean",
                    "description": "Replace all occurrences of old_string",
                    "default": False,
                },
            },
        },
        {
            "id": "search",
            "description": "Search for files matching a glob pattern",
            "parameters": {
                "pattern": {
                    "type": "string",
                    "description": "Glob pattern to match files against (e.g., '**/*.js')",
                },
                "path": {
                    "type": "string",
                    "description": "Directory to search in",
                    "optional": True,
                },
            },
        },
        {
            "id": "grep",
            "description": "Search for content within files using regex patterns",
            "parameters": {
                "pattern": {
                    "type": "string",
                    "description": "Regular expression pattern to search for",
                },
                "path": {
                    "type": "string",
                    "description": "File or directory to search in",
                    "optional": True,
                },
                "glob": {
                    "type": "string",
                    "description": "Glob pattern to filter files (e.g., '*.js')",
                    "optional": True,
                },
                "type": {
                    "type": "string",
                    "description": "File type to search (e.g., 'js', 'py', 'rust')",
                    "optional": True,
                },
                "output_mode": {
                    "type": "string",
                    "description": "Output mode: 'content', 'files_with_matches', or 'count'",
                    "default": "files_with_matches",
                },
                "case_insensitive": {
                    "type": "boolean",
                    "description": "Case insensitive search",
                    "default": False,
                },
            },
        },
        {
            "id": "ls",
            "description": "List directory contents",
            "parameters": {
                "path": {
                    "type": "string",
                    "description": "Directory path to list",
                    "optional": True,
                },
                "all": {
                    "type": "boolean",
                    "description": "Show hidden files",
                    "default": False,
                },
                "long": {
                    "type": "boolean",
                    "description": "Use long listing format",
                    "default": False,
                },
            },
        },
        {
            "id": "fetch",
            "description": "Fetch content from a URL",
            "parameters": {
                "url": {"type": "string", "description": "URL to fetch content from"},
                "method": {
                    "type": "string",
                    "description": "HTTP method to use",
                    "default": "GET",
                },
                "headers": {
                    "type": "object",
                    "description": "HTTP headers to include",
                    "optional": True,
                },
                "body": {
                    "type": "string",
                    "description": "Request body for POST/PUT",
                    "optional": True,
                },
            },
        },
        {
            "id": "web",
            "description": "Search the web and return results",
            "parameters": {
                "query": {"type": "string", "description": "Search query"},
                "max_results": {
                    "type": "integer",
                    "description": "Maximum number of results to return",
                    "default": 10,
                },
            },
        },
        {
            "id": "todowrite",
            "description": "Create or update a structured task list",
            "parameters": {
                "todos": {
                    "type": "array",
                    "description": "List of todo items",
                    "items": {
                        "type": "object",
                        "properties": {
                            "content": {
                                "type": "string",
                                "description": "Task description",
                            },
                            "status": {
                                "type": "string",
                                "description": "Task status: 'pending', 'in_progress', or 'completed'",
                            },
                            "activeForm": {
                                "type": "string",
                                "description": "Present continuous form of the task",
                            },
                        },
                    },
                }
            },
        },
        {
            "id": "todoread",
            "description": "Read the current task list",
            "parameters": {},
        },
    ]
    return tools
