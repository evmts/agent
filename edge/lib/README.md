# Edge Library Modules

Shared utilities and helpers for the edge worker.

## Modules

| File | Purpose |
|------|---------|
| `analytics.ts` | Workers Analytics Engine event tracking |
| `limit-type.ts` | Rate limit tier classification |
| `logger.ts` | Structured JSON logging with request IDs |
| `public-routes.ts` | Public route definitions (auth bypass) |
| `rate-limit.ts` | Rate limit checking via Durable Objects |
| `session.ts` | JWT session management (sign, verify, cookies) |
| `siwe.ts` | SIWE message parsing and signature verification |

## Analytics

Uses Cloudflare Workers Analytics Engine for event tracking.

Event types:
- `request` - General request
- `auth_success` - Successful authentication
- `auth_failure` - Failed authentication
- `rate_limited` - Request blocked by rate limit
- `cache_hit` - Cache hit
- `cache_miss` - Cache miss
- `cache_bypass` - Cache bypassed (authenticated user)
- `cache_stale` - Stale cache served (origin failure)
- `error` - Error during request handling

Data points include:
- Event type (indexed for querying)
- Path, method, status
- Duration in milliseconds
- Cache status
- User address prefix (first 10 chars, privacy)
- Country, colo (Cloudflare data center)

## Logger

Structured logging with JSON output for Cloudflare log collection.

Features:
- Unique request ID per request (UUID)
- Request ID propagation (uses existing X-Request-ID if present)
- Auto-capture: client IP, path, method
- Duration tracking from request start
- User address tracking (set after auth)
- Log levels: debug, info, warn, error

Example log entry:
```json
{
  "level": "info",
  "message": "Cache hit",
  "timestamp": "2025-12-24T12:00:00.000Z",
  "context": {
    "requestId": "123e4567-e89b-12d3-a456-426614174000",
    "clientIP": "1.2.3.4",
    "path": "/owner/repo",
    "method": "GET",
    "userAddress": "0x1234...",
    "status": 200
  },
  "duration_ms": 42
}
```

## Public Routes

Defines routes accessible without authentication.

Route categories:
- Landing pages: `/`, `/about`, `/pricing`, `/docs`
- Auth endpoints: `/api/auth/*`
- Health checks: `/api/health`, `/api/ready`, `/metrics`
- Public repository views (regex patterns)

Edge-handled routes (not proxied to origin):
- `/api/auth/nonce` - Nonce generation
- `/api/auth/verify` - SIWE verification
- `/api/auth/logout` - Session termination

## Rate Limiting

Distributed rate limiting via Durable Objects.

Algorithm:
- Shard by IP prefix (first 2 octets): `shard:1.2`
- Key format: `{clientIP}:{endpoint}`
- Limit type determines window and max requests

Response includes headers:
- `X-RateLimit-Limit` - Max requests in window
- `X-RateLimit-Remaining` - Remaining requests
- `Retry-After` - Seconds until reset (if limited)

Limit tiers (requests/minute):
```
auth        ->  10/min  (nonce, verify, logout)
api:write   ->  60/min  (POST/PUT/DELETE to /api/)
api         -> 120/min  (GET to /api/)
default     -> 300/min  (page requests)
```

## Session Management

JWT-based sessions signed with HS256.

Session payload:
- `address` - User's Ethereum address (lowercase)
- `userId` - Optional user ID from origin database
- `username` - Optional username
- `isAdmin` - Optional admin flag
- `iat` - Issued at timestamp
- `exp` - Expiration timestamp

Session duration: 30 days

Cookie configuration:
- Name: `plue_session`
- HttpOnly (prevents XSS access)
- SameSite=Lax (CSRF protection)
- Secure (HTTPS only in production)
- Path=/

## SIWE Integration

Verifies Sign-In With Ethereum messages and signatures.

Verification steps:
1. Parse SIWE message from string
2. Validate message structure and fields
3. Check domain matches request (prevents cross-domain replay)
4. Verify signature against message hash
5. Recover signer address from signature
6. Return address and parsed message

Domain validation is critical for security - prevents an attacker from using a signature obtained on `attacker.com` to authenticate on `plue.dev`.
