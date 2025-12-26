---
name: development
description: Run Plue development services, start the frontend/API, manage the local dev environment. Use when asked about running, starting, or developing Plue locally.
---

# Plue Development Workflow

## Quick Start

```bash
# Start all services via docker-compose
docker compose -f infra/docker/docker-compose.yaml up -d
```

Then access the app at `http://localhost:8787` (edge worker port).

## Architecture

SIWE authentication is handled by the Cloudflare edge worker:
- Edge worker handles `/api/auth/nonce`, `/api/auth/verify`, `/api/auth/logout`
- Proxies all other requests to Astro SSR (web container)
- Astro SSR calls Zig API directly (api container)

## Service Ports

| Service      | Port  | Access              |
|--------------|-------|---------------------|
| Edge Worker  | 8787  | **Use this URL**    |
| Astro (web)  | 5173  | (proxied by edge)   |
| Zig API      | 4000  | (called by Astro)   |
| Postgres     | 54321 | (internal)          |

## Local Dev (outside Docker)

For faster iteration on UI changes:

```bash
# Terminal 1: Start backend services
docker compose -f infra/docker/docker-compose.yaml up -d postgres api

# Terminal 2: Start edge worker (must start before accessing auth routes)
cd edge && pnpm dev

# Terminal 3: Start Astro frontend
EDGE_URL=http://localhost:8787 bun dev
```

Access at `https://localhost:4321` (Astro with Vite proxy to edge for auth).

Alternatively, access at `http://localhost:8787` (full edge worker proxy).

### How Auth Works in Dev

- Auth routes (`/api/auth/*`) are handled by the edge worker
- Astro's Vite dev server proxies `/api/auth/*` to the edge worker
- Set `EDGE_URL=http://localhost:8787` when running Astro to enable the proxy
- The edge worker uses Durable Objects for nonce storage (requires wrangler)

### Porto Wallet Authentication

Plue uses [Porto](https://porto.sh) for SIWE (Sign In With Ethereum) authentication:

- **Production (HTTPS)**: Porto shows its standard dialog for wallet selection
- **Development (HTTP)**: Porto automatically uses mock mode with test passkeys
- Porto requires HTTPS for WebAuthn - mock mode is used on HTTP origins

Porto mock mode generates EIP-6492 smart wallet signatures. The edge worker detects
these and handles them appropriately for development/testing.

### Testing Auth with Playwright

The Playwright test suite starts all necessary services including the edge worker:

```bash
# Run auth tests
cd e2e && pnpm playwright test cases/auth.spec.ts
```

The Playwright skill can test login flows manually:

```bash
# Via playwright-skill
# Test login at http://localhost:8787/login
```

## Environment Variables

Required in `.env` for docker-compose:
```bash
POSTGRES_PASSWORD=your-password
ANTHROPIC_API_KEY=sk-ant-...
JWT_SECRET=your-jwt-secret
GRAFANA_ADMIN_PASSWORD=your-grafana-password
```
