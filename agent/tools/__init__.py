"""Tools for the agent."""

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

__all__ = [
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
]
