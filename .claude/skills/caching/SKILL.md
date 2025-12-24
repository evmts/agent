---
name: caching
description: Plue caching strategy at edge and origin. Use when working on cache headers, CDN configuration, or performance optimization.
---

# Plue Caching Architecture

## Overview

Plue uses a multi-layer caching strategy optimized for Git's content-addressable nature.

```
Browser Cache ──► Cloudflare Edge ──► Origin Server ──► PostgreSQL
      │                  │                  │
   max-age          Workers Cache      Response headers
```

## Key Insight: Content-Addressable Caching

Git SHA = hash(content), making most objects immutable forever:

```
GET /api/torvalds/linux/blob/abc123/README.md

Cache Key: abc123:/README.md
Cache TTL: 31536000 (1 year)

Why? If content changes, SHA changes, so this exact URL
will NEVER return different content.
```

## Cache TTL Matrix

| Content Type | TTL | Reason |
|-------------|-----|--------|
| Ref → Commit | 5s | Mutable (changes on push) |
| Commit → Tree | Forever | Immutable (SHA = hash) |
| Tree → Entries | Forever | Immutable |
| Blob → Content | Forever | Immutable |
| User Profile | 60s | Semi-static |
| Issue List | 30s | Frequently updated |
| Static Assets | Forever | Versioned in URL |

## Edge Layer (Cloudflare Workers)

### Request Flow

```typescript
// edge/index.ts

// 1. Check for session cookie
if (hasSessionCookie(request)) {
  // Authenticated: bypass cache, proxy to origin
  const response = await proxyToOrigin(request);
  response.headers.set('X-Cache', 'BYPASS');
  return response;
}

// 2. Check Workers Cache
const cacheKey = createCacheKey(request, env);
const cached = await caches.default.match(cacheKey);
if (cached) {
  cached.headers.set('X-Cache', 'HIT');
  return cached;
}

// 3. Cache miss: fetch from origin
const response = await proxyToOrigin(request);

// 4. Cache if cacheable
if (shouldCache(response)) {
  ctx.waitUntil(caches.default.put(cacheKey, response.clone()));
  response.headers.set('X-Cache', 'MISS');
}

return response;
```

### Cache Key Strategy

```typescript
function createCacheKey(request: Request, env: Env): Request {
  const url = new URL(request.url);

  // Include build version for deploy invalidation
  url.searchParams.set('_v', env.BUILD_VERSION);

  return new Request(url.toString(), {
    method: request.method,
    headers: request.headers,
  });
}
```

## Origin Cache Headers

### Zig Server

```zig
// server/routes/git.zig

// Immutable content (by SHA)
fn setBlobHeaders(res: *Response, sha: []const u8) void {
    res.headers.add("Cache-Control", "public, max-age=31536000, immutable");
    res.headers.add("ETag", sha);
}

// Mutable content (ref resolution)
fn setRefHeaders(res: *Response) void {
    res.headers.add("Cache-Control", "public, max-age=5");
}
```

### Astro Frontend

```typescript
// ui/lib/cache.ts

export function cacheStatic(Astro: AstroGlobal) {
  Astro.response.headers.set('Cache-Control', 'public, max-age=31536000, immutable');
}

export function cacheWithTags(Astro: AstroGlobal, tags: string[]) {
  Astro.response.headers.set('Cache-Control', 'public, max-age=86400');
  Astro.response.headers.set('Cache-Tag', tags.join(','));
}

export function cacheShort(Astro: AstroGlobal, tags: string[], maxAge: number = 60) {
  Astro.response.headers.set('Cache-Control', `public, max-age=${maxAge}, stale-while-revalidate=3600`);
  Astro.response.headers.set('Cache-Tag', tags.join(','));
}

export function noCache(Astro: AstroGlobal) {
  Astro.response.headers.set('Cache-Control', 'no-store');
}
```

## Cache Invalidation

### Deploy Invalidation

```typescript
// BUILD_VERSION in cache key changes on deploy
// All cache keys with old version become invalid
url.searchParams.set('_v', env.BUILD_VERSION);
```

### Cache-Tag Purge

```typescript
// edge/purge.ts
export async function purgeCacheByTag(tag: string) {
  // Uses Cloudflare API to purge by Cache-Tag
  await fetch(`https://api.cloudflare.com/client/v4/zones/${zoneId}/purge_cache`, {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${apiToken}` },
    body: JSON.stringify({ tags: [tag] }),
  });
}

// Tags: user:123, repo:456, issue:789
```

### Server-Side Invalidation

```zig
// server/services/edge_notifier.zig
pub const EdgeNotifier = struct {
    pub fn notifyRepoUpdate(self: *Self, repo_id: u64) !void {
        // Purge cache for this repo
        try self.purgeTag("repo:{d}", .{repo_id});
    }
};
```

## Response Headers

| Header | Purpose |
|--------|---------|
| `X-Cache` | HIT/MISS/BYPASS - debugging |
| `Cache-Control` | TTL and cacheability |
| `Cache-Tag` | Tags for selective purge |
| `ETag` | Content hash for conditional requests |
| `Vary` | Cache key variation (Cookie) |

## Key Files

| File | Purpose |
|------|---------|
| `edge/index.ts` | Edge caching logic |
| `edge/purge.ts` | Cache purge utilities |
| `ui/lib/cache.ts` | Astro cache helpers |
| `server/services/edge_notifier.zig` | Cache invalidation |

## Performance Tips

1. **Use SHA-based URLs** - Enable infinite caching
2. **Set Cache-Tag** - Enable selective invalidation
3. **Vary on Cookie** - Separate authenticated/anonymous caches
4. **stale-while-revalidate** - Serve stale while fetching fresh
5. **ETag + If-None-Match** - 304 responses for unchanged content
