# Plue Observability Stack

Comprehensive monitoring, logging, and debugging infrastructure for the Plue platform.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Data Sources                                    │
├─────────────┬─────────────┬─────────────┬─────────────────────────────────────┤
│  Zig API    │  Astro Web  │  PostgreSQL │  Docker Containers                  │
│  /metrics   │  Telemetry  │  Exporter   │  cAdvisor                           │
└──────┬──────┴──────┬──────┴──────┬──────┴──────────────┬─────────────────────┘
       │             │             │                      │
       │             │             │                      │
       ▼             ▼             ▼                      ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│                           Prometheus (Port 9090)                             │
│                        - Metrics scraping & storage                          │
│                        - PromQL query engine                                 │
└─────────────────────────────────────┬────────────────────────────────────────┘
                                      │
                                      ▼
                              ┌───────────────┐
                              │   Grafana     │
                              │  (Port 3001)  │
                              │ - Dashboards  │
                              │ - Alerting    │
                              └───────────────┘

┌──────────────────────────────────────────────────────────────────────────────┐
│                              Log Collection                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│  Docker Container Logs → Promtail → Loki (Port 3100) → Grafana             │
│  (JSON structured logs)                                                      │
└──────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────────┐
│                          AI Agent Access (MCP Servers)                       │
├─────────────────────────────────────────────────────────────────────────────┤
│  Claude Code ←→ prometheus-mcp   ←→ Prometheus API (metrics)                │
│              ←→ workflows-mcp    ←→ PostgreSQL (workflow runs/steps)        │
│              ←→ logs-mcp         ←→ Loki API (application logs)             │
│              ←→ database-mcp     ←→ PostgreSQL (direct queries)             │
│              ←→ playwright-mcp   ←→ Test results (e2e debugging)            │
└──────────────────────────────────────────────────────────────────────────────┘
```

## Quick Start

### Start the Monitoring Stack

```bash
# Start all services including monitoring
docker-compose -f infra/docker/docker-compose.yaml up -d

# Or start just the monitoring stack
docker-compose -f infra/docker/docker-compose.yaml up -d prometheus grafana loki promtail postgres-exporter cadvisor
```

### Access Points

| Service     | URL                      | Credentials          |
|-------------|--------------------------|----------------------|
| Grafana     | http://localhost:3001    | admin / plue123      |
| Prometheus  | http://localhost:9090    | -                    |
| Loki        | http://localhost:3100    | -                    |

## Components

### 1. Prometheus (Metrics)

Scrapes metrics from all services at configured intervals.

**Configuration**: `monitoring/prometheus/prometheus.yml`

**Scraped Targets**:
- `api:4000/metrics` - Zig API server
- `web:5173/metrics` - Astro web server
- `postgres-exporter:9187` - PostgreSQL metrics
- `cadvisor:8080` - Docker container metrics

### 2. Grafana (Visualization)

Pre-configured with data sources and dashboards.

**Configuration**: `monitoring/grafana/provisioning/`

**Dashboards**:
- **Plue Overview** - Service health, request rates, latency, errors, logs

### 3. Loki (Logs)

Aggregates logs from all Docker containers.

**Configuration**: `monitoring/loki/loki-config.yml`

### 4. Promtail (Log Shipper)

Collects Docker container logs and ships to Loki.

**Configuration**: `monitoring/promtail/promtail-config.yml`

### 5. MCP Servers (AI Agent Observability)

Five MCP servers enable AI agents to query, debug, and analyze the system:

#### prometheus-mcp (Metrics)

**Location**: `infra/monitoring/prometheus.ts`

| Tool | Description |
|------|-------------|
| `prometheus_query` | Execute instant PromQL queries |
| `prometheus_query_range` | Execute range queries over time |
| `prometheus_series` | List time series matching labels |
| `prometheus_labels` | Get label names/values |
| `prometheus_targets` | Get scrape targets and health |
| `prometheus_alerts` | Get current firing alerts |
| `service_health` | Quick health summary of all services |
| `error_analysis` | Analyze error patterns and rates |
| `latency_analysis` | Analyze request latency (p50/p95/p99) |

#### workflows-mcp (Workflow Debugging)

**Location**: `infra/monitoring/workflows.ts`

| Tool | Description |
|------|-------------|
| `system_overview` | **START HERE** - Quick snapshot of entire workflow system |
| `quick_debug` | **NEW** One-stop debugging for failed runs (latest=true or run_id=X) |
| `compare_runs` | **NEW** Compare two runs to find regressions |
| `list_workflow_runs` | List recent runs with status/filters |
| `get_run_details` | Step-by-step execution details |
| `get_step_logs` | View logs for a specific step |
| `get_run_logs` | All logs for a workflow run |
| `analyze_failures` | Find failure patterns over time |
| `get_runner_pool` | Warm pool status and health |
| `get_pending_tasks` | Tasks waiting for runners |
| `workflow_stats` | Success rates, durations, throughput |
| `get_workflow_definition` | View workflow plan DAG |
| `recent_agent_activity` | LLM calls, tokens, tool usage |

#### logs-mcp (Log Analysis)

**Location**: `infra/monitoring/logs.ts`

| Tool | Description |
|------|-------------|
| `search_logs` | Search logs with LogQL queries |
| `tail_logs` | Get most recent logs from a service |
| `find_errors` | Find error logs grouped by type |
| `trace_request` | Trace request by ID through all services |
| `find_slow_requests` | Find requests exceeding duration threshold |
| `log_stats` | Log volume and error rates by service |
| `search_exceptions` | Find stack traces and exceptions |
| `workflow_logs` | Logs for specific workflow runs |
| `agent_logs` | AI agent execution logs |

#### database-mcp (Database Debugging)

**Location**: `infra/monitoring/database.ts`

| Tool | Description |
|------|-------------|
| `query` | Execute read-only SQL queries |
| `describe_table` | Get table schema and constraints |
| `list_tables` | List all tables with sizes |
| `find_user` | Find user by username/email/ID |
| `find_repository` | Find repo with workflows and runs |
| `recent_activity` | New users, repos, runs in time window |
| `db_stats` | Database size, connections, tables |
| `find_sessions` | Active user sessions |
| `check_connections` | Active queries and connection pool |
| `explain_query` | EXPLAIN ANALYZE for performance |

#### playwright-mcp (Test Debugging)

**Location**: `infra/monitoring/playwright.ts`

| Tool | Description |
|------|-------------|
| `test_summary` | Overall test run summary |
| `list_failures` | Failed tests with error messages |
| `test_details` | Specific test details and attachments |
| `view_attachment` | View console/network logs |
| `failure_patterns` | Group failures by error pattern |
| `flaky_tests` | Tests that passed on retry |
| `slow_tests` | Tests exceeding duration threshold |
| `test_artifacts` | Available traces/screenshots/videos |
| `list_test_files` | All test files with pass/fail counts |

## Metrics Reference

### API Server Metrics

| Metric | Type | Description |
|--------|------|-------------|
| `plue_uptime_seconds` | Gauge | Server uptime |
| `plue_http_requests_total` | Counter | Total HTTP requests by method/path/status |
| `plue_http_request_duration_ms` | Histogram | Request latency distribution |
| `plue_auth_attempts_total` | Counter | Authentication attempts by result/method |
| `plue_active_sessions` | Gauge | Current active user sessions |
| `plue_active_websockets` | Gauge | Current WebSocket connections |
| `plue_active_pty_sessions` | Gauge | Current PTY sessions |
| `plue_db_queries_total` | Counter | Total database queries |
| `plue_db_query_errors_total` | Counter | Database query errors |

### Example Queries

```promql
# Request rate per second
rate(plue_http_requests_total[5m])

# P95 latency
histogram_quantile(0.95, rate(plue_http_request_duration_ms_bucket[5m]))

# Error rate
sum(rate(plue_http_requests_total{status=~"5.."}[5m]))

# Auth failure rate
increase(plue_auth_attempts_total{result!="success"}[15m])
```

## Frontend Telemetry

Client-side error tracking and performance monitoring.

**Module**: `ui/lib/telemetry.ts`

**Features**:
- Automatic error capture (uncaught exceptions, unhandled rejections)
- Performance metrics (page load, TTFB)
- User interaction tracking
- Network request monitoring
- Timeout handling for async operations

**Usage**:
```typescript
import { initTelemetry, logError, withTimeout } from '../lib/telemetry';

// Initialize (once on page load)
initTelemetry();

// Log errors
try {
  await riskyOperation();
} catch (error) {
  logError(error, { context: 'some-operation' });
}

// Add timeout to async operations
await withTimeout(fetchData(), 30000, 'fetch-data');
```

## Debugging Workflows

### 1. Service Down

```bash
# Check which services are down
curl -s 'http://localhost:9090/api/v1/query?query=up' | jq

# Or in Grafana: Look at the "Service Health" panel
```

### 2. High Latency

```promql
# Find slowest endpoints
topk(10, histogram_quantile(0.95, rate(plue_http_request_duration_ms_bucket[5m])))
```

### 3. Error Investigation

```promql
# Find endpoints with most errors
topk(10, increase(plue_http_requests_total{status=~"5.."}[1h]))
```

### 4. Auth Issues

```promql
# Auth failure breakdown
sum by (result, method) (increase(plue_auth_attempts_total{result!="success"}[1h]))
```

### 5. Viewing Logs

In Grafana:
1. Go to Explore
2. Select "Loki" data source
3. Query: `{job="containerlogs"} |= "error"`

## AI Agent Usage

### MCP Servers

With MCP servers configured (`.mcp.json`), Claude Code can directly query:

```
# Check service health (prometheus-mcp)
> Use service_health tool

# Debug workflow failures (workflows-mcp)
> Use list_workflow_runs with status="failed"
> Use get_run_details with run_id=42

# Search logs (logs-mcp)
> Use find_errors with start="1h"
> Use trace_request with request_id="abc-123"

# Query database (database-mcp)
> Use query with sql="SELECT * FROM users LIMIT 5"
> Use db_stats

# Debug test failures (playwright-mcp)
> Use list_failures
> Use test_details with testTitle="login"
```

### Auto-Invoked Skills

Skills are automatically discovered and used by Claude based on context. No need to type `/command` - just ask about the topic and Claude will use the appropriate skill.

| Skill | Auto-Invoked When | Location |
|-------|-------------------|----------|
| **observability** | Asking about system health, errors, logs, metrics, debugging | `.claude/skills/observability/` |
| **workflow-debugging** | Investigating workflow failures, step errors, agent issues | `.claude/skills/workflow-debugging/` |
| **test-debugging** | Debugging Playwright test failures, flaky tests | `.claude/skills/test-debugging/` |

**Examples of auto-invocation:**
- "Why is the system slow?" → observability skill
- "Debug the latest workflow failure" → workflow-debugging skill
- "What tests are failing?" → test-debugging skill

### Slash Commands

Explicitly invoked debugging workflows:

| Command | Description | Usage |
|---------|-------------|-------|
| `/observability` | Unified dashboard - quick system status | `/observability` or `/observability --full` |
| `/debug-workflows` | Debug workflow execution issues | `/debug-workflows 42` or `/debug-workflows --recent` |
| `/health-check` | Quick system health diagnostics | `/health-check --quick` or `/health-check --full` |
| `/trace-request` | Trace request end-to-end | `/trace-request abc-123` |

### Skills vs Commands

| Feature | Skills (Auto) | Commands (Slash) |
|---------|---------------|------------------|
| Invocation | Automatic based on context | Explicit `/command` |
| Discovery | Claude reads description | User types command |
| Best for | Natural conversation | Quick, specific tasks |
| Location | `.claude/skills/` | `.claude/commands/` |

### Skill Details

#### observability

Comprehensive system monitoring skill:
- Uses all MCP servers (workflows, logs, database, prometheus, playwright)
- Provides debugging decision tree
- Includes common debugging workflows
- Auto-invoked for: health, errors, failures, logs, metrics

#### workflow-debugging

Specialized workflow debugging:
- `quick_debug(latest=true)` - One-stop debugging
- `compare_runs(run_id_a, run_id_b)` - Find regressions
- Common failure patterns with solutions
- Database queries for investigation
- Auto-invoked for: workflow runs, step failures, agent errors

#### test-debugging

Playwright E2E test debugging:
- Test summary and failure listing
- Failure pattern analysis
- Flaky test detection
- Performance bottleneck identification
- Auto-invoked for: test failures, e2e tests, Playwright issues

## File Structure

```
infra/monitoring/
├── README.md                           # This file
├── prometheus.ts                       # Prometheus MCP server
├── workflows.ts                        # Workflows MCP server
├── logs.ts                             # Loki logs MCP server
├── database.ts                         # Database MCP server
├── playwright.ts                       # Playwright MCP server
├── prometheus/
│   └── prometheus.yml                  # Prometheus configuration
├── grafana/
│   ├── provisioning/
│   │   ├── datasources/
│   │   │   └── datasources.yml        # Data source config
│   │   └── dashboards/
│   │       └── dashboards.yml         # Dashboard provider config
│   └── dashboards/
│       ├── plue-overview.json         # Main dashboard
│       └── plue-workflows.json        # Workflows dashboard
├── loki/
│   └── loki-config.yml                # Loki configuration
└── promtail/
    └── promtail-config.yml            # Promtail configuration

.claude/commands/
├── observability.md                    # Unified observability command
├── debug-workflows.md                  # Workflow debugging command
├── health-check.md                     # System health check command
└── trace-request.md                    # Request tracing command

.claude/skills/
├── observability/SKILL.md              # Auto-invoked observability skill
├── workflow-debugging/SKILL.md         # Auto-invoked workflow debugging skill
└── test-debugging/SKILL.md             # Auto-invoked test debugging skill
```

## Troubleshooting

### Prometheus not scraping

1. Check targets: http://localhost:9090/targets
2. Verify service is exposing `/metrics` endpoint
3. Check network connectivity between containers

### Grafana shows "No data"

1. Verify Prometheus is running and has data
2. Check datasource configuration
3. Adjust time range

### Logs not appearing in Loki

1. Verify Promtail is running: `docker-compose logs promtail`
2. Check Promtail configuration paths
3. Ensure containers are outputting JSON logs

### MCP Server not connecting

1. Check Prometheus is accessible at configured URL
2. Verify `.mcp.json` configuration
3. Restart Claude Code to reload MCP servers
