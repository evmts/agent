# SSH Git Server

SSH server implementation for Git-over-SSH protocol. Provides authenticated Git push/pull operations with public key authentication and session management.

## Key Files

| File | Purpose |
|------|---------|
| `server.zig` | Main SSH server implementation |
| `session.zig` | SSH session management and lifecycle |
| `types.zig` | SSH protocol types and structures |
| `auth.zig` | Public key authentication and user lookup |
| `health.zig` | Server health checks and monitoring |
| `rate_limit.zig` | Connection rate limiting |
| `connection_limit.zig` | Concurrent connection limits |
| `security_log.zig` | Security event logging |
| `proxy_protocol.zig` | PROXY protocol v2 support for load balancers |

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    SSH Git Server                           │
│                                                             │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐  │
│  │    Server    │───▶│   Session    │───▶│     Auth     │  │
│  │              │    │              │    │              │  │
│  │ • TCP :22    │    │ • Lifecycle  │    │ • PublicKey  │  │
│  │ • TLS (opt)  │    │ • Command    │    │ • DB lookup  │  │
│  │ • Health     │    │   execution  │    │ • User map   │  │
│  └──────────────┘    └──────────────┘    └──────────────┘  │
│                                                             │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐  │
│  │ Rate Limit   │    │ Conn Limit   │    │Security Log  │  │
│  │              │    │              │    │              │  │
│  │ • Per-IP     │    │ • Max conns  │    │ • Auth fails │  │
│  │ • Token      │    │ • Per-user   │    │ • Anomalies  │  │
│  │   bucket     │    │   limits     │    │ • Audit log  │  │
│  └──────────────┘    └──────────────┘    └──────────────┘  │
│                                                             │
│  ┌───────────────────────────────────────────────────────┐ │
│  │              PROXY Protocol v2                        │ │
│  │                                                       │ │
│  │  • Original client IP preservation                   │ │
│  │  • Load balancer support                             │ │
│  └───────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
                   jj-lib (Rust FFI)
                   Git Operations
```

## Connection Flow

```
Git Client
    │
    │ SSH handshake
    ▼
┌──────────────────┐
│  PROXY Protocol  │  Extract real client IP (if behind LB)
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│   Rate Limit     │  Check connection rate
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  Connection Limit│  Check concurrent connections
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  Authentication  │  Verify SSH public key
│                  │  - Query database for user's keys
│                  │  - Match key fingerprint
│                  │  - Return user ID
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  Session Create  │  Initialize SSH session
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  Git Command     │  Execute git-receive-pack or git-upload-pack
│                  │  - Validate repository access
│                  │  - Stream Git protocol
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  Security Log    │  Log operation and close session
└──────────────────┘
```

## Security Features

| Feature | Implementation |
|---------|----------------|
| Public key auth | Database-backed key lookup |
| Rate limiting | Token bucket per IP |
| Connection limits | Max concurrent per user/global |
| Security logging | All auth attempts logged |
| PROXY protocol | Preserve client IP through LB |
| Health checks | Liveness and readiness endpoints |

## Git Operations

| Command | Description |
|---------|-------------|
| `git-upload-pack` | Clone, fetch, pull operations |
| `git-receive-pack` | Push operations |

Both commands:
- Validate repository access permissions
- Stream Git pack protocol
- Update refs on successful push
- Trigger webhooks/workflows on push
