"""
Agent server entry point with MCP support.
"""
import asyncio
import os
from contextlib import asynccontextmanager

import uvicorn
from fastapi import FastAPI

from agent import create_mcp_wrapper, create_simple_wrapper
from server import app, set_agent

# Constants
DEFAULT_MODEL = "claude-sonnet-4-20250514"
DEFAULT_HOST = "0.0.0.0"
DEFAULT_PORT = 8000
DEFAULT_USE_MCP = True

_wrapper_context = None
_wrapper = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Manage MCP wrapper lifecycle with FastAPI lifespan."""
    global _wrapper_context, _wrapper

    model_id = os.environ.get("ANTHROPIC_MODEL", DEFAULT_MODEL)
    working_dir = os.environ.get("WORKING_DIR", os.getcwd())
    use_mcp = os.environ.get("USE_MCP", str(DEFAULT_USE_MCP).lower()).lower() == "true"

    print(f"Starting agent server...")
    print(f"Using model: {model_id}")
    print(f"Working directory: {working_dir}")
    print(f"MCP enabled: {use_mcp}")

    if use_mcp:
        print("Initializing MCP servers...")
        _wrapper_context = create_mcp_wrapper(
            model_id=model_id,
            working_dir=working_dir,
        )
        _wrapper = await _wrapper_context.__aenter__()
        set_agent(_wrapper)
        print("MCP servers ready")
    else:
        print("Using simple wrapper (no MCP)")
        _wrapper = create_simple_wrapper(model_id=model_id)
        set_agent(_wrapper)

    yield

    # Cleanup
    if use_mcp and _wrapper_context:
        print("Shutting down MCP servers...")
        await _wrapper_context.__aexit__(None, None, None)
        print("MCP servers stopped")


app.router.lifespan_context = lifespan


def main() -> None:
    """Start server with MCP support."""
    host = os.environ.get("HOST", DEFAULT_HOST)
    port = int(os.environ.get("PORT", str(DEFAULT_PORT)))

    print(f"Server will listen on {host}:{port}")
    uvicorn.run(app, host=host, port=port)


if __name__ == "__main__":
    main()
