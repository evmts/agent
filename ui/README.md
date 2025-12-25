# UI

Astro v5 SSR frontend for Plue - a brutalist GitHub clone with AI agents.

## Architecture

```
Request Flow:
  Browser -> middleware.ts (auth, SIWE) -> pages/ (SSR) -> components/ -> API (Zig server)
                                             |
                                             v
                                         layouts/Layout.astro
```

## Directory Structure

| Directory | Purpose |
|-----------|---------|
| `pages/` | File-based routing (SSR + API endpoints) |
| `components/` | Astro components (UI building blocks) |
| `layouts/` | Page layout wrapper |
| `lib/` | Shared utilities (auth, cache, types, git) |
| `public/` | Static assets (favicon, PWA icons) |

## Key Files

| File | Purpose |
|------|---------|
| `middleware.ts` | SIWE authentication, session handling |
| `env.d.ts` | TypeScript environment definitions |

## Development

```bash
zig build run:web    # Start dev server (localhost:3000)
npm run build        # Production build
npm run preview      # Preview production build
```

## Stack

- Astro v5 (SSR mode)
- TypeScript
- View Transitions API
- SIWE (Sign-In With Ethereum)
- Content-addressable caching (via edge proxy)

## Routing

File-based routing in `pages/`:
- `[user]/[repo]/` - Repository pages
- `api/` - REST API endpoints (proxy to Zig server)
- Top-level pages - Landing, explore, login, settings

## Cache Strategy

All responses set `Cache-Control` headers for edge caching:
- Immutable content: `public, max-age=31536000, immutable`
- Dynamic content: `public, max-age=0, must-revalidate`
- Private content: `private, no-cache`

See `lib/cache.ts` for utilities.
