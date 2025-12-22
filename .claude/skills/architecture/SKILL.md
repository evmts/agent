---
name: architecture
description: Plue system architecture, component design, and data flow. Use when understanding how the system works or making architectural decisions.
---

# Plue Architecture

For full details, see: `docs/architecture.md`

## Quick Overview

Plue is a brutalist GitHub clone with integrated AI agents. The architecture is intentionally simple:

```
Client → Cloudflare CDN → Zig Server → PostgreSQL
                              ↓
                         WebSocket (streaming)
                              ↓
                    K8s Sandboxed Runners (gVisor)
```

## Key Components

| Component | Location | Purpose |
|-----------|----------|---------|
| Zig Server | `server/` | HTTP API, WebSocket, Git ops, Agent execution |
| Astro UI | `ui/` | SSR frontend with file-based routing |
| Edge Proxy | `edge/` | CDN caching, auth pages |
| Database | `db/schema.sql` | PostgreSQL schema |
| Agent Tools | `server/src/ai/tools/` | File ops, grep, web fetch, PTY |

## Architecture Decisions

- **No ElectricSQL** — direct Postgres queries
- **No Edge SQLite** — simple CDN proxy
- **WebSocket streaming** — real-time agent output
- **gVisor sandboxing** — secure code execution in K8s
