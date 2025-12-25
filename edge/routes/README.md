# Edge Routes

Route handlers for requests processed at the edge (not proxied to origin).

## Routes

| Route | Method | File | Purpose |
|-------|--------|------|---------|
| `/api/auth/nonce` | GET | `auth.ts` | Generate SIWE nonce |
| `/api/auth/verify` | POST | `auth.ts` | Verify SIWE signature, create session |
| `/api/auth/logout` | POST | `auth.ts` | Clear session cookie |
| `/metrics` | GET | `metrics.ts` | Prometheus metrics endpoint |

## Authentication Routes (auth.ts)

Implements SIWE authentication entirely at the edge using Durable Objects for strong consistency.

### GET /api/auth/nonce

Generate a cryptographically random nonce for SIWE message signing.

Flow:
1. Generate 32-byte random nonce (hex-encoded)
2. Store in AUTH_DO with timestamp
3. Return nonce to client

Response:
```json
{
  "nonce": "0123456789abcdef..."
}
```

### POST /api/auth/verify

Verify SIWE signature and create authenticated session.

Request:
```json
{
  "message": "plue.dev wants you to sign in...",
  "signature": "0x..."
}
```

Flow:
1. Parse and validate SIWE message
2. Verify domain matches request (prevents cross-domain replay)
3. Verify signature against message hash
4. Consume nonce atomically from AUTH_DO (replay protection)
5. Create JWT session token
6. Store session in user's AUTH_DO instance
7. Set HttpOnly session cookie
8. Return success

Response:
```json
{
  "message": "Authentication successful",
  "address": "0x1234..."
}
```

Headers:
```
Set-Cookie: plue_session=<jwt>; Path=/; HttpOnly; SameSite=Lax; Max-Age=2592000
```

Security guarantees:
- Nonce can only be used once (atomic DELETE from Durable Object)
- Domain validation prevents cross-domain replay attacks
- JWT signed with HS256, expires in 30 days
- HttpOnly cookie prevents XSS token theft

### POST /api/auth/logout

Clear session cookie and invalidate session.

Flow:
1. Extract JWT from cookie
2. Verify and decode JWT
3. Mark session as logged out in user's AUTH_DO
4. Clear session cookie

Response:
```json
{
  "message": "Logout successful"
}
```

Headers:
```
Set-Cookie: plue_session=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0
```

Note: Logout is best-effort. The session is invalidated in the Durable Object, but if that fails, the cookie is still cleared (primary security action).

### Helper: getAuthenticatedUser()

Extract and verify user session from request.

Used by main worker to:
1. Bypass cache for authenticated users
2. Add X-Plue-User-Address header for origin
3. Enforce authentication on protected routes

Returns `{ address: string } | null`

## Metrics Route (metrics.ts)

Prometheus-compatible metrics endpoint protected by optional authentication.

### GET /metrics

Returns metrics in Prometheus text exposition format.

Authentication (optional):
- `METRICS_API_KEY` - Requires `Authorization: Bearer <token>` header
- `METRICS_ALLOWED_IPS` - Requires client IP in CIDR allowlist

Metrics exposed:

Counter metrics:
- `plue_edge_requests_total` - Total requests
- `plue_edge_requests_by_status{status}` - Requests by HTTP status
- `plue_edge_auth_success_total` - Successful authentications
- `plue_edge_auth_failure_total` - Failed authentications
- `plue_edge_rate_limited_total` - Rate limited requests
- `plue_edge_cache_hits_total` - Cache hits
- `plue_edge_cache_misses_total` - Cache misses
- `plue_edge_cache_bypasses_total` - Cache bypasses (authenticated)
- `plue_edge_cache_stales_total` - Stale cache serves (origin failure)
- `plue_edge_errors_total` - Total errors

Histogram metrics:
- `plue_edge_request_duration_ms` - Request duration distribution
  - Buckets: 5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000 ms
  - Includes `_sum`, `_count`, `_bucket{le}` series

Computed gauge metrics:
- `plue_edge_cache_hit_rate` - Cache hit ratio (0-1)
- `plue_edge_auth_success_rate` - Auth success ratio (0-1)
- `plue_edge_request_duration_avg_ms` - Average request duration

Example output:
```
# HELP plue_edge_requests_total Total number of requests
# TYPE plue_edge_requests_total counter
plue_edge_requests_total 12345

# HELP plue_edge_cache_hit_rate Cache hit rate (0-1)
# TYPE plue_edge_cache_hit_rate gauge
plue_edge_cache_hit_rate 0.8532
```

Data source: METRICS_DO Durable Object aggregates metrics from all edge instances globally.
