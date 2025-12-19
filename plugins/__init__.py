"""Plugin system for agent customization.

This module provides a Vite/Rollup-style plugin system where plugins are middleware
that intercept the main agent loop. Plugins can:

1. Run INSIDE the agent loop - not separately
2. Multiple plugins form a pipeline - executed in order at each hook point
3. Intercept lifecycle events - on_begin, on_tool_call, on_tool_result, on_final, etc.
"""

from .models import PluginContext, ToolCall, ToolResult
from .decorators import (
    on_begin,
    on_tool_call,
    on_resolve_tool,
    on_tool_result,
    on_final,
    on_done,
)
from .loader import LoadedPlugin, load_plugin_from_file
from .pipeline import PluginPipeline
from .storage import (
    save_plugin,
    list_plugins,
    get_plugin_path,
    get_plugin_content,
    delete_plugin,
    plugin_exists,
)
from .registry import PluginRegistry, plugin_registry
from .script_mode import get_plugin_author_prompt

__all__ = [
    # Models
    "PluginContext",
    "ToolCall",
    "ToolResult",
    # Decorators
    "on_begin",
    "on_tool_call",
    "on_resolve_tool",
    "on_tool_result",
    "on_final",
    "on_done",
    # Loader
    "LoadedPlugin",
    "load_plugin_from_file",
    # Pipeline
    "PluginPipeline",
    # Storage
    "save_plugin",
    "list_plugins",
    "get_plugin_path",
    "get_plugin_content",
    "delete_plugin",
    "plugin_exists",
    # Registry
    "PluginRegistry",
    "plugin_registry",
    # Script mode
    "get_plugin_author_prompt",
]
