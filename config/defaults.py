"""Default configuration values."""

DEFAULT_MODEL = "claude-opus-4-5-20251101"
DEFAULT_REASONING_EFFORT = "medium"
DEFAULT_REVIEW_MODEL = "claude-sonnet-4-20250514"  # Use faster model for code reviews

# Available models configuration
AVAILABLE_MODELS = [
    {
        "id": "claude-opus-4-5-20251101",
        "name": "Claude Opus 4.5",
        "context_window": 200000,
        "supports_reasoning": True,
        "reasoning_levels": ["minimal", "low", "medium", "high"],
    },
    {
        "id": "claude-sonnet-4-20250514",
        "name": "Claude Sonnet 4",
        "context_window": 200000,
        "supports_reasoning": True,
        "reasoning_levels": ["minimal", "low", "medium", "high"],
    },
    {
        "id": "claude-haiku-3-5-20241022",
        "name": "Claude Haiku 3.5",
        "context_window": 200000,
        "supports_reasoning": False,
    },
]

# Model provider configurations
DEFAULT_MODEL_PROVIDERS = {
    "anthropic": {
        "name": "Anthropic",
        "base_url": "https://api.anthropic.com/v1",
        "env_key": "ANTHROPIC_API_KEY",
        "default_model": "claude-sonnet-4-20250514",
    },
    "openai": {
        "name": "OpenAI",
        "base_url": "https://api.openai.com/v1",
        "env_key": "OPENAI_API_KEY",
        "default_model": "gpt-4o",
    },
    "ollama": {
        "name": "Ollama (Local)",
        "base_url": "http://localhost:11434/v1",
        "env_key": None,  # No API key needed
        "default_model": "llama3.2",
    },
    "lmstudio": {
        "name": "LM Studio (Local)",
        "base_url": "http://localhost:1234/v1",
        "env_key": None,
        "default_model": "local-model",
    },
}

# Compaction Configuration
DEFAULT_AUTO_COMPACT_TOKEN_LIMIT = 150000  # Auto-compact at ~80% of 200k context
DEFAULT_COMPACTION_MODEL = "claude-sonnet-4-20250514"  # Use faster/cheaper model for summarization
DEFAULT_PRESERVE_MESSAGES = 5  # Keep last N messages intact

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

# Ghost Commit Configuration
GHOST_COMMIT_CONFIG = {
    "squash_on_close": False,  # Squash all ghost commits on session end
    "ignore_patterns": [
        ".env",
        "*.key",
        "*.pem",
        "credentials.*",
    ],
}
