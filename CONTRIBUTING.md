# Contributing to Claude Agent

Thank you for your interest in contributing to Claude Agent! This document provides guidelines and instructions for contributing.

## Code of Conduct

Please be respectful and constructive in all interactions. We welcome contributors of all experience levels.

## Getting Started

### Development Setup

1. **Fork and clone the repository**
   ```bash
   git clone https://github.com/your-username/agent.git
   cd agent
   ```

2. **Set up Python environment**
   ```bash
   python -m venv .venv
   source .venv/bin/activate  # On Windows: .venv\Scripts\activate
   pip install -e ".[dev]"
   ```

3. **Set up Go environment** (for TUI/SDK work)
   ```bash
   cd claude-tui && go mod download
   cd ../sdk/agent && go mod download
   ```

4. **Set environment variables**
   ```bash
   export ANTHROPIC_API_KEY="your-api-key"
   ```

## Development Workflow

### Branching Strategy

- `main` - Stable release branch
- Feature branches - `feature/description`
- Bug fixes - `fix/description`
- Documentation - `docs/description`

### Making Changes

1. Create a new branch from `main`
   ```bash
   git checkout -b feature/my-feature
   ```

2. Make your changes following the code style guidelines

3. Write or update tests as needed

4. Run the test suite
   ```bash
   # Python tests
   pytest

   # Go tests
   cd sdk/agent && go test ./...
   cd claude-tui && go test ./...
   ```

5. Commit your changes with a descriptive message
   ```bash
   git commit -m "feat: add new feature description"
   ```

### Commit Message Format

We follow conventional commits:

- `feat:` - New features
- `fix:` - Bug fixes
- `docs:` - Documentation changes
- `test:` - Test additions/changes
- `refactor:` - Code refactoring
- `chore:` - Maintenance tasks

Examples:
```
feat: add web search tool integration
fix: resolve path traversal vulnerability in file operations
docs: update README with new environment variables
test: add unit tests for snapshot system
```

## Code Style Guidelines

### Python

- Follow PEP 8 style guide
- Use type hints for function signatures
- Maximum line length: 100 characters
- Use `async/await` for async code
- Docstrings for public functions and classes

```python
async def read_file(path: str, encoding: str = "utf-8") -> str:
    """
    Read contents of a file.

    Args:
        path: Absolute or relative path to file
        encoding: File encoding (default utf-8)

    Returns:
        File contents with line numbers or error message
    """
    ...
```

### Go

- Follow standard Go conventions
- Use `gofmt` for formatting
- Write godoc comments for exported functions
- Handle errors explicitly

```go
// CreateSession creates a new session with the given options.
// It returns the created session or an error if the request fails.
func (c *Client) CreateSession(ctx context.Context, req *CreateSessionRequest) (*Session, error) {
    ...
}
```

## Testing

### Writing Tests

- Write unit tests for new functionality
- Include both success and error cases
- Use descriptive test names

**Python tests:**
```python
import pytest
from agent.tools.file_operations import read_file

@pytest.mark.asyncio
async def test_read_file_success():
    """Test reading an existing file."""
    result = await read_file("test_file.txt")
    assert "content" in result

@pytest.mark.asyncio
async def test_read_file_not_found():
    """Test reading a non-existent file."""
    result = await read_file("nonexistent.txt")
    assert "Error" in result
```

**Go tests:**
```go
func TestClient_CreateSession(t *testing.T) {
    client := NewClient("http://localhost:8000")
    session, err := client.CreateSession(context.Background(), nil)
    if err != nil {
        t.Fatalf("CreateSession failed: %v", err)
    }
    if session.ID == "" {
        t.Error("Expected session ID to be set")
    }
}
```

### Running Tests

```bash
# All Python tests
pytest

# With coverage
pytest --cov=agent --cov-report=html

# Specific test file
pytest tests/test_agent/test_tools/test_file_operations.py

# Go tests
go test ./...

# With verbose output
go test -v ./...
```

## Pull Request Process

1. **Ensure all tests pass** before submitting

2. **Update documentation** if needed (README, docstrings, etc.)

3. **Create a pull request** with:
   - Clear title describing the change
   - Description of what and why
   - Link to any related issues

4. **Address review feedback** promptly

5. **Squash commits** if requested before merge

### PR Checklist

- [ ] Tests pass locally
- [ ] New code has tests
- [ ] Documentation updated
- [ ] No security vulnerabilities introduced
- [ ] Code follows style guidelines

## Security

If you discover a security vulnerability, please:

1. **Do NOT** open a public issue
2. Email the maintainers privately
3. Include details to reproduce the issue
4. Allow time for a fix before disclosure

## Areas for Contribution

### High Priority

- Implement web search tool (integrate with Tavily, SerpAPI, etc.)
- Add more comprehensive test coverage
- Improve error messages and handling
- Performance optimizations

### Good First Issues

- Documentation improvements
- Adding type hints to Python code
- Writing additional tests
- Fixing typos and small bugs

### Feature Ideas

- Session persistence (database storage)
- Multiple model provider support
- Plugin system for custom tools
- Web UI alternative to TUI

## Questions?

- Open a GitHub issue for bugs or feature requests
- Start a discussion for questions or ideas

Thank you for contributing!
