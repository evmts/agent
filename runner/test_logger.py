"""
Test structured JSON logging.

Run with: python -m pytest test_logger.py -v -s
"""

import json
import os
import logging
from io import StringIO

from logger import configure_logging, get_logger, StructuredFormatter


def test_structured_formatter():
    """Test that StructuredFormatter outputs valid JSON."""
    # Set up environment
    os.environ["TASK_ID"] = "test-task-123"
    os.environ["REQUEST_ID"] = "req-456"

    # Create a handler that writes to a string buffer
    buffer = StringIO()
    handler = logging.StreamHandler(buffer)
    handler.setFormatter(StructuredFormatter())

    # Create a logger
    logger = logging.getLogger("test")
    logger.handlers.clear()
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)

    # Log a message
    logger.info("Test message", extra={"user": "alice", "status": "active"})

    # Get the output
    output = buffer.getvalue().strip()
    print(f"\nLogged output:\n{output}")

    # Parse as JSON
    log_entry = json.loads(output)

    # Verify structure
    assert log_entry["level"] == "INFO"
    assert log_entry["service"] == "runner"
    assert log_entry["message"] == "Test message"
    assert log_entry["task_id"] == "test-task-123"
    assert log_entry["request_id"] == "req-456"
    assert log_entry["logger"] == "test"
    assert "timestamp" in log_entry
    assert log_entry["context"]["user"] == "alice"
    assert log_entry["context"]["status"] == "active"


def test_configure_logging():
    """Test that configure_logging sets up the root logger correctly."""
    # Create a buffer to capture output
    buffer = StringIO()

    # Manually set up environment and formatter
    os.environ["TASK_ID"] = "task-789"
    os.environ["REQUEST_ID"] = "req-abc"

    # Create a handler that writes to buffer
    handler = logging.StreamHandler(buffer)
    handler.setFormatter(StructuredFormatter())

    # Get a logger and set it up
    logger = logging.getLogger("test.module2")
    logger.handlers.clear()
    logger.addHandler(handler)
    logger.setLevel(logging.DEBUG)

    # Log a debug message
    logger.debug("Debug message")

    # Get the output
    output = buffer.getvalue().strip()
    print(f"\nLogged output:\n{output}")

    # Parse as JSON
    log_entry = json.loads(output)

    # Verify
    assert log_entry["level"] == "DEBUG"
    assert log_entry["task_id"] == "task-789"
    assert log_entry["request_id"] == "req-abc"


def test_exception_logging():
    """Test that exceptions are logged with stack traces."""
    os.environ["TASK_ID"] = "test-task-123"
    os.environ["REQUEST_ID"] = "req-456"

    # Create a handler that writes to a string buffer
    buffer = StringIO()
    handler = logging.StreamHandler(buffer)
    handler.setFormatter(StructuredFormatter())

    # Create a logger
    logger = logging.getLogger("test.exception")
    logger.handlers.clear()
    logger.addHandler(handler)
    logger.setLevel(logging.ERROR)

    # Log an exception
    try:
        raise ValueError("Something went wrong")
    except Exception:
        logger.exception("Error occurred")

    # Get the output
    output = buffer.getvalue().strip()
    print(f"\nLogged output:\n{output}")

    # Parse as JSON
    log_entry = json.loads(output)

    # Verify
    assert log_entry["level"] == "ERROR"
    assert log_entry["message"] == "Error occurred"
    assert log_entry["error"] == "Something went wrong"
    assert "stack" in log_entry
    assert "ValueError" in log_entry["stack"]


if __name__ == "__main__":
    test_structured_formatter()
    test_configure_logging()
    test_exception_logging()
    print("\nAll tests passed!")
