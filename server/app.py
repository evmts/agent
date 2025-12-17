"""
FastAPI application setup and configuration.
"""

import os

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from server.middleware import RequestLoggingMiddleware


# =============================================================================
# Constants
# =============================================================================

DEFAULT_CORS_ORIGINS = "*"
API_TITLE = "OpenCode API"
API_VERSION = "1.0.0"


# =============================================================================
# FastAPI App
# =============================================================================

app = FastAPI(title=API_TITLE, version=API_VERSION)


# =============================================================================
# CORS Configuration
# =============================================================================

# SECURITY NOTE: allow_origins=["*"] is insecure for production environments.
# It allows any origin to make requests, which can lead to CSRF attacks.
# For production, set CORS_ORIGINS environment variable to specific allowed origins:
# Example: CORS_ORIGINS="https://example.com,https://app.example.com"

cors_origins_env = os.environ.get("CORS_ORIGINS", DEFAULT_CORS_ORIGINS)
cors_origins = (
    [origin.strip() for origin in cors_origins_env.split(",")]
    if cors_origins_env != DEFAULT_CORS_ORIGINS
    else [DEFAULT_CORS_ORIGINS]
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Request logging middleware (added after CORS so it runs first)
app.add_middleware(RequestLoggingMiddleware)
