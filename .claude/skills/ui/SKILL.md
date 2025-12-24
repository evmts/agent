---
name: ui
description: Plue Astro SSR frontend. Use when working on pages, components, client-side interactions, or understanding the frontend architecture.
---

# Plue UI (Astro Frontend)

Server-side rendered frontend using Astro v5 with file-based routing.

## Entry Points

- Pages: `ui/pages/`
- Components: `ui/components/`
- Lib utilities: `ui/lib/`
- Layouts: `ui/layouts/`

## Page Structure

```
ui/pages/
├── index.astro              # Landing page
├── login.astro              # Auth page
├── explore.astro            # Discover repos
├── new.astro                # Create repo
├── settings.astro           # User settings
├── settings/
│   ├── tokens.astro         # API tokens
│   └── ssh-keys.astro       # SSH keys
├── sessions/
│   ├── index.astro          # Agent sessions list
│   └── [id].astro           # Session detail
├── [user]/
│   ├── index.astro          # User profile
│   ├── profile.astro        # Profile edit
│   ├── stars.astro          # Starred repos
│   └── [repo]/
│       ├── index.astro      # Repo home
│       ├── tree/[...path].astro
│       ├── blob/[...path].astro
│       ├── blame/[...path].astro
│       ├── commits/[...path].astro
│       ├── changes/[bookmark].astro
│       ├── bookmarks.astro   # jj branches
│       ├── operations.astro  # jj operation log
│       ├── issues/
│       ├── milestones/
│       ├── landing/          # PR replacement
│       ├── workflows/        # Workflow runs
│       └── settings.astro
```

## Key Libraries

| File | Purpose |
|------|---------|
| `lib/api.ts` | API client for backend calls |
| `lib/auth.ts` | Session/auth utilities |
| `lib/cache.ts` | Response caching |
| `lib/git.ts` | Git/jj operations |
| `lib/telemetry.ts` | Error tracking, performance |
| `lib/csrf.ts` | CSRF token management |

## Components

```
ui/components/
├── Header.astro         # Site header
├── Footer.astro         # Site footer
├── RepoHeader.astro     # Repository header tabs
├── FileTree.astro       # Directory listing
├── CodeViewer.astro     # Syntax-highlighted code
├── IssueList.astro      # Issue listing
├── Timeline.astro       # Activity timeline
├── AgentChat.astro      # Agent session UI
└── ...
```

## API Client

```typescript
// ui/lib/api.ts
import { api } from '../lib/api';

// Server-side (SSR)
const repos = await api.get('/api/repos');

// Client-side with CSRF
await api.post('/api/repos', { name: 'my-repo' }, { csrf: true });
```

## Authentication

```typescript
// ui/lib/auth.ts
import { getUser, requireAuth } from '../lib/auth';

// In Astro page
const user = await getUser(Astro.request);
if (!user) return Astro.redirect('/login');

// Or use helper
const user = await requireAuth(Astro);
```

## Caching Strategy

```typescript
// ui/lib/cache.ts
import { withCache } from '../lib/cache';

// Cache for 5 minutes
const data = await withCache('key', () => fetchData(), { ttl: 300 });
```

## CSRF Protection

```typescript
// Client-side form submission
import { getCsrfToken } from '../lib/csrf';

const token = await getCsrfToken();
await fetch('/api/repos', {
  method: 'POST',
  headers: { 'X-CSRF-Token': token },
  body: JSON.stringify(data)
});
```

## Telemetry

```typescript
// ui/lib/telemetry.ts
import { initTelemetry, logError, withTimeout } from '../lib/telemetry';

// Initialize on page load
initTelemetry();

// Error tracking
try {
  await riskyOp();
} catch (e) {
  logError(e, { context: 'feature-x' });
}

// Timeout wrapper
await withTimeout(fetchData(), 30000, 'fetch-data');
```

## Development

```bash
zig build run:web      # Start Astro dev server (port 3000)
```

## Environment Variables

```bash
PUBLIC_API_URL=http://localhost:4000    # SSR API calls
PUBLIC_CLIENT_API_URL=http://localhost:4000  # Browser API calls
DATABASE_URL=postgresql://...           # Direct DB for SSR
```
