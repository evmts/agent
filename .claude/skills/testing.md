# Testing

This skill covers pytest patterns, fixtures, E2E testing, and SSE stream testing for the Claude Agent platform.

## Overview

The Claude Agent platform uses pytest with async support for testing. Tests use real functionality (no mocks) to ensure accurate integration testing. E2E tests run against a live server with MCP-enabled agents.

## Key Files

| File | Purpose |
|------|---------|
| `tests/conftest.py` | Root pytest fixtures |
| `tests/e2e/conftest.py` | E2E-specific fixtures and helpers |
| `tests/test_server.py` | Server endpoint tests |
| `tests/test_agent/` | Agent-specific tests |
| `tests/e2e/` | End-to-end integration tests |
| `pytest.ini` | Pytest configuration |

## Test Organization

```
tests/
├── conftest.py               # Root fixtures
├── test_config.py            # Configuration tests
├── test_server.py            # API endpoint tests
├── test_agent/               # Agent module tests
│   ├── test_agent.py         # Agent creation tests
│   ├── test_wrapper.py       # Wrapper tests
│   └── test_tools/           # Tool-specific tests
│       └── test_lsp.py       # LSP tool tests
└── e2e/                      # End-to-end tests
    ├── conftest.py           # E2E fixtures
    ├── test_session_lifecycle.py
    ├── test_file_tools.py
    ├── test_shell_tool.py
    ├── test_search_tools.py
    ├── test_todo_tools.py
    └── test_multi_step.py
```

## pytest Configuration

`pytest.ini`:

```ini
[pytest]
testpaths = tests
python_files = test_*.py
python_classes = Test*
python_functions = test_*

# Async support
asyncio_mode = auto

# Markers
markers =
    asyncio: marks tests as async
    slow: marks tests as slow running
    requires_api_key: marks tests requiring real ANTHROPIC_API_KEY
```

## Root Fixtures (`tests/conftest.py`)

### temp_dir

Temporary directory with automatic cleanup:

```python
@pytest.fixture
def temp_dir() -> Iterator[Path]:
    """Create a temporary directory for testing."""
    with tempfile.TemporaryDirectory() as tmpdir:
        yield Path(tmpdir)
```

### temp_file

Pre-populated test file:

```python
@pytest.fixture
def temp_file(temp_dir: Path) -> Path:
    """Create a temporary file for testing."""
    file_path = temp_dir / "test_file.txt"
    file_path.write_text("Hello, World!\nThis is a test file.\nLine 3\n")
    return file_path
```

### mock_env_vars

Set up test environment:

```python
@pytest.fixture
def mock_env_vars(monkeypatch):
    """Set up mock environment variables for testing."""
    monkeypatch.setenv("ANTHROPIC_API_KEY", "test-key-123")
    monkeypatch.setenv("DISABLE_PATH_VALIDATION", "1")
    return monkeypatch
```

### Sample Data

```python
@pytest.fixture
def sample_python_code() -> str:
    """Sample Python code for testing execution."""
    return """
print("Hello from Python!")
result = 2 + 2
print(f"2 + 2 = {result}")
"""

@pytest.fixture
def sample_shell_command() -> str:
    """Sample shell command for testing."""
    return "echo 'Hello from shell'"
```

## E2E Fixtures (`tests/e2e/conftest.py`)

### Constants

```python
E2E_TIMEOUT_SECONDS = 180
TEST_SERVER_PORT = 18765
```

### api_key

Skip test if API key not set:

```python
@pytest.fixture(scope="session")
def api_key() -> str:
    """Get API key from environment, skip if not present."""
    key = os.environ.get("ANTHROPIC_API_KEY")
    if not key:
        pytest.skip("ANTHROPIC_API_KEY not set")
    return key
```

### e2e_temp_dir

Git-initialized temporary directory:

```python
@pytest.fixture
def e2e_temp_dir() -> Generator[Path, None, None]:
    """Create isolated temp directory for E2E tests with git init."""
    with tempfile.TemporaryDirectory(prefix="e2e_test_") as tmpdir:
        # Initialize as git repo for snapshot system
        subprocess.run(["git", "init", "--quiet"], cwd=tmpdir, capture_output=True)
        subprocess.run(["git", "config", "user.email", "test@test.com"], cwd=tmpdir)
        subprocess.run(["git", "config", "user.name", "Test"], cwd=tmpdir)
        yield Path(tmpdir)
```

### clear_state

Auto-clear server state between tests:

```python
@pytest.fixture(autouse=True)
def clear_state():
    """Clear server state before each test."""
    sessions.clear()
    session_messages.clear()
    yield
    sessions.clear()
    session_messages.clear()
```

### mcp_agent

MCP-enabled agent for E2E tests:

```python
@pytest_asyncio.fixture
async def mcp_agent(api_key: str, e2e_temp_dir: Path):
    """Create MCP-enabled agent and configure server."""
    async with create_mcp_wrapper(working_dir=str(e2e_temp_dir)) as wrapper:
        set_agent(wrapper)
        yield wrapper
    set_agent(None)
```

### e2e_client

Async HTTP client with running server:

```python
@pytest_asyncio.fixture
async def e2e_client(mcp_agent) -> AsyncGenerator[httpx.AsyncClient, None]:
    """Create async HTTP client for testing."""
    config = uvicorn.Config(app, host="127.0.0.1", port=TEST_SERVER_PORT)
    server = uvicorn.Server(config)
    server_task = asyncio.create_task(server.serve())
    await asyncio.sleep(0.5)  # Wait for server to start

    async with httpx.AsyncClient(
        base_url=f"http://127.0.0.1:{TEST_SERVER_PORT}",
        timeout=httpx.Timeout(E2E_TIMEOUT_SECONDS),
    ) as client:
        yield client

    server.should_exit = True
    await server_task
```

### multi_file_fixture

Multiple files for search testing:

```python
@pytest.fixture
def multi_file_fixture(e2e_temp_dir: Path) -> dict[str, Path]:
    """Create multiple fixture files for search tests."""
    files = {
        "file1.txt": "Hello World\nLine 2",
        "file2.txt": "Goodbye World\nLine 2",
        "subdir/file3.txt": "Nested Hello",
        "code.py": "def hello():\n    print('Hello')",
    }
    result = {}
    for name, content in files.items():
        path = e2e_temp_dir / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        result[name] = path
    return result
```

## SSE Testing

### SSECollector

Parses streaming responses:

```python
class SSECollector:
    """Collects and parses SSE events from streaming response."""

    def __init__(self):
        self.events: list[dict] = []
        self.final_text: str = ""
        self.tool_calls: list[dict] = []
        self.tool_results: list[dict] = []
        self.errors: list[str] = []

    async def parse_stream(self, response: httpx.Response) -> None:
        """Parse SSE stream from async response."""
        current_event = None
        async for line in response.aiter_lines():
            if line.startswith("event:"):
                current_event = line[6:].strip()
            elif line.startswith("data:"):
                data_str = line[5:].strip()
                try:
                    data = json.loads(data_str)
                    self.events.append({"event": current_event, "data": data})
                    self._process_event(current_event, data)
                except json.JSONDecodeError:
                    pass
```

### collect_sse_response

Helper function:

```python
async def collect_sse_response(response: httpx.Response) -> SSECollector:
    """Helper to collect SSE events from async response."""
    collector = SSECollector()
    await collector.parse_stream(response)
    return collector
```

### Usage

```python
@pytest.mark.asyncio
async def test_message_streaming(e2e_client):
    # Create session
    resp = await e2e_client.post("/session", json={"title": "Test"})
    session = resp.json()

    # Send message with streaming
    async with e2e_client.stream(
        "POST",
        f"/session/{session['id']}/message",
        json={"parts": [{"type": "text", "text": "Say hello"}]},
    ) as response:
        collector = await collect_sse_response(response)

    # Verify results
    assert len(collector.errors) == 0
    assert "hello" in collector.final_text.lower()
```

## Assertion Helpers

```python
def assert_file_contains(file_path: Path, expected: str, msg: str = "") -> None:
    """Assert file contains expected content."""
    assert file_path.exists(), f"File does not exist: {file_path}"
    content = file_path.read_text()
    assert expected in content, f"Expected '{expected}' in file. {msg}"

def assert_file_exact(file_path: Path, expected: str, msg: str = "") -> None:
    """Assert file has exact content."""
    assert file_path.exists()
    content = file_path.read_text()
    assert content == expected, f"File content mismatch. {msg}"
```

## Test Patterns

### Basic Async Test

```python
import pytest

@pytest.mark.asyncio
async def test_something():
    result = await some_async_function()
    assert result == expected
```

### Session Workflow Test

```python
@pytest.mark.asyncio
async def test_session_workflow(e2e_client, fixture_file):
    # Create session
    resp = await e2e_client.post("/session", json={"title": "Test"})
    session = resp.json()

    # Send message
    async with e2e_client.stream(
        "POST",
        f"/session/{session['id']}/message",
        json={"parts": [{"type": "text", "text": "Read fixture.txt"}]},
    ) as response:
        collector = await collect_sse_response(response)

    # Verify tool was called
    read_calls = [c for c in collector.tool_calls if "read" in c["tool"].lower()]
    assert len(read_calls) > 0
```

### Tool Verification Test

```python
@pytest.mark.asyncio
async def test_file_tool(e2e_client, e2e_temp_dir):
    # Setup
    session = (await e2e_client.post("/session", json={})).json()

    # Execute agent task
    async with e2e_client.stream(
        "POST",
        f"/session/{session['id']}/message",
        json={"parts": [{"type": "text", "text": "Create a file test.txt with 'hello'"}]},
    ) as response:
        collector = await collect_sse_response(response)

    # Verify file was created
    created_file = e2e_temp_dir / "test.txt"
    assert_file_contains(created_file, "hello")
```

## Running Tests

### All Tests

```bash
pytest
# or
uv run pytest
```

### Specific Tests

```bash
# Single file
pytest tests/test_server.py

# Single test
pytest tests/test_server.py::test_health_check

# By marker
pytest -m slow
pytest -m "requires_api_key"
```

### With Environment

```bash
# E2E tests need real API key
ANTHROPIC_API_KEY="sk-..." pytest tests/e2e/

# Disable path validation for temp dirs
DISABLE_PATH_VALIDATION=1 pytest
```

### With Coverage

```bash
pytest --cov=agent --cov=server --cov-report=html
```

## Test Markers

```python
@pytest.mark.slow
def test_long_running():
    """Test marked as slow."""
    pass

@pytest.mark.requires_api_key
def test_with_real_api():
    """Test requires ANTHROPIC_API_KEY."""
    pass

@pytest.mark.asyncio
async def test_async_operation():
    """Async test."""
    pass
```

## Best Practices

1. **No mocks**: Use real functionality for accurate integration tests
2. **Isolated directories**: Use `e2e_temp_dir` with git init for each test
3. **Clear state**: `clear_state` fixture runs automatically
4. **Timeout handling**: Set appropriate timeouts for E2E tests
5. **Stream parsing**: Use `SSECollector` for SSE response verification
6. **Descriptive assertions**: Include context in assertion messages

## Related Skills

- [python-backend.md](./python-backend.md) - Server being tested
- [agent-system.md](./agent-system.md) - Agent fixtures
- [api-development.md](./api-development.md) - API endpoints tested
