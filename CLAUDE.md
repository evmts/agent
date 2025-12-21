# Plue

A brutalist GitHub clone with integrated AI agent capabilities. Combines a minimal web interface for repository/issue management with an autonomous Claude-powered agent system.

## Project Structure

```
plue/
├── ui/                    # Astro SSR frontend
│   ├── components/        # Astro components (Terminal, FileTree, etc.)
│   ├── pages/             # File-based routing
│   ├── layouts/           # Base layout with brutalist CSS
│   └── lib/               # Frontend utilities (db, git, markdown, telemetry)
├── server/                # Zig API server (httpz)
│   ├── src/
│   │   ├── main.zig       # Entry point with WebSocket support
│   │   ├── routes.zig     # Route definitions
│   │   ├── config.zig     # Server configuration
│   │   ├── routes/        # API route handlers
│   │   ├── middleware/    # Auth, CORS, rate limiting
│   │   ├── lib/           # DB client, JWT, SIWE auth, metrics
│   │   ├── ai/            # AI agent system
│   │   │   ├── agent.zig  # Agent runner (Claude API)
│   │   │   ├── registry.zig
│   │   │   └── tools/     # Agent tools (grep, file ops, etc.)
│   │   ├── websocket/     # WebSocket + PTY handling
│   │   └── ssh/           # SSH server for git operations
│   ├── jj-ffi/            # Rust FFI for jj-lib (snapshots)
│   └── build.zig          # Zig build configuration
├── core/                  # Core session/state management (Zig)
│   └── src/
│       ├── state.zig      # Dual-layer state (runtime + DB)
│       ├── events.zig     # EventBus pub/sub system
│       ├── models/        # Data models (message, session, part)
│       └── exceptions.zig # Error types
├── db/                    # Database layer
│   └── schema.sql         # PostgreSQL schema
├── monitoring/            # Observability infrastructure
│   ├── prometheus/        # Prometheus config
│   ├── grafana/           # Grafana dashboards & provisioning
│   ├── loki/              # Loki log aggregation config
│   └── promtail/          # Log shipping config
├── mcp/                   # MCP servers for AI agents
│   └── prometheus-mcp/    # Prometheus metrics querying
├── tui/                   # Terminal UI client (Bun)
├── edge/                  # Cloudflare Workers edge proxy
├── snapshot/              # Rust/napi-rs jj-lib bindings
├── terraform/             # Infrastructure as code
│   ├── environments/      # Production config
│   ├── kubernetes/        # K8s resources
│   └── modules/           # Reusable modules
└── e2e/                   # Playwright end-to-end tests
```

## Tech Stack

- **Runtime**: Zig (server), Bun (frontend/TUI)
- **Frontend**: Astro v5 (SSR, file-based routing)
- **Backend**: Zig + httpz (HTTP/WebSocket)
- **Database**: PostgreSQL + ElectricSQL (real-time sync)
- **AI**: Claude API (direct integration)
- **Monitoring**: Prometheus, Grafana, Loki (metrics, dashboards, logs)
- **Infrastructure**: Docker, Kubernetes, Terraform

## Build System

The root `build.zig` is the single entrypoint for all operations. Run from repo root (never `cd` into subdirectories).

### Quick Reference

```bash
zig build              # Build all (server + web + edge + tui)
zig build run          # Start dev environment (docker + server)
zig build test         # Run all tests (Zig + TS + Rust)
zig build lint         # Lint all code
zig build format       # Format all code
zig build ci           # Full CI pipeline
```

### Build Commands

```bash
zig build              # Build everything (default)
zig build server       # Build Zig server only
zig build web          # Build Astro frontend only
zig build edge         # Build Cloudflare Worker only
zig build tui          # Build TUI only
```

### Run Commands

```bash
zig build run          # Full dev: docker + server (recommended)
zig build run:docker   # Start postgres + electric only
zig build run:server   # Run Zig server only
zig build run:web      # Run Astro dev server only
```

### Test Commands

```bash
zig build test         # All unit tests (Zig + TS + Rust)
zig build test:zig     # All Zig tests (server + core)
zig build test:ts      # All TypeScript tests
zig build test:rust    # All Rust tests (jj-ffi + snapshot)
zig build test:e2e     # Playwright E2E tests
zig build test:server  # Server Zig tests only
zig build test:edge    # Edge worker tests only
```

### Lint & Format

```bash
zig build lint         # Lint ALL (zig fmt --check + eslint + clippy)
zig build lint:zig     # Zig format check
zig build lint:ts      # ESLint
zig build lint:rust    # Clippy

zig build format       # Format ALL (zig fmt + eslint --fix + cargo fmt)
zig build format:zig   # Format Zig
zig build format:ts    # Format TypeScript
zig build format:rust  # Format Rust
```

### CI & Utilities

```bash
zig build ci           # Full CI: lint + test + build
zig build check        # Quick: lint + typecheck
zig build clean        # Clean all build artifacts
zig build deps         # Install dependencies (bun install)
zig build docker       # Build Docker images
zig build docker:up    # Start all Docker services
zig build docker:down  # Stop all Docker services
zig build db:migrate   # Run database migrations
zig build db:seed      # Seed test data
```

## Conventions

### Zig
- Dependencies managed via `build.zig.zon`
- Zig 0.15.1+ required

### Bun/TypeScript
- Use `bun` not `node/npm/yarn`
- Bun auto-loads `.env`

### Rust
- Used for jj-lib FFI (`server/jj-ffi/`)
- Cargo builds integrated into Zig build

## Development Workflow

```bash
# First time setup
zig build deps         # Install bun dependencies

# Start development
zig build run          # Starts docker + server

# In another terminal (optional)
zig build run:web      # Start Astro dev server

# Before committing
zig build check        # Quick lint + typecheck
zig build test         # Run all tests
```

### Git Workflow

**Single-branch development**: All work happens on the `plue-git` branch. Do NOT create feature branches or fix branches - commit directly to `plue-git`.

```bash
# Always work on plue-git
git checkout plue-git

# Make changes and commit directly
git add .
git commit -m "feat: description"

# Push when ready
git push origin plue-git
```

## Testing

```bash
# Run all tests
zig build test

# Run specific test suites
zig build test:zig     # Zig unit tests
zig build test:ts      # TypeScript/vitest
zig build test:rust    # Rust/cargo test
zig build test:e2e     # Playwright (requires running services)
```

## Observability & Monitoring

The project includes comprehensive observability infrastructure for debugging issues.

### Monitoring Stack

```bash
# Start all services including monitoring
docker-compose up -d

# Access points:
# - Grafana:    http://localhost:3001  (admin / plue123)
# - Prometheus: http://localhost:9090
# - Loki:       http://localhost:3100
```

### Components

| Component | Port | Purpose |
|-----------|------|---------|
| Prometheus | 9090 | Metrics collection & querying |
| Grafana | 3001 | Dashboards & visualization |
| Loki | 3100 | Log aggregation |
| Promtail | - | Ships Docker logs to Loki |
| postgres-exporter | 9187 | PostgreSQL metrics |
| cAdvisor | 8081 | Docker container metrics |

### Metrics

The Zig API server exposes Prometheus metrics at `/metrics`:

```bash
curl http://localhost:4000/metrics
```

Key metrics:
- `plue_http_requests_total` - Request counts by method/path/status
- `plue_http_request_duration_ms` - Latency histogram
- `plue_auth_attempts_total` - Auth attempts by result
- `plue_active_sessions` - Current active sessions
- `plue_active_websockets` - Current WebSocket connections

### Grafana Dashboards

Pre-configured dashboards are auto-provisioned:
- **Plue Overview** - Service health, request rates, latency, errors, logs

### Frontend Telemetry

Client-side error tracking via `ui/lib/telemetry.ts`:

```typescript
import { initTelemetry, logError, withTimeout } from '../lib/telemetry';

// Initialize on page load
initTelemetry();

// Wrap async operations with timeout
await withTimeout(fetchData(), 30000, 'fetch-data');

// Manual error logging
logError(error, { context: 'some-operation' });
```

### AI Agent Observability (Prometheus MCP)

The Prometheus MCP server (`mcp/prometheus-mcp/`) enables AI agents to query metrics.

> **Note**: After adding MCP servers to `.mcp.json`, restart Claude Code to load them.
> The tools will appear as `service_health`, `error_analysis`, `prometheus_query`, etc.

**Configuration** (`.mcp.json`):
```json
{
  "mcpServers": {
    "prometheus": {
      "command": "bun",
      "args": ["run", "mcp/prometheus-mcp/src/index.ts"],
      "env": { "PROMETHEUS_URL": "http://localhost:9090" }
    }
  }
}
```

**Available Tools**:
- `service_health` - Quick UP/DOWN status of all services
- `error_analysis` - Analyze error rates and patterns
- `latency_analysis` - P50/P95/P99 latency breakdown
- `prometheus_query` - Execute raw PromQL queries
- `prometheus_query_range` - Query metrics over time
- `prometheus_targets` - Check scrape target health
- `prometheus_alerts` - Get current alerts

**Example Usage** (in Claude Code):
```
> Check if all services are healthy
> Analyze errors from the last 15 minutes
> What's the P95 latency for the API?
```

### Debugging Workflows

**Service Down:**
```promql
up == 0
```

**High Error Rate:**
```promql
sum(rate(plue_http_requests_total{status=~"5.."}[5m])) > 0.1
```

**Slow Endpoints:**
```promql
topk(5, histogram_quantile(0.95, rate(plue_http_request_duration_ms_bucket[5m])))
```

**Auth Failures:**
```promql
increase(plue_auth_attempts_total{result!="success"}[1h])
```

**View Logs in Grafana:**
1. Go to Explore → Select "Loki"
2. Query: `{job="containerlogs"} |= "error"`

### File Structure

```
monitoring/
├── prometheus/prometheus.yml     # Scrape configuration
├── grafana/
│   ├── provisioning/            # Auto-provisioned datasources
│   └── dashboards/              # Pre-built dashboards
├── loki/loki-config.yml         # Log storage config
├── promtail/promtail-config.yml # Log collection config
└── README.md                    # Detailed documentation

mcp/prometheus-mcp/              # Prometheus MCP server
├── src/index.ts                 # MCP implementation
└── package.json

mcp/playwright-mcp/              # Playwright test results MCP server
├── src/index.ts                 # MCP implementation
└── package.json
```

## E2E Testing with Playwright

Comprehensive E2E test infrastructure with full observability.

### Running Tests

```bash
# Run all tests
bun playwright test

# Run specific test file
bun playwright test e2e/auth.spec.ts

# Run with UI mode (interactive debugging)
bun playwright test --ui

# Run in headed mode (see browser)
bun playwright test --headed

# Run specific test by name
bun playwright test -g "login"
```

### Test Artifacts

Tests are configured to capture debugging artifacts on failure:

| Artifact | Location | When |
|----------|----------|------|
| Screenshots | `test-results/` | On failure |
| Videos | `test-results/` | On failure |
| Traces | `test-results/` | On failure |
| Console logs | Attached to report | On failure |
| Network logs | Attached to report | On failure |
| JSON results | `test-results/results.json` | Always |
| HTML report | `playwright-report/` | Always |

### Viewing Reports

```bash
# Open HTML report
bun playwright show-report

# View trace file
bun playwright show-trace test-results/path/to/trace.zip
```

### Test Fixtures

Enhanced fixtures in `e2e/fixtures.ts` provide:

```typescript
import { test, expect } from './fixtures';

test('example', async ({ page, testContext, consoleLogs, networkLogs }) => {
  // testContext - injected into all API requests for backend correlation
  console.log(testContext.testId, testContext.runId);

  // consoleLogs - automatically captured browser console
  // networkLogs - automatically captured network requests

  await page.goto('/');
});
```

### AI Agent Test Debugging (Playwright MCP)

The Playwright MCP server enables AI agents to analyze test results.

> **Note**: After adding MCP servers to `.mcp.json`, restart Claude Code to load them.
> The tools will appear as `test_summary`, `list_failures`, etc.

**Configuration** (`.mcp.json`):
```json
{
  "mcpServers": {
    "playwright": {
      "command": "bun",
      "args": ["run", "mcp/playwright-mcp/src/index.ts"],
      "env": { "PROJECT_ROOT": "${workspaceFolder}" }
    }
  }
}
```

**Available Tools**:
- `test_summary` - Get pass/fail counts and overall status
- `list_failures` - List failed tests with error messages
- `test_details` - Get detailed info for a specific test
- `failure_patterns` - Analyze common failure patterns
- `flaky_tests` - List tests that passed on retry
- `slow_tests` - Find performance bottlenecks
- `test_artifacts` - List available traces/screenshots/videos
- `view_attachment` - Read console/network logs from failed tests

**Example Usage** (in Claude Code):
```
> What tests failed in the last run?
> Show me the failure patterns
> Get details for the login test
> What are the slowest tests?
```

### Backend Correlation

Tests inject headers for backend correlation:
- `X-Test-Id` - Unique test identifier
- `X-Test-Name` - Test title
- `X-Test-Run` - Run identifier (set via `PLAYWRIGHT_RUN_ID`)

Query backend logs filtered by test:
```promql
# In Grafana/Loki
{job="containerlogs"} |= "X-Test-Run=my-run-id"
```

### Architecture: How It All Connects

```
Playwright Test Run
        │
        ▼
┌───────────────────┐
│ Test with Headers │──► Backend receives X-Test-Id, X-Test-Run
│ X-Test-Run: abc   │    (can filter logs/metrics by test)
└───────────────────┘
        │
        ▼
┌───────────────────┐     ┌─────────────────┐
│ On Failure:       │────►│ test-results/   │
│ - Screenshot      │     │ - results.json  │
│ - Video           │     │ - traces/       │
│ - Trace           │     │ - screenshots/  │
│ - Console logs    │     └────────┬────────┘
│ - Network logs    │              │
└───────────────────┘              │
                                   ▼
                         ┌─────────────────┐
                         │ Playwright MCP  │◄── AI Agent queries
                         │ Server          │    "What failed?"
                         └─────────────────┘
                                   │
                                   ▼
                         ┌─────────────────┐
                         │ Prometheus/Loki │◄── Filter by X-Test-Run
                         │ (backend logs)  │    to see server-side
                         └─────────────────┘
```

### Debugging Workflow

1. **Run tests**: `bun playwright test`
2. **Check summary**: Use `test_summary` tool or view HTML report
3. **Identify failures**: Use `list_failures` or `failure_patterns`
4. **Get details**: Use `test_details` for specific test
5. **View artifacts**: Open trace in Playwright viewer
6. **Check backend**: Query Prometheus/Loki with test run ID
7. **Fix and re-run**: Iterate until green

### Best Practices

- Use `test.describe()` to group related tests
- Use `test.beforeEach()` for common setup
- Add `test.slow()` for known slow tests
- Use `expect.soft()` for non-critical assertions
- Add `test.skip()` with reason for known issues

## Agent Task Completion Checklist

After completing any task, the agent MUST perform these steps before finishing:

### 1. Update Architecture Documentation

If your changes affected the project structure, added new components, or modified existing architecture:
- Update the **Project Structure** section in this file if directories were added/removed
- Update relevant sections (Tech Stack, Build System, etc.) if new tools or patterns were introduced
- Keep documentation accurate and in sync with the codebase

### 2. Evaluate Observability Needs

Consider whether your changes warrant new observability:

**Add observability when:**
- New API endpoints were added → add metrics for request count/latency
- New error conditions were introduced → ensure errors are logged with context
- New async operations or background jobs → add timing and success/failure metrics
- New user-facing features → consider tracking usage patterns
- New integration points → add health checks and connection metrics

**How to add observability:**
- **Metrics (Prometheus)**: Add to `server/src/lib/metrics.zig`, expose via `/metrics`
- **Dashboards (Grafana)**: Update `monitoring/grafana/dashboards/`
- **Logging (Loki)**: Ensure structured logging with relevant context fields
- **Alerts**: Add alerting rules in `monitoring/prometheus/prometheus.yml`

### 3. Document or Suggest Observability as Follow-up

If you cannot add observability in the current task (time constraints, scope, or requires separate work):
- **Explicitly suggest it as a next task** to the user
- Describe what metrics/logs/dashboards would be valuable
- Example: "Next task: Add `plue_agent_tool_calls_total` metric to track AI agent tool usage patterns"

This ensures the project maintains comprehensive observability as it evolves.
