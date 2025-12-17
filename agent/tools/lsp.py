"""
LSP (Language Server Protocol) client implementation.

Provides hover functionality for type hints and documentation across
multiple programming languages (Python, TypeScript, Go, Rust).
"""

from __future__ import annotations

import asyncio
import json
import os
import shutil
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, ClassVar

# Constants
LSP_INIT_TIMEOUT_SECONDS = 5.0
LSP_REQUEST_TIMEOUT_SECONDS = 2.0
LSP_MAX_CLIENTS = 10

# Language server configurations
LSP_SERVERS: dict[str, dict[str, Any]] = {
    "python": {
        "extensions": [".py", ".pyi"],
        "command": ["pylsp"],
        "root_markers": ["pyproject.toml", "setup.py", "setup.cfg", "requirements.txt", "Pipfile", ".git"],
    },
    "typescript": {
        "extensions": [".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs"],
        "command": ["typescript-language-server", "--stdio"],
        "root_markers": ["package.json", "tsconfig.json", "jsconfig.json", ".git"],
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

# Extension to language ID mapping for LSP
EXTENSION_TO_LANGUAGE: dict[str, str] = {
    ".py": "python",
    ".pyi": "python",
    ".ts": "typescript",
    ".tsx": "typescriptreact",
    ".js": "javascript",
    ".jsx": "javascriptreact",
    ".mjs": "javascript",
    ".cjs": "javascript",
    ".go": "go",
    ".rs": "rust",
}


# --- Exception Classes ---


class LSPError(Exception):
    """Base exception for LSP errors."""
    pass


class LSPConnectionError(LSPError):
    """Failed to connect to language server."""
    pass


class LSPTimeoutError(LSPError):
    """Request timed out."""
    pass


class LSPServerNotFoundError(LSPError):
    """Language server binary not found."""
    pass


class LSPInitializationError(LSPError):
    """Server failed to initialize."""
    pass


# --- Type Definitions ---


@dataclass
class Position:
    """0-based line and character position."""
    line: int
    character: int

    def to_dict(self) -> dict[str, int]:
        return {"line": self.line, "character": self.character}


@dataclass
class Range:
    """Range with start and end positions."""
    start: Position
    end: Position

    def to_dict(self) -> dict[str, dict[str, int]]:
        return {"start": self.start.to_dict(), "end": self.end.to_dict()}

    @classmethod
    def from_dict(cls, data: dict) -> "Range":
        return cls(
            start=Position(data["start"]["line"], data["start"]["character"]),
            end=Position(data["end"]["line"], data["end"]["character"]),
        )


@dataclass
class HoverResult:
    """Result from a hover request."""
    contents: str
    range: Range | None = None
    language: str = ""


@dataclass
class ServerConfig:
    """Configuration for a language server."""
    id: str
    extensions: list[str]
    command: list[str]
    root_markers: list[str]
    init_options: dict = field(default_factory=dict)


# --- Utility Functions ---


def get_language_id(extension: str) -> str:
    """Get LSP language ID from file extension."""
    return EXTENSION_TO_LANGUAGE.get(extension, "plaintext")


def find_workspace_root(file_path: str, markers: list[str]) -> str:
    """Find workspace root by searching upward for marker files.

    Args:
        file_path: Path to file
        markers: List of marker files to search for

    Returns:
        Path to workspace root directory
    """
    path = Path(file_path).resolve()
    current = path.parent if path.is_file() else path

    while current != current.parent:
        for marker in markers:
            if (current / marker).exists():
                return str(current)
        current = current.parent

    # Fallback to file's directory
    return str(path.parent if path.is_file() else path)


def parse_hover_contents(contents: Any) -> str:
    """Parse hover contents from various LSP formats.

    LSP hover contents can be:
    - string: Plain text
    - MarkupContent: {kind: "plaintext"|"markdown", value: string}
    - MarkedString: {language: string, value: string} or string
    - MarkedString[]: Array of the above

    Args:
        contents: Raw hover contents from LSP response

    Returns:
        Formatted string representation
    """
    if contents is None:
        return ""

    if isinstance(contents, str):
        return contents

    if isinstance(contents, dict):
        # MarkupContent or MarkedString
        if "value" in contents:
            value = contents["value"]
            kind = contents.get("kind", "")
            language = contents.get("language", "")

            if language:
                return f"```{language}\n{value}\n```"
            return value
        return str(contents)

    if isinstance(contents, list):
        # Array of MarkedString
        parts = []
        for item in contents:
            parsed = parse_hover_contents(item)
            if parsed:
                parts.append(parsed)
        return "\n\n".join(parts)

    return str(contents)


def get_server_for_file(file_path: str) -> tuple[str, dict[str, Any]] | None:
    """Get server configuration for a file based on extension.

    Args:
        file_path: Path to file

    Returns:
        Tuple of (server_id, config) or None if no server found
    """
    ext = Path(file_path).suffix.lower()

    for server_id, config in LSP_SERVERS.items():
        if ext in config["extensions"]:
            return server_id, config

    return None


# --- LSP Connection (JSON-RPC 2.0 over stdio) ---


class LSPConnection:
    """JSON-RPC 2.0 connection over stdio with Content-Length framing."""

    def __init__(
        self,
        process: asyncio.subprocess.Process,
        reader: asyncio.StreamReader,
        writer: asyncio.StreamWriter,
    ):
        self.process = process
        self.reader = reader
        self.writer = writer
        self._request_id = 0
        self._pending_requests: dict[int, asyncio.Future[dict]] = {}
        self._response_task: asyncio.Task | None = None
        self._closed = False

    async def start_response_listener(self) -> None:
        """Start background task to listen for responses."""
        self._response_task = asyncio.create_task(self._response_listener())

    async def _response_listener(self) -> None:
        """Background task to read responses and match to pending requests."""
        try:
            while not self._closed:
                try:
                    message = await self._read_message()
                    if message is None:
                        break

                    # Check if this is a response (has id but no method)
                    msg_id = message.get("id")
                    if msg_id is not None and "method" not in message:
                        future = self._pending_requests.pop(msg_id, None)
                        if future and not future.done():
                            if "error" in message:
                                future.set_exception(
                                    LSPError(f"LSP error: {message['error']}")
                                )
                            else:
                                future.set_result(message.get("result"))
                    # Ignore notifications and requests from server
                except asyncio.CancelledError:
                    break
                except Exception:
                    # Connection error, stop listening
                    break
        finally:
            # Cancel any pending requests
            for future in self._pending_requests.values():
                if not future.done():
                    future.cancel()

    async def _read_message(self) -> dict | None:
        """Read Content-Length framed JSON message from reader."""
        headers: dict[str, str] = {}

        # Read headers until empty line
        while True:
            line = await self.reader.readline()
            if not line:
                return None

            line_str = line.decode("utf-8").strip()
            if not line_str:
                break

            if ":" in line_str:
                key, value = line_str.split(":", 1)
                headers[key.strip().lower()] = value.strip()

        # Read body based on Content-Length
        content_length = int(headers.get("content-length", 0))
        if content_length == 0:
            return None

        body = await self.reader.readexactly(content_length)
        return json.loads(body.decode("utf-8"))

    async def _write_message(self, message: dict) -> None:
        """Write Content-Length framed JSON message to writer."""
        body = json.dumps(message).encode("utf-8")
        header = f"Content-Length: {len(body)}\r\n\r\n".encode("utf-8")
        self.writer.write(header + body)
        await self.writer.drain()

    async def send_request(self, method: str, params: dict) -> Any:
        """Send JSON-RPC request and await response.

        Args:
            method: LSP method name
            params: Request parameters

        Returns:
            Response result

        Raises:
            LSPTimeoutError: If request times out
            LSPError: If server returns error
        """
        self._request_id += 1
        request_id = self._request_id

        future: asyncio.Future[dict] = asyncio.get_event_loop().create_future()
        self._pending_requests[request_id] = future

        message = {
            "jsonrpc": "2.0",
            "id": request_id,
            "method": method,
            "params": params,
        }

        await self._write_message(message)

        try:
            result = await asyncio.wait_for(future, timeout=LSP_REQUEST_TIMEOUT_SECONDS)
            return result
        except asyncio.TimeoutError:
            self._pending_requests.pop(request_id, None)
            raise LSPTimeoutError(f"Request '{method}' timed out")

    async def send_notification(self, method: str, params: dict) -> None:
        """Send JSON-RPC notification (no response expected).

        Args:
            method: LSP method name
            params: Notification parameters
        """
        message = {
            "jsonrpc": "2.0",
            "method": method,
            "params": params,
        }
        await self._write_message(message)

    async def close(self) -> None:
        """Close connection and terminate process."""
        self._closed = True

        if self._response_task:
            self._response_task.cancel()
            try:
                await self._response_task
            except asyncio.CancelledError:
                pass

        self.writer.close()
        try:
            await asyncio.wait_for(self.writer.wait_closed(), timeout=1.0)
        except (asyncio.TimeoutError, Exception):
            pass

        # Terminate process
        try:
            self.process.terminate()
            await asyncio.wait_for(self.process.wait(), timeout=2.0)
        except asyncio.TimeoutError:
            self.process.kill()
            await self.process.wait()
        except Exception:
            pass


# --- LSP Client ---


class LSPClient:
    """LSP client for a single language server instance."""

    def __init__(
        self,
        server_id: str,
        root: str,
        connection: LSPConnection,
    ):
        self.server_id = server_id
        self.root = root
        self.connection = connection
        self.capabilities: dict = {}
        self._file_versions: dict[str, int] = {}
        self._file_versions_lock = asyncio.Lock()
        self._initialized = False
        self._open_files: set[str] = set()

    @classmethod
    async def create(
        cls,
        server_id: str,
        root: str,
        command: list[str],
        init_options: dict | None = None,
    ) -> "LSPClient":
        """Factory method to spawn server and initialize connection.

        Args:
            server_id: Server identifier
            root: Workspace root path
            command: Command to spawn server
            init_options: Optional initialization options

        Returns:
            Initialized LSPClient

        Raises:
            LSPServerNotFoundError: If server binary not found
            LSPInitializationError: If initialization fails
        """
        # Check if command exists
        if not shutil.which(command[0]):
            raise LSPServerNotFoundError(
                f"LSP server '{command[0]}' not found. "
                f"Please install the language server."
            )

        # Spawn process
        try:
            process = await asyncio.create_subprocess_exec(
                *command,
                stdin=asyncio.subprocess.PIPE,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                cwd=root,
            )
        except Exception as e:
            raise LSPConnectionError(f"Failed to spawn LSP server: {e}")

        if process.stdin is None or process.stdout is None:
            raise LSPConnectionError("Failed to get process pipes")

        # Create connection
        connection = LSPConnection(
            process=process,
            reader=process.stdout,
            writer=process.stdin,
        )

        # Start response listener
        await connection.start_response_listener()

        # Create client
        client = cls(server_id, root, connection)

        # Initialize
        try:
            await client.initialize(init_options)
        except Exception as e:
            await connection.close()
            raise LSPInitializationError(f"Failed to initialize LSP server: {e}")

        return client

    async def initialize(self, init_options: dict | None = None) -> dict:
        """Send initialize request and initialized notification.

        Args:
            init_options: Optional initialization options

        Returns:
            Server capabilities
        """
        params = {
            "processId": os.getpid(),
            "rootUri": f"file://{self.root}",
            "rootPath": self.root,
            "capabilities": {
                "textDocument": {
                    "hover": {
                        "contentFormat": ["markdown", "plaintext"],
                    },
                    "synchronization": {
                        "didOpen": True,
                        "didClose": True,
                    },
                },
            },
        }

        if init_options:
            params["initializationOptions"] = init_options

        # Send initialize with longer timeout
        try:
            result = await asyncio.wait_for(
                self.connection.send_request("initialize", params),
                timeout=LSP_INIT_TIMEOUT_SECONDS,
            )
        except asyncio.TimeoutError:
            raise LSPInitializationError("Initialize request timed out")

        self.capabilities = result.get("capabilities", {}) if result else {}

        # Send initialized notification
        await self.connection.send_notification("initialized", {})

        self._initialized = True
        return self.capabilities

    async def open_file(self, file_path: str) -> None:
        """Send textDocument/didOpen notification.

        Args:
            file_path: Path to file to open
        """
        if file_path in self._open_files:
            return

        try:
            with open(file_path, "r", encoding="utf-8") as f:
                content = f.read()
        except Exception as e:
            raise LSPError(f"Failed to read file: {e}")

        ext = Path(file_path).suffix
        language_id = get_language_id(ext)

        async with self._file_versions_lock:
            version = self._file_versions.get(file_path, 0)
            self._file_versions[file_path] = version

        params = {
            "textDocument": {
                "uri": f"file://{file_path}",
                "languageId": language_id,
                "version": version,
                "text": content,
            }
        }

        await self.connection.send_notification("textDocument/didOpen", params)
        self._open_files.add(file_path)

    async def hover(
        self,
        file_path: str,
        line: int,
        character: int,
    ) -> HoverResult | None:
        """Send textDocument/hover request.

        Args:
            file_path: Path to source file
            line: 0-based line number
            character: 0-based character offset

        Returns:
            HoverResult or None if no hover info
        """
        # Ensure file is open
        await self.open_file(file_path)

        params = {
            "textDocument": {
                "uri": f"file://{file_path}",
            },
            "position": {
                "line": line,
                "character": character,
            },
        }

        result = await self.connection.send_request("textDocument/hover", params)

        if result is None:
            return None

        contents = parse_hover_contents(result.get("contents"))
        if not contents:
            return None

        hover_range = None
        if "range" in result:
            hover_range = Range.from_dict(result["range"])

        ext = Path(file_path).suffix
        language = get_language_id(ext)

        return HoverResult(contents=contents, range=hover_range, language=language)

    async def close(self) -> None:
        """Shutdown server gracefully."""
        if self._initialized:
            try:
                # Send shutdown request
                await asyncio.wait_for(
                    self.connection.send_request("shutdown", {}),
                    timeout=2.0,
                )
                # Send exit notification
                await self.connection.send_notification("exit", {})
            except Exception:
                pass

        await self.connection.close()


# --- LSP Manager (Singleton) ---


class LSPManager:
    """Singleton manager for LSP client lifecycle and pooling."""

    _instance: ClassVar["LSPManager | None"] = None
    _lock: ClassVar[asyncio.Lock] = asyncio.Lock()

    def __init__(self):
        self._clients: list[LSPClient] = []
        self._broken: set[tuple[str, str]] = set()  # (server_id, root) pairs
        self._client_lock = asyncio.Lock()

    @classmethod
    async def get_instance(cls) -> "LSPManager":
        """Get or create singleton instance."""
        async with cls._lock:
            if cls._instance is None:
                cls._instance = cls()
            return cls._instance

    @classmethod
    def reset_instance(cls) -> None:
        """Reset singleton instance (for testing)."""
        cls._instance = None

    def _is_broken(self, server_id: str, root: str) -> bool:
        """Check if server+root combination has failed previously."""
        return (server_id, root) in self._broken

    def _mark_broken(self, server_id: str, root: str) -> None:
        """Mark server+root as broken to prevent retry loops."""
        self._broken.add((server_id, root))

    def _find_client(self, server_id: str, root: str) -> LSPClient | None:
        """Find existing client by server ID and root."""
        for client in self._clients:
            if client.server_id == server_id and client.root == root:
                return client
        return None

    async def get_client(self, file_path: str) -> LSPClient | None:
        """Get or spawn client for file.

        Args:
            file_path: Path to file

        Returns:
            LSPClient or None if unavailable
        """
        # Get server config for file
        server_info = get_server_for_file(file_path)
        if server_info is None:
            return None

        server_id, config = server_info

        # Find workspace root
        root = find_workspace_root(file_path, config["root_markers"])

        # Check if broken
        if self._is_broken(server_id, root):
            return None

        async with self._client_lock:
            # Check for existing client
            client = self._find_client(server_id, root)
            if client:
                return client

            # Evict oldest client if at max
            if len(self._clients) >= LSP_MAX_CLIENTS:
                oldest = self._clients.pop(0)
                try:
                    await oldest.close()
                except Exception:
                    pass

            # Spawn new client
            try:
                client = await LSPClient.create(
                    server_id=server_id,
                    root=root,
                    command=config["command"],
                )
                self._clients.append(client)
                return client
            except LSPServerNotFoundError:
                self._mark_broken(server_id, root)
                raise
            except Exception as e:
                self._mark_broken(server_id, root)
                raise LSPError(f"Failed to create LSP client: {e}")

    async def shutdown_all(self) -> None:
        """Shutdown all active clients."""
        async with self._client_lock:
            for client in self._clients:
                try:
                    await client.close()
                except Exception:
                    pass
            self._clients.clear()


# --- Public API ---


_manager: LSPManager | None = None


async def get_lsp_manager() -> LSPManager:
    """Get the LSP manager instance."""
    return await LSPManager.get_instance()


async def hover(file_path: str, line: int, character: int) -> dict[str, Any]:
    """Get type information and documentation for a symbol at a position.

    Args:
        file_path: Absolute path to the source file
        line: 0-based line number
        character: 0-based character offset within the line

    Returns:
        dict with:
            - success: bool
            - contents: str (formatted markdown/plaintext)
            - range: dict with start/end positions (optional)
            - language: str language identifier
            - error: str error message if success=False
    """
    # Validate file exists
    if not os.path.isfile(file_path):
        return {
            "success": False,
            "error": f"File not found: {file_path}",
        }

    # Check if we have a server for this file type
    server_info = get_server_for_file(file_path)
    if server_info is None:
        ext = Path(file_path).suffix
        supported = ", ".join(
            ext for config in LSP_SERVERS.values() for ext in config["extensions"]
        )
        return {
            "success": False,
            "error": f"No LSP server available for '{ext}' files. Supported: {supported}",
        }

    try:
        manager = await get_lsp_manager()
        client = await manager.get_client(file_path)

        if client is None:
            return {
                "success": False,
                "error": "Failed to get LSP client",
            }

        result = await client.hover(file_path, line, character)

        if result is None:
            return {
                "success": True,
                "contents": "No hover information available at this position",
                "language": get_language_id(Path(file_path).suffix),
            }

        response: dict[str, Any] = {
            "success": True,
            "contents": result.contents,
            "language": result.language,
        }

        if result.range:
            response["range"] = result.range.to_dict()

        return response

    except LSPServerNotFoundError as e:
        server_id = server_info[0]
        install_hints = {
            "python": "pip install python-lsp-server",
            "typescript": "npm install -g typescript-language-server typescript",
            "go": "go install golang.org/x/tools/gopls@latest",
            "rust": "rustup component add rust-analyzer",
        }
        hint = install_hints.get(server_id, "")
        error_msg = str(e)
        if hint:
            error_msg += f" Install with: {hint}"
        return {
            "success": False,
            "error": error_msg,
        }

    except LSPTimeoutError as e:
        return {
            "success": False,
            "error": f"LSP request timed out: {e}",
        }

    except LSPError as e:
        return {
            "success": False,
            "error": str(e),
        }

    except Exception as e:
        return {
            "success": False,
            "error": f"Unexpected error: {e}",
        }
