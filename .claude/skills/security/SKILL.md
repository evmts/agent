---
name: security
description: Plue security architecture including SIWE authentication, sandboxing, and origin protection. Use when working on auth, permissions, or security-related features.
---

# Plue Security

## Authentication: SIWE (Sign-In With Ethereum)

Plue uses wallet-based authentication via EIP-4361 (SIWE).

### Auth Flow

```
1. Client requests nonce: GET /api/auth/nonce
2. Server generates nonce, stores with 5min TTL
3. Client creates SIWE message with nonce
4. User signs message with wallet (MetaMask, etc.)
5. Client submits: POST /api/auth/verify { message, signature }
6. Server verifies signature, validates nonce (one-time use)
7. Server creates session, sets HttpOnly cookie
```

### Server Implementation

```zig
// server/routes/auth.zig
// server/lib/siwe.zig (SIWE message parsing/verification)

// Nonce stored in database with TTL
// siwe_nonces table: nonce, wallet_address, expires_at, used_at

// Session stored in auth_sessions table
// session_key -> user_id, expires_at
```

### Key Files

| File | Purpose |
|------|---------|
| `server/routes/auth.zig` | Auth endpoints |
| `server/lib/siwe.zig` | SIWE verification |
| `server/middleware/auth.zig` | Auth middleware |
| `db/schema.sql` | `siwe_nonces`, `auth_sessions` tables |

## Authorization

### Middleware

```zig
// server/middleware/auth.zig
pub fn withAuth(handler: Handler) Handler
pub fn withAuthAndCsrf(handler: Handler) Handler
pub fn withRateLimit(preset: Preset, key: []const u8, handler: Handler) Handler
```

### Scopes (API Tokens)

```sql
-- access_tokens table
-- token_hash, user_id, scopes (JSONB), expires_at
-- Scopes: repo:read, repo:write, issue:read, issue:write, etc.
```

## CSRF Protection

Double-submit cookie pattern:

```zig
// server/middleware/csrf.zig
// 1. Generate token, store in session
// 2. Client includes X-CSRF-Token header
// 3. Server validates token matches session
```

## Rate Limiting

```zig
// server/middleware/rate_limit.zig
pub const presets = .{
    .login = .{ .requests = 10, .window_ms = 60_000 },     // 10/min
    .api = .{ .requests = 100, .window_ms = 60_000 },      // 100/min
    .api_write = .{ .requests = 30, .window_ms = 60_000 }, // 30/min
};
```

## Sandboxed Execution (gVisor)

Agent and workflow code runs in sandboxed Kubernetes pods.

### Defense in Depth

1. **Node Isolation** - gVisor node pool separate from API nodes
2. **gVisor Runtime** - Userspace kernel intercepts all syscalls
3. **Pod Security Context** - Non-root, read-only filesystem, no capabilities
4. **Network Policy** - Only reach Anthropic API + callback URL
5. **Resource Limits** - CPU, memory, disk, runtime limits

### Configuration

```yaml
# Pod spec for runner
spec:
  runtimeClassName: gvisor
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    readOnlyRootFilesystem: true
    allowPrivilegeEscalation: false
    capabilities:
      drop: ["ALL"]
  resources:
    limits:
      cpu: "2"
      memory: "4Gi"
```

### Network Policy

```yaml
# Only allow:
# - DNS (kube-dns)
# - api.anthropic.com:443
# - API callback URL
# Block everything else including cloud metadata
```

## SSH Authentication

Git over SSH uses public key authentication:

```zig
// server/ssh/server.zig
// 1. Client connects with SSH key
// 2. Server looks up key fingerprint in ssh_keys table
// 3. If found, authenticate user
// 4. Execute git-receive-pack or git-upload-pack
```

```sql
-- ssh_keys table
-- user_id, fingerprint, public_key, title, created_at
```

## Origin Protection (Planned)

mTLS between Cloudflare and origin:

1. **Custom CA** - Generate private CA for Plue
2. **Client Certificate** - Cloudflare uses client cert signed by our CA
3. **Origin Verification** - Origin only accepts connections with valid client cert

See `docs/infrastructure.md` for implementation details.

## Security Headers

```zig
// Response headers set by middleware
Content-Security-Policy: default-src 'self'
X-Content-Type-Options: nosniff
X-Frame-Options: DENY
X-XSS-Protection: 1; mode=block
Strict-Transport-Security: max-age=31536000; includeSubDomains
```

## Secrets Management

```bash
# Local development
.env file (gitignored)

# Production
Kubernetes Secrets
Google Secret Manager (via External Secrets Operator)
```
