"""
Tests for task management tool.
"""
import asyncio
import pytest

from agent.tools.task import (
    cancel_task,
    create_task,
    get_task_status,
    list_tasks,
    _tasks,
    _running_tasks,
)


@pytest.fixture
def clean_tasks():
    """Clean up task storage before and after tests."""
    _tasks.clear()
    _running_tasks.clear()
    yield
    _tasks.clear()
    _running_tasks.clear()


@pytest.mark.asyncio
async def test_create_task_success(clean_tasks):
    """Test creating a simple task."""
    result = await create_task("Test task", "echo 'Hello World'", timeout=10)

    assert "Task created successfully" in result
    assert "Test task" in result
    assert "echo 'Hello World'" in result
    assert len(_tasks) == 1


@pytest.mark.asyncio
async def test_task_completion(clean_tasks):
    """Test that a task completes successfully."""
    result = await create_task("Echo test", "echo 'test output'", timeout=10)

    # Extract task ID from result
    task_id = None
    for line in result.split("\n"):
        if line.startswith("Task ID:"):
            task_id = line.split(": ")[1].strip()
            break

    assert task_id is not None

    # Wait for task to complete
    await asyncio.sleep(0.5)

    status = await get_task_status(task_id)
    assert "completed" in status.lower() or "running" in status.lower()


@pytest.mark.asyncio
async def test_list_tasks_empty(clean_tasks):
    """Test listing tasks when none exist."""
    result = await list_tasks()
    assert "No tasks found" in result


@pytest.mark.asyncio
async def test_list_tasks_with_tasks(clean_tasks):
    """Test listing tasks when some exist."""
    await create_task("Task 1", "echo 'one'", timeout=10)
    await create_task("Task 2", "echo 'two'", timeout=10)

    result = await list_tasks()
    assert "Task 1" in result
    assert "Task 2" in result
    assert "Total: 2 task(s)" in result


@pytest.mark.asyncio
async def test_cancel_task(clean_tasks):
    """Test cancelling a running task."""
    result = await create_task("Long task", "sleep 10", timeout=30)

    # Extract task ID
    task_id = None
    for line in result.split("\n"):
        if line.startswith("Task ID:"):
            task_id = line.split(": ")[1].strip()
            break

    assert task_id is not None

    # Give task a moment to start
    await asyncio.sleep(0.1)

    cancel_result = await cancel_task(task_id)
    assert "cancellation requested" in cancel_result or "cancelled" in cancel_result


@pytest.mark.asyncio
async def test_get_status_nonexistent_task(clean_tasks):
    """Test getting status of a non-existent task."""
    result = await get_task_status("nonexistent-task-id")
    assert "not found" in result


@pytest.mark.asyncio
async def test_cancel_nonexistent_task(clean_tasks):
    """Test cancelling a non-existent task."""
    result = await cancel_task("nonexistent-task-id")
    assert "not found" in result


@pytest.mark.asyncio
async def test_task_failure(clean_tasks):
    """Test that a failing task is marked as failed."""
    result = await create_task("Failing task", "this-command-does-not-exist", timeout=10)

    # Extract task ID
    task_id = None
    for line in result.split("\n"):
        if line.startswith("Task ID:"):
            task_id = line.split(": ")[1].strip()
            break

    assert task_id is not None

    # Wait for task to fail
    await asyncio.sleep(0.5)

    status = await get_task_status(task_id)
    # Task should either fail or complete with error code
    assert "failed" in status.lower() or "exit code" in status.lower()
