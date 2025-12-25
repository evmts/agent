# Core Libraries

Shared utilities and libraries used across the Zig server. Includes JSON handling, JWT authentication, metrics collection, and SIWE authentication.

## Key Files

| File | Purpose |
|------|---------|
| `json.zig` | JSON parsing, stringification, and manipulation utilities |
| `jwt.zig` | JWT token generation and validation for API authentication |
| `metrics.zig` | Prometheus metrics collection and export |
| `siwe.zig` | Sign-In With Ethereum (EIP-4361) implementation |

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Core Libraries                           │
│                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │    JSON     │  │     JWT     │  │      Metrics        │ │
│  │             │  │             │  │                     │ │
│  │ • Parse     │  │ • Generate  │  │ • Counters          │ │
│  │ • Stringify │  │ • Validate  │  │ • Gauges            │ │
│  │ • Manipulate│  │ • HMAC-256  │  │ • Histograms        │ │
│  └─────────────┘  └─────────────┘  │ • Prometheus export │ │
│                                    └─────────────────────┘ │
│                                                             │
│  ┌───────────────────────────────────────────────────────┐ │
│  │                    SIWE (EIP-4361)                    │ │
│  │                                                       │ │
│  │  • Message construction                              │ │
│  │  • Signature verification (via crypto/secp256k1)     │ │
│  │  • Nonce management                                  │ │
│  │  • Session creation                                  │ │
│  └───────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

## JSON Utilities

Provides type-safe JSON operations:

```zig
const lib = @import("lib/json.zig");

// Parse JSON string
const parsed = try lib.parseJson(allocator, json_string);

// Stringify with proper escaping
const json_str = try lib.stringifyJson(allocator, value);
```

## JWT Authentication

Token-based API authentication:

```zig
const jwt = @import("lib/jwt.zig");

// Generate token
const token = try jwt.generate(allocator, .{
    .user_id = user_id,
    .exp = expiry_timestamp,
}, secret_key);

// Validate token
const claims = try jwt.validate(allocator, token, secret_key);
```

## Metrics Collection

Prometheus-compatible metrics:

```zig
const metrics = @import("lib/metrics.zig");

// Increment counter
metrics.http_requests_total.inc(.{ .method = "GET", .status = "200" });

// Observe histogram
metrics.request_duration_seconds.observe(duration, .{ .route = "/api/repos" });
```

## SIWE Authentication

Sign-In With Ethereum implementation:

```zig
const siwe = @import("lib/siwe.zig");

// Verify SIWE message and signature
const address = try siwe.verify(allocator, .{
    .message = siwe_message,
    .signature = signature,
    .nonce = expected_nonce,
});
```
