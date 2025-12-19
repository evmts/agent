---
name: development
description: Run Plue development services, start the frontend/API, manage the local dev environment. Use when asked about running, starting, or developing Plue locally.
---

# Plue Development Workflow

## Quick Start

```bash
# Start all services (postgres, electric, frontend, api)
bun run dev:all
```

## Individual Services

```bash
bun run db:up          # Start postgres + electric
bun run dev            # Frontend at localhost:5173
bun run dev:api        # API at localhost:4000
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
| Frontend  | 5173  |
| API       | 4000  |
| Postgres  | 54321 |
| Electric  | 3000  |
| Adminer   | 8080  |

## Environment Variables

```bash
DATABASE_URL=postgresql://postgres:password@localhost:54321/electric
ELECTRIC_URL=http://localhost:3000
PORT=4000
ANTHROPIC_API_KEY=sk-ant-...
PUBLIC_CLIENT_API_URL=http://localhost:4000
PUBLIC_CLIENT_ELECTRIC_URL=http://localhost:3000
```
