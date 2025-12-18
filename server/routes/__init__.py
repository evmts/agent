"""
Route registration for the OpenCode API.
"""

from fastapi import FastAPI

from . import agents, app as app_routes, commands, config, events, health, mcp, messages, permissions, project, sessions, tools


def register_routes(app: FastAPI) -> None:
    """Register all routes with the FastAPI application."""
    app.include_router(agents.router)
    app.include_router(app_routes.router)
    app.include_router(commands.router)
    app.include_router(config.router)
    app.include_router(events.router)
    app.include_router(health.router)
    app.include_router(mcp.router)
    app.include_router(permissions.router)
    app.include_router(project.router)
    sessions.register_routes(app)
    messages.register_routes(app)
    tools.register_routes(app)
