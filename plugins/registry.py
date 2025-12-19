"""Plugin registry for discovering and managing plugins.

The registry provides a central place to discover, load, and cache plugins.
"""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Optional

from .loader import LoadedPlugin, load_plugin_from_file
from .storage import list_plugins, get_plugin_path, PLUGINS_DIR

logger = logging.getLogger(__name__)


class PluginRegistry:
    """Discovers and manages available plugins.

    The registry caches loaded plugins to avoid reloading them multiple times.
    Use reload() to force a fresh load of a plugin.

    Attributes:
        plugins_dir: Directory to search for plugins
    """

    def __init__(self, plugins_dir: Path | None = None):
        """Initialize the registry.

        Args:
            plugins_dir: Optional custom plugins directory
        """
        self.plugins_dir = plugins_dir or PLUGINS_DIR
        self._loaded: dict[str, LoadedPlugin] = {}

    def discover(self) -> list[str]:
        """Discover all available plugin names.

        Returns:
            List of plugin names (without .py extension)
        """
        return [p.stem for p in list_plugins(self.plugins_dir)]

    def load(self, name: str) -> LoadedPlugin:
        """Load a plugin by name.

        If the plugin is already loaded, returns the cached version.
        Use reload() to force a fresh load.

        Args:
            name: Plugin name (without .py extension)

        Returns:
            The loaded plugin

        Raises:
            ValueError: If the plugin is not found
        """
        if name in self._loaded:
            return self._loaded[name]

        path = get_plugin_path(name, self.plugins_dir)
        if not path:
            raise ValueError(f"Plugin not found: {name}")

        plugin = load_plugin_from_file(path)
        self._loaded[name] = plugin
        logger.debug("Loaded plugin '%s' from %s", name, path)
        return plugin

    def load_many(self, names: list[str]) -> list[LoadedPlugin]:
        """Load multiple plugins in order.

        Args:
            names: List of plugin names to load

        Returns:
            List of loaded plugins in the same order

        Raises:
            ValueError: If any plugin is not found
        """
        return [self.load(name) for name in names]

    def reload(self, name: str) -> LoadedPlugin:
        """Force reload a plugin.

        This clears the cached version and loads fresh from disk.

        Args:
            name: Plugin name (without .py extension)

        Returns:
            The freshly loaded plugin

        Raises:
            ValueError: If the plugin is not found
        """
        if name in self._loaded:
            del self._loaded[name]
        return self.load(name)

    def unload(self, name: str) -> bool:
        """Unload a plugin from the cache.

        Args:
            name: Plugin name (without .py extension)

        Returns:
            True if the plugin was unloaded, False if not in cache
        """
        if name in self._loaded:
            del self._loaded[name]
            logger.debug("Unloaded plugin '%s'", name)
            return True
        return False

    def is_loaded(self, name: str) -> bool:
        """Check if a plugin is loaded in cache.

        Args:
            name: Plugin name (without .py extension)

        Returns:
            True if the plugin is in cache
        """
        return name in self._loaded

    def get_loaded(self, name: str) -> Optional[LoadedPlugin]:
        """Get a loaded plugin from cache without loading.

        Args:
            name: Plugin name (without .py extension)

        Returns:
            The loaded plugin if in cache, None otherwise
        """
        return self._loaded.get(name)

    def clear_cache(self) -> int:
        """Clear all cached plugins.

        Returns:
            Number of plugins cleared from cache
        """
        count = len(self._loaded)
        self._loaded.clear()
        logger.debug("Cleared %d plugins from cache", count)
        return count


# Global registry instance
plugin_registry = PluginRegistry()
