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
const db = @import("../lib/db.zig");

const log = std.log.scoped(.ssh_server);

/// SSH Server Configuration
pub const Config = struct {
    /// SSH server host address
    host: []const u8 = "0.0.0.0",
    /// SSH server port
    port: u16 = 2222,
    /// Path to SSH host key (RSA)
    host_key_path: []const u8 = "data/ssh_host_key",
    /// Maximum connections
    max_connections: usize = 100,
};

/// SSH Server
pub const Server = struct {
    allocator: std.mem.Allocator,
    config: Config,
    pool: *db.Pool,
    listener: ?std.net.Server = null,
    running: bool = false,

    pub fn init(allocator: std.mem.Allocator, config: Config, pool: *db.Pool) Server {
        return .{
            .allocator = allocator,
            .config = config,
            .pool = pool,
        };
    }

    pub fn deinit(self: *Server) void {
        if (self.listener) |*listener| {
            listener.deinit();
        }
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

        log.info("SSH server listening on {s}:{d}", .{ self.config.host, self.config.port });
        log.info("Note: This is a simplified implementation for git operations", .{});
        log.info("For production use, consider using a full SSH implementation", .{});

        // Accept connections
        while (self.running) {
            const connection = self.listener.?.accept() catch |err| {
                log.err("Accept failed: {}", .{err});
                continue;
            };

            // Handle connection in a new thread
            const thread = try std.Thread.spawn(.{}, handleConnection, .{
                self.allocator,
                self.pool,
                connection,
            });
            thread.detach();
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
    address: std.net.Address,
    authenticated: bool = false,
    auth_user: ?types.AuthUser = null,

    pub fn deinit(self: *Connection, allocator: std.mem.Allocator) void {
        if (self.auth_user) |*user| {
            allocator.free(user.username);
        }
        self.stream.close();
    }
};

/// Handle a single SSH connection
fn handleConnection(
    allocator: std.mem.Allocator,
    pool: *db.Pool,
    net_connection: std.net.Server.Connection,
) void {
    var conn = Connection{
        .stream = net_connection.stream,
        .address = net_connection.address,
    };
    defer conn.deinit(allocator);

    log.info("SSH connection from {}", .{conn.address});

    // Send SSH version string
    conn.stream.writeAll(types.SSH_VERSION ++ "\r\n") catch |err| {
        log.err("Failed to send SSH version: {}", .{err});
        return;
    };

    // Read client version
    var version_buf: [255]u8 = undefined;
    const version = readLine(&conn, &version_buf) catch |err| {
        log.err("Failed to read client version: {}", .{err});
        return;
    };

    log.info("Client version: {s}", .{version});

    // Validate SSH-2.0
    if (!std.mem.startsWith(u8, version, "SSH-2.0-")) {
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

    log.info("SSH connection closed from {}", .{conn.address});
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
    while (pos < buffer.len) {
        const byte = try conn.stream.reader().readByte();
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
    var mock_pool = @as(*db.Pool, undefined);

    const config = Config{
        .port = 0, // Random port
    };

    var server = Server.init(allocator, config, mock_pool);
    defer server.deinit();

    try std.testing.expect(!server.running);
}
