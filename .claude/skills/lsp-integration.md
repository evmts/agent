# LSP Integration

This skill covers the Language Server Protocol (LSP) client implementation for code intelligence features like hover information and diagnostics.

## Overview

The LSP integration provides type information, documentation, and diagnostics for code symbols across multiple programming languages. It uses JSON-RPC 2.0 over stdio with Content-Length framing to communicate with language servers.

## Key Files

| File | Purpose |
|------|---------|
| `agent/tools/lsp.py` | Complete LSP implementation |
| `config/defaults.py` | LSP server configurations |

## Architecture

```
hover(file_path, line, character)
    │
    ├── LSPManager (Singleton)
    │   ├── Client pool (max 10)
    │   └── Broken server tracking
    │
    └── LSPClient (per server+root)
        ├── LSPConnection (JSON-RPC 2.0)
        │   ├── Content-Length framing
        │   └── Request/response matching
        └── Language Server Process
```

## Supported Languages

| Language | Server | Extensions | Install Command |
|----------|--------|------------|-----------------|
| Python | pylsp | `.py`, `.pyi` | `pip install python-lsp-server` |
| TypeScript/JS | typescript-language-server | `.ts`, `.tsx`, `.js`, `.jsx`, `.mjs`, `.cjs` | `npm install -g typescript-language-server typescript` |
| Go | gopls | `.go` | `go install golang.org/x/tools/gopls@latest` |
| Rust | rust-analyzer | `.rs` | `rustup component add rust-analyzer` |

## Constants

```python
# Timeouts
LSP_INIT_TIMEOUT_SECONDS = 5.0      # Server initialization
LSP_REQUEST_TIMEOUT_SECONDS = 2.0   # Individual requests
LSP_DIAGNOSTICS_TIMEOUT_SECONDS = 5.0  # Waiting for diagnostics

# Pool management
LSP_MAX_CLIENTS = 10                # Maximum concurrent clients
```

## Public API

### hover()

Get type information and documentation at a position:

```python
from agent.tools.lsp import hover

result = await hover(
    file_path="/path/to/file.py",
    line=10,        # 0-based
    character=5,    # 0-based
)

# Returns:
{
    "success": True,
    "contents": "def my_function(x: int) -> str:\n    ...",
    "language": "python",
    "range": {"start": {"line": 10, "character": 4}, "end": ...}
}

# Or on error:
{
    "success": False,
    "error": "No LSP server available for '.xyz' files"
}
```

### diagnostics()

Get errors, warnings, and hints for a file:

```python
from agent.tools.lsp import diagnostics

result = await diagnostics(
    file_path="/path/to/file.py",
    timeout=5.0,
)

# Returns:
{
    "success": True,
    "file_path": "/path/to/file.py",
    "diagnostics": [
        "ERROR [mypy] [15:4] Incompatible types in assignment",
        "WARN [pylsp] [23:1] Unused import"
    ],
    "error_count": 1,
    "warning_count": 1,
    "summary": "1 errors, 1 warnings",
    "formatted_output": "Diagnostics for /path/to/file.py:\n..."
}
```

### touch_file()

Open a file to trigger diagnostics:

```python
from agent.tools.lsp import touch_file

result = await touch_file(
    file_path="/path/to/file.py",
    wait_for_diagnostics=True,
    timeout=3.0,
)
```

## Core Classes

### LSPConnection

JSON-RPC 2.0 communication layer:

```python
class LSPConnection:
    """JSON-RPC 2.0 connection over stdio with Content-Length framing."""

    async def send_request(self, method: str, params: dict) -> Any:
        """Send request and await response."""

    async def send_notification(self, method: str, params: dict) -> None:
        """Send notification (no response expected)."""

    def on_notification(self, method: str, handler: Callable) -> None:
        """Register handler for server notifications."""
```

Message format:
```
Content-Length: 123\r\n
\r\n
{"jsonrpc": "2.0", "id": 1, "method": "textDocument/hover", "params": {...}}
```

### LSPClient

Per-server instance managing document lifecycle:

```python
class LSPClient:
    """Single language server instance."""

    @classmethod
    async def create(cls, server_id: str, root: str, command: list[str]) -> "LSPClient":
        """Spawn server process and initialize."""

    async def initialize(self) -> None:
        """Send initialize request with capabilities."""

    async def open_file(self, file_path: str) -> None:
        """Send textDocument/didOpen."""

    async def hover(self, file_path: str, line: int, character: int) -> HoverResult | None:
        """Send textDocument/hover request."""

    async def wait_for_diagnostics(self, file_path: str, timeout: float) -> list[Diagnostic]:
        """Wait for publishDiagnostics notification."""

    async def close(self) -> None:
        """Send shutdown and exit."""
```

### LSPManager

Singleton managing client pool:

```python
class LSPManager:
    """Singleton manager for LSP client lifecycle and pooling."""

    @classmethod
    async def get_instance(cls) -> "LSPManager":
        """Get or create singleton instance."""

    async def get_client(self, file_path: str) -> LSPClient | None:
        """Get or spawn client for file."""

    async def shutdown_all(self) -> None:
        """Shutdown all active clients."""
```

Key behaviors:
- **Client pooling**: Max 10 clients, evicts oldest when full
- **Broken server tracking**: Prevents retry loops for failed servers
- **Workspace root discovery**: Finds project root via marker files

## Data Types

### Diagnostic

```python
@dataclass
class Diagnostic:
    range: Range           # Location in file
    severity: DiagnosticSeverity  # ERROR, WARNING, INFO, HINT
    message: str           # Error message
    source: str            # e.g., "typescript", "pylsp"
    code: str | int | None # Optional diagnostic code

    def pretty_format(self) -> str:
        """Format as 'ERROR [source] [line:col] message'"""

class DiagnosticSeverity(IntEnum):
    ERROR = 1
    WARNING = 2
    INFO = 3
    HINT = 4
```

### HoverResult

```python
@dataclass
class HoverResult:
    contents: str          # Formatted markdown/plaintext
    range: Range | None    # Symbol range
    language: str          # Language identifier
```

## Workspace Root Discovery

Language servers need a workspace root for proper analysis:

```python
def find_workspace_root(file_path: str, markers: list[str]) -> str:
    """Find workspace root by searching upward for marker files."""
```

Marker files per language:
- **Python**: `pyproject.toml`, `setup.py`, `requirements.txt`, `.git`
- **TypeScript/JS**: `package.json`, `tsconfig.json`, `.git`
- **Go**: `go.mod`, `go.work`, `.git`
- **Rust**: `Cargo.toml`, `.git`

## Error Handling

### Exception Classes

```python
class LSPError(Exception):
    """Base exception for LSP errors."""

class LSPConnectionError(LSPError):
    """Failed to connect to language server."""

class LSPTimeoutError(LSPError):
    """Request timed out."""

class LSPServerNotFoundError(LSPError):
    """Language server binary not found."""

class LSPInitializationError(LSPError):
    """Server failed to initialize."""
```

### Error Messages with Install Hints

```python
# When server not found
{
    "success": False,
    "error": "Language server 'pylsp' not found. Install with: pip install python-lsp-server"
}
```

## Agent Tool Integration

The LSP functions are wrapped as agent tools:

```python
# In agent/agent.py

@agent.tool_plain
async def hover(file_path: str, line: int, character: int) -> str:
    """Get type information and documentation for a symbol."""
    result = await lsp_hover_impl(file_path, line, character)
    if result.get("success"):
        return result.get("contents", "No hover information available")
    return f"Error: {result.get('error', 'Unknown error')}"

@agent.tool_plain
async def get_diagnostics(file_path: str, timeout: float = 5.0) -> str:
    """Get diagnostics (errors, warnings, hints) for a file."""
    result = await lsp_diagnostics_impl(file_path, timeout=timeout)
    if result.get("success"):
        return result.get("formatted_output", "No diagnostics found")
    return f"Error: {result.get('error', 'Unknown error')}"

@agent.tool_plain
async def check_file_errors(file_path: str, timeout: float = 3.0) -> str:
    """Check a file for errors before editing."""
    result = await lsp_touch_file_impl(file_path, wait_for_diagnostics=True)
    if result.get("success"):
        if not result.get("diagnostics"):
            return f"No errors found in {file_path}"
        return result.get("summary", "") + "\n" + "\n".join(result.get("diagnostics", []))
    return f"Error: {result.get('error', 'Unknown error')}"
```

## Common Tasks

### Adding a New Language Server

1. Add configuration to `LSP_SERVERS`:
   ```python
   LSP_SERVERS["ruby"] = {
       "extensions": [".rb"],
       "command": ["solargraph", "stdio"],
       "root_markers": ["Gemfile", ".ruby-version", ".git"],
   }
   ```

2. Add extension mappings to `EXTENSION_TO_LANGUAGE`:
   ```python
   EXTENSION_TO_LANGUAGE[".rb"] = "ruby"
   ```

### Testing LSP Integration

```python
import pytest
from agent.tools.lsp import hover, diagnostics, LSPManager

@pytest.mark.asyncio
async def test_hover_python():
    result = await hover("/path/to/file.py", 10, 5)
    assert result["success"]
    assert "contents" in result

@pytest.fixture(autouse=True)
def reset_lsp():
    """Reset LSP manager between tests."""
    yield
    LSPManager.reset_instance()
```

### Debugging LSP Issues

1. Check server is installed: `which pylsp`
2. Check server starts: `pylsp --help`
3. Check file extension is supported
4. Check workspace root detection
5. Increase timeout for slow servers

## Best Practices

1. **File validation**: Always verify file exists before LSP calls
2. **Timeout handling**: Use appropriate timeouts, longer for diagnostics
3. **Error messages**: Include install hints for missing servers
4. **Pool management**: Let manager handle client lifecycle
5. **Workspace roots**: Ensure marker files exist in project root

## Related Skills

- [tools-development.md](./tools-development.md) - Tool registration patterns
- [agent-system.md](./agent-system.md) - Agent tool configuration
- [testing.md](./testing.md) - LSP testing patterns
