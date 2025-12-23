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
│                          AI Agent Access                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│  Claude Code ←→ Prometheus MCP Server ←→ Prometheus API                     │
│  (Tools: prometheus_query, service_health, error_analysis, etc.)            │
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

### 5. Prometheus MCP Server (AI Agent)

Enables AI agents (Claude Code) to query metrics programmatically.

**Location**: `mcp/prometheus-mcp/`

**Tools Available**:
- `prometheus_query` - Execute instant PromQL queries
- `prometheus_query_range` - Execute range queries
- `prometheus_series` - List time series
- `prometheus_labels` - Get label names/values
- `prometheus_targets` - Get scrape targets
- `prometheus_alerts` - Get current alerts
- `service_health` - Quick health summary
- `error_analysis` - Analyze error patterns
- `latency_analysis` - Analyze request latency

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

With the Prometheus MCP server configured, Claude Code can:

```
# Check service health
> Use the service_health tool

# Analyze recent errors
> Use error_analysis with duration="15m"

# Check latency
> Use latency_analysis with duration="1h"

# Custom queries
> Use prometheus_query with query="up"
```

## File Structure

```
monitoring/
├── README.md                           # This file
├── prometheus/
│   └── prometheus.yml                  # Prometheus configuration
├── grafana/
│   ├── provisioning/
│   │   ├── datasources/
│   │   │   └── datasources.yml        # Data source config
│   │   └── dashboards/
│   │       └── dashboards.yml         # Dashboard provider config
│   └── dashboards/
│       └── plue-overview.json         # Main dashboard
├── loki/
│   └── loki-config.yml                # Loki configuration
└── promtail/
    └── promtail-config.yml            # Promtail configuration

mcp/
└── prometheus-mcp/
    ├── package.json
    ├── tsconfig.json
    └── src/
        └── index.ts                   # MCP server implementation
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
