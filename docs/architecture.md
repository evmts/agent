# Plue Architecture

> **Note**: The comprehensive architecture documentation with detailed diagrams has moved to [`/architecture.md`](../architecture.md) in the repository root.

## Quick Reference

For comprehensive documentation including:
- System architecture diagrams
- Unified workflow/agent model
- Execution flow diagrams
- Sandboxing architecture (5 layers)
- Database schema relationships
- Git caching strategy
- Edge caching flow
- Warm pool architecture
- Infrastructure topology
- Tech stack summary
- Key architectural decisions

See: **[`/architecture.md`](../architecture.md)**

## Related Documentation

- **[Infrastructure](./infrastructure.md)** - Deployment, K8s, Terraform details
- **[Migration](./migration.md)** - Migration guide and implementation phases

## Quick Overview

```
Browser ──► Cloudflare Edge ──► Zig API ──► PostgreSQL
                                   │
                                   ├──► SSH Server (Git via jj-lib)
                                   └──► K8s Runners (gVisor sandbox)
```

### Core Insight

Workflows and agents are the same thing—both execute code in sandboxed containers. The only difference is who decides the steps:
- **Scripted mode**: Human-written Python code
- **Agent mode**: Claude LLM decides the steps

Both share the same execution environment, tools, and streaming protocol.
