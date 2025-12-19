"""Plugin loader for loading plugins from Python files.

Provides functionality to dynamically load plugins from .py files.
Plugins are Python modules with decorated hook functions.
"""

from __future__ import annotations

import importlib.util
import inspect
import logging
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable

logger = logging.getLogger(__name__)

PLUGIN_API_VERSION = "1.0"


@dataclass
class LoadedPlugin:
    """A plugin loaded from a file.

    Attributes:
        name: Plugin name (from metadata or filename)
        path: Path to the plugin file
        hooks: Dict mapping hook names to handler functions
        metadata: Plugin metadata from __plugin__ dict
    """

    name: str
    path: Path
    hooks: dict[str, Callable[..., Any]] = field(default_factory=dict)
    metadata: dict[str, Any] = field(default_factory=dict)


def load_plugin_from_file(plugin_path: Path) -> LoadedPlugin:
    """Load a plugin from a Python file.

    The plugin file should contain:
    1. An optional __plugin__ dict with metadata
    2. Functions decorated with @on_begin, @on_tool_call, etc.

    Example plugin file:
        __plugin__ = {"api": "1.0", "name": "my_plugin"}

        @on_begin
        async def init(ctx):
            ctx.state["data"] = []

    Args:
        plugin_path: Path to the .py file

    Returns:
        LoadedPlugin with hooks and metadata

    Raises:
        FileNotFoundError: If plugin file doesn't exist
        ImportError: If plugin fails to import
        ValueError: If plugin API version is incompatible
    """
    if not plugin_path.exists():
        raise FileNotFoundError(f"Plugin file not found: {plugin_path}")

    # Read source directly to bypass import caching
    source = plugin_path.read_text()

    # Create a unique module name to avoid conflicts
    import random
    random_suffix = random.randint(0, 2**32)
    module_name = f"plugin_{plugin_path.stem}_{random_suffix}"

    # Create module with necessary namespace
    import types
    module = types.ModuleType(module_name)
    module.__file__ = str(plugin_path)

    # Inject our decorators into module namespace before execution
    from plugins import decorators

    module.on_begin = decorators.on_begin
    module.on_tool_call = decorators.on_tool_call
    module.on_resolve_tool = decorators.on_resolve_tool
    module.on_tool_result = decorators.on_tool_result
    module.on_final = decorators.on_final
    module.on_done = decorators.on_done

    # Also inject models for plugins that need them
    from plugins import models

    module.PluginContext = models.PluginContext
    module.ToolCall = models.ToolCall
    module.ToolResult = models.ToolResult

    # Add to sys.modules temporarily for relative imports within plugin
    sys.modules[module_name] = module

    try:
        # Compile and execute the source directly
        code = compile(source, str(plugin_path), "exec")
        exec(code, module.__dict__)
    except Exception as e:
        # Clean up on failure
        sys.modules.pop(module_name, None)
        raise ImportError(f"Failed to execute plugin {plugin_path}: {e}") from e

    # Extract metadata
    metadata = getattr(
        module,
        "__plugin__",
        {
            "api": PLUGIN_API_VERSION,
            "name": plugin_path.stem,
        },
    )

    # Validate API version
    plugin_api = metadata.get("api", PLUGIN_API_VERSION)
    if not _is_compatible_version(plugin_api, PLUGIN_API_VERSION):
        raise ValueError(
            f"Incompatible plugin API version: {plugin_api} "
            f"(expected {PLUGIN_API_VERSION})"
        )

    # Collect hooks from decorated functions
    hooks: dict[str, Callable[..., Any]] = {}

    for name, obj in inspect.getmembers(module):
        if callable(obj) and hasattr(obj, "_hook_name"):
            hook_name = obj._hook_name
            if hook_name in hooks:
                logger.warning(
                    f"Plugin {plugin_path.stem}: Duplicate hook {hook_name}, "
                    f"using {name}"
                )
            hooks[hook_name] = obj

    # Also check for class-based plugins
    for name, cls in inspect.getmembers(module, inspect.isclass):
        if hasattr(cls, "_plugin_name"):
            try:
                instance = cls()
                for method_name in dir(instance):
                    if method_name.startswith("_"):
                        continue
                    method = getattr(instance, method_name)
                    if callable(method) and hasattr(method, "_hook_name"):
                        hook_name = method._hook_name
                        hooks[hook_name] = method
            except Exception as e:
                logger.warning(
                    f"Plugin {plugin_path.stem}: Failed to instantiate {name}: {e}"
                )

    plugin_name = metadata.get("name", plugin_path.stem)
    logger.debug(
        f"Loaded plugin '{plugin_name}' from {plugin_path} with hooks: {list(hooks.keys())}"
    )

    return LoadedPlugin(
        name=plugin_name,
        path=plugin_path,
        hooks=hooks,
        metadata=metadata,
    )


def _is_compatible_version(plugin_version: str, required_version: str) -> bool:
    """Check if plugin version is compatible with required version.

    For now, we require exact major version match.
    """
    try:
        plugin_major = plugin_version.split(".")[0]
        required_major = required_version.split(".")[0]
        return plugin_major == required_major
    except (IndexError, AttributeError):
        return False
