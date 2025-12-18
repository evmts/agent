"""Tools for the agent."""

from .grep import grep
from .lsp import (
    Diagnostic,
    DiagnosticSeverity,
    DiagnosticsResult,
    diagnostics,
    get_all_diagnostics_summary,
    get_lsp_manager,
    hover,
    touch_file,
)
from .multiedit import (
    MULTIEDIT_DESCRIPTION,
    multiedit,
)
from .patch import (
    PATCH_DESCRIPTION,
    patch,
)

__all__ = [
    # Search tools
    "grep",
    # LSP tools
    "Diagnostic",
    "DiagnosticSeverity",
    "DiagnosticsResult",
    "diagnostics",
    "get_all_diagnostics_summary",
    "get_lsp_manager",
    "hover",
    "touch_file",
    # Edit tools
    "multiedit",
    "MULTIEDIT_DESCRIPTION",
    "patch",
    "PATCH_DESCRIPTION",
]
