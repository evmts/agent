# Middleware

HTTP middleware for the Zig server, inspired by the Bun/Hono implementation.

## Architecture

The middleware system provides a layered approach to request/response handling:

1. **Logger** - Request logging with unique IDs
2. **Security** - Security headers (HSTS, CSP, X-Frame-Options, etc.)
3. **CORS** - Cross-Origin Resource Sharing with configurable origins
4. **Body Limit** - Request body size limits (default 10MB)
5. **Auth** - Session-based authentication
6. **Rate Limit** - Request rate limiting per IP

## Files

### Core Middleware

- **cors.zig** - CORS headers and preflight OPTIONS handling
  - Configurable allowed origins, methods, headers
  - Automatic localhost allowance in development
  - Preflight request support
  - Exposed headers for ElectricSQL

- **security.zig** - Security HTTP headers
  - X-Content-Type-Options: nosniff
  - X-Frame-Options: DENY
  - X-XSS-Protection: 1; mode=block
  - Strict-Transport-Security (production only)
  - Content-Security-Policy
  - Referrer-Policy: strict-origin-when-cross-origin

- **body_limit.zig** - Request body size limits
  - Default 10MB limit
  - Configurable per-route limits
  - Returns 413 Payload Too Large if exceeded
  - Human-readable error messages

- **logger.zig** - HTTP request logging
  - Generates unique request IDs
  - Logs method, path, and timing
  - Format: `[REQUEST_ID] METHOD /path`

- **auth.zig** - Session-based authentication (existing)
  - Loads user from session cookie
  - Sets context variables
  - Optional enforcement (requireAuth, requireAdmin, etc.)

- **rate_limit.zig** - Request rate limiting (existing)
  - In-memory rate limiter
  - Configurable limits and time windows
  - Presets for auth, API, email
  - IP-based tracking

### Module Exports

- **mod.zig** - Re-exports all middleware for easy importing

## Usage

### In main.zig

```zig
const middleware = @import("middleware/mod.zig");

// Initialize rate limiters
var api_rate_limiter = middleware.RateLimiter.init(allocator, middleware.rate_limit_presets.api);
defer api_rate_limiter.deinit();

// Add to context
var ctx = Context{
    .allocator = allocator,
    .pool = pool,
    .config = cfg,
    .api_rate_limiter = &api_rate_limiter,
    // ...
};
```

### Applying Middleware

Due to httpz's architecture, middleware needs to be applied per-route or through wrapper functions. The intended order is:

1. Logger (first - logs all requests)
2. Security headers
3. CORS
4. Body limit
5. Auth
6. Rate limit (last - after auth to use user-specific limits)

### Example: Route with Middleware

```zig
// Apply middleware chain to a route
fn protectedRoute(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    // Logger
    try middleware.loggerMiddleware(ctx, req, res);

    // Security headers
    if (!try middleware.securityMiddleware(middleware.security_default)(ctx, req, res)) return;

    // CORS
    if (!try middleware.corsMiddleware(middleware.cors_default)(ctx, req, res)) return;

    // Body limit
    if (!try middleware.bodyLimitMiddleware(middleware.body_limit_default)(ctx, req, res)) return;

    // Auth
    if (!try middleware.authMiddleware(ctx, req, res)) return;
    if (!try middleware.requireAuth(ctx, req, res)) return;

    // Your handler logic here
    res.content_type = .JSON;
    try res.writer().writeAll("{\"success\":true}");
}
```

## Configuration

### CORS

```zig
const cors_config = middleware.CorsConfig{
    .allowed_origins = &.{"https://example.com"},
    .allowed_methods = &.{"GET", "POST", "PUT", "DELETE"},
    .allowed_headers = &.{"Content-Type", "Authorization"},
    .max_age = 600,
    .credentials = true,
};
```

### Security

```zig
const security_config = middleware.SecurityConfig{
    .x_frame_options = "DENY",
    .hsts_enabled = true,
    .hsts_max_age = 31536000,
    .csp_enabled = true,
    // ... see security.zig for all options
};
```

### Body Limit

```zig
const body_limit_config = middleware.BodyLimitConfig{
    .max_size = 50 * 1024 * 1024, // 50MB
};
```

### Rate Limit

```zig
const rate_limit_config = middleware.RateLimitConfig{
    .max_requests = 100,
    .window_ms = 15 * 60 * 1000, // 15 minutes
};

var limiter = middleware.RateLimiter.init(allocator, rate_limit_config);
defer limiter.deinit();
```

## Testing

Each middleware file includes unit tests. Run with:

```bash
zig build test
```

## Implementation Notes

### httpz Middleware Architecture

Unlike Hono (which has built-in middleware chaining), httpz requires manual middleware application. There are several approaches:

1. **Per-Route Wrapper** - Wrap each route handler with middleware
2. **Router Groups** - Apply middleware to route groups
3. **Handler Chain** - Create a middleware chain helper

The current implementation documents the intended middleware order and provides individual middleware functions that can be composed.

### Future Improvements

- [ ] Implement middleware chain helper for automatic composition
- [ ] Add response timing to logger
- [ ] Add Redis-backed rate limiter for multi-server deployments
- [ ] Add request ID propagation through context
- [ ] Add middleware performance metrics
- [ ] Add conditional middleware (e.g., CORS only for API routes)

## References

- Bun implementation: `/Users/williamcory/agent/server/middleware/`
- Hono middleware: Uses higher-order functions and middleware chain
- httpz docs: Check for updates to middleware support
