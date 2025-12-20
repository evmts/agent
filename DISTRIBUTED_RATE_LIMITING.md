# Distributed Rate Limiting Implementation

## Overview
Implemented distributed rate limiting using PostgreSQL to share rate limits across all server instances behind a load balancer.

## Changes Made

### 1. Database Schema (`db/schema.sql`)
Added new `rate_limits` table:
```sql
CREATE TABLE IF NOT EXISTS rate_limits (
  key VARCHAR(255) PRIMARY KEY,
  count INTEGER NOT NULL DEFAULT 0,
  window_start TIMESTAMP NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMP NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_rate_limits_expires ON rate_limits(expires_at);
```

### 2. Database Operations (`server/src/lib/db.zig`)
Added three new functions:

- `checkRateLimit()`: Atomically checks and increments rate limit counter using `INSERT ... ON CONFLICT`
- `getRateLimitState()`: Gets current rate limit state without incrementing
- `cleanupExpiredRateLimits()`: Removes expired rate limit entries

### 3. Rate Limit Middleware (`server/src/middleware/rate_limit.zig`)
Completely rewrote the middleware to use PostgreSQL instead of in-memory storage:

**New Presets**:
- `login`: 5 requests per minute (60 seconds)
- `register`: 3 requests per minute (60 seconds)
- `password_reset`: 3 requests per hour (3600 seconds)
- `auth`: 10 requests per minute (60 seconds)
- `api`: 100 requests per 15 minutes (900 seconds)
- `email`: 3 requests per hour (3600 seconds)

**Rate Limit Headers**:
All responses now include:
- `X-RateLimit-Limit`: Maximum number of requests allowed
- `X-RateLimit-Remaining`: Number of requests remaining
- `X-RateLimit-Reset`: Unix timestamp when the limit resets
- `Retry-After`: Seconds until limit resets (only on 429 responses)

### 4. Server Context (`server/src/main.zig`)
- Removed in-memory rate limiters from Context struct
- Rate limiters are now created per-request with access to the database pool

### 5. Cleanup Service (`server/src/services/session_cleanup.zig`)
Added cleanup of expired rate limits to the existing session cleanup service.

### 6. Route Helpers (`server/src/routes.zig`)
Added two new helper functions for applying rate limits to routes:

```zig
// Rate limit only
fn withRateLimit(handler, config, key_prefix)

// Rate limit + auth + CSRF
fn withRateLimitAuthAndCsrf(handler, config, key_prefix)
```

## Usage Examples

### Applying Rate Limits to Auth Endpoints

```zig
// Login endpoint - 5 requests per minute
router.post("/api/auth/siwe/verify",
    withRateLimitAuthAndCsrf(
        auth_routes.verify,
        middleware.rate_limit_presets.login,
        "auth:verify"
    ),
    .{}
);

// Register endpoint - 3 requests per minute
router.post("/api/auth/siwe/register",
    withRateLimitAuthAndCsrf(
        auth_routes.register,
        middleware.rate_limit_presets.register,
        "auth:register"
    ),
    .{}
);

// Password reset - 3 requests per hour
router.post("/api/auth/password/reset-request",
    withRateLimit(
        auth_routes.requestPasswordReset,
        middleware.rate_limit_presets.password_reset,
        "auth:password-reset"
    ),
    .{}
);
```

### Custom Rate Limit Configuration

```zig
const custom_config = middleware.RateLimitConfig{
    .max_requests = 10,
    .window_seconds = 300, // 5 minutes
    .skip_on_success = false,
};

router.post("/api/custom",
    withRateLimit(handler, custom_config, "custom"),
    .{}
);
```

## Implementation Details

### Atomic Operations
The `checkRateLimit` function uses PostgreSQL's `INSERT ... ON CONFLICT` to atomically:
1. Create a new rate limit entry if one doesn't exist
2. Reset the counter if the window has expired
3. Increment the counter if the window is still active
4. Return the current count and reset time

This ensures correctness even with concurrent requests across multiple server instances.

### Window Management
- Windows are based on `expires_at` timestamp
- When a window expires, the counter resets to 1 (the current request)
- The `window_start` timestamp tracks when the current window began

### Key Format
Rate limit keys use the format: `{prefix}:{ip_address}`
- Prefix identifies the endpoint (e.g., "auth:login", "api:general")
- IP address is extracted from `X-Forwarded-For` or `X-Real-IP` headers
- Falls back to "unknown" if no IP headers are present

### Error Handling
- If database operations fail, the middleware "fails open" (allows the request)
- Errors are logged for monitoring
- This prevents database issues from taking down the entire service

### Cleanup
- Expired rate limit entries are automatically cleaned up every 5 minutes
- Cleanup runs in the existing session cleanup background service
- This prevents the table from growing unbounded

## Benefits

1. **Distributed**: Rate limits are shared across all server instances
2. **Persistent**: Rate limits survive server restarts
3. **Accurate**: Atomic operations ensure accurate counting
4. **Scalable**: PostgreSQL handles concurrent access efficiently
5. **Observable**: Rate limit headers provide visibility to clients
6. **Fail-safe**: Errors fail open to prevent service disruption

## Security

### Stricter Limits for Auth Endpoints
- `/api/auth/siwe/verify` (login): 5 per minute
- `/api/auth/siwe/register`: 3 per minute
- `/api/auth/password/reset`: 3 per hour

These limits prevent brute force attacks while allowing legitimate use.

### Rate Limit Headers
All responses include rate limit information:
- Clients can see their remaining quota
- Clients can see when their limit resets
- 429 responses include `Retry-After` header

## Testing

The implementation includes unit tests for:
- Configuration defaults
- Preset values
- Rate limit logic (requires integration tests with database)

## Future Enhancements

1. **Redis Backend**: For even better performance, could use Redis instead of PostgreSQL
2. **User-based Limits**: Rate limit by user ID instead of IP for authenticated requests
3. **Dynamic Limits**: Adjust limits based on user tier or subscription level
4. **Burst Limits**: Allow bursts followed by sustained rate limits
5. **Global Limits**: Add per-endpoint global limits across all IPs

## Migration

To apply these changes:

1. Run database migration to create `rate_limits` table:
```bash
psql $DATABASE_URL < db/schema.sql
```

2. Restart server instances to pick up new code

3. Monitor logs for rate limit activity:
```bash
tail -f logs/server.log | grep rate_limit
```

4. Update routes to use new rate limit wrappers (optional, existing code works)

## Notes

- The implementation is backward compatible - routes without rate limiting continue to work
- Rate limits can be added incrementally to endpoints as needed
- The cleanup service runs automatically, no manual maintenance required
- Rate limit keys include endpoint prefix to allow different limits per endpoint
