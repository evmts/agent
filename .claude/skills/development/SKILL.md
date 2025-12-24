---
name: development
description: Run Plue development services, start the frontend/API, manage the local dev environment. Use when asked about running, starting, or developing Plue locally.
---

# Plue Development Workflow

## Quick Start

```bash
# Start all services (postgres, frontend, api)
zig build run
```

## Individual Services

```bash
zig build run          # Start postgres and server
zig build run:web      # Frontend at localhost:3000
```

## Production Build

```bash
bun run build
bun run start          # Astro frontend
bun run start:api      # API server
```

## Service Ports

| Service   | Port  |
|-----------|-------|
| Frontend  | 3000  |
| API       | 4000  |
| Postgres  | 5432  |
| Adminer   | 8080  |

## Environment Variables

```bash
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/plue
PORT=4000
ANTHROPIC_API_KEY=sk-ant-...
```
