"""Plugin pipeline for executing hooks across multiple plugins.

The pipeline executes hooks in order across all loaded plugins.
Like Rollup/Vite, transformations chain through plugins.
"""

from __future__ import annotations

import asyncio
import logging
from typing import Any

from .loader import LoadedPlugin
from .models import PluginContext, ToolCall, ToolResult

logger = logging.getLogger(__name__)

DEFAULT_HOOK_TIMEOUT_S = 5.0


class PluginPipeline:
    """Executes hooks across multiple plugins in order.

    Plugins are executed sequentially for each hook. Some hooks
    (like on_tool_call, on_tool_result, on_final) can transform
    their input by returning a modified value.

    The on_resolve_tool hook is special: the first plugin to return
    a non-None result short-circuits further plugin execution.

    Attributes:
        plugins: List of loaded plugins in execution order
        timeout_s: Timeout for each hook call
    """

    def __init__(
        self,
        plugins: list[LoadedPlugin],
        timeout_s: float = DEFAULT_HOOK_TIMEOUT_S,
    ):
        """Initialize the pipeline.

        Args:
            plugins: List of plugins in execution order
            timeout_s: Timeout for each individual hook call
        """
        self.plugins = plugins
        self.timeout_s = timeout_s

    async def on_begin(self, ctx: PluginContext) -> None:
        """Run on_begin for all plugins.

        Called at the start of a request. Plugins should initialize
        their state here.

        Args:
            ctx: Shared plugin context
        """
        for plugin in self.plugins:
            handler = plugin.hooks.get("on_begin")
            if handler:
                try:
                    async with asyncio.timeout(self.timeout_s):
                        await self._call(handler, ctx)
                except asyncio.TimeoutError:
                    logger.warning(
                        f"Plugin {plugin.name} on_begin timed out "
                        f"after {self.timeout_s}s"
                    )
                except Exception as e:
                    logger.warning(f"Plugin {plugin.name} on_begin failed: {e}")

    async def on_tool_call(self, ctx: PluginContext, call: ToolCall) -> ToolCall:
        """Run on_tool_call for all plugins.

        Called before a tool executes. Plugins can modify the tool call
        by returning a new ToolCall object.

        Args:
            ctx: Shared plugin context
            call: The tool call to be made

        Returns:
            Possibly modified ToolCall
        """
        current = call
        for plugin in self.plugins:
            handler = plugin.hooks.get("on_tool_call")
            if handler:
                try:
                    async with asyncio.timeout(self.timeout_s):
                        result = await self._call(handler, ctx, current)
                        if result is not None:
                            current = result
                except asyncio.TimeoutError:
                    logger.warning(
                        f"Plugin {plugin.name} on_tool_call timed out "
                        f"after {self.timeout_s}s"
                    )
                except Exception as e:
                    logger.warning(f"Plugin {plugin.name} on_tool_call failed: {e}")
        return current

    async def on_resolve_tool(
        self, ctx: PluginContext, call: ToolCall
    ) -> ToolResult | None:
        """Run on_resolve_tool. First plugin to return a result wins.

        This hook allows plugins to provide their own tool execution,
        bypassing the default tool. The first plugin to return a
        non-None ToolResult short-circuits further execution.

        Args:
            ctx: Shared plugin context
            call: The tool call to potentially resolve

        Returns:
            ToolResult if a plugin resolved the call, None otherwise
        """
        for plugin in self.plugins:
            handler = plugin.hooks.get("on_resolve_tool")
            if handler:
                try:
                    async with asyncio.timeout(self.timeout_s):
                        result = await self._call(handler, ctx, call)
                        if result is not None:
                            logger.debug(
                                f"Plugin {plugin.name} resolved tool {call.tool_name}"
                            )
                            return result  # Short-circuit!
                except asyncio.TimeoutError:
                    logger.warning(
                        f"Plugin {plugin.name} on_resolve_tool timed out "
                        f"after {self.timeout_s}s"
                    )
                except Exception as e:
                    logger.warning(f"Plugin {plugin.name} on_resolve_tool failed: {e}")
        return None  # No plugin handled it

    async def on_tool_result(
        self, ctx: PluginContext, call: ToolCall, result: ToolResult
    ) -> ToolResult:
        """Run on_tool_result for all plugins.

        Called after a tool executes. Plugins can transform the result
        by returning a new ToolResult object.

        Args:
            ctx: Shared plugin context
            call: The tool call that was made
            result: The result from tool execution

        Returns:
            Possibly transformed ToolResult
        """
        current = result
        for plugin in self.plugins:
            handler = plugin.hooks.get("on_tool_result")
            if handler:
                try:
                    async with asyncio.timeout(self.timeout_s):
                        transformed = await self._call(handler, ctx, call, current)
                        if transformed is not None:
                            current = transformed
                except asyncio.TimeoutError:
                    logger.warning(
                        f"Plugin {plugin.name} on_tool_result timed out "
                        f"after {self.timeout_s}s"
                    )
                except Exception as e:
                    logger.warning(f"Plugin {plugin.name} on_tool_result failed: {e}")
        return current

    async def on_final(self, ctx: PluginContext, text: str) -> str:
        """Run on_final for all plugins.

        Called before the final response is returned. Plugins can
        transform the text by returning a new string.

        Args:
            ctx: Shared plugin context
            text: The final response text

        Returns:
            Possibly transformed text
        """
        current = text
        for plugin in self.plugins:
            handler = plugin.hooks.get("on_final")
            if handler:
                try:
                    async with asyncio.timeout(self.timeout_s):
                        transformed = await self._call(handler, ctx, current)
                        if transformed is not None:
                            current = transformed
                except asyncio.TimeoutError:
                    logger.warning(
                        f"Plugin {plugin.name} on_final timed out "
                        f"after {self.timeout_s}s"
                    )
                except Exception as e:
                    logger.warning(f"Plugin {plugin.name} on_final failed: {e}")
        return current

    async def on_done(self, ctx: PluginContext) -> None:
        """Run on_done for all plugins.

        Called at the end of a request. Plugins should do cleanup here.

        Args:
            ctx: Shared plugin context
        """
        for plugin in self.plugins:
            handler = plugin.hooks.get("on_done")
            if handler:
                try:
                    async with asyncio.timeout(self.timeout_s):
                        await self._call(handler, ctx)
                except asyncio.TimeoutError:
                    logger.warning(
                        f"Plugin {plugin.name} on_done timed out "
                        f"after {self.timeout_s}s"
                    )
                except Exception as e:
                    logger.warning(f"Plugin {plugin.name} on_done failed: {e}")

    async def _call(self, handler: Any, *args: Any) -> Any:
        """Call a handler, handling both sync and async functions.

        Args:
            handler: The function to call
            *args: Arguments to pass to the handler

        Returns:
            The handler's return value
        """
        if asyncio.iscoroutinefunction(handler):
            return await handler(*args)
        return handler(*args)

    def __len__(self) -> int:
        """Return the number of plugins in the pipeline."""
        return len(self.plugins)

    def __bool__(self) -> bool:
        """Return True if there are any plugins."""
        return len(self.plugins) > 0
