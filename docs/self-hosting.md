# Self-Hosting Plue

This guide covers deploying Plue on your own infrastructure.

## Prerequisites

- Docker and Docker Compose (recommended), or:
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
docker-compose up -d

# Access the application
# Frontend: http://localhost:5173
# API: http://localhost:4000
```

### Docker Services

| Service | Port | Description |
|---------|------|-------------|
| PostgreSQL | 54321 | Database with logical replication |
| ElectricSQL | 3000 | Real-time sync layer |
| API | 4000 | Hono backend server |
| Web | 5173 | Astro SSR frontend |
| SSH | 2222 | Git over SSH (optional) |

## Environment Variables

Create a `.env` file with the following:

### Required

```bash
# Database
DATABASE_URL=postgresql://postgres:password@localhost:54321/electric

# Site
SITE_URL=http://localhost:5173
HOST=0.0.0.0
PORT=4000

# Security (generate random 32+ character strings)
SESSION_SECRET=your-random-session-secret-here
JWT_SECRET=your-random-jwt-secret-here

# AI Agent
ANTHROPIC_API_KEY=sk-ant-your-key-here
```

### Optional

```bash
# Production settings
NODE_ENV=production
SECURE_COOKIES=true

# Email (choose Resend or SMTP)
EMAIL_FROM=noreply@yourdomain.com
RESEND_API_KEY=re_your_key

# Or SMTP
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=your-email@gmail.com
SMTP_PASS=your-app-password

# SSH server
SSH_PORT=2222
SSH_HOST_KEY_PATH=/path/to/host_key

# CORS (comma-separated origins)
CORS_ORIGINS=https://yourdomain.com

# Database timeout (seconds)
DB_QUERY_TIMEOUT=30
```

### Docker-Specific Variables

When running with Docker Compose, these are set automatically:

```bash
# Internal service URLs (service-to-service)
ELECTRIC_URL=http://electric:3000
PUBLIC_API_URL=http://api:4000

# Browser-accessible URLs
PUBLIC_CLIENT_API_URL=http://localhost:4000
PUBLIC_CLIENT_ELECTRIC_URL=http://localhost:3000
```

## Manual Deployment

If you prefer not to use Docker:

### 1. Install Dependencies

```bash
# Install Bun
curl -fsSL https://bun.sh/install | bash

# Install project dependencies
bun install
```

### 2. Set Up PostgreSQL

PostgreSQL must have logical replication enabled:

```sql
-- postgresql.conf
wal_level = logical
```

Create the database:

```bash
createdb electric
```

### 3. Run Migrations

```bash
bun run db:migrate
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

Start ElectricSQL (if using real-time sync):

```bash
docker run -d \
  -e DATABASE_URL=$DATABASE_URL \
  -e ELECTRIC_INSECURE=true \
  -p 3000:3000 \
  electricsql/electric
```

Start the API server:

```bash
bun run server/main.ts
```

Start the web frontend:

```bash
bun ./dist/server/entry.mjs
```

## Production Considerations

### Security Checklist

- [ ] Set `NODE_ENV=production`
- [ ] Set `SECURE_COOKIES=true`
- [ ] Use strong random values for `SESSION_SECRET` and `JWT_SECRET`
- [ ] Configure HTTPS with a reverse proxy (nginx, Caddy)
- [ ] Restrict `CORS_ORIGINS` to your domain
- [ ] Use a strong PostgreSQL password
- [ ] Keep `ELECTRIC_INSECURE=false` and configure proper auth

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

    # WebSocket for PTY/terminal
    location /ws {
        proxy_pass http://plue_api;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

### Database Backups

Regular PostgreSQL backups:

```bash
# Daily backup
pg_dump -h localhost -p 54321 -U postgres electric > backup_$(date +%Y%m%d).sql

# Restore
psql -h localhost -p 54321 -U postgres electric < backup_20240101.sql
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

# Run migrations
bun run db:migrate

# Rebuild
bun run build

# Restart services
docker-compose down && docker-compose up -d
# Or restart your process manager
```

## Troubleshooting

### Database Connection Issues

```bash
# Test PostgreSQL connection
psql $DATABASE_URL -c "SELECT 1"

# Check if logical replication is enabled
psql $DATABASE_URL -c "SHOW wal_level"
# Should return: logical
```

### ElectricSQL Not Syncing

```bash
# Check ElectricSQL health
curl http://localhost:3000/v1/health

# View ElectricSQL logs
docker-compose logs electric
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
        │ Electric │           │ Anthropic│
        │  :3000   │           │   API    │
        └────┬─────┘           └──────────┘
             │
             ▼
        ┌──────────┐
        │ Postgres │
        │  :54321  │
        └──────────┘
```

## Support

- Check the [GitHub Issues](https://github.com/your-org/plue/issues) for known problems
- Review logs: `docker-compose logs -f`
- For ElectricSQL issues, see [ElectricSQL docs](https://electric-sql.com/docs)
