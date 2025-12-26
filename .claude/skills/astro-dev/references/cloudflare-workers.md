# Cloudflare Workers Deployment for Astro

## Overview

Cloudflare recommends **Workers** for all new Astro deployments. This guide covers Workers-specific deployment patterns, NOT Cloudflare Pages.

## Why Workers?

- **Modern architecture** - Recommended by Cloudflare for new projects
- **Full Workers API access** - KV, D1, R2, Queues, Durable Objects
- **Workers Assets** - Built-in static asset serving
- **Better performance** - Optimized for edge computing
- **Unified platform** - One deployment target for SSR and static assets

## Installation

```bash
# Using create-cloudflare (recommended)
npm create cloudflare@latest my-app -- --framework=astro

# Or add to existing project
npm install @astrojs/cloudflare
npx astro add cloudflare
```

## Configuration

### astro.config.mjs

```javascript
import { defineConfig } from 'astro/config';
import cloudflare from '@astrojs/cloudflare';

export default defineConfig({
  output: 'server', // or 'hybrid' for mixed rendering
  adapter: cloudflare({
    imageService: 'compile', // Use sharp at build time
    platformProxy: {
      enabled: true, // Enable Cloudflare runtime in dev
      persist: true, // Persist state between restarts
    },
  }),
});
```

### wrangler.jsonc

```jsonc
{
  "name": "my-astro-app",
  "main": "./dist/_worker.js",
  "compatibility_date": "2024-10-01",
  "assets": {
    "directory": "./dist"
  }
}
```

**Key differences from Pages:**
- `main` points to `_worker.js` (not `_worker.js/_routes.json`)
- `assets.directory` for static file serving
- No `pages_build_output_dir` needed

### public/.assetsignore

```
!*.wasm
!*.mjs
!*.json
```

Tells Workers which public files should NOT be served as static assets.

## Rendering Modes

### Server-Side Rendering (SSR)

All pages render on-demand:

```javascript
// astro.config.mjs
export default defineConfig({
  output: 'server',
  adapter: cloudflare(),
});
```

```astro
---
// src/pages/dynamic.astro
const data = await fetch('https://api.example.com/data').then(r => r.json());
---
<h1>{data.title}</h1>
```

### Hybrid Rendering

Static by default, opt-in to SSR:

```javascript
// astro.config.mjs
export default defineConfig({
  output: 'hybrid',
  adapter: cloudflare(),
});
```

```astro
---
// src/pages/product/[id].astro
export const prerender = false; // This page is SSR

const { id } = Astro.params;
---
```

### Pre-rendering in Server Mode

```astro
---
// src/pages/about.astro
export const prerender = true; // Static generation
---
```

## Accessing Cloudflare Runtime

### In Pages (.astro files)

```astro
---
// Access runtime via locals
const { env, cf, ctx } = Astro.locals.runtime;

// Use KV
const value = await env.MY_KV.get('key');

// Access request properties
const country = cf.country;
const city = cf.city;
---

<h1>Hello from {country}!</h1>
```

### In API Routes

```typescript
// src/pages/api/data.ts
import type { APIRoute } from 'astro';

export const GET: APIRoute = async ({ locals }) => {
  const { env, cf, ctx } = locals.runtime;
  
  // Use D1
  const result = await env.DB.prepare(
    'SELECT * FROM users WHERE id = ?'
  ).bind(1).first();
  
  return new Response(JSON.stringify(result), {
    headers: { 'Content-Type': 'application/json' },
  });
};
```

## Bindings

### KV Namespace

**wrangler.jsonc:**
```jsonc
{
  "kv_namespaces": [
    {
      "binding": "MY_KV",
      "id": "your-kv-id",
      "preview_id": "your-preview-kv-id"
    }
  ]
}
```

**Usage:**
```typescript
const { env } = Astro.locals.runtime;

// Get
const value = await env.MY_KV.get('key', { type: 'json' });

// Put with expiration
await env.MY_KV.put('key', JSON.stringify(data), {
  expirationTtl: 3600, // 1 hour
});

// Delete
await env.MY_KV.delete('key');

// List keys
const list = await env.MY_KV.list({ prefix: 'user:' });
```

### D1 Database

**wrangler.jsonc:**
```jsonc
{
  "d1_databases": [
    {
      "binding": "DB",
      "database_name": "my-database",
      "database_id": "your-db-id"
    }
  ]
}
```

**Usage:**
```typescript
const { env } = Astro.locals.runtime;

// Query
const { results } = await env.DB.prepare(
  'SELECT * FROM posts WHERE published = ?'
).bind(true).all();

// Insert
await env.DB.prepare(
  'INSERT INTO posts (title, content) VALUES (?, ?)'
).bind(title, content).run();

// Transaction
await env.DB.batch([
  env.DB.prepare('UPDATE users SET credits = credits - ? WHERE id = ?').bind(10, userId),
  env.DB.prepare('INSERT INTO transactions (user_id, amount) VALUES (?, ?)').bind(userId, -10),
]);
```

See `references/cloudflare-d1.md` for detailed D1 setup.

### R2 Bucket

**wrangler.jsonc:**
```jsonc
{
  "r2_buckets": [
    {
      "binding": "MY_BUCKET",
      "bucket_name": "my-bucket"
    }
  ]
}
```

**Usage:**
```typescript
const { env } = Astro.locals.runtime;

// Upload
const file = await request.formData().then(fd => fd.get('file'));
await env.MY_BUCKET.put('uploads/file.jpg', file);

// Download
const object = await env.MY_BUCKET.get('uploads/file.jpg');
if (object) {
  return new Response(object.body, {
    headers: {
      'Content-Type': object.httpMetadata.contentType,
    },
  });
}

// Delete
await env.MY_BUCKET.delete('uploads/file.jpg');
```

### Environment Variables

**wrangler.jsonc:**
```jsonc
{
  "vars": {
    "API_URL": "https://api.example.com",
    "ENVIRONMENT": "production"
  }
}
```

**For secrets:**
```bash
echo "secret-value" | wrangler secret put API_KEY
```

**Usage:**
```typescript
const { env } = Astro.locals.runtime;
const apiUrl = env.API_URL;
const apiKey = env.API_KEY; // From secrets
```

## TypeScript Support

### Generate Types

```bash
npx wrangler types
```

This creates `.wrangler/types/runtime.d.ts`.

### Type Definitions

**src/env.d.ts:**
```typescript
/// <reference types="astro/client" />
/// <reference types="@cloudflare/workers-types" />

type Runtime = import('@astrojs/cloudflare').Runtime<Env>;

declare namespace App {
  interface Locals extends Runtime {
    user?: {
      id: string;
      email: string;
    };
  }
}

interface Env {
  MY_KV: KVNamespace;
  DB: D1Database;
  MY_BUCKET: R2Bucket;
  API_KEY: string;
  API_URL: string;
}
```

## Development

### Local Development

```bash
# Standard dev server with platformProxy
npm run dev

# With type generation
npx wrangler types && npm run dev
```

The `platformProxy` in `astro.config.mjs` provides:
- Local KV simulation
- Local D1 database access
- Environment variable access
- CF request properties (mocked)

### Remote Development

```bash
# Use remote bindings in development
npx wrangler dev --remote
```

## Deployment

### Deploy with Wrangler

```bash
# Build
npm run build

# Deploy to production
npx wrangler deploy

# Deploy to specific environment
npx wrangler deploy --env staging
```

### CI/CD with GitHub Actions

```yaml
name: Deploy to Cloudflare Workers

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: 'npm'
      
      - run: npm ci
      - run: npm run build
      
      - name: Deploy
        uses: cloudflare/wrangler-action@v3
        with:
          apiToken: ${{ secrets.CLOUDFLARE_API_TOKEN }}
          accountId: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
```

### Multiple Environments

**wrangler.jsonc:**
```jsonc
{
  "name": "my-app",
  "main": "./dist/_worker.js",
  "compatibility_date": "2024-10-01",
  "assets": {
    "directory": "./dist"
  },
  "env": {
    "staging": {
      "name": "my-app-staging",
      "vars": {
        "ENVIRONMENT": "staging"
      }
    },
    "production": {
      "name": "my-app-production",
      "vars": {
        "ENVIRONMENT": "production"
      }
    }
  }
}
```

**Deploy:**
```bash
npx wrangler deploy --env staging
npx wrangler deploy --env production
```

## Image Optimization

### Configuration

```javascript
// astro.config.mjs
export default defineConfig({
  adapter: cloudflare({
    imageService: 'compile', // Recommended for Workers
  }),
});
```

**Options:**
- `'compile'` - Uses sharp at build time (recommended)
- `'passthrough'` - No optimization
- Custom service (must be compatible with Workers runtime)

### Usage

```astro
---
import { Image } from 'astro:assets';
import photo from '../assets/photo.jpg';
---

<Image src={photo} alt="Photo" width={800} />
```

## Performance Optimization

### Caching

Workers automatically caches hashed assets:

```typescript
// Custom cache control
export const GET: APIRoute = () => {
  return new Response(data, {
    headers: {
      'Cache-Control': 'public, max-age=3600',
      'CDN-Cache-Control': 'public, max-age=86400',
    },
  });
};
```

### Edge Caching with KV

```typescript
async function getCachedData(env: Env, key: string) {
  // Try cache
  const cached = await env.MY_KV.get(key, { type: 'json' });
  if (cached) return cached;
  
  // Fetch fresh
  const fresh = await fetchFromAPI();
  
  // Cache for 1 hour
  await env.MY_KV.put(key, JSON.stringify(fresh), {
    expirationTtl: 3600,
  });
  
  return fresh;
}
```

## Redirects

**public/_redirects:**
```
/old-page /new-page 301
/blog/* /news/:splat 302
```

## Monitoring

### View Logs

```bash
# Real-time logs
npx wrangler tail

# Filter by status
npx wrangler tail --status error
```

### Analytics

Access in Cloudflare dashboard:
- Request count
- Error rate
- P50/P99 latency
- Bandwidth usage

## Common Patterns

### Authentication

```typescript
// src/middleware.ts
import type { MiddlewareHandler } from 'astro';

export const onRequest: MiddlewareHandler = async ({ locals, request }, next) => {
  const token = request.headers.get('Authorization');
  
  if (token) {
    const { env } = locals.runtime;
    const user = await verifyToken(token, env.JWT_SECRET);
    locals.user = user;
  }
  
  return next();
};
```

### Rate Limiting

```typescript
async function rateLimit(env: Env, ip: string): Promise<boolean> {
  const key = `rate:${ip}`;
  const count = await env.MY_KV.get(key);
  
  if (count && parseInt(count) > 100) {
    return false; // Rate limited
  }
  
  await env.MY_KV.put(key, String((parseInt(count || '0') + 1)), {
    expirationTtl: 60, // 1 minute window
  });
  
  return true;
}
```

## Troubleshooting

### Common Issues

**Issue: "Module not found"**
- Ensure all dependencies are in `dependencies`, not `devDependencies`
- Run `npm install` again

**Issue: Bindings not working**
- Check `wrangler.jsonc` configuration
- Run `wrangler types` to regenerate types
- Verify binding IDs in Cloudflare dashboard

**Issue: Build fails**
- Check Node.js version (18+)
- Run `astro check` for TypeScript errors
- Ensure `@astrojs/cloudflare` is up to date

**Issue: 404 on routes**
- Verify `output: 'server'` for SSR routes
- Check file-based routing in `src/pages/`

## Migration from Pages

If migrating from Cloudflare Pages:

1. Remove `pages_build_output_dir` from config
2. Update to `wrangler.jsonc` format
3. Change `main` to `./dist/_worker.js`
4. Add `assets.directory` configuration
5. Move bindings from Pages dashboard to `wrangler.jsonc`
6. Update deployment command to `wrangler deploy`

## Resources

- [Cloudflare Workers Docs](https://developers.cloudflare.com/workers/)
- [Astro Cloudflare Adapter](https://docs.astro.build/en/guides/integrations-guide/cloudflare/)
- [Wrangler CLI Reference](https://developers.cloudflare.com/workers/wrangler/)
- [Workers Examples](https://developers.cloudflare.com/workers/examples/)

## Best Practices

1. **Use Workers for new projects** - Pages is legacy
2. **Enable platformProxy** - Test with real bindings locally
3. **Generate types** - Run `wrangler types` after binding changes
4. **Use environment variables** - Keep config out of code
5. **Leverage edge caching** - Use KV for expensive operations
6. **Monitor with wrangler tail** - Watch real-time logs
7. **Deploy to staging first** - Test before production
8. **Keep wrangler updated** - Get latest features and fixes
