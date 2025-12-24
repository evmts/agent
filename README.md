# Plue

A brutalist GitHub clone with integrated AI agent capabilities.

## Features

- **Git Hosting** - SSH-based git push/pull with jj (Jujutsu) backend
- **Issue Tracking** - Full issue lifecycle with labels, milestones, dependencies
- **AI Agents** - Claude-powered agents for code review, issue triage, PR assistance
- **Workflows** - CI/CD and agent workflows in the same execution model
- **SIWE Authentication** - Sign-In With Ethereum wallet-based auth

## Quick Start

```bash
# Prerequisites: Docker, Zig 0.15.1+, Bun

# Start the dev environment
zig build run          # Docker + Zig API server (localhost:4000)
zig build run:web      # Astro dev server (localhost:3000) - separate terminal

# Run tests
zig build test         # All tests (Zig + TypeScript + Rust)
```

## Architecture

See [architecture.md](./architecture.md) for comprehensive diagrams and documentation.

```
┌─────────────────────────────────────────────────────────────────────┐
│  Browser ──► Cloudflare Edge ──► Zig API ──► PostgreSQL            │
│                                     │                               │
│                                     ├──► SSH Server (Git)          │
│                                     └──► K8s Runners (gVisor)      │
└─────────────────────────────────────────────────────────────────────┘
```

## Project Structure

```
plue/
├── server/            # Zig API server (httpz)
│   ├── routes/        # HTTP API handlers
│   ├── ai/            # Agent system + tools
│   ├── workflows/     # Workflow execution engine
│   ├── ssh/           # Git over SSH
│   └── middleware/    # Auth, CSRF, rate limiting
├── ui/                # Astro SSR frontend
│   ├── pages/         # File-based routing
│   ├── components/    # UI components
│   └── lib/           # Auth, API client, cache
├── edge/              # Cloudflare Workers caching proxy
├── runner/            # Python agent execution (K8s pods)
├── db/                # PostgreSQL schema + DAOs
├── core/              # Zig agent core library
├── e2e/               # Playwright E2E tests
├── infra/             # Terraform, Helm, K8s, Docker
└── docs/              # Architecture & infrastructure docs
```

## Documentation

- **[Architecture](./architecture.md)** - System design, data flow, component details
- **[Infrastructure](./docs/infrastructure.md)** - Deployment, K8s, Terraform
- **[CLAUDE.md](./CLAUDE.md)** - Instructions for Claude Code

## Tech Stack

| Layer | Technology |
|-------|------------|
| Server | Zig + httpz |
| Frontend | Astro v5 (SSR) |
| Database | PostgreSQL 16 |
| VCS | jj (Jujutsu) via Rust FFI |
| Edge | Cloudflare Workers |
| Auth | SIWE (Sign-In With Ethereum) |
| Agents | Claude API + gVisor sandbox |
| Infra | GKE, Terraform, Helm |

## Development

```bash
# Database only
docker compose up -d postgres

# Full environment
zig build run          # API server with hot reload
zig build run:web      # Astro dev server

# Testing
zig build test         # All tests
zig build test:zig     # Zig tests only
zig build test:edge    # Edge worker tests

# Linting
zig build lint         # Lint all code
```

## Environment Variables

```bash
# Required
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/plue
ANTHROPIC_API_KEY=sk-ant-...

# Optional
SSH_ENABLED=true
SSH_PORT=2222
LOG_LEVEL=debug
```

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md) for development guidelines.

## License

MIT
