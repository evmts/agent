"""Plugin models for the plugin system.

Defines the core data structures used by plugins:
- PluginContext: Shared context passed to all plugin hooks
- ToolCall: Represents a tool invocation
- ToolResult: Result from a tool execution
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Callable, Awaitable, Optional, Protocol, runtime_checkable


@dataclass
class PluginContext:
    """Shared context for all plugins during a request.

    This context is passed to every hook and is shared across all plugins
    in the pipeline. Plugins can use `state` to store data between hooks
    and `memory` to inject context into the agent.

    Attributes:
        session_id: The current session identifier
        working_dir: Working directory for file operations
        user_text: The user's original message text

        state: Mutable dict for plugin state (shared across hooks within a request)
        memory: List to inject context into the agent (shared across plugins)
    """

    session_id: str
    working_dir: str
    user_text: str

    # Mutable state shared across plugins for this request
    state: dict[str, Any] = field(default_factory=dict)

    # Memory to inject into agent context (shared across plugins)
    memory: list[dict[str, Any]] = field(default_factory=list)


@dataclass
class ToolCall:
    """Represents a tool invocation.

    Created when the agent decides to call a tool. Plugins can inspect
    or modify this before the tool executes.

    Attributes:
        tool_name: Name of the tool being called
        tool_call_id: Unique identifier for this tool call
        input: Arguments passed to the tool
    """

    tool_name: str
    tool_call_id: str
    input: dict[str, Any]


@dataclass
class ToolResult:
    """Result from a tool execution.

    Contains the output from a tool call. Plugins can transform this
    before it's returned to the agent.

    Attributes:
        tool_call_id: ID of the tool call this result is for
        tool_name: Name of the tool that was called
        output: The tool's output as a string
        success: Whether the tool execution succeeded
        error: Error message if the tool failed
    """

    tool_call_id: str
    tool_name: str
    output: str
    success: bool = True
    error: str | None = None


@runtime_checkable
class Plugin(Protocol):
    """Protocol for plugin implementations.

    Plugins can implement any subset of these hooks. All hooks are optional.
    """

    name: str

    async def on_begin(self, ctx: PluginContext) -> None:
        """Called at the start of a request. Initialize state here."""
        ...

    async def on_tool_call(
        self, ctx: PluginContext, call: ToolCall
    ) -> ToolCall | None:
        """Called before a tool executes. Return modified call or None."""
        ...

    async def on_resolve_tool(
        self, ctx: PluginContext, call: ToolCall
    ) -> ToolResult | None:
        """Return a ToolResult to short-circuit execution, or None for default."""
        ...

    async def on_tool_result(
        self, ctx: PluginContext, call: ToolCall, result: ToolResult
    ) -> ToolResult | None:
        """Called after tool executes. Return modified result or None."""
        ...

    async def on_final(self, ctx: PluginContext, text: str) -> str | None:
        """Called before final response. Return modified text or None."""
        ...

    async def on_done(self, ctx: PluginContext) -> None:
        """Called when request completes. Cleanup here."""
        ...
