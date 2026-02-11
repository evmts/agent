# HTTP Server Health Endpoint

Implemented a minimal Zap-backed HTTP server in `src/http_server.zig`.

- Binds to `127.0.0.1` only (localhost trust model)
- Single endpoint: `GET /api/health` → `{"status":"ok"}` (JSON)
- CORS: allows only localhost origins; responds to `OPTIONS` with 204
- Lifecycle: `Server.create(alloc, cfg)` → `start()` (non-blocking, background thread) → `stop()` → `destroy()`

Tests are colocated at the bottom of `src/http_server.zig` and cover lifecycle, health response, 404s, and CORS headers.

Run:

```
zig build test
```



## Security Posture

- Origin parsing uses strict URI parsing with exact host validation.
- Accepted schemes: http and https only.
- Accepted hosts: localhost, 127.0.0.1, ::1 (IPv6; bracketed forms like [::1] are normalized).
- No wildcard subdomains; e.g., http://localhost.attacker.com is rejected.
- When the Origin header is absent, Access-Control-Allow-Origin is not set.
