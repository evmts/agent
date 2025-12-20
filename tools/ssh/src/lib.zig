//! Plue SSH Server - Git operations over SSH
//!
//! A native Zig library for SSH server functionality using libssh.
//! Designed to be called from Bun via FFI.

const std = @import("std");
const posix = std.posix;
const Allocator = std.mem.Allocator;

// libssh C bindings
const c = @cImport({
    @cInclude("libssh/libssh.h");
    @cInclude("libssh/server.h");
    @cInclude("libssh/callbacks.h");
});

pub const SSHError = error{
    InitFailed,
    BindFailed,
    KeyLoadFailed,
    AcceptFailed,
    AuthFailed,
    ChannelFailed,
    SessionFailed,
    NotInitialized,
    MaxConnectionsReached,
};

/// SSH session state
pub const SessionState = enum(u8) {
    connected = 0,
    authenticated = 1,
    channel_open = 2,
    executing = 3,
    closed = 4,
};

/// Authentication callback type - called from Zig, implemented in JS
pub const AuthCallback = *const fn (
    username: [*:0]const u8,
    pubkey_base64: [*:0]const u8,
) callconv(.c) bool;

/// SSH Server configuration
pub const ServerConfig = struct {
    port: u16,
    host_key_path: []const u8,
    max_connections: u32,
};

/// SSH Server Manager
pub const SSHServer = struct {
    bind: c.ssh_bind,
    config: ServerConfig,
    running: bool,
    connection_count: u32,
    auth_callback: ?AuthCallback,
    allocator: Allocator,
    server_thread: ?std.Thread,

    pub fn init(allocator: Allocator, config: ServerConfig) !*SSHServer {
        // Initialize libssh
        if (c.ssh_init() != 0) {
            return SSHError.InitFailed;
        }

        // Create bind object
        const bind = c.ssh_bind_new() orelse return SSHError.InitFailed;
        errdefer c.ssh_bind_free(bind);

        // Set options
        const port: c_int = @intCast(config.port);
        if (c.ssh_bind_options_set(bind, c.SSH_BIND_OPTIONS_BINDPORT, &port) != 0) {
            return SSHError.BindFailed;
        }

        // Load host key
        const key_path_z = try allocator.dupeZ(u8, config.host_key_path);
        defer allocator.free(key_path_z);

        if (c.ssh_bind_options_set(bind, c.SSH_BIND_OPTIONS_HOSTKEY, key_path_z.ptr) != 0) {
            return SSHError.KeyLoadFailed;
        }

        const server = try allocator.create(SSHServer);
        server.* = .{
            .bind = bind,
            .config = config,
            .running = false,
            .connection_count = 0,
            .auth_callback = null,
            .allocator = allocator,
            .server_thread = null,
        };

        return server;
    }

    pub fn deinit(self: *SSHServer) void {
        self.stop();
        c.ssh_bind_free(self.bind);
        _ = c.ssh_finalize();
        self.allocator.destroy(self);
    }

    pub fn setAuthCallback(self: *SSHServer, callback: AuthCallback) void {
        self.auth_callback = callback;
    }

    pub fn start(self: *SSHServer) !void {
        if (self.running) return;

        // Listen for connections
        if (c.ssh_bind_listen(self.bind) != 0) {
            return SSHError.BindFailed;
        }

        self.running = true;

        // Start accept loop in background thread
        self.server_thread = std.Thread.spawn(.{}, acceptLoop, .{self}) catch |err| {
            self.running = false;
            return err;
        };
    }

    pub fn stop(self: *SSHServer) void {
        if (!self.running) return;
        self.running = false;

        // Wait for server thread to finish
        if (self.server_thread) |thread| {
            thread.join();
            self.server_thread = null;
        }
    }

    fn acceptLoop(self: *SSHServer) void {
        while (self.running) {
            // Create new session
            const session = c.ssh_new() orelse continue;
            defer c.ssh_free(session);

            // Accept incoming connection (with timeout)
            if (c.ssh_bind_accept(self.bind, session) != c.SSH_OK) {
                continue;
            }

            if (self.connection_count >= self.config.max_connections) {
                c.ssh_disconnect(session);
                continue;
            }

            // Handle connection in current thread (simplified)
            // In production, spawn thread per connection
            self.connection_count += 1;
            self.handleConnection(session);
            self.connection_count -= 1;
        }
    }

    fn handleConnection(self: *SSHServer, session: c.ssh_session) void {
        // Perform key exchange
        if (c.ssh_handle_key_exchange(session) != c.SSH_OK) {
            return;
        }

        // Authenticate
        if (!self.authenticateSession(session)) {
            return;
        }

        // Handle channel requests
        self.handleChannels(session);

        c.ssh_disconnect(session);
    }

    fn authenticateSession(self: *SSHServer, session: c.ssh_session) bool {
        var auth_attempts: u32 = 0;
        const max_attempts: u32 = 3;

        while (auth_attempts < max_attempts) {
            const msg = c.ssh_message_get(session);
            if (msg == null) break;
            defer c.ssh_message_free(msg);

            if (c.ssh_message_type(msg) != c.SSH_REQUEST_AUTH) {
                _ = c.ssh_message_reply_default(msg);
                continue;
            }

            const subtype = c.ssh_message_subtype(msg);

            if (subtype == c.SSH_AUTH_METHOD_PUBLICKEY) {
                const username = c.ssh_message_auth_user(msg);
                const pubkey = c.ssh_message_auth_pubkey(msg);

                if (username != null and pubkey != null) {
                    // Get pubkey as base64
                    var pubkey_b64: [*c]u8 = null;
                    if (c.ssh_pki_export_pubkey_base64(pubkey, &pubkey_b64) == c.SSH_OK) {
                        defer c.ssh_string_free_char(pubkey_b64);

                        // Call auth callback if set
                        if (self.auth_callback) |callback| {
                            if (callback(username, pubkey_b64)) {
                                _ = c.ssh_message_auth_reply_success(msg, 0);
                                return true;
                            }
                        }
                    }
                }
            }

            // Auth failed, request again
            _ = c.ssh_message_auth_set_methods(msg, c.SSH_AUTH_METHOD_PUBLICKEY);
            _ = c.ssh_message_reply_default(msg);
            auth_attempts += 1;
        }

        return false;
    }

    fn handleChannels(self: *SSHServer, session: c.ssh_session) void {
        _ = self;

        // Wait for channel open request
        var channel: c.ssh_channel = null;
        var msg = c.ssh_message_get(session);
        while (msg != null) {
            defer c.ssh_message_free(msg);

            if (c.ssh_message_type(msg) == c.SSH_REQUEST_CHANNEL_OPEN) {
                channel = c.ssh_message_channel_request_open_reply_accept(msg);
                if (channel != null) {
                    break;
                }
            }
            _ = c.ssh_message_reply_default(msg);
            msg = c.ssh_message_get(session);
        }

        if (channel == null) return;
        defer c.ssh_channel_free(channel);

        // Wait for exec request
        msg = c.ssh_message_get(session);
        while (msg != null) {
            defer c.ssh_message_free(msg);

            if (c.ssh_message_type(msg) == c.SSH_REQUEST_CHANNEL) {
                const subtype = c.ssh_message_subtype(msg);
                if (subtype == c.SSH_CHANNEL_REQUEST_EXEC) {
                    const command = c.ssh_message_channel_request_command(msg);
                    if (command != null) {
                        _ = c.ssh_message_channel_request_reply_success(msg);
                        executeGitCommand(channel, std.mem.span(command));
                        return;
                    }
                }
            }
            _ = c.ssh_message_reply_default(msg);
            msg = c.ssh_message_get(session);
        }
    }

    pub fn getConnectionCount(self: *SSHServer) u32 {
        return self.connection_count;
    }
};

/// Execute a git command and pipe I/O through the SSH channel
fn executeGitCommand(channel: c.ssh_channel, command: []const u8) void {
    // Parse command - expect "git-upload-pack 'repo'" or "git-receive-pack 'repo'"
    var iter = std.mem.splitSequence(u8, command, " ");
    const cmd = iter.first();

    // Only allow git commands
    if (!std.mem.startsWith(u8, cmd, "git-upload-pack") and
        !std.mem.startsWith(u8, cmd, "git-receive-pack"))
    {
        const err_msg = "Error: Only git commands are allowed\n";
        _ = c.ssh_channel_write(channel, err_msg.ptr, @intCast(err_msg.len));
        _ = c.ssh_channel_send_eof(channel);
        return;
    }

    // Get repository path
    const repo_path = iter.rest();
    if (repo_path.len == 0) {
        const err_msg = "Error: Repository path required\n";
        _ = c.ssh_channel_write(channel, err_msg.ptr, @intCast(err_msg.len));
        _ = c.ssh_channel_send_eof(channel);
        return;
    }

    // Execute git command using fork/exec
    const pid = std.posix.fork() catch {
        const err_msg = "Error: Failed to fork process\n";
        _ = c.ssh_channel_write(channel, err_msg.ptr, @intCast(err_msg.len));
        _ = c.ssh_channel_send_eof(channel);
        return;
    };

    if (pid == 0) {
        // Child process - exec git command
        // This is a simplified version - in production, set up proper pipes
        const result = std.process.Child.run(.{
            .allocator = std.heap.page_allocator,
            .argv = &.{ cmd, repo_path },
        }) catch {
            std.posix.exit(127);
        };
        _ = result;
        std.posix.exit(0);
    } else {
        // Parent - wait for child and send output
        const status = std.posix.waitpid(pid, 0);
        _ = status;
        _ = c.ssh_channel_send_eof(channel);
    }
}

// ============================================================================
// C FFI Interface for Bun
// ============================================================================

var global_server: ?*SSHServer = null;
var gpa = std.heap.GeneralPurposeAllocator(.{}){};

/// Initialize the SSH server
export fn ssh_server_init(port: u16, host_key_path: [*:0]const u8, max_connections: u32) bool {
    if (global_server != null) return true;

    const allocator = gpa.allocator();
    const config = ServerConfig{
        .port = port,
        .host_key_path = std.mem.span(host_key_path),
        .max_connections = max_connections,
    };

    global_server = SSHServer.init(allocator, config) catch return false;
    return true;
}

/// Set authentication callback
export fn ssh_server_set_auth_callback(callback: AuthCallback) void {
    if (global_server) |server| {
        server.setAuthCallback(callback);
    }
}

/// Start the SSH server
export fn ssh_server_start() bool {
    const server = global_server orelse return false;
    server.start() catch return false;
    return true;
}

/// Stop the SSH server
export fn ssh_server_stop() void {
    if (global_server) |server| {
        server.stop();
    }
}

/// Cleanup the SSH server
export fn ssh_server_cleanup() void {
    const allocator = gpa.allocator();
    if (global_server) |server| {
        server.deinit();
        _ = allocator;
        global_server = null;
    }
}

/// Get current connection count
export fn ssh_server_connection_count() u32 {
    const server = global_server orelse return 0;
    return server.getConnectionCount();
}

/// Check if server is running
export fn ssh_server_is_running() bool {
    const server = global_server orelse return false;
    return server.running;
}

// ============================================================================
// Tests
// ============================================================================

test "libssh initialization" {
    // Test that libssh can be initialized
    const result = c.ssh_init();
    try std.testing.expectEqual(@as(c_int, 0), result);
    _ = c.ssh_finalize();
}

test "server config parsing" {
    const config = ServerConfig{
        .port = 2222,
        .host_key_path = "/path/to/key",
        .max_connections = 100,
    };

    try std.testing.expectEqual(@as(u16, 2222), config.port);
    try std.testing.expectEqual(@as(u32, 100), config.max_connections);
}
