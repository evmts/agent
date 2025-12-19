"""Footer plugin - Adds a footer to all responses.

This is an example plugin that demonstrates the on_final hook
for transforming the agent's final response.
"""

__plugin__ = {"api": "1.0", "name": "footer"}


@on_begin
async def init(ctx):
    """Initialize tool tracking."""
    ctx.state["tools_used"] = []


@on_tool_call
async def track_tool(ctx, call):
    """Track which tools were used."""
    if call.tool_name not in ctx.state["tools_used"]:
        ctx.state["tools_used"].append(call.tool_name)
    return None


@on_final
async def add_footer(ctx, text):
    """Add a footer with session info."""
    tools_used = ctx.state.get("tools_used", [])
    footer_parts = [
        "",
        "---",
        f"Session: {ctx.session_id}",
    ]
    if tools_used:
        footer_parts.append(f"Tools used: {', '.join(tools_used)}")

    return text + "\n".join(footer_parts)
