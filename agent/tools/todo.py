"""
Todo management tools for tracking tasks during agent sessions.
"""
import time
import uuid
from typing import Literal

# In-memory storage for todos by session_id
_todo_storage: dict[str, list[dict]] = {}

TodoStatus = Literal["pending", "in_progress", "completed"]


async def todo_write(session_id: str, todos: list[dict]) -> str:
    """
    Replace the entire todo list for a session.

    Args:
        session_id: The session identifier
        todos: List of todo items, each with 'content' and 'status' keys

    Returns:
        Confirmation message with todo count
    """
    # Process and validate todos
    processed_todos = []
    for todo in todos:
        if "content" not in todo or "status" not in todo:
            return "Error: Each todo must have 'content' and 'status' fields"

        # Validate status
        status = todo["status"]
        if status not in ("pending", "in_progress", "completed"):
            return f"Error: Invalid status '{status}'. Must be 'pending', 'in_progress', or 'completed'"

        # Create processed todo with ID and timestamp
        processed_todo = {
            "id": todo.get("id", str(uuid.uuid4())),
            "content": todo["content"],
            "status": status,
            "created_at": todo.get("created_at", time.time()),
        }
        processed_todos.append(processed_todo)

    # Store the todos
    _todo_storage[session_id] = processed_todos

    return f"Todo list updated: {len(processed_todos)} item(s)"


async def todo_read(session_id: str) -> str:
    """
    Read and format the todo list for a session.

    Args:
        session_id: The session identifier

    Returns:
        Formatted todo list with status icons
    """
    todos = _todo_storage.get(session_id, [])

    if not todos:
        return "No todos"

    # Status icons
    status_icons = {
        "pending": "⏳",
        "in_progress": "🔄",
        "completed": "✅",
    }

    # Format todos
    lines = []
    for i, todo in enumerate(todos, 1):
        icon = status_icons.get(todo["status"], "❓")
        lines.append(f"{i}. {icon} {todo['content']} (ID: {todo['id'][:8]})")

    return "\n".join(lines)


async def todo_add(session_id: str, content: str) -> str:
    """
    Add a single todo item to the session.

    Args:
        session_id: The session identifier
        content: The todo content/description

    Returns:
        Confirmation message
    """
    # Get existing todos or create new list
    todos = _todo_storage.get(session_id, [])

    # Create new todo
    new_todo = {
        "id": str(uuid.uuid4()),
        "content": content,
        "status": "pending",
        "created_at": time.time(),
    }

    todos.append(new_todo)
    _todo_storage[session_id] = todos

    return f"Added todo: {content} (ID: {new_todo['id'][:8]})"


async def todo_update(session_id: str, todo_id: str, status: TodoStatus) -> str:
    """
    Update the status of a specific todo.

    Args:
        session_id: The session identifier
        todo_id: The ID of the todo to update (can be partial ID)
        status: The new status

    Returns:
        Confirmation message or error if not found
    """
    # Validate status
    if status not in ("pending", "in_progress", "completed"):
        return f"Error: Invalid status '{status}'. Must be 'pending', 'in_progress', or 'completed'"

    todos = _todo_storage.get(session_id, [])

    if not todos:
        return "Error: No todos found"

    # Find the todo (support partial ID matching)
    matching_todo = None
    for todo in todos:
        if todo["id"].startswith(todo_id) or todo["id"] == todo_id:
            matching_todo = todo
            break

    if matching_todo is None:
        return f"Error: Todo with ID '{todo_id}' not found"

    # Update status
    old_status = matching_todo["status"]
    matching_todo["status"] = status

    return f"Updated todo '{matching_todo['content']}': {old_status} → {status}"
