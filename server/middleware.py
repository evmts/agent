"""HTTP middleware for request/response logging."""

import logging
import time

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response

logger = logging.getLogger(__name__)

# Slow request threshold in milliseconds
SLOW_REQUEST_THRESHOLD_MS = 1000


class RequestLoggingMiddleware(BaseHTTPMiddleware):
    """Middleware that logs all HTTP requests with timing information.

    Log levels:
    - DEBUG: Request start
    - INFO: Successful responses
    - WARNING: 4xx errors, slow requests (>1s)
    - ERROR: 5xx errors
    """

    async def dispatch(self, request: Request, call_next) -> Response:
        """Process request and log timing/status information."""
        start_time = time.perf_counter()

        # Log request start at DEBUG level (only visible when debugging)
        logger.debug("%s %s", request.method, request.url.path)

        response = await call_next(request)

        duration_ms = (time.perf_counter() - start_time) * 1000

        # Log based on status code and duration
        self._log_response(request, response, duration_ms)

        return response

    def _log_response(
        self, request: Request, response: Response, duration_ms: float
    ) -> None:
        """Log response with appropriate level based on status and duration."""
        method = request.method
        path = request.url.path
        status = response.status_code

        if status >= 500:
            logger.error("%s %s -> %d (%.1fms)", method, path, status, duration_ms)
        elif status >= 400:
            logger.warning("%s %s -> %d (%.1fms)", method, path, status, duration_ms)
        elif duration_ms > SLOW_REQUEST_THRESHOLD_MS:
            logger.warning(
                "%s %s -> %d (%.1fms) SLOW", method, path, status, duration_ms
            )
        else:
            logger.info("%s %s -> %d (%.1fms)", method, path, status, duration_ms)
