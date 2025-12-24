# Structured Logging

Plue uses structured JSON logging across all components for consistent log aggregation and analysis.

## Overview

All services output JSON-formatted logs with:
- **timestamp**: ISO 8601 UTC timestamp
- **level**: Log level (DEBUG, INFO, WARNING, ERROR)
- **service**: Service identifier (edge, runner, api, etc.)
- **request_id**: Unique request identifier for distributed tracing
- **message**: Human-readable log message
- **context**: Additional structured metadata

## Request ID Propagation

Request IDs flow through the system for end-to-end tracing:

1. **Edge Worker** generates or accepts `X-Request-ID` header
2. **Edge** propagates `X-Request-ID` to origin server
3. **Origin** receives and uses `X-Request-ID` for all logging
4. **Runner** receives `REQUEST_ID` environment variable from server
5. All responses include `X-Request-ID` header

```
┌──────────┐  X-Request-ID   ┌──────────┐  X-Request-ID   ┌──────────┐  REQUEST_ID    ┌──────────┐
│  Client  │ ───────────────>│   Edge   │ ───────────────>│  Server  │ ──────────────>│  Runner  │
└──────────┘  (generated)    └──────────┘  (propagated)   └──────────┘  (env var)     └──────────┘
                                  │                            │                            │
                                  ▼                            ▼                            ▼
                              JSON Logs                   JSON Logs                   JSON Logs
```

## Edge Worker (TypeScript)

The edge worker uses the `Logger` class from `edge/lib/logger.ts`.

### Usage

```typescript
import { Logger } from './lib/logger';

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const logger = new Logger(request);

    logger.info('Request started');
    logger.info('Cache hit', { cacheKey: 'foo' });
    logger.warn('Rate limited', { limitType: 'api' });
    logger.error('Origin failed', new Error('Connection timeout'));

    const response = await handleRequest(request, env);
    response.headers.set('X-Request-ID', logger.getRequestId());

    return response;
  }
};
```

### Log Format

```json
{
  "level": "info",
  "message": "Request started",
  "timestamp": "2025-12-24T07:52:15.517472Z",
  "context": {
    "requestId": "550e8400-e29b-41d4-a716-446655440000",
    "clientIP": "203.0.113.42",
    "path": "/api/repos",
    "method": "GET"
  },
  "duration_ms": 125
}
```

## Runner (Python)

The runner uses structured logging from `runner/logger.py`.

### Usage

```python
from logger import configure_logging, get_logger

# Configure on startup (reads TASK_ID and REQUEST_ID from environment)
configure_logging(level="INFO")

# Get logger for module
logger = get_logger(__name__)

# Log with context
logger.info("Starting workflow", extra={"workflow_id": 123, "step": "build"})
logger.warning("High memory usage", extra={"memory_mb": 512})

# Log exceptions with stack traces
try:
    execute_task()
except Exception:
    logger.exception("Task failed")
```

### Log Format

```json
{
  "timestamp": "2025-12-24T07:52:15.517472Z",
  "level": "INFO",
  "service": "runner",
  "logger": "workflow.executor",
  "message": "Starting workflow",
  "task_id": "task-123",
  "request_id": "req-abc-456",
  "context": {
    "workflow_id": 123,
    "step": "build"
  }
}
```

### Error Logs

```json
{
  "timestamp": "2025-12-24T07:52:15.518336Z",
  "level": "ERROR",
  "service": "runner",
  "logger": "workflow.executor",
  "message": "Task failed",
  "task_id": "task-123",
  "request_id": "req-abc-456",
  "error": "Invalid configuration",
  "stack": "Traceback (most recent call last):\n  File \"executor.py\", line 42, in run\n    validate_config(config)\nValueError: Invalid configuration\n"
}
```

## Environment Variables

### Runner

- `LOG_LEVEL`: Log level (DEBUG, INFO, WARNING, ERROR) - defaults to INFO
- `TASK_ID`: Task identifier - included in all logs
- `REQUEST_ID`: Request identifier - propagated from server

### Edge

No configuration needed - request ID is generated or extracted from `X-Request-ID` header.

## Log Aggregation

All logs are collected by:
- **Loki**: Log aggregation and querying (Grafana)
- **Prometheus**: Metrics derived from logs
- **Grafana**: Visualization and alerting

### Example Loki Queries

```logql
# All errors from runner
{service="runner"} | json | level="ERROR"

# Logs for specific request
{request_id="550e8400-e29b-41d4-a716-446655440000"}

# High memory warnings
{service="runner"} | json | context_memory_mb > 500

# Error rate by service
rate({level="ERROR"}[5m])
```

## Best Practices

1. **Always use structured context**: Pass extra fields via `extra={}` (Python) or as object (TypeScript)
2. **Include request_id**: Ensure REQUEST_ID environment variable is set for runners
3. **Log exceptions properly**: Use `logger.exception()` to capture stack traces
4. **Avoid logging secrets**: Never log API keys, tokens, or sensitive data
5. **Use appropriate levels**:
   - DEBUG: Detailed diagnostic information
   - INFO: Normal operation events
   - WARNING: Unexpected but handled conditions
   - ERROR: Error conditions that should be investigated

## Testing

### Python Runner

```bash
cd runner
python test_logger.py
```

### Edge Worker

```bash
cd edge
npm test -- logger.test.ts
```
