"""
Permission system for runtime approval prompts.

Provides three-tier permission system (ask/allow/deny) for sensitive operations.
"""

from .checker import PermissionChecker
from .dangerous import is_dangerous_bash_command
from .models import (
    Action,
    BashPermission,
    Level,
    PermissionsConfig,
    Request,
    Response,
)
from .patterns import match_pattern
from .store import PermissionStore

__all__ = [
    # Permission levels
    "Level",
    "Action",
    # Models
    "PermissionsConfig",
    "BashPermission",
    "Request",
    "Response",
    # Functions
    "match_pattern",
    "is_dangerous_bash_command",
    # Classes
    "PermissionChecker",
    "PermissionStore",
]
