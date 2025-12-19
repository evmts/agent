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
| electric | 3000  | ElectricSQL sync service |
| api      | 4000  | Hono API server          |
| web      | 5173  | Astro frontend           |
| adminer  | 8080  | Database admin UI        |

## Configuration

Docker configuration is in:
- `docker-compose.yml` - Service definitions
- `Dockerfile` - Container build instructions
