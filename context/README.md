# Context Dependencies

This directory contains the GitHub repositories for all Python dependencies used in the agent project. These provide reference documentation and source code for understanding the libraries we depend on.

## Dependencies Added

### Core Web Framework
- **fastapi/** - Modern, fast web framework for building APIs with Python
  - Repository: https://github.com/fastapi/fastapi
  - Used for: REST API server implementation

- **uvicorn/** - ASGI web server for Python
  - Repository: https://github.com/encode/uvicorn
  - Used for: Running the FastAPI server

### Streaming & Server-Sent Events
- **sse-starlette/** - Server-Sent Events support for Starlette/FastAPI
  - Repository: https://github.com/sysid/sse-starlette
  - Used for: Real-time streaming responses to clients

### AI & Agent Libraries
- **pydantic-ai/** - Type-safe AI agent framework (already present)
  - Repository: https://github.com/pydantic/pydantic-ai
  - Used for: Core agent implementation with Claude

- **strands-agents/** - Model-driven AI agent SDK
  - Repository: https://github.com/strands-agents/sdk-python
  - Used for: Agent framework and tooling

- **strands-agents-tools/** - Tool ecosystem for AI agents
  - Repository: https://github.com/strands-agents/tools
  - Used for: Pre-built tools for file operations, system execution, etc.

- **anthropic-sdk-python/** - Official Anthropic Python client
  - Repository: https://github.com/anthropics/anthropic-sdk-python
  - Used for: Claude LLM API integration

### HTTP & Web Operations
- **httpx/** - Next generation HTTP client for Python
  - Repository: https://github.com/encode/httpx
  - Used for: Making HTTP requests in tools (web fetching, API calls)

### Version Control
- **GitPython/** - Python library for Git repository interaction
  - Repository: https://github.com/gitpython-developers/GitPython
  - Used for: Snapshot system for file state tracking

### Web Scraping & Parsing
- **beautifulsoup/** - HTML/XML parsing library
  - Repository: https://github.com/tec-cloud/beautifulsoup (mirror)
  - Used for: Extracting text content from web pages

### Testing Framework
- **pytest/** - Testing framework for Python
  - Repository: https://github.com/pytest-dev/pytest
  - Used for: Unit and integration testing

- **pytest-asyncio/** - Asyncio support for pytest
  - Repository: https://github.com/pytest-dev/pytest-asyncio
  - Used for: Testing async code

## Usage

These repositories are provided for reference and understanding the underlying libraries. You can browse their documentation, source code, and examples to better understand how the agent system works and how to extend it.

Each repository contains:
- Source code and implementation details
- Documentation and examples
- Issue tracking and discussions
- Contribution guidelines

## Note

These are git clones of the official repositories and may not always reflect the exact versions specified in `pyproject.toml`. For the exact versions used in the project, refer to the lock file (`uv.lock`) or the version constraints in `pyproject.toml`.