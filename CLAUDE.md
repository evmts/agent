# Plue

A brutalist GitHub clone with integrated AI agent capabilities.

> **IMPORTANT: Pre-MVP Development**
>
> This project has NOT been deployed or released yet. We are still working towards the MVP. Therefore:
> - **NO backwards compatibility** - Break things freely, rename anything, delete without hesitation
> - **NO tech debt** - Don't write hacky workarounds "for now", do it right or don't do it
> - **NO migration files** - Just modify `schema.sql` directly, there are no production databases to migrate
> - **NO deprecation paths** - Remove old code completely, don't leave compatibility shims
>
> Move fast and break things. Clean code only.

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
│   ├── routes/        # API handlers
│   ├── ai/            # Agent system + tools
│   ├── workflows/     # Workflow execution engine
│   ├── ssh/           # Git over SSH
│   └── middleware/    # Auth, CSRF, rate limiting
├── ui/                # Astro SSR frontend
│   ├── pages/         # File-based routing
│   ├── components/    # UI components
│   └── lib/           # Auth, cache, API client
├── edge/              # Cloudflare Workers caching proxy
├── runner/            # Python agent execution (K8s pods)
├── db/                # Database layer
│   ├── schema.sql     # PostgreSQL schema
│   └── daos/          # Data Access Objects (Zig)
├── core/              # Zig agent core library
├── e2e/               # End-to-end tests (Playwright)
├── infra/             # Terraform, Helm, K8s, Docker
└── docs/              # Additional documentation
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
| API routes | `server/routes/` |
| Agent tools | `server/ai/tools/` |
| Database schema | `db/schema.sql` |
| Database DAOs | `db/daos/` |
| Frontend pages | `ui/pages/` |
| Cache utilities | `ui/lib/cache.ts` |
| Edge worker | `edge/index.ts` |
| E2E tests | `e2e/cases/` |

## Documentation

| Document | Purpose |
|----------|---------|
| [`architecture.md`](./architecture.md) | Comprehensive system design with diagrams |
| [`docs/infrastructure.md`](./docs/infrastructure.md) | Deployment, K8s, Terraform |
| [`docs/migration.md`](./docs/migration.md) | Migration from previous architecture |

## Skills

Claude Code skills provide domain-specific context. Located in `.claude/skills/`:

### Core Skills
| Skill | Description |
|-------|-------------|
| `architecture` | System design, component overview, data flow |
| `server` | Zig API server - routes, middleware, SSH |
| `ui` | Astro SSR frontend - pages, components, libs |
| `database` | Schema, migrations, table structure |

### Subsystem Skills
| Skill | Description |
|-------|-------------|
| `edge` | Cloudflare Workers caching proxy |
| `runner` | Python agent execution in K8s pods |
| `agent-system` | AI agent tools and configuration |
| `git` | jj-lib FFI, SSH server, Git operations |

### Cross-Cutting Skills
| Skill | Description |
|-------|-------------|
| `security` | SIWE auth, sandboxing, mTLS, permissions |
| `caching` | Edge caching, content-addressable strategy |
| `observability` | System health, metrics, logs, debugging |

### Infrastructure Skills
| Skill | Description |
|-------|-------------|
| `infrastructure` | Deployment, K8s, Terraform |
| `docker` | Docker containerization, docker-compose |
| `development` | Local dev environment setup |

### Debugging Skills
| Skill | Description |
|-------|-------------|
| `workflow-debugging` | Workflow execution issues |
| `test-debugging` | Playwright E2E test failures |

## Git Workflow

Single-branch development on `plue-git`. No feature branches.

```bash
git checkout plue-git
git add . && git commit -m "feat: description"
git push origin plue-git
```

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
