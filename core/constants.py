"""
Core constants for the agent system.

This module defines system-wide constants used across the codebase.
Following the style guide: no magic constants in code.
"""

# Web fetch limits
MAX_RESPONSE_SIZE = 5 * 1024 * 1024  # 5MB - maximum size for HTTP responses
DEFAULT_WEB_TIMEOUT = 30  # 30 seconds - default timeout for web requests
MAX_WEB_TIMEOUT = 120  # 120 seconds - maximum allowed timeout for web requests
