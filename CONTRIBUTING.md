# Contributing to Plue

## Prerequisites

- [Zig](https://ziglang.org/) 0.15.1+
- [Bun](https://bun.sh/) 1.0+
- [Rust](https://rustup.rs/) (for jj-ffi)
- [Docker](https://docker.com/) (for postgres/electric)

## Quick Start

```bash
# Clone and setup
git clone https://github.com/your-org/plue.git
cd plue

# Install dependencies
zig build deps

# Start development
zig build run
```

## Build System

All commands run from the repo root using `zig build`. Never `cd` into subdirectories.

### Essential Commands

| Command | Description |
|---------|-------------|
| `zig build` | Build all components |
| `zig build run` | Start dev environment (docker + server) |
| `zig build test` | Run all tests |
| `zig build lint` | Lint all code |
| `zig build format` | Format all code |
| `zig build ci` | Full CI pipeline |

### All Commands

Run `zig build --help` to see all available commands.

## Development Workflow

### 1. Start Development

```bash
zig build run          # Starts postgres, electric, and server
```

In a separate terminal (optional):
```bash
zig build run:web      # Start Astro dev server
```

### 2. Make Changes

Edit code in your preferred editor. The project structure:

- `server/` - Zig API server
- `ui/` - Astro frontend (pages, components)
- `edge/` - Cloudflare Workers
- `tui/` - Terminal UI
- `core/` - Shared Zig core
- `db/` - Database schema

### 3. Before Committing

```bash
zig build check        # Quick lint + typecheck
zig build test         # Run all tests
```

Or run the full CI locally:
```bash
zig build ci
```

## Code Style

### Zig
- Formatted with `zig fmt` (enforced by `zig build lint:zig`)
- Follow standard Zig conventions

### TypeScript
- Formatted with ESLint + Biome
- Run `zig build format:ts` to auto-fix

### Rust
- Formatted with `cargo fmt`
- Linted with `clippy`

## Testing

```bash
# All tests
zig build test

# Specific suites
zig build test:zig     # Zig unit tests
zig build test:ts      # TypeScript tests
zig build test:rust    # Rust tests
zig build test:e2e     # E2E tests (requires running services)
```

## Pull Request Process

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Make your changes
4. Run `zig build ci` to verify
5. Commit with a descriptive message
6. Push and open a PR

## Project Architecture

See [CLAUDE.md](./CLAUDE.md) for detailed architecture documentation.

### Key Components

- **Server (Zig)**: HTTP/WebSocket API, AI agent system
- **Frontend (Astro)**: SSR web interface
- **Edge (CF Workers)**: Edge caching with ElectricSQL sync
- **Database**: PostgreSQL + ElectricSQL for real-time sync

## Getting Help

- Check existing issues
- Read [CLAUDE.md](./CLAUDE.md) for architecture details
- Ask in discussions
