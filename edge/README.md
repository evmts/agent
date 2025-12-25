# Edge Worker

Cloudflare Workers caching proxy that sits in front of the Plue origin server.

## Purpose

The edge worker provides:

- **Caching**: Content-addressable caching with build version invalidation
- **Authentication**: SIWE auth handled at edge (nonce generation, signature verification)
- **Rate Limiting**: IP-based rate limiting via Durable Objects
- **Security**: CSP headers, HTTPS enforcement, origin protection
- **Observability**: Prometheus metrics, structured logging, analytics

## Architecture

```
Client -> Edge Worker -> Origin Server
             |
             +-> Durable Objects (Auth, Rate Limit, Metrics)
```

Request flow:

1. Rate limit check (early rejection if exceeded)
2. Auth route handling (nonce, verify, logout) - handled at edge
3. Session validation from JWT cookie
4. Cache lookup (GET/HEAD only, public routes only)
5. Origin proxy (with user address header if authenticated)
6. Response caching (if Cache-Control allows)
7. Security headers added to all responses

## Key Files

| File | Purpose |
|------|---------|
| `index.ts` | Main worker entry point, request orchestration |
| `auth-do.ts` | Auth Durable Object (nonce storage, session state) |
| `rate-limit-do.ts` | Rate limit Durable Object (atomic counters) |
| `metrics-do.ts` | Metrics Durable Object (aggregation across edge) |
| `wrangler.toml` | Cloudflare Workers configuration |

## Caching Strategy

Cache key includes:
- Request URL (path + query params)
- Build version (`BUILD_VERSION` env var)

Cache behavior:
- Only cache GET/HEAD requests
- Skip cache for API routes (they handle their own)
- Skip cache for authenticated users (personalized content)
- Respect origin's Cache-Control headers
- Serve stale on origin failure (graceful degradation)

```
+-----------+     +-----------+     +--------+
| Client    | --> | Edge      | --> | Origin |
|           | <-- | (Cache)   | <-- |        |
+-----------+     +-----------+     +--------+
                        |
                        v
                  [Cache Storage]
                  - Public content
                  - Version-keyed
                  - Stale fallback
```

## Authentication Flow

SIWE (Sign-In With Ethereum) handled entirely at edge:

```
1. GET /api/auth/nonce
   -> Generate nonce
   -> Store in AUTH_DO (strong consistency)
   -> Return to client

2. POST /api/auth/verify {message, signature}
   -> Verify SIWE signature with domain validation
   -> Consume nonce atomically (replay protection)
   -> Create JWT session token
   -> Set HttpOnly cookie
   -> Return success

3. Subsequent requests
   -> Verify JWT from cookie
   -> Add X-Plue-User-Address header
   -> Proxy to origin with user context
```

## Rate Limiting

Distributed rate limiting via Durable Objects:

- Sharded by IP prefix (first 2 octets) for scalability
- Per-endpoint limits with different tiers
- Atomic counters with strong consistency
- Headers: X-RateLimit-Limit, X-RateLimit-Remaining, Retry-After

Limit tiers (see `lib/limit-type.ts`):
- `auth`: 10/min for auth endpoints
- `api:write`: 60/min for write operations
- `api`: 120/min for read operations
- `default`: 300/min for page requests

## Observability

Prometheus metrics endpoint: `/metrics`

Protected by either:
- `METRICS_API_KEY` - Bearer token auth
- `METRICS_ALLOWED_IPS` - IP allowlist (CIDR notation)

Metrics include:
- Request counts by status
- Auth success/failure rates
- Cache hit/miss ratios
- Rate limit events
- Request duration histograms

## Development

```bash
# Run locally (proxies to localhost:4321)
npm run dev

# Run tests
npm test

# Deploy to staging
npm run deploy:dev

# Deploy to production (auto-sets BUILD_VERSION)
npm run deploy
```

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `ORIGIN_HOST` | Yes | Origin server hostname |
| `BUILD_VERSION` | Yes | Cache invalidation key |
| `JWT_SECRET` | Yes | Secret for signing session JWTs |
| `METRICS_API_KEY` | No | Bearer token for /metrics endpoint |
| `METRICS_ALLOWED_IPS` | No | Comma-separated CIDR list for /metrics |

## Security

- CSP headers on all responses
- SIWE domain validation (prevents cross-domain replay)
- Nonce replay protection via Durable Objects
- HttpOnly session cookies
- HTTPS enforcement (HSTS header)
- Request ID propagation for tracing
- 15-second timeout on origin requests
