"""
Structured JSON logging for the Plue Runner.

Outputs JSON logs compatible with Loki/Grafana ingestion.
Each log entry includes:
- timestamp: ISO 8601 timestamp
- level: Log level (DEBUG, INFO, WARNING, ERROR, CRITICAL)
- service: Always "runner"
- request_id: Request ID propagated from edge/server
- task_id: Current task identifier
- message: Log message
- context: Additional context fields
"""

import json
import logging
import os
import sys
from datetime import datetime
from typing import Optional, Dict, Any


class StructuredFormatter(logging.Formatter):
    """
    Custom formatter that outputs JSON logs with structured fields.

    Each log record is formatted as a single JSON object with:
    - timestamp: ISO 8601 timestamp
    - level: Log level name
    - service: Service name (runner)
    - request_id: Request ID from environment or context
    - task_id: Task ID from environment or context
    - logger: Logger name (module path)
    - message: Formatted log message
    - context: Additional context from extra fields
    - error: Error message (if exception)
    - stack: Stack trace (if exception)
    """

    def __init__(self):
        super().__init__()
        self.service = "runner"
        # Get task_id and request_id from environment (set by container)
        self.task_id = os.environ.get("TASK_ID", "unknown")
        self.request_id = os.environ.get("REQUEST_ID", "unknown")

    def format(self, record: logging.LogRecord) -> str:
        """Format a log record as JSON."""
        # Build base log entry
        log_entry: Dict[str, Any] = {
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "level": record.levelname,
            "service": self.service,
            "logger": record.name,
            "message": record.getMessage(),
        }

        # Add task_id and request_id if available
        # Check record first (set via extra={}), then fall back to environment
        task_id = getattr(record, "task_id", self.task_id)
        request_id = getattr(record, "request_id", self.request_id)

        if task_id and task_id != "unknown":
            log_entry["task_id"] = task_id
        if request_id and request_id != "unknown":
            log_entry["request_id"] = request_id

        # Add context from extra fields
        # Any fields passed via extra={} that aren't standard fields
        context = {}
        for key, value in record.__dict__.items():
            if key not in {
                'name', 'msg', 'args', 'created', 'filename', 'funcName',
                'levelname', 'levelno', 'lineno', 'module', 'msecs',
                'message', 'pathname', 'process', 'processName', 'relativeCreated',
                'thread', 'threadName', 'exc_info', 'exc_text', 'stack_info',
                'task_id', 'request_id', 'taskName'  # Filter out LogRecord internal fields
            }:
                # Only add non-None values to avoid clutter
                if value is not None:
                    context[key] = value

        if context:
            log_entry["context"] = context

        # Add exception info if present
        if record.exc_info:
            log_entry["error"] = str(record.exc_info[1])
            if record.exc_text:
                log_entry["stack"] = record.exc_text
            else:
                import traceback
                log_entry["stack"] = "".join(traceback.format_exception(*record.exc_info))

        # Output as single-line JSON
        return json.dumps(log_entry)


def configure_logging(level: str = "INFO", task_id: Optional[str] = None, request_id: Optional[str] = None) -> None:
    """
    Configure the root logger to use structured JSON output.

    Args:
        level: Log level (DEBUG, INFO, WARNING, ERROR, CRITICAL)
        task_id: Task identifier (defaults to TASK_ID env var)
        request_id: Request identifier (defaults to REQUEST_ID env var)
    """
    # Update environment variables if provided
    if task_id:
        os.environ["TASK_ID"] = task_id
    if request_id:
        os.environ["REQUEST_ID"] = request_id

    # Create handler that writes to stdout
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(StructuredFormatter())

    # Configure root logger
    root_logger = logging.getLogger()
    root_logger.handlers.clear()  # Remove any existing handlers
    root_logger.addHandler(handler)
    root_logger.setLevel(getattr(logging, level.upper(), logging.INFO))


def get_logger(name: str) -> logging.Logger:
    """
    Get a logger instance with the given name.

    The logger will use the structured formatter configured via configure_logging().

    Args:
        name: Logger name (typically __name__)

    Returns:
        Logger instance
    """
    return logging.getLogger(name)
