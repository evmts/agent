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

## Tech Stack

- **Runtime**: Bun (not Node.js)
- **Frontend**: Astro v5 (SSR, file-based routing)
- **Backend**: Hono + Bun.serve (WebSocket support)
- **Database**: PostgreSQL + ElectricSQL (real-time sync)
- **AI**: Vercel AI SDK + Claude Sonnet 4
- **Validation**: Zod v4

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
