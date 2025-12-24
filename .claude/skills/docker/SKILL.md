---
name: docker
description: Plue Docker containerization and container management. Use when asked about Docker, containers, or deploying Plue with docker-compose.
---

# Plue Docker Setup

## Commands

```bash
bun run docker:up      # Start all containers
bun run docker:down    # Stop containers
bun run docker:logs    # View logs
```

## Services

| Service  | Port  | Description              |
|----------|-------|--------------------------|
| postgres | 54321 | PostgreSQL database      |
| api      | 4000  | Zig API server           |
| web      | 5173  | Astro frontend           |
| adminer  | 8080  | Database admin UI        |

## Configuration

Docker configuration is in:
- `infra/docker/docker-compose.yaml` - Service definitions
- `infra/docker/Dockerfile` - Container build instructions
