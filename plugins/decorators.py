"""Decorator-based plugin authoring API.

Provides decorators for defining plugin hooks:
- @on_begin: Called at start of request
- @on_tool_call: Called before tool executes
- @on_resolve_tool: Can short-circuit tool execution
- @on_tool_result: Called after tool executes
- @on_final: Called before final response
- @on_done: Called when request completes

Example usage:
    @on_begin
    async def init(ctx: PluginContext):
        ctx.state["counter"] = 0

    @on_tool_call
    async def log_tool(ctx: PluginContext, call: ToolCall) -> ToolCall | None:
        print(f"Tool called: {call.tool_name}")
        return None  # Don't modify
"""

from typing import Callable, TypeVar

F = TypeVar("F", bound=Callable)


def on_begin(fn: F) -> F:
    """Hook: Called at start of request.

    Use this to initialize plugin state.

    Args:
        fn: Async function with signature (ctx: PluginContext) -> None

    Returns:
        The decorated function with hook metadata attached.
    """
    fn._hook_name = "on_begin"  # type: ignore[attr-defined]
    return fn


def on_tool_call(fn: F) -> F:
    """Hook: Called before tool executes.

    Can modify or block tool calls. Return modified ToolCall or None.

    Args:
        fn: Async function with signature
            (ctx: PluginContext, call: ToolCall) -> ToolCall | None

    Returns:
        The decorated function with hook metadata attached.
    """
    fn._hook_name = "on_tool_call"  # type: ignore[attr-defined]
    return fn


def on_resolve_tool(fn: F) -> F:
    """Hook: Can provide tool result, short-circuiting execution.

    Return a ToolResult to bypass default tool execution, or None to
    let the default execution happen.

    Args:
        fn: Async function with signature
            (ctx: PluginContext, call: ToolCall) -> ToolResult | None

    Returns:
        The decorated function with hook metadata attached.
    """
    fn._hook_name = "on_resolve_tool"  # type: ignore[attr-defined]
    return fn


def on_tool_result(fn: F) -> F:
    """Hook: Called after tool executes.

    Can transform the tool result. Return modified ToolResult or None.

    Args:
        fn: Async function with signature
            (ctx: PluginContext, call: ToolCall, result: ToolResult) -> ToolResult | None

    Returns:
        The decorated function with hook metadata attached.
    """
    fn._hook_name = "on_tool_result"  # type: ignore[attr-defined]
    return fn


def on_final(fn: F) -> F:
    """Hook: Called before final text is returned.

    Can transform the final response text. Return modified text or None.

    Args:
        fn: Async function with signature
            (ctx: PluginContext, text: str) -> str | None

    Returns:
        The decorated function with hook metadata attached.
    """
    fn._hook_name = "on_final"  # type: ignore[attr-defined]
    return fn


def on_done(fn: F) -> F:
    """Hook: Called at end of request.

    Use this for cleanup. Cannot modify anything at this point.

    Args:
        fn: Async function with signature (ctx: PluginContext) -> None

    Returns:
        The decorated function with hook metadata attached.
    """
    fn._hook_name = "on_done"  # type: ignore[attr-defined]
    return fn
