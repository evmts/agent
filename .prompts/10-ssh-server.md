# Production-Grade SSH Server Implementation

## Overview

Implement a production-ready SSH server in Zig that handles git operations over SSH protocol. The server must authenticate users via public keys stored in the database, extract git commands from SSH sessions, and provide enterprise-grade reliability with graceful shutdown, security hardening, and comprehensive monitoring.

## Core Requirements

### 1. SSH Server Core

Create a configurable SSH server that can:
- Listen on configurable host and port
- Support configurable SSH ciphers, key exchanges, and MACs
- Generate and manage SSH host keys (RSA 4096-bit)
- Handle graceful shutdown with connection draining
- Implement per-connection write timeouts for DoS protection

### 2. Public Key Authentication

Implement secure authentication:
- Authenticate users based on public key fingerprints from database
- Validate SSH username matches configured git user
- Log all authentication attempts for security monitoring
- Support minimum key size validation
- Calculate SSH SHA256 fingerprints for key matching

### 3. Session & Command Handling

Handle SSH sessions properly:
- Extract `SSH_ORIGINAL_COMMAND` from session environment
- Parse git commands (`git-receive-pack`, `git-upload-pack`)
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
└── shutdown.zig        // Graceful shutdown handling
```

## Implementation Guidelines

### SSH Server Structure

```zig
pub const SshServer = struct {
    config: SshConfig,
    db: *DataAccessObject,
    listener: std.net.Server,
    shutdown_manager: ShutdownManager,
    rate_limiter: RateLimiter,
    connection_tracker: ConnectionTracker,
    host_key_manager: HostKeyManager,
    
    pub fn start(self: *SshServer, allocator: std.mem.Allocator) !void {
        // Initialize subsystems
        // Setup signal handlers
        // Main accept loop with shutdown checks
        // Graceful shutdown sequence
    }
    
    pub fn handleConnection(self: *SshServer, allocator: std.mem.Allocator, conn: std.net.Connection) !void {
        // Rate limit check
        // Track connection
        // Create session
        // Authenticate
        // Handle command
        // Clean up
    }
};
```

### Authentication Flow

```zig
pub const SshAuthenticator = struct {
    db: *DataAccessObject,
    
    pub fn authenticate(
        self: *SshAuthenticator,
        allocator: std.mem.Allocator,
        public_key_data: []const u8,
        username: []const u8
    ) !AuthResult {
        // Calculate fingerprint
        // Lookup in database
        // Validate key security
        // Check user status
        // Return auth result
    }
};
```

### Session Management

```zig
pub const SshSession = struct {
    connection: std.net.Connection,
    user_id: ?i64,
    key_id: ?i64,
    command: ?[]const u8,
    environment: std.process.EnvMap,
    
    pub fn extractCommand(self: *SshSession, allocator: std.mem.Allocator) !void {
        // Get SSH_ORIGINAL_COMMAND
        // Validate command format
        // Parse git operation
        // Set up environment
    }
    
    pub fn execute(self: *SshSession, allocator: std.mem.Allocator) !i32 {
        // Validate permissions
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
- Log all connection attempts with timestamp and IP
- Log authentication successes and failures
- Log executed commands
- Support structured logging for SIEM integration

## Testing Strategy

### Unit Tests
- Test each component in isolation
- Mock network connections for unit tests
- Test error handling and edge cases
- Verify memory safety

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

### Example Test

```zig
test "SSH server graceful shutdown" {
    const allocator = testing.allocator;
    
    var server = try SshServer.init(allocator, test_config);
    defer server.deinit();
    
    // Start server in background
    const thread = try std.Thread.spawn(.{}, serverThread, .{&server});
    
    // Wait for server to start
    std.time.sleep(100 * std.time.ns_per_ms);
    
    // Create some connections
    var clients = try allocator.alloc(SshClient, 5);
    defer allocator.free(clients);
    
    for (clients) |*client| {
        client.* = try SshClient.connect(allocator, "127.0.0.1", test_port);
    }
    
    // Request shutdown
    server.shutdown_manager.requestShutdown();
    
    // Verify connections are drained gracefully
    thread.join();
    
    // Verify all resources cleaned up
    try testing.expect(server.connection_tracker.count() == 0);
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
- Check repository access before executing commands
- Enforce read/write permissions based on operation

## Performance Considerations

### Connection Pooling
- Reuse database connections
- Implement connection pool with proper sizing
- Monitor pool health

### Memory Management
- Use arena allocators for per-connection state
- Clean up all allocations on connection close
- Monitor memory usage

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
    max_connections: u32 = 1000,
    max_connections_per_ip: u32 = 10,
    auth_timeout_seconds: u32 = 60,
    connection_timeout_seconds: u32 = 300,
    graceful_shutdown_timeout_seconds: u32 = 30,
    rate_limit_window_seconds: u32 = 300,
    rate_limit_max_attempts: u32 = 10,
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
    
    // Authentication errors
    AuthenticationFailed,
    KeyNotFound,
    KeyTooWeak,
    UserDisabled,
    
    // Protocol errors
    InvalidProtocol,
    InvalidCommand,
    UnsupportedCipher,
    
    // System errors
    HostKeyGenerationFailed,
    ShutdownInProgress,
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

## References

- [Gitea SSH Implementation](https://github.com/go-gitea/gitea/blob/main/modules/ssh/ssh.go)
- [SSH Protocol RFC](https://www.rfc-editor.org/rfc/rfc4253)
- [OpenSSH Security Best Practices](https://www.openssh.com/security.html)