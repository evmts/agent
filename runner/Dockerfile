# Runner container for executing agents and workflows in sandboxed K8s pods
FROM python:3.12-slim

# Install system dependencies and uv
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    jq \
    && rm -rf /var/lib/apt/lists/* \
    && curl -LsSf https://astral.sh/uv/install.sh | sh

ENV PATH="/root/.local/bin:$PATH"

# Create non-root user
RUN useradd -m -u 1000 runner
WORKDIR /app

# Install Python dependencies with uv (faster, reproducible)
COPY pyproject.toml uv.lock* ./
RUN uv sync --frozen --no-dev

# Copy application code
COPY . ./runner/

# Switch to non-root user
USER 1000:1000

# Set working directory for execution
WORKDIR /workspace

# Entry point - use uv run for proper environment
ENTRYPOINT ["uv", "run", "python", "-m", "runner.main"]
