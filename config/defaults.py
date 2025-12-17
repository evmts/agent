"""Default configuration values."""

DEFAULT_MODEL = "claude-opus-4-5-20251101"

# LSP Configuration
LSP_INIT_TIMEOUT_SECONDS = 5.0
LSP_REQUEST_TIMEOUT_SECONDS = 2.0
LSP_MAX_CLIENTS = 10

LSP_SERVERS = {
    "python": {
        "extensions": [".py", ".pyi"],
        "command": ["pylsp"],
        "root_markers": ["pyproject.toml", "setup.py", "setup.cfg", "requirements.txt", ".git"],
    },
    "typescript": {
        "extensions": [".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs"],
        "command": ["typescript-language-server", "--stdio"],
        "root_markers": ["package.json", "tsconfig.json", ".git"],
    },
    "go": {
        "extensions": [".go"],
        "command": ["gopls"],
        "root_markers": ["go.mod", "go.work", ".git"],
    },
    "rust": {
        "extensions": [".rs"],
        "command": ["rust-analyzer"],
        "root_markers": ["Cargo.toml", ".git"],
    },
}
