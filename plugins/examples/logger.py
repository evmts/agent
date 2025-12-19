"""Logger plugin - Logs all tool calls and results.

This is an example plugin that demonstrates basic hook usage
for observability and debugging.
"""

__plugin__ = {"api": "1.0", "name": "logger"}

import logging

logger = logging.getLogger("plugin.logger")


@on_begin
async def log_start(ctx):
    """Log when a request starts."""
    logger.info("[logger] Request started: session=%s", ctx.session_id)
    ctx.state["tool_count"] = 0


@on_tool_call
async def log_tool_call(ctx, call):
    """Log each tool call."""
    ctx.state["tool_count"] = ctx.state.get("tool_count", 0) + 1
    logger.info(
        "[logger] Tool call #%d: %s(%s)",
        ctx.state["tool_count"],
        call.tool_name,
        call.input,
    )
    return None  # Don't modify the call


@on_tool_result
async def log_tool_result(ctx, call, result):
    """Log tool results (truncated)."""
    output_preview = result.output[:100] if result.output else ""
    if len(result.output) > 100:
        output_preview += "..."
    logger.info(
        "[logger] Tool result: %s -> %s (success=%s)",
        call.tool_name,
        output_preview,
        result.success,
    )
    return None  # Don't modify the result


@on_done
async def log_end(ctx):
    """Log when a request completes."""
    tool_count = ctx.state.get("tool_count", 0)
    logger.info(
        "[logger] Request completed: session=%s, tools_called=%d",
        ctx.session_id,
        tool_count,
    )
