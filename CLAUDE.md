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
├── server/                # Hono API server
│   ├── main.ts            # Entry point with WebSocket support
│   ├── index.ts           # Hono app with middleware
│   └── routes/            # API routes (sessions, messages, pty)
├── core/                  # Core session/state management
│   ├── state.ts           # Dual-layer state (runtime + DB)
│   ├── events.ts          # EventBus pub/sub system
│   ├── sessions.ts        # Session CRUD operations
│   └── models/            # Data models (message, session, part)
├── ai/                    # AI agent system
│   ├── agent.ts           # Agent runner (Vercel AI SDK + Claude)
│   ├── registry.ts        # Agent configuration
│   └── tools/             # 9 agent tools (grep, file ops, terminal)
├── db/                    # Database layer
│   ├── schema.sql         # PostgreSQL schema
│   └── migrate.ts         # Migration script
└── native/                # Rust bindings (jj-lib for snapshots)
```

## Development

```bash
# Start all services (postgres, electric, frontend, api)
bun run dev:all

# Or run individually:
bun run db:up          # Start postgres + electric
bun run dev            # Frontend at localhost:5173
bun run dev:api        # API at localhost:4000

# Database
bun run db:migrate     # Run migrations

# Build for production
bun run build
bun run start          # Astro frontend
bun run start:api      # API server
```

## Tech Stack

- **Runtime**: Bun (not Node.js)
- **Frontend**: Astro v5 (SSR, file-based routing)
- **Backend**: Hono + Bun.serve (WebSocket support)
- **Database**: PostgreSQL + ElectricSQL (real-time sync)
- **AI**: Vercel AI SDK + Claude Sonnet 4
- **Validation**: Zod v4

## Key Patterns

### State Management
- Runtime Maps for active sessions/tasks (memory)
- PostgreSQL for persistence (sessions, messages, snapshots)
- EventBus for pub/sub communication

### Agent System
- Modes: `general`, `explore`, `plan`
- Tools: grep, readFile, writeFile, multiedit, webFetch, unifiedExec, etc.
- Max 10 steps per run (configurable)
- Streaming output via SSE

### Frontend
- Astro SSR with Node adapter
- Pure CSS (brutalist design, no frameworks)
- File-based routing in `ui/pages/`
- Components are `.astro` files

## Environment Variables

```bash
DATABASE_URL=postgresql://postgres:password@localhost:54321/electric
ELECTRIC_URL=http://localhost:3000
PORT=4000
ANTHROPIC_API_KEY=sk-ant-...
PUBLIC_CLIENT_API_URL=http://localhost:4000
PUBLIC_CLIENT_ELECTRIC_URL=http://localhost:3000
```

## Database Tables

- `users`, `repositories`, `issues`, `comments` - GitHub-like entities
- `sessions`, `messages`, `snapshots` - Agent state persistence
- `subtasks`, `file_trackers` - Agent task tracking

## Bun Conventions

- Use `bun <file>` not `node <file>`
- Use `bun test` not jest/vitest
- Use `bun install` not npm/yarn/pnpm
- Use `Bun.serve()` not express
- Use `Bun.file()` not fs.readFile
- Bun auto-loads `.env` (no dotenv needed)

## Testing

```ts
import { test, expect } from "bun:test";

test("example", () => {
  expect(1).toBe(1);
});
```

Run with `bun test`.

## Docker

```bash
bun run docker:up      # Start all containers
bun run docker:down    # Stop containers
bun run docker:logs    # View logs
```

Services: postgres (54321), electric (3000), api (4000), web (5173), adminer (8080)
