"""
Route registration for the OpenCode API.
"""

from fastapi import FastAPI

from . import events, health, mcp, messages, sessions, tools


def register_routes(app: FastAPI) -> None:
    """Register all routes with the FastAPI application."""
    app.include_router(events.router)
    app.include_router(health.router)
    app.include_router(mcp.router)
    sessions.register_routes(app)
    messages.register_routes(app)
    tools.register_routes(app)
