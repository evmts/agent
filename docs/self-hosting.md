# Self-Hosting Plue

This guide covers deploying Plue on your own infrastructure.

## Prerequisites

- Docker and Docker Compose (recommended), or:
  - Zig 0.15.1+
  - [Bun](https://bun.sh) v1.1+
  - PostgreSQL 16+
  - Rust toolchain (for snapshot module)
- An Anthropic API key for AI agent features

## Quick Start with Docker

The fastest way to deploy Plue:

```bash
# Clone the repository
git clone https://github.com/your-org/plue.git
cd plue

# Copy environment template
cp .env.example .env

# Edit .env with your configuration (see Environment Variables below)

# Start all services
docker-compose -f infra/docker/docker-compose.yaml up -d

# Access the application
# Frontend (Astro): http://localhost:5173
# API (Zig): http://localhost:4000
```

### Docker Services

| Service | Port | Description |
|---------|------|-------------|
| PostgreSQL | 54321 | Database |
| API | 4000 | Zig backend server |
| Web | 5173 | Astro SSR frontend |
| SSH | 2222 | Git over SSH (optional) |

## Environment Variables

Create a `.env` file with the following:

### Required

```bash
# Database
DATABASE_URL=postgresql://postgres:password@localhost:54321/plue

# Security (generate random 32+ character strings)
JWT_SECRET=your-random-jwt-secret-here

# AI Agent
ANTHROPIC_API_KEY=sk-ant-your-key-here
```

### Optional

```bash
# Service ports (override if needed)
HOST=0.0.0.0
PORT=4000

# SSH server
SSH_PORT=2222
SSH_HOST_KEY_PATH=/path/to/host_key

# Public URLs (for SSR + client)
SITE_URL=http://localhost:5173
PUBLIC_CLIENT_API_URL=http://localhost:4000
```

### Docker-Specific Variables

When running with Docker Compose, these are set automatically:

```bash
# Internal service URLs (service-to-service)
PUBLIC_API_URL=http://api:4000

# Browser-accessible URLs
PUBLIC_CLIENT_API_URL=http://localhost:4000
```

## Manual Deployment

If you prefer not to use Docker:

### 1. Install Dependencies

```bash
# Install Zig (example for macOS)
brew install zig

# Install Bun
curl -fsSL https://bun.sh/install | bash

# Install project dependencies
bun install
```

### 2. Set Up PostgreSQL

Create the database:

```bash
createdb plue
```

### 3. Run Migrations

```bash
psql $DATABASE_URL -f db/schema.sql
```

### 4. Build the Snapshot Module (Optional)

Required for jj-lib VCS integration:

```bash
cd snapshot
cargo build --release
bun run build
```

### 5. Build the Frontend

```bash
bun run build
```

### 6. Start Services

Start the API server (Zig):

```bash
zig build run
```

Start the web frontend (Astro SSR):

```bash
bun ./dist/server/entry.mjs
```

## Production Considerations

### Security Checklist

- [ ] Set production environment flags (if applicable)
- [ ] Enable secure cookies (if applicable)
- [ ] Use a strong random value for `JWT_SECRET`
- [ ] Configure HTTPS with a reverse proxy (nginx, Caddy)
- [ ] Use a strong PostgreSQL password
- [ ] Lock down SSH access (keys only, no password auth)

### Reverse Proxy Example (nginx)

```nginx
upstream plue_web {
    server 127.0.0.1:5173;
}

upstream plue_api {
    server 127.0.0.1:4000;
}

server {
    listen 443 ssl http2;
    server_name plue.yourdomain.com;

    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;

    # Frontend
    location / {
        proxy_pass http://plue_web;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # API
    location /api {
        proxy_pass http://plue_api;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    # SSE streams work over standard HTTP; no upgrade needed
}
```

### Database Backups

Regular PostgreSQL backups:

```bash
# Daily backup
pg_dump -h localhost -p 54321 -U postgres plue > backup_$(date +%Y%m%d).sql

# Restore
psql -h localhost -p 54321 -U postgres plue < backup_20240101.sql
```

### Resource Requirements

Minimum recommended specs:

| Component | CPU | RAM | Storage |
|-----------|-----|-----|---------|
| Small (dev) | 2 cores | 4 GB | 20 GB |
| Medium | 4 cores | 8 GB | 50 GB |
| Large | 8 cores | 16 GB | 100 GB |

PostgreSQL will use the most memory. Adjust `shared_buffers` and `work_mem` accordingly.

## Upgrading

```bash
# Pull latest changes
git pull origin main

# Install any new dependencies
bun install

# Apply schema changes (if any)
psql $DATABASE_URL -f db/schema.sql

# Rebuild
bun run build

# Restart services
docker-compose -f infra/docker/docker-compose.yaml down
docker-compose -f infra/docker/docker-compose.yaml up -d
# Or restart your process manager
```

## Troubleshooting

### Database Connection Issues

```bash
# Test PostgreSQL connection
psql $DATABASE_URL -c "SELECT 1"

```

### API Health Check

```bash
curl http://localhost:4000/health
```

### Build Failures

If the snapshot module fails to build:

```bash
# Ensure Rust is installed
rustup --version

# Clean and rebuild
cd snapshot
cargo clean
cargo build --release
```

## Architecture Overview

```
                    ┌─────────────┐
                    │   Clients   │
                    └──────┬──────┘
                           │
              ┌────────────┼────────────┐
              │            │            │
              ▼            ▼            ▼
        ┌──────────┐ ┌──────────┐ ┌──────────┐
        │   Web    │ │   API    │ │   SSH    │
        │  :5173   │ │  :4000   │ │  :2222   │
        └────┬─────┘ └────┬─────┘ └────┬─────┘
             │            │            │
             └────────────┼────────────┘
                          │
              ┌───────────┴───────────┐
              │                       │
              ▼                       ▼
        ┌──────────┐           ┌──────────┐
        │ Postgres │           │ Anthropic│
        │  :54321  │           │   API    │
        └──────────┘           └──────────┘
```

## Support

- Check the [GitHub Issues](https://github.com/your-org/plue/issues) for known problems
- Review logs: `docker-compose -f infra/docker/docker-compose.yaml logs -f`
