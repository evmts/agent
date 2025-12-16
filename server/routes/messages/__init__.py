"""
Message route registration.
"""

from fastapi import FastAPI

from . import get, list, send


def register_routes(app: FastAPI) -> None:
    """Register all message routes."""
    app.include_router(list.router)
    app.include_router(get.router)
    app.include_router(send.router)
