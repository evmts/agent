"""
Task management for async operations.
"""
import asyncio
import time
import uuid
from dataclasses import dataclass
from typing import Any


@dataclass
class TaskInfo:
    """Information about a background task."""
    id: str
    description: str
    status: str  # "pending", "running", "completed", "failed"
    result: str | None
    error: str | None
    created_at: float


# Global task storage
_tasks: dict[str, TaskInfo] = {}
_running_tasks: dict[str, asyncio.Task] = {}


async def _run_command_task(task_id: str, command: str, timeout: int) -> None:
    """
    Internal function to run a command as a background task.

    Args:
        task_id: Unique task identifier
        command: Shell command to execute
        timeout: Maximum execution time in seconds
    """
    task_info = _tasks[task_id]
    task_info.status = "running"

    try:
        # Import here to avoid circular dependency
        from .code_execution import execute_shell

        result = await execute_shell(command, timeout=timeout)
        task_info.status = "completed"
        task_info.result = result

    except asyncio.CancelledError:
        task_info.status = "cancelled"
        task_info.error = "Task was cancelled"
        raise

    except Exception as e:
        task_info.status = "failed"
        task_info.error = str(e)

    finally:
        # Clean up the running task reference
        if task_id in _running_tasks:
            del _running_tasks[task_id]


async def create_task(description: str, command: str, timeout: int = 300) -> str:
    """
    Create a background task that runs a shell command.

    Args:
        description: Human-readable description of the task
        command: Shell command to execute
        timeout: Maximum execution time in seconds (default: 300)

    Returns:
        Task ID that can be used to check status
    """
    task_id = str(uuid.uuid4())

    # Create task info
    task_info = TaskInfo(
        id=task_id,
        description=description,
        status="pending",
        result=None,
        error=None,
        created_at=time.time(),
    )

    _tasks[task_id] = task_info

    # Start the background task
    background_task = asyncio.create_task(_run_command_task(task_id, command, timeout))
    _running_tasks[task_id] = background_task

    return (
        f"Task created successfully\n"
        f"Task ID: {task_id}\n"
        f"Description: {description}\n"
        f"Command: {command}\n"
        f"Timeout: {timeout}s\n"
        f"\n"
        f"Use get_task_status('{task_id}') to check the status."
    )


async def get_task_status(task_id: str) -> str:
    """
    Get the status of a background task.

    Args:
        task_id: Task identifier

    Returns:
        Formatted status information
    """
    if task_id not in _tasks:
        return f"Error: Task '{task_id}' not found"

    task = _tasks[task_id]
    elapsed = time.time() - task.created_at

    output = [
        f"Task ID: {task.id}",
        f"Description: {task.description}",
        f"Status: {task.status}",
        f"Elapsed time: {elapsed:.1f}s",
    ]

    if task.status == "completed" and task.result:
        output.append(f"\nResult:\n{task.result}")
    elif task.status == "failed" and task.error:
        output.append(f"\nError:\n{task.error}")
    elif task.status == "cancelled" and task.error:
        output.append(f"\nCancelled:\n{task.error}")
    elif task.status == "running":
        output.append("\nTask is still running...")
    elif task.status == "pending":
        output.append("\nTask is pending execution...")

    return "\n".join(output)


async def list_tasks() -> str:
    """
    List all tasks with their statuses.

    Returns:
        Formatted list of tasks (most recent first)
    """
    if not _tasks:
        return "No tasks found"

    # Sort by creation time (most recent first)
    sorted_tasks = sorted(_tasks.values(), key=lambda t: t.created_at, reverse=True)

    output = ["Background Tasks:", "=" * 80]

    for task in sorted_tasks:
        elapsed = time.time() - task.created_at
        status_symbol = {
            "pending": "⏳",
            "running": "🔄",
            "completed": "✓",
            "failed": "✗",
            "cancelled": "⊗",
        }.get(task.status, "?")

        output.append(
            f"\n{status_symbol} [{task.status.upper()}] {task.id[:8]}... ({elapsed:.1f}s)"
        )
        output.append(f"  {task.description}")

        if task.status == "failed" and task.error:
            # Show first line of error
            error_line = task.error.split("\n")[0]
            output.append(f"  Error: {error_line}")

    output.append("\n" + "=" * 80)
    output.append(f"Total: {len(_tasks)} task(s)")

    return "\n".join(output)


async def cancel_task(task_id: str) -> str:
    """
    Cancel a running task.

    Args:
        task_id: Task identifier

    Returns:
        Confirmation message
    """
    if task_id not in _tasks:
        return f"Error: Task '{task_id}' not found"

    task = _tasks[task_id]

    if task.status not in ["pending", "running"]:
        return f"Error: Task '{task_id}' is {task.status} and cannot be cancelled"

    if task_id in _running_tasks:
        _running_tasks[task_id].cancel()
        return (
            f"Task '{task_id}' cancellation requested\n"
            f"Description: {task.description}\n"
            f"Status will be updated to 'cancelled' shortly."
        )
    else:
        # Task is pending but hasn't started yet
        task.status = "cancelled"
        task.error = "Task was cancelled before execution"
        return (
            f"Task '{task_id}' cancelled\n"
            f"Description: {task.description}"
        )
