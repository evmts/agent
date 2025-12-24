---
name: nodejs
description: Node.js/TypeScript development standards for Plue. Use when working with frontend, edge workers, or TypeScript code.
---

# Node.js / TypeScript Development

## Package Manager: pnpm

We use **pnpm** for package management. It's faster and uses less disk space than npm.

### Key Commands

```bash
# Install dependencies
pnpm install

# Add a dependency
pnpm add <package>

# Add dev dependency
pnpm add -D <package>

# Run scripts
pnpm run <script>
```

## Runtime: Bun

We use **Bun** as our local development runtime for speed:

```bash
# Run TypeScript directly
bun run src/index.ts

# Run tests
bun test

# Type checking
bun run typecheck
```

## Deployment: Cloudflare Workers

Production deployments run on **Cloudflare Workers**, not Node.js or Bun.

### Important Constraints

- No Node.js APIs (fs, path, etc.) in edge code
- Use Web APIs (fetch, Request, Response, crypto)
- Durable Objects for state
- Workers KV for key-value storage

### Edge Worker Structure

```
edge/
├── index.ts          # Main worker entry
├── routes/           # Route handlers
├── wrangler.toml     # Cloudflare config
└── package.json
```

### Deployment

```bash
# Deploy edge worker
cd edge && pnpm run deploy

# Local development
cd edge && pnpm run dev
```

## Project Locations

| Component | Location | Runtime |
|-----------|----------|---------|
| UI (Astro) | `ui/` | Bun (dev), Cloudflare Pages (prod) |
| Edge Worker | `edge/` | Cloudflare Workers |
| E2E Tests | `e2e/` | Bun + Playwright |

## Important: Runtime Awareness

When writing TypeScript:

1. **Check the target runtime** before using APIs
2. **Edge code**: Use only Web APIs
3. **Local/tests**: Can use Bun APIs
4. **No Node.js** built-ins anywhere

## Related Skills

- `edge` - Cloudflare Workers details
- `ui` - Astro frontend
- `caching` - Edge caching strategy
