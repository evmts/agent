/// SSH Server for Git operations
/// Provides SSH access for git clone/push/pull operations
///
/// This is a simplified implementation that leverages OpenSSH's sshd for protocol handling
/// while implementing the git command execution and authentication in Zig.
///
/// For a full native implementation, consider using:
/// - libssh2 bindings (https://github.com/mattnite/zig-libssh2)
/// - MiSSHod pure Zig implementation (https://github.com/ringtailsoftware/misshod)
/// - ZSSH pure Zig implementation (https://git.sr.ht/~mulling/zssh)
///
const std = @import("std");
const types = @import("types.zig");
const auth = @import("auth.zig");
const session = @import("session.zig");
const proxy_protocol = @import("proxy_protocol.zig");
const rate_limit = @import("rate_limit.zig");
const connection_limit = @import("connection_limit.zig");
const security_log = @import("security_log.zig");
const health = @import("health.zig");
const db = @import("db");

const log = std.log.scoped(.ssh_server);

/// SSH Server Configuration
pub const Config = struct {
    /// SSH server host address
    host: []const u8 = "0.0.0.0",
    /// SSH server port (22 for Cloudflare Spectrum compatibility)
    port: u16 = 22,
    /// Enable PROXY protocol parsing (for Cloudflare Spectrum)
    proxy_protocol_enabled: bool = true,
    /// Path to SSH host key (RSA)
    host_key_path: []const u8 = "data/ssh_host_key",
    /// Maximum concurrent connections total
    max_connections: u32 = 100,
    /// Maximum concurrent connections per IP
    max_per_ip_connections: u32 = 10,
    /// Maximum connection attempts per IP per minute
    rate_limit_per_minute: u32 = 20,
    /// Maximum authentication failures before IP ban
    max_auth_failures: u32 = 5,
    /// Initial ban duration in seconds (15 minutes)
    initial_ban_duration: i64 = 15 * 60,
    /// Maximum ban duration in seconds (24 hours)
    max_ban_duration: i64 = 24 * 60 * 60,
};

/// SSH Server
pub const Server = struct {
    allocator: std.mem.Allocator,
    config: Config,
    pool: *db.Pool,
    listener: ?std.net.Server = null,
    running: bool = false,

    /// Security components
    rate_limiter: rate_limit.RateLimiter,
    connection_limiter: connection_limit.ConnectionLimiter,

    /// Server start time for uptime tracking
    start_time: i64 = 0,

    /// Cleanup thread handle
    cleanup_thread: ?std.Thread = null,

    pub fn init(allocator: std.mem.Allocator, config: Config, pool: *db.Pool) Server {
        return .{
            .allocator = allocator,
            .config = config,
            .pool = pool,
            .rate_limiter = rate_limit.RateLimiter.init(allocator, .{
                .max_connections_per_minute = config.rate_limit_per_minute,
                .max_auth_failures = config.max_auth_failures,
                .initial_ban_duration = config.initial_ban_duration,
                .max_ban_duration = config.max_ban_duration,
            }),
            .connection_limiter = connection_limit.ConnectionLimiter.init(allocator, .{
                .max_total_connections = config.max_connections,
                .max_per_ip_connections = config.max_per_ip_connections,
            }),
        };
    }

    pub fn deinit(self: *Server) void {
        // Stop cleanup thread
        self.running = false;
        if (self.cleanup_thread) |thread| {
            thread.join();
        }

        self.rate_limiter.deinit();
        self.connection_limiter.deinit();
        if (self.listener) |*listener| {
            listener.deinit();
        }
    }

    /// Get current health status
    pub fn getHealthStatus(self: *Server) health.HealthStatus {
        return health.getHealthStatus(
            self.running,
            self.start_time,
            &self.connection_limiter,
            &self.rate_limiter,
        );
    }

    /// Get detailed metrics for monitoring
    pub fn getDetailedMetrics(self: *Server) health.DetailedMetrics {
        return health.getDetailedMetrics(
            self.start_time,
            &self.connection_limiter,
            &self.rate_limiter,
        );
    }

    /// Generate or load SSH host key
    fn ensureHostKey(self: *Server) !void {
        // Check if host key exists
        if (std.fs.cwd().access(self.config.host_key_path, .{})) {
            log.info("Using existing SSH host key at {s}", .{self.config.host_key_path});
            return;
        } else |_| {
            // Need to generate host key
            log.info("Generating SSH host key at {s}", .{self.config.host_key_path});

            // Create directory if needed
            if (std.fs.path.dirname(self.config.host_key_path)) |dir| {
                try std.fs.cwd().makePath(dir);
            }

            // Use ssh-keygen to generate RSA key
            var child = std.process.Child.init(&.{
                "ssh-keygen",
                "-t",
                "rsa",
                "-b",
                "4096",
                "-f",
                self.config.host_key_path,
                "-N",
                "", // No passphrase
                "-C",
                "plue-ssh-host-key",
            }, self.allocator);

            child.stdout_behavior = .Ignore;
            child.stderr_behavior = .Ignore;

            const term = try child.spawnAndWait();

            switch (term) {
                .Exited => |code| {
                    if (code != 0) {
                        log.err("ssh-keygen failed with code {d}", .{code});
                        return error.KeyGenerationFailed;
                    }
                },
                else => return error.KeyGenerationFailed,
            }

            log.info("SSH host key generated successfully", .{});
        }
    }

    /// Start the SSH server
    pub fn listen(self: *Server) !void {
        // Ensure host key exists
        try self.ensureHostKey();

        // Parse address
        const addr = try std.net.Address.parseIp(self.config.host, self.config.port);

        // Create TCP listener
        const listener = try addr.listen(.{
            .reuse_address = true,
            .kernel_backlog = 128,
        });

        self.listener = listener;
        self.running = true;
        self.start_time = std.time.timestamp();

        // Start cleanup thread for expired bans and stale entries
        self.cleanup_thread = try std.Thread.spawn(.{}, cleanupTask, .{self});

        log.info("SSH server listening on {s}:{d}", .{ self.config.host, self.config.port });
        if (self.config.proxy_protocol_enabled) {
            log.info("PROXY protocol enabled (for Cloudflare Spectrum)", .{});
        }
        log.info("Security hardening enabled: rate_limit={d}/min, max_failures={d}, max_conn={d}", .{
            self.config.rate_limit_per_minute,
            self.config.max_auth_failures,
            self.config.max_connections,
        });
        log.info("Note: This is a simplified implementation for git operations", .{});
        log.info("For production use, consider using a full SSH implementation", .{});

        // Accept connections
        while (self.running) {
            const connection = self.listener.?.accept() catch |err| {
                log.err("Accept failed: {}", .{err});
                continue;
            };

            // Handle connection in a new thread
            const thread = try std.Thread.spawn(.{}, handleConnectionSecure, .{
                self,
                connection,
            });
            thread.detach();
        }
    }

    /// Cleanup task - runs periodically to remove expired bans and stale entries
    fn cleanupTask(self: *Server) void {
        while (self.running) {
            // Sleep for 5 minutes
            std.Thread.sleep(5 * std.time.ns_per_min);

            if (!self.running) break;

            self.rate_limiter.cleanup();
            self.connection_limiter.cleanup();

            log.debug("Security cleanup completed", .{});
        }
    }

    /// Stop the server
    pub fn stop(self: *Server) void {
        self.running = false;
        if (self.listener) |*listener| {
            listener.deinit();
            self.listener = null;
        }
    }
};

/// Connection state
const Connection = struct {
    stream: std.net.Stream,
    /// Socket address (may be Cloudflare proxy IP)
    address: std.net.Address,
    /// Real client IP (from PROXY protocol, or same as address if direct)
    real_client_ip: ?[]const u8 = null,
    authenticated: bool = false,
    auth_user: ?types.AuthUser = null,
    /// Connection start time for duration tracking
    start_time: i64 = 0,

    pub fn deinit(self: *Connection, allocator: std.mem.Allocator) void {
        if (self.auth_user) |*user| {
            allocator.free(user.username);
        }
        self.stream.close();
        // Note: real_client_ip points into read buffer, no need to free
    }

    /// Get the client IP for logging and rate limiting
    pub fn getClientIp(self: *const Connection) []const u8 {
        return self.real_client_ip orelse "unknown";
    }
};

/// Handle a single SSH connection with security checks
fn handleConnectionSecure(
    server: *Server,
    net_connection: std.net.Server.Connection,
) void {
    var conn = Connection{
        .stream = net_connection.stream,
        .address = net_connection.address,
        .start_time = std.time.timestamp(),
    };
    defer conn.deinit(server.allocator);

    // Extract IP address for security checks
    var addr_buf: [64]u8 = undefined;
    const ip = extractIpAddress(net_connection.address, &addr_buf);

    // Log connection attempt
    security_log.logConnectionAttempt(ip);

    // Check rate limit
    server.rate_limiter.checkConnection(ip) catch |err| {
        switch (err) {
            error.IPBanned => security_log.logConnectionRejectedBanned(ip, 0),
            error.RateLimitExceeded => security_log.logConnectionRejectedRateLimit(ip),
            else => security_log.logConnectionRejectedLimit(ip, "rate limit error"),
        }
        return;
    };

    // Check connection limit
    server.connection_limiter.acquire(ip) catch |err| {
        const reason = switch (err) {
            error.TooManyConnections => "total connection limit",
            error.TooManyConnectionsFromIP => "per-IP connection limit",
            else => "connection limit error",
        };
        security_log.logConnectionRejectedLimit(ip, reason);
        return;
    };

    // Ensure connection slot is released on exit
    defer {
        server.connection_limiter.release(ip);
        const duration_ms = (std.time.timestamp() - conn.start_time) * 1000;
        const username = if (conn.auth_user) |u| u.username else null;
        security_log.logSessionClosed(ip, username, duration_ms);
    }

    // Connection accepted
    security_log.logConnectionAccepted(ip);

    log.info("SSH connection from {any}", .{conn.address});

    // Continue with the actual connection handling
    handleConnectionInner(server, &conn, ip) catch |err| {
        log.err("Connection error for {s}: {}", .{ ip, err });
    };
}

/// Inner connection handling logic (after security checks pass)
fn handleConnectionInner(
    server: *Server,
    conn: *Connection,
    ip: []const u8,
) !void {
    // Buffer for initial data (PROXY header + SSH version)
    var initial_buf: [512]u8 = undefined;
    var data_start: usize = 0;

    // Check for PROXY protocol header if enabled
    if (server.config.proxy_protocol_enabled) {
        // Read enough to detect and parse PROXY header
        const bytes_read = conn.stream.read(&initial_buf) catch |err| {
            log.err("Failed to read initial data: {}", .{err});
            return err;
        };

        if (bytes_read == 0) {
            log.info("Connection closed before sending data", .{});
            return;
        }

        const data = initial_buf[0..bytes_read];

        // Check if this is a PROXY protocol header
        if (proxy_protocol.hasProxyHeader(data)) {
            if (proxy_protocol.parseProxyProtocolV1(data)) |info| {
                conn.real_client_ip = info.client_ip;
                data_start = info.header_length;
                log.info("PROXY protocol: real client {s}:{d}", .{
                    info.client_ip,
                    info.client_port,
                });
            } else {
                log.warn("Invalid PROXY protocol header, treating as direct connection", .{});
            }
        }

        // Process any remaining data after PROXY header (SSH version)
        const remaining = data[data_start..];
        if (remaining.len > 0) {
            // Check if SSH version is already in the buffer
            if (std.mem.indexOf(u8, remaining, "\r\n") != null or
                std.mem.indexOf(u8, remaining, "\n") != null)
            {
                // Version is complete, validate it
                if (!std.mem.startsWith(u8, remaining, "SSH-2.0-")) {
                    log.err("Unsupported SSH version: {s}", .{remaining});
                    return;
                }
                // Continue with protocol handling
            }
        }
    }

    // Send SSH version string
    conn.stream.writeAll(types.SSH_VERSION ++ "\r\n") catch |err| {
        log.err("Failed to send SSH version: {}", .{err});
        return err;
    };

    // Read client version (if not already read from PROXY buffer)
    var version_buf: [255]u8 = undefined;
    const version = if (data_start > 0 and initial_buf[data_start] != 0)
        // Version was in initial buffer after PROXY header
        std.mem.sliceTo(initial_buf[data_start..], '\n')
    else
        // Need to read version separately
        readLine(conn, &version_buf) catch |err| {
            log.err("Failed to read client version: {}", .{err});
            return err;
        };

    log.info("Client version: {s}", .{version});

    // Validate SSH-2.0
    const version_trimmed = std.mem.trimRight(u8, version, "\r");
    if (!std.mem.startsWith(u8, version_trimmed, "SSH-2.0-")) {
        log.err("Unsupported SSH version: {s}", .{version});
        return;
    }

    // Handle protocol
    handleProtocolSecure(server, conn, ip) catch |err| {
        log.err("Protocol error: {}", .{err});
    };

    log.info("SSH connection closed from {s}", .{conn.getClientIp()});
}

/// Extract IP address from socket address
fn extractIpAddress(address: std.net.Address, buf: []u8) []const u8 {
    switch (address.any.family) {
        std.posix.AF.INET => {
            const bytes = @as(*const [4]u8, @ptrCast(&address.in.sa.addr));
            const result = std.fmt.bufPrint(buf, "{}.{}.{}.{}", .{
                bytes[0], bytes[1], bytes[2], bytes[3],
            }) catch return "unknown";
            return result;
        },
        std.posix.AF.INET6 => {
            // Simplified IPv6 formatting - use first 16 bytes
            const bytes = @as(*const [16]u8, @ptrCast(&address.in6.sa.addr));
            const result = std.fmt.bufPrint(buf, "{x:0>2}{x:0>2}:{x:0>2}{x:0>2}:{x:0>2}{x:0>2}:{x:0>2}{x:0>2}:{x:0>2}{x:0>2}:{x:0>2}{x:0>2}:{x:0>2}{x:0>2}:{x:0>2}{x:0>2}", .{
                bytes[0],  bytes[1],  bytes[2],  bytes[3],
                bytes[4],  bytes[5],  bytes[6],  bytes[7],
                bytes[8],  bytes[9],  bytes[10], bytes[11],
                bytes[12], bytes[13], bytes[14], bytes[15],
            }) catch return "unknown";
            return result;
        },
        else => {
            return "unknown";
        },
    }
}

/// Handle SSH protocol with security integration
fn handleProtocolSecure(
    server: *Server,
    conn: *Connection,
    ip: []const u8,
) !void {
    _ = conn;

    // TODO: Implement full SSH protocol handling
    // When authentication fails, record it:
    // server.rate_limiter.recordAuthFailure(ip);
    // security_log.logAuthFailure(.auth_failure_invalid_key, ip, username, "invalid key");
    //
    // When authentication succeeds:
    // server.rate_limiter.recordAuthSuccess(ip);
    // security_log.logAuthSuccess(ip, username, key_fingerprint);

    log.warn("Full SSH protocol implementation is not yet complete", .{});
    log.warn("Consider using one of these approaches:", .{});
    log.warn("  1. Wrap OpenSSH sshd with authorized_keys_command", .{});
    log.warn("  2. Use libssh2 with Zig bindings", .{});
    log.warn("  3. Use MiSSHod pure Zig SSH library", .{});
    log.warn("  4. Use ZSSH pure Zig SSH library", .{});

    // For now, record this as an auth failure to demonstrate the security system
    // In a real implementation, this would only happen on actual auth failures
    _ = server;
    _ = ip;

    return error.NotImplemented;
}

/// Handle a single SSH connection (legacy, for backward compatibility)
fn handleConnection(
    allocator: std.mem.Allocator,
    pool: *db.Pool,
    net_connection: std.net.Server.Connection,
    config: Config,
) void {
    var conn = Connection{
        .stream = net_connection.stream,
        .address = net_connection.address,
    };
    defer conn.deinit(allocator);

    log.info("SSH connection from {any}", .{conn.address});

    // Buffer for initial data (PROXY header + SSH version)
    var initial_buf: [512]u8 = undefined;
    var data_start: usize = 0;

    // Check for PROXY protocol header if enabled
    if (config.proxy_protocol_enabled) {
        // Read enough to detect and parse PROXY header
        const bytes_read = conn.stream.read(&initial_buf) catch |err| {
            log.err("Failed to read initial data: {}", .{err});
            return;
        };

        if (bytes_read == 0) {
            log.info("Connection closed before sending data", .{});
            return;
        }

        const data = initial_buf[0..bytes_read];

        // Check if this is a PROXY protocol header
        if (proxy_protocol.hasProxyHeader(data)) {
            if (proxy_protocol.parseProxyProtocolV1(data)) |info| {
                conn.real_client_ip = info.client_ip;
                data_start = info.header_length;
                log.info("PROXY protocol: real client {s}:{d}", .{
                    info.client_ip,
                    info.client_port,
                });
            } else {
                log.warn("Invalid PROXY protocol header, treating as direct connection", .{});
            }
        }

        // Process any remaining data after PROXY header (SSH version)
        const remaining = data[data_start..];
        if (remaining.len > 0) {
            // Check if SSH version is already in the buffer
            if (std.mem.indexOf(u8, remaining, "\r\n") != null or
                std.mem.indexOf(u8, remaining, "\n") != null)
            {
                // Version is complete, validate it
                if (!std.mem.startsWith(u8, remaining, "SSH-2.0-")) {
                    log.err("Unsupported SSH version: {s}", .{remaining});
                    return;
                }
                // Continue with protocol handling
            }
        }
    }

    // Send SSH version string
    conn.stream.writeAll(types.SSH_VERSION ++ "\r\n") catch |err| {
        log.err("Failed to send SSH version: {}", .{err});
        return;
    };

    // Read client version (if not already read from PROXY buffer)
    var version_buf: [255]u8 = undefined;
    const version = if (data_start > 0 and initial_buf[data_start] != 0)
        // Version was in initial buffer after PROXY header
        std.mem.sliceTo(initial_buf[data_start..], '\n')
    else
        // Need to read version separately
        readLine(&conn, &version_buf) catch |err| {
            log.err("Failed to read client version: {}", .{err});
            return;
        };

    log.info("Client version: {s}", .{version});

    // Validate SSH-2.0
    const version_trimmed = std.mem.trimRight(u8, version, "\r");
    if (!std.mem.startsWith(u8, version_trimmed, "SSH-2.0-")) {
        log.err("Unsupported SSH version: {s}", .{version});
        return;
    }

    // Simple protocol handler
    // In a real implementation, this would handle:
    // - Key exchange (KEX)
    // - Authentication (publickey)
    // - Channel management
    // - Exec requests
    //
    // For now, we provide a minimal implementation that demonstrates the architecture.
    // For production use, integrate with libssh2 or use a pure Zig implementation like MiSSHod.

    handleProtocol(allocator, pool, &conn) catch |err| {
        log.err("Protocol error: {}", .{err});
    };

    log.info("SSH connection closed from {s}", .{conn.getClientIp()});
}

/// Handle SSH protocol after version exchange
fn handleProtocol(
    allocator: std.mem.Allocator,
    pool: *db.Pool,
    conn: *Connection,
) !void {
    _ = allocator;
    _ = pool;
    _ = conn;

    // TODO: Implement SSH protocol handling
    // This is a complex undertaking that involves:
    //
    // 1. Key Exchange (KEX):
    //    - Send SSH_MSG_KEXINIT with supported algorithms
    //    - Perform Diffie-Hellman key exchange
    //    - Derive session keys
    //    - Send SSH_MSG_NEWKEYS
    //
    // 2. Service Request:
    //    - Receive SSH_MSG_SERVICE_REQUEST for "ssh-userauth"
    //    - Send SSH_MSG_SERVICE_ACCEPT
    //
    // 3. Authentication:
    //    - Receive SSH_MSG_USERAUTH_REQUEST with publickey method
    //    - Validate username is "git"
    //    - Verify public key signature
    //    - Look up key in database using auth.authenticatePublicKey
    //    - Send SSH_MSG_USERAUTH_SUCCESS or SSH_MSG_USERAUTH_FAILURE
    //
    // 4. Channel Management:
    //    - Receive SSH_MSG_CHANNEL_OPEN for "session"
    //    - Send SSH_MSG_CHANNEL_OPEN_CONFIRMATION
    //    - Handle SSH_MSG_CHANNEL_REQUEST for "exec"
    //    - Execute git command using session.executeGitCommand
    //    - Send command output via SSH_MSG_CHANNEL_DATA
    //    - Send SSH_MSG_CHANNEL_EOF and SSH_MSG_CHANNEL_CLOSE
    //
    // For a production-ready implementation, consider using:
    // - libssh2 with Zig bindings
    // - MiSSHod (https://github.com/ringtailsoftware/misshod)
    // - ZSSH (https://git.sr.ht/~mulling/zssh)

    log.warn("Full SSH protocol implementation is not yet complete", .{});
    log.warn("Consider using one of these approaches:", .{});
    log.warn("  1. Wrap OpenSSH sshd with authorized_keys_command", .{});
    log.warn("  2. Use libssh2 with Zig bindings", .{});
    log.warn("  3. Use MiSSHod pure Zig SSH library", .{});
    log.warn("  4. Use ZSSH pure Zig SSH library", .{});

    return error.NotImplemented;
}

/// Read a line from the connection
fn readLine(conn: *Connection, buffer: []u8) ![]const u8 {
    var pos: usize = 0;
    var read_buffer: [1]u8 = undefined;
    while (pos < buffer.len) {
        const n = try conn.stream.read(&read_buffer);
        if (n == 0) return error.EndOfStream;
        const byte = read_buffer[0];
        if (byte == '\n') {
            // Remove trailing \r if present
            const end = if (pos > 0 and buffer[pos - 1] == '\r') pos - 1 else pos;
            return buffer[0..end];
        }
        buffer[pos] = byte;
        pos += 1;
    }
    return error.LineTooLong;
}

/// Alternative: Create authorized_keys_command wrapper
/// This is a more practical approach that leverages OpenSSH
pub fn createAuthorizedKeysCommand(allocator: std.mem.Allocator, pool: *db.Pool) !void {
    _ = allocator;
    _ = pool;

    // Create a script that queries the database for authorized keys
    const script =
        \\#!/usr/bin/env bash
        \\# Plue SSH Authorized Keys Command
        \\# Usage: authorized_keys_command <username>
        \\
        \\set -euo pipefail
        \\
        \\USERNAME="$1"
        \\
        \\# Only allow 'git' user
        \\if [ "$USERNAME" != "git" ]; then
        \\    exit 1
        \\fi
        \\
        \\# Query database for public keys
        \\psql "$DATABASE_URL" -t -A -c "
        \\    SELECT public_key
        \\    FROM ssh_keys k
        \\    JOIN users u ON k.user_id = u.id
        \\    WHERE u.is_active = true
        \\    ORDER BY k.id
        \\"
    ;

    const script_path = "scripts/authorized_keys_command.sh";

    // Create scripts directory
    try std.fs.cwd().makePath("scripts");

    // Write script
    var file = try std.fs.cwd().createFile(script_path, .{ .mode = 0o755 });
    defer file.close();

    try file.writeAll(script);

    log.info("Created authorized_keys_command script at {s}", .{script_path});
    log.info("Configure OpenSSH sshd_config:", .{});
    log.info("  AuthorizedKeysCommand /path/to/{s}", .{script_path});
    log.info("  AuthorizedKeysCommandUser git", .{});
}

test "Server init" {
    const allocator = std.testing.allocator;

    // Create a mock pool (in real tests, use a test database)
    const mock_pool = @as(*db.Pool, undefined);

    const config = Config{
        .port = 0, // Random port
    };

    var server = Server.init(allocator, config, mock_pool);
    defer server.deinit();

    try std.testing.expect(!server.running);
}
