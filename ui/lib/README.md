# Lib

Shared utilities and libraries for Plue UI.

## Core Utilities

| File | Purpose |
|------|---------|
| `index.ts` | Library exports |
| `types.ts` | Shared TypeScript types |
| `auth.ts` | Authentication helpers |
| `auth-helpers.ts` | SIWE auth utilities |
| `client-auth.ts` | Client-side auth state |
| `cache.ts` | Cache header utilities |
| `time.ts` | Time formatting |
| `date-utils.ts` | Date manipulation |
| `toast.ts` | Toast notifications |
| `telemetry.ts` | Analytics and metrics |

## Git & Version Control

| File | Purpose |
|------|---------|
| `git.ts` | Git operations (via API) |
| `jj.ts` | Jujutsu VCS operations |
| `jj-types.ts` | Jujutsu type definitions |

## Issues & Content

| File | Purpose |
|------|---------|
| `git-issues.ts` | Issue management |
| `git-issue-types.ts` | Issue type definitions |
| `git-issue-dependencies.ts` | Issue dependency parsing |
| `issue-reference-parser.ts` | Cross-reference parsing |
| `markdown.ts` | Markdown rendering |
| `frontmatter.ts` | YAML frontmatter parsing |

## Infrastructure

| File | Purpose |
|------|---------|
| `porto.ts` | API client utilities |

## Usage Patterns

### Auth
```typescript
import { getUser } from './lib/auth-helpers';

const user = await getUser(request);
if (!user) {
  return redirect('/login');
}
```

### Cache Headers
```typescript
import { cacheForever, noCache } from './lib/cache';

// Immutable content
return new Response(data, {
  headers: { 'Cache-Control': cacheForever() }
});

// Dynamic content
return new Response(data, {
  headers: { 'Cache-Control': noCache() }
});
```

### Markdown
```typescript
import { renderMarkdown } from './lib/markdown';

const html = await renderMarkdown(content);
```

### Issue References
```typescript
import { parseIssueReferences } from './lib/issue-reference-parser';

const refs = parseIssueReferences(text);
// Returns: [{ owner, repo, number }]
```

## Testing

Tests located in `__tests__/`:
- `auth-helpers.test.ts`
- `cache.test.ts`
- `markdown.test.ts`
- `references.test.ts`
- `frontmatter.test.ts`
- `time.test.ts`
- `mentions.test.ts`

Run tests:
```bash
npm test
```
