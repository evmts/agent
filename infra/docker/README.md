# Docker

Multi-stage Dockerfile and docker-compose configuration for local development.

## Overview

The Dockerfile builds all Plue services (API, Web, TUI) with optimized multi-stage builds. The docker-compose stack includes the full observability suite for local testing.

## Services

| Service | Port | Description |
|---------|------|-------------|
| `api` | 4000 | Zig API server (httpz) |
| `web` | 5173 | Astro SSR frontend |
| `tui` | - | Terminal interface (profile: tui) |
| `postgres` | 54321 | PostgreSQL 16 database |
| `prometheus` | 9090 | Metrics collection |
| `grafana` | 3001 | Dashboards and visualization |
| `loki` | 3100 | Log aggregation |
| `promtail` | - | Log shipper (Docker container logs) |
| `postgres-exporter` | 9187 | Postgres metrics exporter |
| `cadvisor` | 8081 | Container metrics exporter |
| `adminer` | 8080 | DB admin UI (profile: dev) |

## Quick Start

**Start core services:**
```bash
docker-compose up
```

**Start with TUI:**
```bash
docker-compose --profile tui up
```

**Start with DB admin:**
```bash
docker-compose --profile dev up
```

## Build Stages

```
Dockerfile stages:

base ─────┬─→ deps ──→ build ──→ web (Astro SSR)
          │
          └─→ tui-build ─────────→ tui (Bun compiled binary)

api-build ───────────────────────→ api (Zig server + jj-ffi)
```

### API Stage
- Base: debian:bookworm-slim
- Builds Zig server (httpz) with jj-lib FFI (Rust)
- Includes voltaire crypto wrappers (panic=abort for smaller binary)
- Runtime includes libjj_ffi.so in expected path

### Web Stage
- Base: oven/bun:1
- Builds Astro for SSR production mode
- Runs with Bun runtime (faster than Node)

### TUI Stage
- Compiled with `bun build --compile`
- Produces standalone binary (no Node/Bun runtime needed)

## Environment Variables

Required:
```bash
POSTGRES_PASSWORD=<secure-password>
ANTHROPIC_API_KEY=<claude-api-key>
JWT_SECRET=<secure-jwt-secret>
GRAFANA_ADMIN_PASSWORD=<grafana-password>
```

Optional:
```bash
POSTGRES_DB=plue
POSTGRES_USER=postgres
GRAFANA_ADMIN_USER=admin
PUBLIC_CLIENT_API_URL=http://localhost:5173
```

Create `.env` file in `infra/docker/`:
```bash
POSTGRES_PASSWORD=dev_password
ANTHROPIC_API_KEY=sk-ant-...
JWT_SECRET=development_secret_at_least_32_chars
GRAFANA_ADMIN_PASSWORD=admin
```

## Health Checks

All services include health checks:
- `postgres`: pg_isready
- `api`: curl http://localhost:4000/health
- `prometheus`: wget http://localhost:9090/-/healthy
- `grafana`: wget http://localhost:3000/api/health
- `loki`: wget http://localhost:3100/ready

## Volumes

Persistent data stored in named volumes:
- `postgres_data`: Database files
- `prometheus_data`: Metrics retention (7 days)
- `grafana_data`: Dashboards and config
- `loki_data`: Log storage

## Monitoring Access

Once running:
- Grafana: http://localhost:3001 (admin/GRAFANA_ADMIN_PASSWORD)
- Prometheus: http://localhost:9090
- Postgres Exporter: http://localhost:9187/metrics
- cAdvisor: http://localhost:8081
- Adminer: http://localhost:8080 (profile: dev)

## Profiles

Docker Compose profiles control optional services:

**tui**: Terminal interface
```bash
docker-compose --profile tui up tui
```

**dev**: Database admin UI
```bash
docker-compose --profile dev up adminer
```

## Networking

All services share `plue_network` bridge network. Internal DNS:
- `api:4000` (API server)
- `web:5173` (Web frontend)
- `postgres:5432` (Database)
- `prometheus:9090` (Metrics)
- `loki:3100` (Logs)

## Build from Project Root

The Dockerfile expects to be run from the project root:
```bash
cd /path/to/plue
docker build -f infra/docker/Dockerfile -t plue-api --target api .
docker build -f infra/docker/Dockerfile -t plue-web --target web .
```

Or use docker-compose:
```bash
cd infra/docker
docker-compose build
```

## Troubleshooting

**voltaire submodule issues:**
If `server/voltaire` is a symlink, replace it with the real directory:
```bash
rm server/voltaire
git submodule update --init server/voltaire
```

**Database schema not applied:**
Schema auto-loads from `db/schema.sql` on first postgres startup. If postgres volume exists, drop it:
```bash
docker-compose down -v
docker-compose up
```

**Missing environment variables:**
Docker Compose will fail fast if required vars are unset. Check `.env` file exists with all required values.
