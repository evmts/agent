---
name: architecture
description: Plue system architecture, component design, and data flow. Use when understanding how the system works or making architectural decisions.
---

# Plue Architecture

For comprehensive documentation with diagrams, see: [`architecture.md`](../../architecture.md) in the repository root.

## Quick Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│  Browser ──► Cloudflare Edge ──► Zig API ──► PostgreSQL            │
│                                     │                               │
│                                     ├──► SSH Server (Git)          │
│                                     └──► K8s Runners (gVisor)      │
└─────────────────────────────────────────────────────────────────────┘
```

## Core Components

| Component | Location | Purpose |
|-----------|----------|---------|
| Zig Server | `server/` | HTTP API, SSH, Agent execution |
| Astro UI | `ui/` | SSR frontend with file-based routing |
| Edge Proxy | `edge/` | CDN caching at Cloudflare |
| Database | `db/schema.sql` | PostgreSQL 16 |
| Agent Runner | `runner/` | Python agent execution in K8s |

## Key Architectural Decisions

| Decision | Approach | Why |
|----------|----------|-----|
| Language | Zig for server | Performance, safety, single binary |
| VCS | Jujutsu (jj) | First-class change tracking |
| Auth | SIWE (Ethereum) | Passwordless, decentralized |
| Sandboxing | gVisor on GKE | Syscall interception |
| Streaming | SSE | Simpler than WebSocket, HTTP-native |
| Caching | Content-addressable | Git SHAs are perfect cache keys |

## The Unified Workflow/Agent Model

Key insight: workflows and agents are the same thing—both execute code in sandboxed containers, the only difference is who decides the steps (human-written code vs LLM).

```
Event (push, PR, mention, prompt)
           │
           ▼
   Match to Workflow Definition
   (.plue/workflows/*.py)
           │
     ┌─────┴─────┐
     ▼           ▼
  Scripted    Agent Mode
    Mode      (LLM decides)
     │           │
     └─────┬─────┘
           ▼
   Same Execution Environment
   (gVisor sandbox, same tools)
```

## Data Flow

1. **Request** → Cloudflare Edge → Check cache/auth → Zig API
2. **Git Push** → SSH Server → jj-lib (Rust FFI) → Trigger workflows
3. **Agent** → K8s Job → gVisor pod → Stream back via SSE
4. **Persistence** → PostgreSQL for state, disk for git repos

## Related Skills

- `server` - Zig API internals
- `edge` - Cloudflare Workers caching
- `runner` - Python agent execution
- `database` - Schema and DAOs
- `security` - Auth, sandboxing, mTLS
- `git` - jj-lib FFI, SSH server
- `caching` - Cache strategy

## Directory Overview

```
plue/
├── server/         # Zig API (httpz)
├── ui/             # Astro SSR
├── edge/           # Cloudflare Workers
├── runner/         # Python agent runner
├── db/             # PostgreSQL schema + DAOs
├── core/           # Zig agent core library
├── e2e/            # Playwright tests
├── infra/          # Terraform, Helm, K8s
└── docs/           # Additional documentation
```
