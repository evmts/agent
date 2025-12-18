"""
OpenCode-compatible API server.

Implements the OpenCode API specification for use with OpenCode clients
(including Go Bubbletea TUI).
"""

from .app import app
from .routes import register_routes
from .state import get_agent, set_agent, set_permission_checker, get_permission_checker

# Register all routes with the app
register_routes(app)

__all__ = ["app", "set_agent", "get_agent", "set_permission_checker", "get_permission_checker"]
