"""
Tools route registration.
"""

from fastapi import FastAPI

from . import get, list


def register_routes(app: FastAPI) -> None:
    """Register all tools routes."""
    app.include_router(list.router)
    app.include_router(get.router)
