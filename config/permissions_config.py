"""PermissionsConfig model and permission checking utilities."""

import logging
from fnmatch import fnmatch

from pydantic import BaseModel, Field


logger = logging.getLogger(__name__)


class PermissionsConfig(BaseModel):
    """Default permissions configuration."""

    edit_patterns: list[str] = Field(
        default_factory=lambda: ["**/*"],
        description="File patterns that can be edited",
    )
    bash_patterns: list[str] = Field(
        default_factory=lambda: ["*"],
        description="Bash command patterns that can be executed",
    )
    webfetch_enabled: bool = Field(
        default=True,
        description="Whether web fetch is enabled",
    )


class PermissionChecker:
    """Utility to check permissions with bypass support."""

    @staticmethod
    def should_skip_checks(bypass_mode: bool, session_id: str | None = None) -> bool:
        """
        Check if permission checks should be skipped.

        Args:
            bypass_mode: If True, skip all permission checks
            session_id: Optional session ID for logging

        Returns:
            True if checks should be skipped, False otherwise
        """
        if bypass_mode:
            session_info = f" (session: {session_id})" if session_id else ""
            logger.warning("⚠️  BYPASS MODE ACTIVE - Skipping permission checks%s", session_info)
            return True
        return False

    @staticmethod
    def check_bash_permission(
        command: str,
        patterns: list[str],
        bypass_mode: bool = False,
        session_id: str | None = None,
    ) -> bool:
        """
        Check if bash command is allowed.

        Args:
            command: The bash command to check
            patterns: List of allowed command patterns (glob patterns)
            bypass_mode: If True, skip permission check
            session_id: Optional session ID for logging

        Returns:
            True if command is allowed, False otherwise
        """
        if PermissionChecker.should_skip_checks(bypass_mode, session_id):
            return True

        # Check if command matches any pattern
        for pattern in patterns:
            if fnmatch(command, pattern):
                return True

        return False

    @staticmethod
    def check_file_permission(
        file_path: str,
        patterns: list[str],
        bypass_mode: bool = False,
        session_id: str | None = None,
    ) -> bool:
        """
        Check if file operation is allowed.

        Args:
            file_path: The file path to check
            patterns: List of allowed file patterns (glob patterns)
            bypass_mode: If True, skip permission check
            session_id: Optional session ID for logging

        Returns:
            True if file operation is allowed, False otherwise
        """
        if PermissionChecker.should_skip_checks(bypass_mode, session_id):
            return True

        # Check if file path matches any pattern
        for pattern in patterns:
            if fnmatch(file_path, pattern):
                return True

        return False

    @staticmethod
    def check_webfetch_permission(
        url: str,
        webfetch_enabled: bool = True,
        bypass_mode: bool = False,
        session_id: str | None = None,
    ) -> bool:
        """
        Check if web fetch is allowed.

        Args:
            url: The URL to fetch
            webfetch_enabled: Whether web fetch is enabled in config
            bypass_mode: If True, skip permission check
            session_id: Optional session ID for logging

        Returns:
            True if web fetch is allowed, False otherwise
        """
        if PermissionChecker.should_skip_checks(bypass_mode, session_id):
            return True

        return webfetch_enabled
