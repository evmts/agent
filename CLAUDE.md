# Plue

A brutalist GitHub clone with integrated AI agent capabilities.

## Quick Start

```bash
zig build run          # Start docker + server (localhost:4000)
zig build run:web      # Start Astro dev (localhost:3000) - separate terminal
zig build test         # Run all tests
```

## Project Structure

```
plue/
├── server/            # Zig API server (httpz)
│   ├── src/ai/        # Agent system + tools
│   ├── src/routes/    # API handlers
│   └── jj-ffi/        # Rust FFI for jj-lib
├── ui/                # Astro SSR frontend
│   ├── pages/         # Astro pages
│   ├── components/    # UI components
│   └── lib/           # Utilities (auth, cache, git, etc.)
├── edge/              # Cloudflare Workers caching proxy
│   ├── index.ts       # Main worker (proxy + cache)
│   ├── purge.ts       # Cache purge utilities
│   └── types.ts       # Environment bindings
├── core/              # Zig agent core library
│   ├── root.zig       # Module entry point
│   ├── models/        # Domain entities (Session, Message, Part)
│   ├── state.zig      # Runtime state tracking
│   └── events.zig     # Event bus
├── db/                # Database layer (@plue/db)
│   ├── root.zig       # Zig module entry
│   ├── daos/          # Data Access Objects (Zig)
│   ├── schema.sql     # PostgreSQL schema
│   └── *.ts           # TypeScript DB utilities
├── e2e/               # End-to-end tests (@plue/e2e)
│   ├── cases/         # Test spec files
│   ├── fixtures.ts    # Test fixtures
│   └── playwright.config.ts
├── docs/              # Architecture & infrastructure docs
├── infra/             # All deployment infrastructure
│   ├── terraform/     # Infrastructure as code
│   ├── helm/          # Helm charts
│   ├── k8s/           # Kubernetes manifests
│   ├── docker/        # Dockerfile, docker-compose
│   ├── monitoring/    # Prometheus, Grafana, Loki
│   └── scripts/       # Deployment scripts
└── runner/            # Agent execution environment
```

## Build Commands

| Command | Purpose |
|---------|---------|
| `zig build` | Build all |
| `zig build run` | Dev environment (docker + server) |
| `zig build test` | All tests (Zig + TS + Rust) |
| `zig build test:zig` | Zig tests only |
| `zig build test:edge` | Edge worker tests |
| `zig build lint` | Lint all code |

## Key Locations

| What | Where |
|------|-------|
| API routes | `server/src/routes/` |
| Agent tools | `server/src/ai/tools/` |
| Database schema | `db/schema.sql` |
| Database DAOs | `db/daos/` |
| Frontend pages | `ui/pages/` |
| Cache utilities | `ui/lib/cache.ts` |
| Edge worker | `edge/index.ts` |
| E2E tests | `e2e/cases/` |

## Documentation

- **Architecture**: `docs/architecture.md` - System design, components, data flow
- **Infrastructure**: `docs/infrastructure.md` - Deployment, K8s, Terraform
- **Migration**: `docs/migration.md` - Migration from previous architecture

## Git Workflow

Single-branch development on `plue-git`. No feature branches.

```bash
git checkout plue-git
git add . && git commit -m "feat: description"
git push origin plue-git
```

## Tech Stack

- **Server**: Zig + httpz
- **Frontend**: Astro v5 (SSR)
- **Database**: PostgreSQL
- **Edge**: Cloudflare Workers
- **Infra**: Docker, GKE, Terraform

## Subagent Prompting

When spawning subagents via the Task tool, craft prompts thoughtfully. All agent communication should be extremely token-efficient—dense with information, no filler.

**Structure your prompts well:**
- Use XML tags to delineate distinct sections (e.g., `<context>`, `<task>`, `<constraints>`)
- Use markdown for readability within sections
- Front-load critical context before stating the task

**Provide rich context:**
- Include relevant file paths, function names, and architectural decisions
- Share the "why" behind the task, not just the "what"
- Surface any constraints, edge cases, or prior attempts that inform the work

**Enable autonomy:**
- State the desired outcome clearly, but avoid dictating implementation steps
- Let the agent leverage its tools and judgment to find the best path
- Specify what success looks like rather than how to achieve it

**Example structure:**
```
<context>
[Relevant background, file locations, architectural notes]
</context>

<task>
[Clear statement of the goal]
</task>

<output>
[What you expect back: a summary, code changes, a recommendation, etc.]
</output>
```
