# Runner container for executing agents and workflows in sandboxed K8s pods
FROM python:3.12-slim

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN useradd -m -u 1000 runner
WORKDIR /app

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY src/ ./src/

# Switch to non-root user
USER 1000:1000

# Set working directory for execution
WORKDIR /workspace

# Entry point
ENTRYPOINT ["python", "-m", "src.main"]
