# Runner Tests

Security and functionality tests for the Python runner.

## Test Coverage

### Security Tests (test_tools.py)

Comprehensive security validation for all tools:

```
test_tools.py
├── TestReadFileSecurity
│   ├── Absolute path traversal blocking
│   ├── Relative path traversal (../..)
│   ├── Symlink escape protection
│   ├── Valid workspace path handling
│   └── Input validation
├── TestWriteFileSecurity
│   ├── Path traversal protection
│   ├── Parent directory creation safety
│   └── Append mode validation
├── TestListFilesSecurity
│   ├── Directory traversal blocking
│   ├── Glob pattern safety
│   └── Result limiting
├── TestShellSecurity
│   ├── Working directory validation
│   ├── Timeout handling
│   └── Command execution (intentional injection)
├── TestToolInputValidation
│   ├── Type checking
│   ├── Required parameter validation
│   └── Optional parameter defaults
└── TestPathNormalization
    ├── Dot segment resolution
    ├── Escape detection after normalization
    └── Multiple slash handling
```

## Security Test Patterns

### Path Traversal Tests

Each tool is tested against multiple traversal attack vectors:

```python
# Absolute paths
"/etc/passwd" -> "Error: path traversal not allowed"

# Relative traversal
"../../etc/passwd" -> "Error: path traversal not allowed"

# Dotdot in middle
"foo/../../etc/passwd" -> "Error: path traversal not allowed"

# Symlink escape (if exists)
"link-to-etc" -> "Error: path traversal not allowed"
```

### Valid Path Tests

Ensure legitimate operations within workspace succeed:

```python
# Relative paths
"src/main.py" -> Success

# Subdirectories
"deep/nested/file.txt" -> Success

# Current directory
"." -> Success

# Normalized paths
"./foo/../bar.txt" -> Success (resolves to bar.txt)
```

### Input Validation Tests

Verify proper error handling for invalid inputs:

```python
# Missing required parameters
{} -> "Error: path is required"

# Invalid types
{"path": 123} -> Exception

# Empty values
{"path": ""} -> "Error: file not found"

# Null bytes
{"path": "test\x00file"} -> Exception
```

## Running Tests

```bash
# All tests
uv run pytest

# Specific test file
uv run pytest tests/test_tools.py

# Specific test class
uv run pytest tests/test_tools.py::TestReadFileSecurity

# Specific test
uv run pytest tests/test_tools.py::TestReadFileSecurity::test_blocks_absolute_path_traversal

# Verbose output
uv run pytest -v

# Show print statements
uv run pytest -s

# Coverage report
uv run pytest --cov=runner --cov-report=html
```

## Test Environment

Tests run outside the K8s sandbox, so /workspace doesn't exist. This is
intentional - we test the security logic, not the actual filesystem operations.

Expected test behavior:

```python
# Path traversal tests
read_file_tool({"path": "/etc/passwd"})
# -> "Error: path traversal not allowed"  (PASS - security works)

# Valid path tests
read_file_tool({"path": "test.txt"})
# -> "Error: file not found" (PASS - security allows, file missing)
```

Tests verify:
1. Security checks execute correctly
2. Valid paths pass security validation
3. Invalid paths are rejected before filesystem access

## Security Assumptions

### Intentional Behaviors

Some behaviors are intentional and NOT vulnerabilities:

| Behavior               | Reason                                    |
|------------------------|-------------------------------------------|
| Shell injection        | Tool executes arbitrary commands by design|
| Command chaining (&&)  | Workflows need sequential execution       |
| Shell metacharacters   | Required for useful command execution     |

### Security Boundary

The security model relies on:

1. gVisor sandbox (enforced by K8s)
2. Filesystem restrictions (only /workspace accessible)
3. Network restrictions (only callback URL reachable)
4. Resource limits (CPU, memory, timeout)
5. Tool path validation (prevent workspace escape)

Tests focus on #5 (path validation) because #1-4 are enforced at the
infrastructure layer.

## Adding New Tests

When adding a new tool:

```python
class TestNewToolSecurity:
    """Test new_tool security controls."""

    def test_blocks_absolute_path_traversal(self):
        result = new_tool({"path": "/etc/passwd"})
        assert "Error: path traversal not allowed" in result

    def test_blocks_relative_path_traversal(self):
        result = new_tool({"path": "../../etc/passwd"})
        assert "Error: path traversal not allowed" in result

    def test_allows_valid_workspace_path(self):
        result = new_tool({"path": "valid.txt"})
        assert "path traversal not allowed" not in result

    def test_handles_missing_required_param(self):
        result = new_tool({})
        assert "Error: param is required" in result
```

## Related Documentation

- See tools/README.md for tool implementation details
- See ../README.md for overall runner architecture
- See /Users/williamcory/plue/docs/infrastructure.md for K8s security config
