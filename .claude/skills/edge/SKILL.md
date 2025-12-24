---
name: edge
description: Plue Cloudflare Workers edge proxy. Use when working on CDN caching, edge routing, or understanding how requests flow through the edge layer.
---

# Plue Edge (Cloudflare Workers)

Caching proxy layer deployed on Cloudflare Workers. Handles CDN caching and routes requests to origin.

## Entry Point

- Main: `edge/index.ts`
- Types: `edge/types.ts`
- Purge utilities: `edge/purge.ts`

## Request Flow

```
Browser → Cloudflare Edge → [Cache Check] → Origin (Zig API or Astro)
                               ↓
                         Cache HIT? → Return cached
                               ↓
                         Cache MISS → Fetch origin → Cache if public
```

## Caching Logic

```typescript
// edge/index.ts

// Skip cache for:
// 1. Non-GET/HEAD methods (POST, PUT, DELETE, etc.)
// 2. API routes (/api/*) - backend handles its own caching
// 3. Authenticated users (has session cookie)

if (request.method !== 'GET' && request.method !== 'HEAD') {
  return proxyToOrigin(request, env);
}

if (url.pathname.startsWith('/api/')) {
  return proxyToOrigin(request, env);
}

if (hasSessionCookie(request)) {
  // Authenticated users get personalized content
  const response = await proxyToOrigin(request, env);
  response.headers.set('X-Cache', 'BYPASS');
  return response;
}
```

## Cache Key Strategy

```typescript
function createCacheKey(request: Request, env: Env): Request {
  const url = new URL(request.url);

  // Include build version for deploy invalidation
  // When BUILD_VERSION changes, all cache keys become invalid
  url.searchParams.set('_v', env.BUILD_VERSION || 'dev');

  return new Request(url.toString(), {
    method: request.method,
    headers: request.headers,
  });
}
```

## Cache Headers

Only caches responses with proper Cache-Control:

```typescript
function shouldCache(response: Response): boolean {
  if (response.status !== 200) return false;

  const cacheControl = response.headers.get('Cache-Control');
  if (!cacheControl) return false;

  // Cache if public with max-age
  return cacheControl.includes('public') &&
    (cacheControl.includes('max-age') || cacheControl.includes('s-maxage'));
}
```

## Cache Headers Added

| Header | Value | Meaning |
|--------|-------|---------|
| `X-Cache` | `HIT` | Served from edge cache |
| `X-Cache` | `MISS` | Fetched from origin, now cached |
| `X-Cache` | `BYPASS` | Not cacheable (authenticated/API) |

## Environment Bindings

```typescript
// edge/types.ts
export interface Env {
  ORIGIN_HOST: string;      // Origin server hostname
  BUILD_VERSION: string;    // For cache busting on deploy
  AUTH_DO?: DurableObjectNamespace;  // Auth Durable Object (planned)
  RATE_LIMIT_DO?: DurableObjectNamespace;  // Rate limit DO (planned)
}
```

## Redirect Handling

Rewrites redirect URLs to edge domain:

```typescript
if (response.status >= 300 && response.status < 400) {
  const location = response.headers.get('Location');
  if (location?.includes(env.ORIGIN_HOST)) {
    headers.set('Location', location.replace(
      `https://${env.ORIGIN_HOST}`,
      url.origin
    ));
  }
}
```

## Cache Purging

```typescript
// edge/purge.ts
// Utilities for cache invalidation

// Called by EdgeNotifier in server when content changes
await purgeCacheByUrl(url);
await purgeCacheByTag(tag);
```

## Deployment

Deployed via Terraform:

```hcl
# infra/terraform/modules/cloudflare-workers/main.tf
resource "cloudflare_worker_script" "edge" {
  name    = "plue-edge"
  content = file("${path.module}/edge/dist/index.js")
}
```

## Testing

```bash
zig build test:edge    # Run edge worker tests
```

## Integration with Server

The server notifies edge of cache invalidation:

```zig
// server/services/edge_notifier.zig
pub const EdgeNotifier = struct {
    pub fn notifyCacheInvalidation(self: *Self, paths: []const []const u8) !void {
        // POST to edge worker to purge cache
    }
};
```

## Related Skills

- `caching` - Detailed caching strategy
- `security` - Planned auth at edge (SIWE)
