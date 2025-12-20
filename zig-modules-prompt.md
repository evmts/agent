# Zig Native Modules Implementation Guide

<objective>
Implement three high-performance native Zig libraries that will be called from the Plue server via Bun FFI. These modules replace TypeScript implementations with native code for improved performance and reduced dependencies.
</objective>

<context>
Plue is a GitHub clone with an integrated AI agent system. The server runs on Bun with Hono framework. We've identified three components that benefit from native Zig implementation:

1. **SSH Server** - Git operations over SSH (currently uses `ssh2` npm package)
2. **JWT Library** - Token signing/verification (currently uses `jose` npm package)
3. **Rate Limiter** - Request rate limiting (currently in-memory TypeScript)

Existing Zig modules have been created in this codebase (all in `tools/`):
- `tools/webui/` - Native desktop window (uses zig-webui library)
- `tools/grep/` - Text search with glob matching
- `tools/pty/` - PTY session management
- `tools/jwt/` - JWT signing/verification (HS256)
- `tools/ratelimit/` - In-memory rate limiting
- `tools/ssh/` - SSH server for Git operations (libssh)

All modules follow the same pattern: Zig shared library with C-compatible exports, called via Bun FFI.
</context>

---

## Module 1: zig-ssh (SSH Server for Git Operations)

<requirements>
- Handle SSH connections for git clone/push/pull operations
- Public key authentication against database of user SSH keys
- Execute git-upload-pack and git-receive-pack for repository access
- Support concurrent connections (target: 100+ simultaneous)
</requirements>

<technical_spec>
```
Location: /tools/ssh/
Dependencies: libssh (via C interop)
Exports: C-compatible functions for Bun FFI

Key Functions:
- ssh_server_start(port: u16, host_key_path: [*:0]const u8) -> bool
- ssh_server_stop() -> void
- ssh_set_auth_callback(callback: *const fn) -> void
- ssh_get_connection_count() -> u32
```
</technical_spec>

<reference_implementation>
The current TypeScript implementation is at:
- `server/ssh/server.ts` - SSH server setup using ssh2
- `server/ssh/auth.ts` - Public key authentication
- `server/ssh/session.ts` - Git command execution

Key behavior to replicate:
```typescript
// From server/ssh/server.ts
const server = new Server({ hostKeys: [hostKey] }, (client) => {
  client.on('authentication', (ctx) => authenticate(ctx));
  client.on('ready', () => {
    client.on('session', (accept, reject) => handleSession(accept, reject, client));
  });
});
```
</reference_implementation>

<libssh2_guidance>
Search for "zig libssh2" examples. The library provides:
- `libssh2_session_init()` - Create session
- `libssh2_session_handshake()` - Perform SSH handshake
- `libssh2_userauth_publickey()` - Public key auth
- `libssh2_channel_open_session()` - Open channel
- `libssh2_channel_exec()` - Execute command

Zig can link libssh2 via:
```zig
const c = @cImport({
    @cInclude("libssh2.h");
});
```

In build.zig:
```zig
exe.linkSystemLibrary("ssh2");
exe.linkLibC();
```
</libssh2_guidance>

---

## Module 2: zig-jwt (JWT Sign/Verify)

<requirements>
- Sign JWTs with HS256 (HMAC-SHA256)
- Verify JWT signatures
- Parse and validate claims (exp, iat, etc.)
- Handle standard JWT structure: header.payload.signature
</requirements>

<technical_spec>
```
Location: /tools/jwt/
Dependencies: None (use Zig std crypto)
Exports: C-compatible functions for Bun FFI

Key Functions:
- jwt_init(secret: [*]const u8, secret_len: usize) -> bool
- jwt_sign(payload_json: [*:0]const u8) -> ?[*:0]const u8
- jwt_verify(token: [*:0]const u8) -> ?[*:0]const u8  // Returns payload or null
- jwt_free(ptr: [*]const u8) -> void
```
</technical_spec>

<reference_implementation>
The current TypeScript implementation is at `server/lib/jwt.ts`:

```typescript
import { SignJWT, jwtVerify } from 'jose';

export async function signJWT(payload): Promise<string> {
  const jwt = await new SignJWT(payload)
    .setProtectedHeader({ alg: 'HS256' })
    .setIssuedAt()
    .setExpirationTime('7d')
    .sign(getSecret());
  return jwt;
}

export async function verifyJWT(token: string): Promise<JWTPayload | null> {
  const { payload } = await jwtVerify(token, getSecret());
  return payload;
}
```

JWT Structure:
- Header: `{"alg":"HS256","typ":"JWT"}` (base64url encoded)
- Payload: `{"userId":1,"username":"foo","iat":...,"exp":...}` (base64url encoded)
- Signature: HMAC-SHA256(header.payload, secret) (base64url encoded)
</reference_implementation>

<crypto_guidance>
Zig std library provides everything needed:
```zig
const std = @import("std");
const HmacSha256 = std.crypto.auth.hmac.sha2.HmacSha256;

// Sign
var mac: [HmacSha256.mac_length]u8 = undefined;
HmacSha256.create(&mac, message, key);

// Base64URL encoding
const base64url = std.base64.url_safe_no_pad;
```
</crypto_guidance>

---

## Module 3: zig-ratelimit (In-Memory Rate Limiter)

<requirements>
- Token bucket or sliding window algorithm
- Per-key rate limiting (e.g., by IP or user ID)
- Configurable limits (requests per window)
- Automatic cleanup of expired entries
- Thread-safe for concurrent access
</requirements>

<technical_spec>
```
Location: /tools/ratelimit/
Dependencies: None
Exports: C-compatible functions for Bun FFI

Key Functions:
- ratelimit_init(max_requests: u32, window_ms: u64) -> bool
- ratelimit_check(key: [*:0]const u8) -> bool  // true = allowed, false = rate limited
- ratelimit_reset(key: [*:0]const u8) -> void
- ratelimit_cleanup() -> u32  // Returns number of expired entries removed
- ratelimit_get_remaining(key: [*:0]const u8) -> u32
```
</technical_spec>

<reference_implementation>
The current TypeScript implementation is at `server/middleware/rate-limit.ts`:

```typescript
const rateLimitStore = new Map<string, { count: number; resetAt: number }>();

export function checkRateLimit(key: string, limit: number, windowMs: number): boolean {
  const now = Date.now();
  const record = rateLimitStore.get(key);

  if (!record || now > record.resetAt) {
    rateLimitStore.set(key, { count: 1, resetAt: now + windowMs });
    return true;
  }

  if (record.count >= limit) {
    return false;
  }

  record.count++;
  return true;
}
```
</reference_implementation>

<algorithm_guidance>
Sliding window counter algorithm recommended:
```zig
const Entry = struct {
    count: u32,
    window_start: i64,
};

// Use std.StringHashMap for key->Entry mapping
// Use std.Thread.Mutex for thread safety
// Periodically cleanup entries older than window_ms
```
</algorithm_guidance>

---

## Build Structure

<project_structure>
Each module should follow this structure:
```
tools/{module}/
├── build.zig           # Build configuration
├── build.zig.zon       # Package manifest
├── src/
│   ├── lib.zig         # Library with C exports
│   └── main.zig        # Optional CLI for testing
└── README.md           # Usage documentation
```
</project_structure>

<build_template>
```zig
// build.zig template
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "plue_{module}",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/lib.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,  // If needed
        }),
    });

    b.installArtifact(lib);

    // Tests
    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/lib.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&b.addRunArtifact(tests).step);
}
```
</build_template>

---

## FFI Integration Pattern

<bun_ffi_example>
After building the Zig library, integrate with Bun like this:

```typescript
// Example: zig-jwt integration
import { dlopen, FFIType, ptr } from "bun:ffi";
import { join } from "path";

const libPath = join(import.meta.dirname, "tools/jwt/zig-out/lib/libplue_jwt.dylib");

const lib = dlopen(libPath, {
  jwt_init: {
    args: [FFIType.ptr, FFIType.u64],
    returns: FFIType.bool,
  },
  jwt_sign: {
    args: [FFIType.cstring],
    returns: FFIType.ptr,
  },
  jwt_verify: {
    args: [FFIType.cstring],
    returns: FFIType.ptr,
  },
  jwt_free: {
    args: [FFIType.ptr],
    returns: FFIType.void,
  },
});

export function signJWT(payload: object): string {
  const json = JSON.stringify(payload);
  const result = lib.symbols.jwt_sign(Buffer.from(json + "\0"));
  if (!result) throw new Error("JWT signing failed");
  // Convert result pointer to string...
}
```
</bun_ffi_example>

---

## Testing Requirements

<testing_checklist>
For each module, verify:

1. **Build succeeds**: `zig build` completes without errors
2. **Tests pass**: `zig build test` runs unit tests
3. **CLI works** (if provided): Manual testing via command line
4. **FFI integration**: Create a simple Bun script that calls the library
5. **Concurrency**: Test with multiple simultaneous operations

Performance targets:
- JWT: 100,000+ sign/verify operations per second
- Rate limiter: 1,000,000+ check operations per second
- SSH: Handle 100+ concurrent connections
</testing_checklist>

---

## Implementation Order

<priority>
1. **zig-jwt** (Simplest, no external deps, immediate value)
2. **zig-ratelimit** (No deps, useful for API protection)
3. **zig-ssh** (Most complex, requires libssh2)
</priority>

<success_criteria>
- All libraries compile on macOS (arm64) and Linux (x86_64)
- C-compatible exports work with Bun FFI
- Performance meets or exceeds TypeScript implementations
- Code includes comprehensive error handling
- Each module has at least basic unit tests
</success_criteria>

---

## Environment Notes

<environment>
- Zig version: 0.15.1
- Target platforms: macOS arm64, Linux x86_64
- Runtime: Bun (for FFI integration)
- Working directory: /Users/williamcory/agent/
</environment>

<existing_code_reference>
Reference these existing Zig modules for patterns:
- `tools/grep/src/lib.zig` - Example of search with C exports
- `tools/pty/src/lib.zig` - Example of system calls with C exports
- `tools/webui/src/main.zig` - Example of external library integration
- `tools/jwt/src/lib.zig` - Example of crypto with C exports
- `tools/ratelimit/src/lib.zig` - Example of thread-safe data structures
- `tools/ssh/src/lib.zig` - Example of libssh integration
</existing_code_reference>
