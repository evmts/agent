"""
MCP server status endpoint.
"""

from fastapi import APIRouter

from agent.agent import create_mcp_servers
from config import get_working_directory

router = APIRouter()


@router.get("/mcp/servers")
async def get_mcp_servers() -> dict:
    """Get MCP server status and available tools."""
    working_dir = get_working_directory()

    # Create MCP servers to inspect their configuration
    mcp_servers = create_mcp_servers(working_dir)

    servers = []

    for mcp_server in mcp_servers:
        # Extract server name from command or args
        server_name = "unknown"
        description = ""

        # Identify server by command arguments
        if hasattr(mcp_server, 'args') and mcp_server.args:
            if 'mcp_server_shell' in str(mcp_server.args):
                server_name = "shell"
                description = "Execute shell commands and scripts"
            elif 'mcp_server_filesystem' in str(mcp_server.args):
                server_name = "filesystem"
                description = "Read, write, and manage files"

        # For now, we'll return a basic structure
        # In a real implementation, you would connect to the servers and query their tools
        server_info = {
            "name": server_name,
            "description": description,
            "status": "connected",  # Would need actual health check
            "url": "",
            "tools": get_server_tools(server_name),
            "lastError": "",
            "connectedAt": None,
        }

        servers.append(server_info)

    return {"servers": servers}


def get_server_tools(server_name: str) -> list[dict]:
    """Get the tools provided by a specific MCP server."""
    # This is a static mapping for known servers
    # In a real implementation, you would query the MCP server for its tools

    if server_name == "shell":
        return [
            {
                "name": "execute_command",
                "description": "Execute a shell command and return the output",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "command": {"type": "string", "description": "The shell command to execute"},
                        "timeout": {"type": "number", "description": "Timeout in seconds (default: 60)"},
                    },
                    "required": ["command"],
                },
                "examples": ["ls -la", "git status", "npm install"],
            }
        ]
    elif server_name == "filesystem":
        return [
            {
                "name": "read_file",
                "description": "Read the contents of a file",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "path": {"type": "string", "description": "Path to the file to read"},
                    },
                    "required": ["path"],
                },
                "examples": ["/path/to/file.txt"],
            },
            {
                "name": "write_file",
                "description": "Write contents to a file",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "path": {"type": "string", "description": "Path to the file to write"},
                        "content": {"type": "string", "description": "Content to write to the file"},
                    },
                    "required": ["path", "content"],
                },
                "examples": [],
            },
            {
                "name": "list_directory",
                "description": "List contents of a directory",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "path": {"type": "string", "description": "Path to the directory to list"},
                    },
                    "required": ["path"],
                },
                "examples": ["/path/to/directory"],
            },
            {
                "name": "search_files",
                "description": "Search for files matching a pattern",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "pattern": {"type": "string", "description": "Search pattern (glob or regex)"},
                        "path": {"type": "string", "description": "Directory to search in"},
                    },
                    "required": ["pattern"],
                },
                "examples": ["*.py", "**/*.js"],
            },
        ]

    return []
