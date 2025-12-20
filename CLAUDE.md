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

## Build System

The root `build.zig` is the single entrypoint for all operations. Run from repo root (never `cd` into subdirectories).

### Quick Reference

```bash
zig build              # Build all (server + web + edge + tui)
zig build run          # Start dev environment (docker + server)
zig build test         # Run all tests (Zig + TS + Rust)
zig build lint         # Lint all code
zig build format       # Format all code
zig build ci           # Full CI pipeline
```

### Build Commands

```bash
zig build              # Build everything (default)
zig build server       # Build Zig server only
zig build web          # Build Astro frontend only
zig build edge         # Build Cloudflare Worker only
zig build tui          # Build TUI only
```

### Run Commands

```bash
zig build run          # Full dev: docker + server (recommended)
zig build run:docker   # Start postgres + electric only
zig build run:server   # Run Zig server only
zig build run:web      # Run Astro dev server only
```

### Test Commands

```bash
zig build test         # All unit tests (Zig + TS + Rust)
zig build test:zig     # All Zig tests (server + core)
zig build test:ts      # All TypeScript tests
zig build test:rust    # All Rust tests (jj-ffi + snapshot)
zig build test:e2e     # Playwright E2E tests
zig build test:server  # Server Zig tests only
zig build test:edge    # Edge worker tests only
```

### Lint & Format

```bash
zig build lint         # Lint ALL (zig fmt --check + eslint + clippy)
zig build lint:zig     # Zig format check
zig build lint:ts      # ESLint
zig build lint:rust    # Clippy

zig build format       # Format ALL (zig fmt + eslint --fix + cargo fmt)
zig build format:zig   # Format Zig
zig build format:ts    # Format TypeScript
zig build format:rust  # Format Rust
```

### CI & Utilities

```bash
zig build ci           # Full CI: lint + test + build
zig build check        # Quick: lint + typecheck
zig build clean        # Clean all build artifacts
zig build deps         # Install dependencies (bun install)
zig build docker       # Build Docker images
zig build docker:up    # Start all Docker services
zig build docker:down  # Stop all Docker services
zig build db:migrate   # Run database migrations
zig build db:seed      # Seed test data
```

## Conventions

### Zig
- Dependencies managed via `build.zig.zon`
- Zig 0.15.1+ required

### Bun/TypeScript
- Use `bun` not `node/npm/yarn`
- Bun auto-loads `.env`

### Rust
- Used for jj-lib FFI (`server/jj-ffi/`)
- Cargo builds integrated into Zig build

## Development Workflow

```bash
# First time setup
zig build deps         # Install bun dependencies

# Start development
zig build run          # Starts docker + server

# In another terminal (optional)
zig build run:web      # Start Astro dev server

# Before committing
zig build check        # Quick lint + typecheck
zig build test         # Run all tests
```

## Testing

```bash
# Run all tests
zig build test

# Run specific test suites
zig build test:zig     # Zig unit tests
zig build test:ts      # TypeScript/vitest
zig build test:rust    # Rust/cargo test
zig build test:e2e     # Playwright (requires running services)
```
