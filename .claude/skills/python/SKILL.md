---
name: python
description: Python development standards for Plue. Use when working with Python code, dependencies, or the runner.
---

# Python Development

## Package Manager: uv

We use **uv** (by Astral) for Python package management. It's 10-100x faster than pip.

### Key Commands

```bash
# Install dependencies
uv sync

# Add a dependency
uv add <package>

# Add dev dependency
uv add --dev <package>

# Run Python with dependencies
uv run python -m runner.main

# Run tests
uv run pytest
```

### Project Structure

```
runner/
├── pyproject.toml    # Project config and dependencies
├── uv.lock           # Lockfile (commit this)
├── __init__.py
├── main.py
└── ...
```

### pyproject.toml

```toml
[project]
name = "plue-runner"
version = "0.1.0"
requires-python = ">=3.12"
dependencies = [
    "anthropic>=0.39.0",
    "httpx>=0.27.0",
]

[dependency-groups]
dev = [
    "pytest>=8.0.0",
]
```

## Important: No venv, No pip

- Do NOT use `python -m venv` or `virtualenv`
- Do NOT use `pip install`
- Do NOT create `requirements.txt`
- Always use `uv` commands instead

## Docker

Use uv in Dockerfiles:

```dockerfile
# Install uv
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.local/bin:$PATH"

# Install dependencies
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev

# Run with uv
ENTRYPOINT ["uv", "run", "python", "-m", "runner.main"]
```

## Related Skills

- `runner` - Agent execution environment
- `docker` - Container configuration
