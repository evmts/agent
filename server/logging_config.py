"""Centralized logging configuration for the agent server."""

import logging
import os
import sys
import time
from contextlib import contextmanager
from functools import wraps
from typing import Callable, Generator, Optional, TypeVar

# Log format constants
SIMPLE_FORMAT = "%(asctime)s | %(levelname)-8s | %(name)s | %(message)s"
DETAILED_FORMAT = (
    "%(asctime)s | %(levelname)-8s | %(name)s:%(funcName)s:%(lineno)d | %(message)s"
)

# Environment variable names
LOG_LEVEL_ENV = "LOG_LEVEL"

# Default values
DEFAULT_LOG_LEVEL = "INFO"

T = TypeVar("T")


def setup_logging(level: Optional[str] = None) -> None:
    """Configure logging for the entire application.

    Args:
        level: Log level override. If not provided, uses LOG_LEVEL env var or INFO.
    """
    level_name = (level or os.environ.get(LOG_LEVEL_ENV, DEFAULT_LOG_LEVEL)).upper()
    log_level = getattr(logging, level_name, logging.INFO)

    # Use simple format for INFO+, detailed format with line numbers for DEBUG
    fmt = DETAILED_FORMAT if log_level == logging.DEBUG else SIMPLE_FORMAT

    logging.basicConfig(
        level=log_level,
        format=fmt,
        datefmt="%Y-%m-%d %H:%M:%S",
        stream=sys.stdout,
        force=True,
    )

    # Quiet noisy third-party libraries
    logging.getLogger("httpx").setLevel(logging.WARNING)
    logging.getLogger("httpcore").setLevel(logging.WARNING)
    logging.getLogger("uvicorn.access").setLevel(logging.WARNING)
    logging.getLogger("uvicorn.error").setLevel(logging.INFO)


@contextmanager
def log_timing(
    logger: logging.Logger, operation: str, level: int = logging.DEBUG
) -> Generator[None, None, None]:
    """Context manager for timing operations.

    Args:
        logger: Logger instance to use.
        operation: Name of the operation being timed.
        level: Log level for the timing message (default: DEBUG).

    Example:
        with log_timing(logger, "Database query"):
            result = db.query(...)
    """
    start = time.perf_counter()
    try:
        yield
    finally:
        duration_ms = (time.perf_counter() - start) * 1000
        logger.log(level, "%s completed in %.1fms", operation, duration_ms)


def timed(
    operation: Optional[str] = None, level: int = logging.DEBUG
) -> Callable[[Callable[..., T]], Callable[..., T]]:
    """Decorator for timing async functions.

    Args:
        operation: Name of the operation. Defaults to function name.
        level: Log level for the timing message (default: DEBUG).

    Example:
        @timed("fetch_user_data")
        async def get_user(user_id: str):
            ...
    """

    def decorator(func: Callable[..., T]) -> Callable[..., T]:
        op_name = operation or func.__name__

        @wraps(func)
        async def wrapper(*args, **kwargs) -> T:
            logger = logging.getLogger(func.__module__)
            start = time.perf_counter()
            try:
                return await func(*args, **kwargs)
            finally:
                duration_ms = (time.perf_counter() - start) * 1000
                logger.log(level, "%s completed in %.1fms", op_name, duration_ms)

        return wrapper

    return decorator
