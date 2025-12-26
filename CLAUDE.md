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

> **CRITICAL: Manual Testing Required**
>
> **YOU MUST test the app end-to-end in a browser after making changes.** Curl commands are NOT sufficient - you must verify the actual user experience.
>
> After ANY code change:
> 1. Rebuild Docker if server code changed: `docker compose -f infra/docker/docker-compose.yaml build api --no-cache`
> 2. Restart services: `docker compose -f infra/docker/docker-compose.yaml up -d`
> 3. Start the frontend: `bunx astro dev --host`
> 4. **Open the app in a browser and test the affected pages** - check for errors, verify functionality works
> 5. Check Astro server logs for API errors or rendering failures
> 6. Check Docker API logs: `docker logs plue-api-1 --tail 30`
>
> **Why browser testing matters:**
> - Curl testing individual endpoints can pass while the full page fails
> - SSR pages make multiple API calls - all must succeed
> - JavaScript hydration errors only appear in browser
> - Visual regressions are invisible to curl
>
> Quick verification:
> ```bash
> curl http://localhost:4000/health                    # API health check
> curl http://localhost:4000/api/repos                 # Verify routes work
> docker logs plue-api-1 --tail 20                     # Check for errors
> # Then OPEN https://localhost:4321/ IN A BROWSER
> ```
>
> **Do not mark a task complete until you have loaded the affected pages in a browser and verified they render without errors.**
> Untested code is broken code. Curl-only tested code is also broken code.

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
| Database DAOs (Zig) | `db/daos/` |
| API client | `ui/lib/api.ts` |
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
