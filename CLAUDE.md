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
├── edge/              # Cloudflare Workers proxy
├── db/schema.sql      # PostgreSQL schema
├── docs/              # Architecture & infrastructure docs
└── terraform/         # Infrastructure as code
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
| Frontend pages | `ui/pages/` |
| Edge router | `edge/src/router.ts` |

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
