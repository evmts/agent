# Plue

A brutalist GitHub clone with integrated AI agent capabilities. Combines a minimal web interface for repository/issue management with an autonomous Claude-powered agent system.

## Project Structure

```
plue/
├── ui/                    # Astro SSR frontend
│   ├── components/        # Astro components (Terminal, FileTree, etc.)
│   ├── pages/             # File-based routing
│   ├── layouts/           # Base layout with brutalist CSS
│   └── lib/               # Frontend utilities (db, git, markdown)
├── server/                # Zig API server (httpz)
│   ├── src/
│   │   ├── main.zig       # Entry point with WebSocket support
│   │   ├── routes.zig     # Route definitions
│   │   ├── config.zig     # Server configuration
│   │   ├── routes/        # API route handlers
│   │   ├── middleware/    # Auth, CORS, rate limiting
│   │   ├── lib/           # DB client, JWT, SIWE auth
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
- **Infrastructure**: Docker, Kubernetes, Terraform

## Zig Conventions

- Build with `zig build` or `zig build -Doptimize=ReleaseFast`
- Run server with `zig build run`
- Run tests with `zig build test`
- Dependencies managed via `build.zig.zon`

## Bun Conventions (Frontend/TUI)

- Use `bun <file>` not `node <file>`
- Use `bun test` not jest/vitest
- Use `bun install` not npm/yarn/pnpm
- Bun auto-loads `.env` (no dotenv needed)

## Development

```bash
# Start database
docker compose up postgres electric -d

# Run Zig server
cd server && zig build run

# Run Astro frontend
bun run dev

# Run TUI
cd tui && bun run dev
```

## Testing

```bash
# Zig tests
cd server && zig build test

# Frontend tests
bun test

# E2E tests
bun run test:e2e
```
