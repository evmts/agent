"""
Agent server entry point.
"""
import os

import uvicorn

from agent import AgentWrapper, create_agent
from server import app, set_agent


def main() -> None:
    """Initialize agent and start server."""
    # Create Pydantic AI agent
    model_id = os.environ.get("ANTHROPIC_MODEL", "claude-sonnet-4-20250514")
    pydantic_agent = create_agent(model_id=model_id)

    # Wrap for server compatibility
    wrapped_agent = AgentWrapper(pydantic_agent)

    # Register with server
    set_agent(wrapped_agent)

    # Start server
    host = os.environ.get("HOST", "0.0.0.0")
    port = int(os.environ.get("PORT", "8000"))

    print(f"Starting agent server on {host}:{port}")
    print(f"Using model: {model_id}")

    uvicorn.run(app, host=host, port=port)


if __name__ == "__main__":
    main()
