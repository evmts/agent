# Production-Grade SSH Server Implementation

## Overview

Implement a production-ready SSH server in Zig that handles git operations over SSH protocol. The server must authenticate users via public keys stored in the database, extract git commands from SSH sessions, and provide enterprise-grade reliability with graceful shutdown, security hardening, and comprehensive monitoring.

**IMPORTANT**: Based on research, implementing SSH protocol in pure Zig would be a multi-month effort. This implementation will use libssh2 (C library) for SSH protocol handling while keeping all server logic in pure Zig.

## Core Requirements

### 1. SSH Server Core

Create a configurable SSH server that can:
- Listen on configurable host and port
- Support configurable SSH ciphers, key exchanges, and MACs
- Generate and manage SSH host keys (RSA 4096-bit)
- Handle graceful shutdown with connection draining
- Implement per-connection and per-write timeouts for DoS protection
- Support proxy protocol for load balancer integration
- Enforce username validation (must match configured git user)

### 2. Public Key Authentication

Implement secure authentication:
- Authenticate users based on public key fingerprints from database
- Support SSH certificate authentication with trusted CAs
- Support deploy keys with repository-specific access
- Validate SSH username matches configured git user
- Log all authentication attempts for security monitoring
- Enforce minimum key size validation by algorithm type
- Calculate SSH SHA256 fingerprints for key matching
- Handle principal-based authentication for certificates

### 3. Session & Command Handling

Handle SSH sessions properly:
- Extract `SSH_ORIGINAL_COMMAND` from session environment
- Parse and validate git commands with strict security checks
- Support git commands: `git-receive-pack`, `git-upload-pack`, `git-upload-archive`
- Support LFS commands: `git-lfs-authenticate`, `git-lfs-transfer`
- Support AGit flow: `ssh_info` command
- Validate repository path format (owner/repo)
- Set up environment variables (`GIT_PROTOCOL`)
- Handle session I/O streams (stdin, stdout, stderr)
- Clean session termination with proper exit codes

### 4. Security Hardening

Implement enterprise-grade security:
- **Rate Limiting**: Prevent SSH brute force attacks with per-IP tracking
- **Connection Limits**: Enforce maximum concurrent connections
- **Timeout Management**: Connection and authentication timeouts
- **Input Validation**: Validate all SSH protocol inputs and git commands
- **Audit Logging**: Log all connection attempts and security events
- **Cipher Security**: Enforce strong ciphers and disable weak algorithms

### 5. Graceful Shutdown & Resource Management

Production-ready lifecycle management:
- Handle shutdown signals (SIGINT, SIGTERM) with connection draining
- Track active connections for graceful shutdown
- Enforce memory and file descriptor limits
- Clean up all resources on shutdown
- Support configurable drain timeout

## File Structure

```
src/ssh/
├── server.zig          // Main SSH server implementation
├── auth.zig            // Public key authentication
├── session.zig         // SSH session handling
├── command.zig         // Command extraction and validation
├── security.zig        // Rate limiting and security
├── host_key.zig        // Host key management
├── shutdown.zig        // Graceful shutdown handling
└── bindings.zig        // libssh2 C bindings and wrappers
```

## Implementation Guidelines

### CRITICAL: NO MOCKING ALLOWED

**ABSOLUTE PROHIBITION ON MOCKING**: Under NO circumstances are you allowed to create mock implementations, stub functions, or fake bindings. This includes but is not limited to:

- ❌ **NO MOCK C BINDINGS** - Do not create fake libssh2 bindings or struct definitions
- ❌ **NO STUB IMPLEMENTATIONS** - Do not create placeholder functions that pretend to work
- ❌ **NO FAKE DATA** - Do not hardcode test data or return dummy values
- ❌ **NO SKIPPING TESTS** - Do not use `error.SkipZigTest` to bypass failing tests
- ❌ **NO FACADE IMPLEMENTATIONS** - Do not create code that looks complete but doesn't actually work

**MANDATORY REQUIREMENTS**:
1. **STOP IMMEDIATELY** if libssh2 is not available or cannot be linked
2. **ASK FOR HELP** before attempting any workaround or alternative approach
3. **ONLY IMPLEMENT** with real, working libssh2 integration
4. **TEST WITH REAL SSH** - All tests must use actual SSH protocol, not mocks

**IF YOU CANNOT LINK LIBSSH2**: 
- STOP and report the issue
- DO NOT proceed with implementation
- DO NOT create mock bindings
- DO NOT pretend the implementation works

Creating mock implementations wastes time and creates technical debt. It is better to have no implementation than a fake one.

## C Library Integration (libssh2)

### Adding as Git Submodule

Add zig-libssh2 as a submodule to your project:

```bash
git submodule add https://github.com/mattnite/zig-libssh2.git deps/zig-libssh2
git submodule update --init --recursive
```

### Build Configuration

Add libssh2 to your project's build.zig:

```zig
const std = @import("std");
const libssh2 = @import("deps/zig-libssh2/libssh2.zig");
const mbedtls = @import("deps/zig-libssh2/deps.zig").build_pkgs.mbedtls;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    
    // Build mbedTLS (required by libssh2)
    const tls = mbedtls.create(b, target, optimize);
    
    // Create libssh2 static library
    const ssh2 = libssh2.create(b, target, optimize);
    tls.link(ssh2.step);
    
    // Your SSH server executable
    const exe = b.addExecutable(.{
        .name = "plue-ssh-server",
        .root_source_file = .{ .path = "src/ssh/server.zig" },
        .target = target,
        .optimize = optimize,
    });
    
    // Link libssh2 to your executable
    ssh2.link(exe);
    
    // Link system libraries
    exe.linkLibC();
    if (target.isWindows()) {
        exe.linkSystemLibrary("ws2_32");
        exe.linkSystemLibrary("crypt32");
    }
    
    b.installArtifact(exe);
}
```

### C Bindings Pattern

Create a bindings.zig file to wrap libssh2:

```zig
const std = @import("std");

pub const c = @cImport({
    @cInclude("libssh2.h");
    @cInclude("libssh2_sftp.h");
});

// Error handling wrapper
pub fn checkError(rc: c_int) !void {
    if (rc < 0) return switch (rc) {
        c.LIBSSH2_ERROR_SOCKET_DISCONNECT => error.SocketDisconnected,
        c.LIBSSH2_ERROR_TIMEOUT => error.Timeout,
        c.LIBSSH2_ERROR_HOSTKEY_INIT => error.HostKeyInit,
        c.LIBSSH2_ERROR_HOSTKEY_SIGN => error.HostKeySign,
        c.LIBSSH2_ERROR_DECRYPT => error.Decrypt,
        c.LIBSSH2_ERROR_PUBLICKEY_UNVERIFIED => error.PublicKeyUnverified,
        c.LIBSSH2_ERROR_AUTHENTICATION_FAILED => error.AuthenticationFailed,
        else => error.LibSSH2Error,
    };
}

// Session wrapper for RAII pattern
pub const Session = struct {
    handle: *c.LIBSSH2_SESSION,
    
    pub fn init() !Session {
        const handle = c.libssh2_session_init() orelse return error.SessionInitFailed;
        return Session{ .handle = handle };
    }
    
    pub fn deinit(self: *Session) void {
        _ = c.libssh2_session_free(self.handle);
    }
    
    pub fn handshake(self: *Session, socket: std.os.socket_t) !void {
        try checkError(c.libssh2_session_handshake(self.handle, socket));
    }
    
    pub fn setBlocking(self: *Session, blocking: bool) void {
        c.libssh2_session_set_blocking(self.handle, if (blocking) 1 else 0);
    }
};
```

### Memory Management Between Zig and C

1. **libssh2 allocation callbacks**: Set custom allocators to use Zig's allocator:

```zig
fn sshAlloc(count: usize, abstract: ?*anyopaque) callconv(.C) ?*anyopaque {
    const allocator = @ptrCast(*std.mem.Allocator, @alignCast(@alignOf(std.mem.Allocator), abstract.?));
    const mem = allocator.alloc(u8, count) catch return null;
    return mem.ptr;
}

fn sshFree(ptr: ?*anyopaque, abstract: ?*anyopaque) callconv(.C) void {
    if (ptr == null) return;
    const allocator = @ptrCast(*std.mem.Allocator, @alignCast(@alignOf(std.mem.Allocator), abstract.?));
    // Calculate original slice from ptr and count (stored separately)
    allocator.free(mem_slice);
}

fn sshRealloc(ptr: ?*anyopaque, count: usize, abstract: ?*anyopaque) callconv(.C) ?*anyopaque {
    // Implementation similar to above
}

// Initialize libssh2 with custom allocator
pub fn initLibSSH2(allocator: std.mem.Allocator) !void {
    const rc = c.libssh2_init_ex(sshAlloc, sshFree, sshRealloc, @ptrCast(*anyopaque, &allocator));
    try checkError(rc);
}
```

### Critical Implementation Patterns

1. **Error Handling Hierarchy**
   - Convert generic errors to specific domain errors at boundaries
   - Example: `if (err == error.NotFound) return error.KeyNotFound;`
   - Always handle database errors explicitly

2. **String Enum Parsing**
   - Database stores lowercase strings: "read", "write", "admin"
   - Use `std.meta.stringToEnum()` for safe parsing
   - Always provide fallback: `orelse .None`

3. **Caching Strategy**
   - Cache computed permissions per user/repo pair
   - Clear cache on permission changes
   - Use simple HashMap with composite keys

4. **User Validation**
   - Check user exists AND is_active AND NOT is_deleted AND NOT prohibit_login
   - Site admins bypass most checks
   - Restricted users need explicit access

### SSH Server Structure

```zig
const bindings = @import("bindings.zig");

pub const SshServer = struct {
    config: SshConfig,
    db: *DataAccessObject,
    listener: std.net.Server,
    shutdown_manager: ShutdownManager,
    rate_limiter: RateLimiter,
    connection_tracker: ConnectionTracker,
    host_key_manager: HostKeyManager,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, config: SshConfig, db: *DataAccessObject) !SshServer {
        // Initialize libssh2 with custom allocator
        try bindings.initLibSSH2(allocator);
        
        // Rest of initialization
        return SshServer{
            .config = config,
            .db = db,
            // ... initialize other fields
        };
    }
    
    pub fn deinit(self: *SshServer) void {
        bindings.c.libssh2_exit();
        // Clean up other resources
    }
    
    pub fn start(self: *SshServer, allocator: std.mem.Allocator) !void {
        // Initialize subsystems
        // Setup signal handlers
        // Main accept loop with shutdown checks
        // Graceful shutdown sequence
    }
    
    pub fn handleConnection(self: *SshServer, allocator: std.mem.Allocator, conn: std.net.Connection) !void {
        // Create arena for connection-scoped allocations
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const conn_allocator = arena.allocator();
        
        // Rate limit check
        if (!try self.rate_limiter.checkConnection(conn.address)) {
            return error.RateLimitExceeded;
        }
        
        // Track connection
        try self.connection_tracker.add(conn.address);
        defer self.connection_tracker.remove(conn.address);
        
        // Create SSH session
        var session = try bindings.Session.init();
        defer session.deinit();
        
        // Perform SSH handshake
        try session.handshake(conn.stream.handle);
        
        // Set up host key
        try self.setupHostKey(&session);
        
        // Handle authentication
        const auth_result = try self.authenticateSession(&session, conn_allocator);
        if (!auth_result.authenticated) {
            return error.AuthenticationFailed;
        }
        
        // Create security context for permission checks
        var security_ctx = try SecurityContext.init(
            conn_allocator,
            self.db,
            &self.permission_cache,
            auth_result.user_id
        );
        
        // Extract and handle command
        try self.handleCommand(&session, &security_ctx, conn_allocator);
    }
};
```

### Authentication Flow

```zig
pub const AuthResult = struct {
    authenticated: bool,
    user_id: ?i64,
    key_id: ?i64,
    username: []const u8,
};

pub fn authenticateSession(
    self: *SshServer,
    session: *bindings.Session,
    allocator: std.mem.Allocator
) !AuthResult {
    // Get username from SSH session
    var username_ptr: [*c]u8 = undefined;
    var username_len: c_int = undefined;
    _ = bindings.c.libssh2_session_userauth_list(
        session.handle,
        null,
        0
    );
    
    // Set authentication callback
    bindings.c.libssh2_session_callback_set(
        session.handle,
        bindings.c.LIBSSH2_CALLBACK_USERAUTH_PUBLICKEY_SIGN,
        @ptrCast(authCallback)
    );
    
    // Wait for authentication attempt
    while (!bindings.c.libssh2_userauth_authenticated(session.handle)) {
        const rc = bindings.c.libssh2_session_handshake(session.handle, socket);
        if (rc == bindings.c.LIBSSH2_ERROR_EAGAIN) continue;
        try bindings.checkError(rc);
    }
    
    // Extract public key info
    const key_data = try extractPublicKey(session, allocator);
    defer allocator.free(key_data);
    
    // Calculate SHA256 fingerprint
    var hash: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(key_data, &hash, .{});
    const fingerprint = try std.fmt.allocPrint(allocator, "SHA256:{s}", .{
        std.base64.standard.Encoder.encode(&hash)
    });
    defer allocator.free(fingerprint);
    
    // Lookup key in database
    const key = try self.db.getPublicKeyByFingerprint(allocator, fingerprint);
    defer {
        allocator.free(key.name);
        allocator.free(key.content);
    }
    
    // Validate user
    const user = try self.db.getUserExt(allocator, key.user_id);
    defer {
        allocator.free(user.name);
        allocator.free(user.visibility);
    }
    
    // Check user status
    if (user.is_deleted or !user.is_active or user.prohibit_login) {
        return AuthResult{
            .authenticated = false,
            .user_id = null,
            .key_id = null,
            .username = "",
        };
    }
    
    // Update last used timestamp
    try self.db.updatePublicKeyLastUsed(key.id);
    
    return AuthResult{
        .authenticated = true,
        .user_id = key.user_id,
        .key_id = key.id,
        .username = try allocator.dupe(u8, user.name),
    };
}
```

### Certificate Authentication

```zig
pub const KeyType = enum(u8) {
    User = 1,
    Deploy = 2,
    Principal = 3,
};

pub fn authenticateCertificate(
    session: *bindings.Session,
    cert_data: []const u8,
    allocator: std.mem.Allocator,
    config: *const SshConfig,
    db: *DataAccessObject,
) !AuthResult {
    // Parse SSH certificate
    const cert = try parseSSHCertificate(cert_data);
    defer cert.deinit();
    
    // Validate certificate type
    if (cert.cert_type != .UserCert) {
        return SshError.InvalidCertificateType;
    }
    
    // Check if CA is trusted
    var ca_trusted = false;
    for (config.trusted_user_ca_keys) |ca_key| {
        if (std.mem.eql(u8, cert.signature_key, ca_key)) {
            ca_trusted = true;
            break;
        }
    }
    if (!ca_trusted) {
        return SshError.UntrustedCA;
    }
    
    // Validate certificate validity period
    const now = std.time.timestamp();
    if (now < cert.valid_after or now > cert.valid_before) {
        return SshError.CertificateExpired;
    }
    
    // Look up principal in database
    for (cert.valid_principals) |principal| {
        if (try lookupPrincipalKey(allocator, db, principal, config)) |key| {
            return AuthResult{
                .authenticated = true,
                .user_id = key.user_id,
                .key_id = key.id,
                .username = try allocator.dupe(u8, principal),
            };
        }
    }
    
    return SshError.PrincipalNotFound;
}
```

### Deploy Key Authentication

```zig
pub fn authenticateDeployKey(
    key: *const PublicKey,
    repo_path: []const u8,
    allocator: std.mem.Allocator,
    db: *DataAccessObject,
) !AuthResult {
    if (key.key_type != .Deploy) {
        return SshError.InvalidKeyType;
    }
    
    // Parse repository path
    const parts = std.mem.split(u8, repo_path, "/");
    if (parts.len != 2) {
        return SshError.InvalidRepositoryPath;
    }
    
    const owner = parts[0];
    const repo_name = parts[1];
    
    // Get repository ID
    const repo_id = try db.getRepositoryIdByOwnerAndName(allocator, owner, repo_name);
    
    // Check if deploy key is authorized for this repository
    const authorized = try db.isDeployKeyAuthorizedForRepo(key.id, repo_id);
    if (!authorized) {
        return SshError.DeployKeyNotAuthorized;
    }
    
    // Deploy keys don't have a user_id, they have repository-specific access
    return AuthResult{
        .authenticated = true,
        .user_id = null, // Deploy keys aren't associated with users
        .key_id = key.id,
        .username = try std.fmt.allocPrint(allocator, "deploy_key_{d}", .{key.id}),
    };
}
```

### Key Validation

```zig
pub const KeyValidator = struct {
    minimum_key_sizes: std.StringHashMap(u32),
    minimum_key_size_check: bool,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, config: *const SshConfig) !KeyValidator {
        return KeyValidator{
            .minimum_key_sizes = try config.minimum_key_sizes.clone(),
            .minimum_key_size_check = config.minimum_key_size_check,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *KeyValidator) void {
        self.minimum_key_sizes.deinit();
    }
    
    pub fn validateKey(self: *const KeyValidator, key_content: []const u8) !void {
        if (!self.minimum_key_size_check) return;
        
        const key_info = try parseSSHPublicKey(key_content);
        defer key_info.deinit();
        
        const min_size = self.minimum_key_sizes.get(key_info.algorithm) orelse {
            return SshError.KeyTypeNotAllowed;
        };
        
        if (key_info.bit_length < min_size) {
            std.log.warn("Key too weak: {s} key with {d} bits (minimum {d})", 
                .{ key_info.algorithm, key_info.bit_length, min_size });
            return SshError.KeyTooWeak;
        }
    }
};
```

### Username Validation

```zig
pub fn validateSSHUsername(
    session: *bindings.Session, 
    config: *const SshConfig,
    allocator: std.mem.Allocator,
) ![]const u8 {
    // Get username from SSH session
    var username_buf: [256]u8 = undefined;
    const username_len = bindings.c.libssh2_session_username(
        session.handle,
        &username_buf,
        username_buf.len,
    );
    
    if (username_len < 0) {
        return SshError.InvalidUsername;
    }
    
    const username = username_buf[0..@intCast(usize, username_len)];
    
    if (!std.mem.eql(u8, username, config.builtin_server_user)) {
        std.log.warn("Invalid SSH username '{s}' - must use '{s}' for all git operations via ssh", 
            .{ username, config.builtin_server_user });
        return SshError.InvalidUsername;
    }
    
    return try allocator.dupe(u8, username);
}

### Session Management

```zig
pub const SshSession = struct {
    connection: std.net.Connection,
    user_id: ?i64,
    key_id: ?i64,
    command: ?[]const u8,
    environment: std.process.EnvMap,
    security_context: *SecurityContext,  // Integration with permission system
    
    pub fn extractCommand(self: *SshSession, allocator: std.mem.Allocator) !void {
        // Get SSH_ORIGINAL_COMMAND
        // Validate command format
        // Parse git operation
        // Set up environment
    }
    
    pub fn execute(self: *SshSession, allocator: std.mem.Allocator) !i32 {
        // Validate permissions using security context
        // Execute git command
        // Stream I/O
        // Return exit code
    }
};
```

## Security Requirements

### Rate Limiting
- Track connection attempts per IP address
- Implement exponential backoff for failed attempts
- Support configurable thresholds
- Clean up old entries periodically

### Connection Security
- Enforce maximum concurrent connections globally
- Limit connections per IP address
- Implement connection timeouts
- Validate all protocol inputs

### Audit Logging

Production logging patterns:

```zig
pub const KeyInfo = struct {
    key_type: KeyType,
    fingerprint: []const u8,
    key_id: i64,
};

pub fn logAuthenticationAttempt(
    remote_addr: []const u8,
    username: []const u8,
    authenticated: bool,
    key_info: ?KeyInfo,
    error_reason: ?[]const u8,
) void {
    if (authenticated) {
        if (key_info) |ki| {
            switch (ki.key_type) {
                .Deploy => std.log.info("SSH: Deploy key authentication success from {s} (fingerprint: {s})", 
                    .{ remote_addr, ki.fingerprint }),
                .Principal => std.log.info("SSH: Principal authentication success from {s} (principal: {s})", 
                    .{ remote_addr, username }),
                .User => std.log.info("SSH: User authentication success from {s} (user: {s})", 
                    .{ remote_addr, username }),
            }
        }
    } else {
        if (error_reason) |reason| {
            std.log.warn("Failed authentication attempt from {s}: {s}", .{ remote_addr, reason });
        }
        // Standard message for fail2ban
        std.log.warn("Failed authentication attempt from {s}", .{remote_addr});
    }
}

pub fn logCommandExecution(
    user_id: i64,
    username: []const u8,
    command: []const u8,
    repo_path: []const u8,
    success: bool,
) void {
    if (success) {
        std.log.info("SSH: User {s} ({d}) executed '{s}' on repository '{s}'", 
            .{ username, user_id, command, repo_path });
    } else {
        std.log.warn("SSH: User {s} ({d}) failed to execute '{s}' on repository '{s}'", 
            .{ username, user_id, command, repo_path });
    }
}

pub fn logSecurityEvent(
    event_type: []const u8,
    remote_addr: []const u8,
    details: []const u8,
) void {
    std.log.warn("SSH Security Event: {s} from {s} - {s}", 
        .{ event_type, remote_addr, details });
}
```

## Testing Strategy

### Unit Tests
- Test each component in isolation
- Mock network connections for unit tests
- Test error handling and edge cases
- Verify memory safety
- **IMPORTANT**: Include tests in the same file as implementation
- **CRITICAL**: No test abstractions - copy setup code in each test
- **IMPORTANT**: Test data setup must be complete (e.g., create all referenced users)

### Integration Tests
- Test with real SSH client connections
- Test authentication flow end-to-end
- Test graceful shutdown scenarios
- Test security features (rate limiting, timeouts)

### Security Tests
- Test brute force protection
- Test malformed input handling
- Test resource exhaustion scenarios
- Test concurrent connection limits

### Critical Test Cases

```zig
test "SSH certificate authentication with valid CA" {
    const allocator = testing.allocator;
    var dao = MockDAO.init(allocator);
    defer dao.deinit();
    
    // Add trusted CA
    var config = try SshConfig.init(allocator);
    defer config.deinit();
    try config.trusted_user_ca_keys.append(test_ca_public_key);
    
    // Create valid certificate
    const cert = try createTestCertificate(.{
        .ca_key = test_ca_private_key,
        .principals = &.{"alice@example.com"},
        .valid_after = std.time.timestamp() - 3600,
        .valid_before = std.time.timestamp() + 3600,
    });
    
    const result = try authenticateCertificate(session, cert, allocator, &config, &dao);
    try testing.expect(result.authenticated);
}

test "SSH certificate with invalid principal" {
    const allocator = testing.allocator;
    var dao = MockDAO.init(allocator);
    defer dao.deinit();
    
    var config = try SshConfig.init(allocator);
    defer config.deinit();
    try config.trusted_user_ca_keys.append(test_ca_public_key);
    
    const cert = try createTestCertificate(.{
        .ca_key = test_ca_private_key,
        .principals = &.{"unknown@example.com"},
        .valid_after = std.time.timestamp() - 3600,
        .valid_before = std.time.timestamp() + 3600,
    });
    
    try testing.expectError(SshError.PrincipalNotFound, 
        authenticateCertificate(session, cert, allocator, &config, &dao));
}

test "Deploy key authentication for specific repository" {
    const allocator = testing.allocator;
    var dao = MockDAO.init(allocator);
    defer dao.deinit();
    
    // Add deploy key
    const key = PublicKey{
        .id = 1,
        .key_type = .Deploy,
        .fingerprint = "SHA256:test",
        .content = test_deploy_key,
    };
    
    // Authorize for specific repo
    try dao.authorizeDeployKeyForRepo(key.id, 42);
    
    // Should succeed for authorized repo
    const result = try authenticateDeployKey(&key, "owner/authorized-repo", allocator, &dao);
    try testing.expect(result.authenticated);
    try testing.expect(result.user_id == null); // Deploy keys don't have user_id
    
    // Should fail for unauthorized repo
    try testing.expectError(SshError.DeployKeyNotAuthorized,
        authenticateDeployKey(&key, "owner/other-repo", allocator, &dao));
}

test "Minimum key size enforcement for weak RSA key" {
    const allocator = testing.allocator;
    var config = try SshConfig.init(allocator);
    defer config.deinit();
    
    const validator = try KeyValidator.init(allocator, &config);
    defer validator.deinit();
    
    // 2048-bit RSA key (below 3071 minimum)
    const weak_rsa_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDf..."; // 2048-bit key
    
    try testing.expectError(SshError.KeyTooWeak, validator.validateKey(weak_rsa_key));
}

test "Username validation rejects wrong user" {
    const allocator = testing.allocator;
    var config = try SshConfig.init(allocator);
    config.builtin_server_user = "git";
    defer config.deinit();
    
    // Mock session with wrong username
    var session = try createMockSession("wronguser");
    defer session.deinit();
    
    try testing.expectError(SshError.InvalidUsername, 
        validateSSHUsername(&session, &config, allocator));
}

test "Git command validation rejects malicious commands" {
    const allocator = testing.allocator;
    
    // Path traversal attempt
    try testing.expectError(SshError.InvalidRepositoryPath,
        GitCommand.parse("git-upload-pack '../../etc/passwd'", allocator));
    
    // Command injection attempt
    try testing.expectError(SshError.InvalidCommand,
        GitCommand.parse("git-upload-pack 'repo'; rm -rf /", allocator));
    
    // Invalid verb
    try testing.expectError(SshError.CommandNotAllowed,
        GitCommand.parse("git-shell 'repo'", allocator));
}

test "AGit flow ssh_info command handling" {
    const allocator = testing.allocator;
    
    const cmd = try GitCommand.parse("ssh_info", allocator);
    defer cmd.deinit();
    
    try testing.expectEqualStrings("ssh_info", cmd.verb);
    try testing.expectEqualStrings("", cmd.repo_path);
    try testing.expect(cmd.lfs_verb == null);
    try testing.expect(cmd.getOperation() == .ssh_info);
}

test "LFS command parsing and validation" {
    const allocator = testing.allocator;
    
    // Valid LFS authenticate
    const cmd1 = try GitCommand.parse("git-lfs-authenticate 'owner/repo' download", allocator);
    defer cmd1.deinit();
    try testing.expectEqualStrings("git-lfs-authenticate", cmd1.verb);
    try testing.expectEqualStrings("owner/repo", cmd1.repo_path);
    try testing.expectEqualStrings("download", cmd1.lfs_verb.?);
    
    // Invalid LFS verb
    try testing.expectError(SshError.InvalidCommand,
        GitCommand.parse("git-lfs-authenticate 'owner/repo' delete", allocator));
}

test "Per-write timeout enforcement on large transfers" {
    const allocator = testing.allocator;
    var server = try SshServer.init(allocator, test_config);
    defer server.deinit();
    
    // Mock slow transfer
    var session = try createMockSlowSession();
    defer session.deinit();
    
    // Should timeout after configured per-write timeout
    try testing.expectError(SshError.WriteTimeout,
        server.handleConnection(allocator, session.connection));
}

test "Proxy protocol header parsing" {
    const allocator = testing.allocator;
    var config = try SshConfig.init(allocator);
    config.use_proxy_protocol = true;
    try config.proxy_protocol_trusted_ips.append("10.0.0.1");
    defer config.deinit();
    
    // Valid PROXY protocol v2 header
    const proxy_header = "PROXY TCP4 192.168.1.100 10.0.0.1 45678 22\r\n";
    const conn = try parseProxyProtocol(proxy_header, config);
    
    try testing.expectEqualStrings("192.168.1.100", conn.real_remote_addr);
    try testing.expect(conn.real_remote_port == 45678);
}
```

## Integration Points

### Database Integration
- Use DataAccessObject from src/database/dao.zig
- Query PublicKey table for authentication
- Update last_used timestamps
- Handle database errors gracefully

### Git Command Integration
- Will integrate with git command wrapper (Task 1)
- Pass environment and streams to git process
- Handle git command output and errors

### Permission Integration
- Use permission system from Task 4
- Create SecurityContext for each authenticated session
- Check repository access before executing commands
- Enforce read/write permissions based on operation
- Handle user status (active, deleted, restricted) during authentication
- Validate repository state (archived, mirror) affects write operations

## Performance Considerations

### Connection Pooling
- Reuse database connections
- Implement connection pool with proper sizing
- Monitor pool health

### Memory Management
- Use arena allocators for per-connection state
- Clean up all allocations on connection close
- Monitor memory usage
- **CRITICAL**: Always use defer/errdefer for cleanup immediately after allocation
- Pass allocators explicitly to methods that need them (not in constructors)
- Be explicit about memory ownership - who allocates, who frees

### Scalability
- Design for horizontal scaling
- Support load balancing
- Implement health checks

## Configuration

```zig
pub const SshConfig = struct {
    host: []const u8 = "0.0.0.0",
    port: u16 = 22,
    host_key_path: []const u8 = "/etc/plue/ssh_host_rsa_key",
    builtin_server_user: []const u8 = "git",
    max_connections: u32 = 1000,
    max_connections_per_ip: u32 = 10,
    auth_timeout_seconds: u32 = 60,
    connection_timeout_seconds: u32 = 300,
    graceful_shutdown_timeout_seconds: u32 = 30,
    rate_limit_window_seconds: u32 = 300,
    rate_limit_max_attempts: u32 = 10,
    
    // SSH Certificate Support
    trusted_user_ca_keys: [][]const u8 = &.{},
    trusted_user_ca_keys_file: []const u8 = "ssh/trusted-user-ca-keys.pem",
    authorized_principals_allow: [][]const u8 = &.{"username", "email"},
    authorized_principals_enabled: bool = false,
    
    // Timeouts for DoS protection
    per_write_timeout: std.time.Duration = std.time.Duration.fromSeconds(30),
    per_write_per_kb_timeout: std.time.Duration = std.time.Duration.fromMilliseconds(10),
    
    // Load balancer support
    use_proxy_protocol: bool = false,
    proxy_protocol_trusted_ips: [][]const u8 = &.{},
    
    // Key validation
    minimum_key_size_check: bool = true,
    minimum_key_sizes: std.StringHashMap(u32) = undefined, // Initialized in init()
    
    // Cipher configuration
    ciphers: []const []const u8 = &.{
        "chacha20-poly1305@openssh.com",
        "aes256-gcm@openssh.com",
        "aes128-gcm@openssh.com",
    },
    key_exchanges: []const []const u8 = &.{
        "curve25519-sha256",
        "curve25519-sha256@libssh.org",
    },
    macs: []const []const u8 = &.{
        "umac-128-etm@openssh.com",
        "hmac-sha2-256-etm@openssh.com",
    },
    
    pub fn init(allocator: std.mem.Allocator) !SshConfig {
        var config = SshConfig{};
        config.minimum_key_sizes = std.StringHashMap(u32).init(allocator);
        
        // Gitea's default minimum key sizes
        try config.minimum_key_sizes.put("ed25519", 256);
        try config.minimum_key_sizes.put("ed25519-sk", 256);
        try config.minimum_key_sizes.put("ecdsa", 256);
        try config.minimum_key_sizes.put("ecdsa-sk", 256);
        try config.minimum_key_sizes.put("rsa", 3071);
        
        return config;
    }
};
```

## Error Handling

Define comprehensive error types:

```zig
pub const SshError = error{
    // Connection errors
    ConnectionRefused,
    ConnectionTimeout,
    TooManyConnections,
    RateLimitExceeded,
    ProxyProtocolError,
    
    // Authentication errors
    AuthenticationFailed,
    KeyNotFound,
    KeyTooWeak,
    KeyTypeNotAllowed,
    UserDisabled,
    UserNotFound,
    UserInactive,
    UserDeleted,
    InvalidUsername,
    
    // Certificate errors
    CertificateInvalid,
    CertificateExpired,
    UntrustedCA,
    PrincipalNotFound,
    InvalidCertificateType,
    
    // Deploy key errors
    DeployKeyNotAuthorized,
    DeployKeyRepoMismatch,
    
    // Command errors
    InvalidCommand,
    InvalidRepositoryPath,
    CommandNotAllowed,
    
    // Protocol errors
    InvalidProtocol,
    UnsupportedCipher,
    
    // System errors
    HostKeyGenerationFailed,
    ShutdownInProgress,
    WriteTimeout,
} || error{OutOfMemory};
```

## Monitoring & Observability

### Metrics to Track
- Active connection count
- Authentication success/failure rate
- Command execution times
- Rate limit hits
- Error rates by type

### Health Checks
- Expose health endpoint
- Check database connectivity
- Verify host key accessibility
- Monitor resource usage

## Database Schema Requirements

The SSH server expects these tables to exist:
- `public_key`: id, user_id, fingerprint, content, name, created_at, last_used_at, key_type (1=User, 2=Deploy, 3=Principal)
- `user`: id, name, is_admin, is_active, is_deleted, prohibit_login, is_restricted, visibility
- `repository`: id, owner_id, owner_name, name, is_private, is_archived, is_mirror, visibility
- `deploy_key`: id, key_id, repo_id, mode (read/write), created_at
- `principal`: id, user_id, key_id, principal_value, created_at
- `organization`: id, name, visibility, max_repo_creation
- `access_token`: id, user_id, name, token_hash, scopes, created_at, expires_at

## SSH-Specific Implementation Patterns

### Channel and Command Execution

```zig
pub fn handleCommand(
    self: *SshServer,
    session: *bindings.Session,
    security_ctx: *SecurityContext,
    allocator: std.mem.Allocator
) !void {
    // Open channel for command execution
    const channel = bindings.c.libssh2_channel_open_session(session.handle) orelse {
        return error.ChannelOpenFailed;
    };
    defer _ = bindings.c.libssh2_channel_free(channel);
    
    // Get the command from environment
    var command_buf: [1024]u8 = undefined;
    var command_len: usize = command_buf.len;
    const rc = bindings.c.libssh2_channel_exec(
        channel,
        "git-upload-pack '/repo/path'"
    );
    try bindings.checkError(rc);
    
    // Parse git command
    const git_cmd = try parseGitCommand(allocator, command_buf[0..command_len]);
    defer git_cmd.deinit();
    
    // Check permissions
    const repo_id = try self.db.getRepositoryIdByPath(git_cmd.repo_path);
    switch (git_cmd.operation) {
        .upload_pack => try security_ctx.requireRepoRead(repo_id, .Code),
        .receive_pack => try security_ctx.requireRepoWrite(repo_id, .Code),
    }
    
    // Execute git process
    var child = std.process.Child.init(&.{
        "git",
        git_cmd.operation.toString(),
        git_cmd.repo_path,
    }, allocator);
    
    // Connect SSH channel to git process stdio
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    
    try child.spawn();
    
    // Proxy data between SSH channel and git process
    try proxyChannelToProcess(channel, &child);
    
    // Wait for completion
    const term = try child.wait();
    
    // Send exit status
    _ = bindings.c.libssh2_channel_send_eof(channel);
    _ = bindings.c.libssh2_channel_close(channel);
}
```

### Git Command Validation

```zig
pub const GitCommand = struct {
    verb: []const u8,
    repo_path: []const u8,
    lfs_verb: ?[]const u8,
    allocator: std.mem.Allocator,
    
    pub fn parse(cmd: []const u8, allocator: std.mem.Allocator) !GitCommand {
        // Handle special commands first
        if (std.mem.eql(u8, cmd, "ssh_info")) {
            // AGit Flow support
            return GitCommand{
                .verb = try allocator.dupe(u8, "ssh_info"),
                .repo_path = try allocator.dupe(u8, ""),
                .lfs_verb = null,
                .allocator = allocator,
            };
        }
        
        // Parse command with shell quote handling
        const args = try shellquote.split(cmd, allocator);
        defer allocator.free(args);
        
        if (args.len < 2) {
            return SshError.InvalidCommand;
        }
        
        const verb = args[0];
        if (!isAllowedVerbForServe(verb)) {
            std.log.warn("SSH: Rejected command verb: {s}", .{verb});
            return SshError.CommandNotAllowed;
        }
        
        // Parse repository path
        var repo_path = std.mem.trim(u8, args[1], " \t");
        repo_path = std.mem.trimPrefix(u8, repo_path, "/");
        repo_path = std.mem.trimSuffix(u8, repo_path, ".git");
        
        // Validate repository path format
        if (!isValidRepoPath(repo_path)) {
            std.log.warn("SSH: Invalid repository path format: {s}", .{repo_path});
            return SshError.InvalidRepositoryPath;
        }
        
        // Handle LFS commands
        var lfs_verb: ?[]const u8 = null;
        if (isAllowedVerbForServeLfs(verb) and args.len > 2) {
            lfs_verb = args[2];
            if (!isValidLfsVerb(lfs_verb.?)) {
                return SshError.InvalidCommand;
            }
        }
        
        return GitCommand{
            .verb = try allocator.dupe(u8, verb),
            .repo_path = try allocator.dupe(u8, repo_path),
            .lfs_verb = if (lfs_verb) |lv| try allocator.dupe(u8, lv) else null,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *GitCommand) void {
        self.allocator.free(self.verb);
        self.allocator.free(self.repo_path);
        if (self.lfs_verb) |lv| {
            self.allocator.free(lv);
        }
    }
    
    fn isAllowedVerbForServe(verb: []const u8) bool {
        return std.mem.eql(u8, verb, "git-upload-pack") or
               std.mem.eql(u8, verb, "git-receive-pack") or  
               std.mem.eql(u8, verb, "git-upload-archive");
    }
    
    fn isAllowedVerbForServeLfs(verb: []const u8) bool {
        return std.mem.eql(u8, verb, "git-lfs-authenticate") or
               std.mem.eql(u8, verb, "git-lfs-transfer");
    }
    
    fn isValidLfsVerb(verb: []const u8) bool {
        return std.mem.eql(u8, verb, "download") or
               std.mem.eql(u8, verb, "upload");
    }
    
    fn isValidRepoPath(path: []const u8) bool {
        const parts = std.mem.split(u8, path, "/");
        var count: usize = 0;
        var iter = parts;
        while (iter.next()) |_| : (count += 1) {}
        
        // Must be owner/repo format
        if (count != 2) return false;
        
        // Validate path components
        iter = std.mem.split(u8, path, "/");
        while (iter.next()) |part| {
            if (part.len == 0) return false;
            if (std.mem.indexOf(u8, part, "..") != null) return false;
            if (std.mem.indexOf(u8, part, "\\") != null) return false;
        }
        
        return true;
    }
    
    pub fn getOperation(self: *const GitCommand) enum { upload_pack, receive_pack, upload_archive, lfs, ssh_info } {
        if (std.mem.eql(u8, self.verb, "git-upload-pack")) return .upload_pack;
        if (std.mem.eql(u8, self.verb, "git-receive-pack")) return .receive_pack;
        if (std.mem.eql(u8, self.verb, "git-upload-archive")) return .upload_archive;
        if (std.mem.eql(u8, self.verb, "git-lfs-authenticate") or 
            std.mem.eql(u8, self.verb, "git-lfs-transfer")) return .lfs;
        if (std.mem.eql(u8, self.verb, "ssh_info")) return .ssh_info;
        unreachable;
    }
};
```

### Host Key Management

```zig
pub fn setupHostKey(self: *SshServer, session: *bindings.Session) !void {
    // Load or generate host key
    const host_key = try self.host_key_manager.getOrCreateHostKey();
    defer host_key.deinit();
    
    // Set host key for session
    const rc = bindings.c.libssh2_session_hostkey(
        session.handle,
        host_key.data.ptr,
        @intCast(c_int, host_key.data.len),
        bindings.c.LIBSSH2_HOSTKEY_TYPE_RSA
    );
    try bindings.checkError(rc);
}
```

## Implementation Phases

1. **Phase 1: Basic SSH Server**
   - TCP listener with connection handling
   - libssh2 integration and build setup
   - Basic SSH protocol negotiation
   - Host key generation and loading

2. **Phase 2: Authentication**
   - Public key authentication callbacks
   - Database integration for key lookup
   - User validation (active, not deleted, etc.)
   - Fingerprint calculation and matching

3. **Phase 3: Session Management**
   - Channel creation and management
   - Command extraction from SSH environment
   - Git command parsing and validation
   - Permission checking via SecurityContext

4. **Phase 4: Command Execution**
   - Git process spawning
   - I/O proxying between SSH and git
   - Exit status handling
   - Error propagation

5. **Phase 5: Security Hardening**
   - Rate limiting implementation
   - Connection tracking
   - Graceful shutdown
   - Timeout enforcement

6. **Phase 6: Production Features**
   - Metrics and monitoring
   - Health checks
   - Advanced logging
   - Deploy key support

## References

- [Gitea SSH Implementation](https://github.com/go-gitea/gitea/blob/main/modules/ssh/ssh.go)
- [SSH Protocol RFC](https://www.rfc-editor.org/rfc/rfc4253)
- [OpenSSH Security Best Practices](https://www.openssh.com/security.html)