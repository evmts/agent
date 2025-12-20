//! Plue PTY - Pseudo-terminal session management
//!
//! A native Zig library for managing PTY sessions.
//! Designed to be called from Bun via FFI.

const std = @import("std");
const posix = std.posix;
const c = @cImport({
    @cInclude("util.h"); // macOS: forkpty
    @cInclude("unistd.h"); // execvp
    @cInclude("sys/wait.h");
    @cInclude("signal.h");
    @cInclude("fcntl.h");
    @cInclude("termios.h");
});

const Allocator = std.mem.Allocator;

pub const PTYError = error{
    ForkFailed,
    ExecFailed,
    SessionNotFound,
    ReadFailed,
    WriteFailed,
    InvalidSession,
    MaxSessionsReached,
};

/// PTY session state
pub const SessionState = enum(u8) {
    running = 0,
    exited = 1,
    signaled = 2,
    unknown = 3,
};

/// A single PTY session
pub const Session = struct {
    id: u32,
    pid: c_int,
    master_fd: c_int,
    state: SessionState,
    exit_code: ?i32,
    command: []const u8,
    created_at: i64,
    last_activity: i64,

    pub fn isRunning(self: *const Session) bool {
        return self.state == .running;
    }
};

/// PTY Manager - manages multiple PTY sessions
pub const PTYManager = struct {
    sessions: std.AutoHashMap(u32, *Session),
    allocator: Allocator,
    next_id: u32,
    max_sessions: u32,

    pub fn init(allocator: Allocator, max_sessions: u32) PTYManager {
        return .{
            .sessions = std.AutoHashMap(u32, *Session).init(allocator),
            .allocator = allocator,
            .next_id = 1,
            .max_sessions = max_sessions,
        };
    }

    pub fn deinit(self: *PTYManager) void {
        // Close all sessions
        var iter = self.sessions.valueIterator();
        while (iter.next()) |session_ptr| {
            const session = session_ptr.*;
            self.closeSessionInternal(session);
            self.allocator.free(session.command);
            self.allocator.destroy(session);
        }
        self.sessions.deinit();
    }

    /// Create a new PTY session
    pub fn createSession(self: *PTYManager, command: []const u8, args: ?[]const []const u8) !*Session {
        if (self.sessions.count() >= self.max_sessions) {
            return PTYError.MaxSessionsReached;
        }

        var master_fd: c_int = undefined;

        // Fork with PTY
        const pid = c.forkpty(&master_fd, null, null, null);

        if (pid < 0) {
            return PTYError.ForkFailed;
        }

        if (pid == 0) {
            // Child process
            // Build argv for execvp
            var argv_buf: [64]?[*:0]const u8 = .{null} ** 64;
            var argc: usize = 0;

            // Add command as first arg
            const cmd_z = std.heap.c_allocator.dupeZ(u8, command) catch {
                std.posix.exit(127);
            };
            argv_buf[argc] = cmd_z.ptr;
            argc += 1;

            // Add additional args
            if (args) |extra_args| {
                for (extra_args) |arg| {
                    if (argc >= argv_buf.len - 1) break;
                    const arg_z = std.heap.c_allocator.dupeZ(u8, arg) catch {
                        std.posix.exit(127);
                    };
                    argv_buf[argc] = arg_z.ptr;
                    argc += 1;
                }
            }
            argv_buf[argc] = null;

            // Execute command
            _ = c.execvp(cmd_z.ptr, @ptrCast(&argv_buf));

            // If we get here, exec failed
            std.posix.exit(127);
        }

        // Parent process
        // Set non-blocking mode on master FD
        const flags = c.fcntl(master_fd, c.F_GETFL, @as(c_int, 0));
        _ = c.fcntl(master_fd, c.F_SETFL, flags | c.O_NONBLOCK);

        const session_id = self.next_id;
        self.next_id +%= 1;

        const now = std.time.timestamp();
        const session = try self.allocator.create(Session);
        session.* = .{
            .id = session_id,
            .pid = pid,
            .master_fd = master_fd,
            .state = .running,
            .exit_code = null,
            .command = try self.allocator.dupe(u8, command),
            .created_at = now,
            .last_activity = now,
        };

        try self.sessions.put(session_id, session);
        return session;
    }

    /// Read output from a session
    pub fn readOutput(self: *PTYManager, session_id: u32, buffer: []u8) !usize {
        const session = self.sessions.get(session_id) orelse return PTYError.SessionNotFound;

        // Update process status
        self.updateStatus(session);

        const result = posix.read(@intCast(session.master_fd), buffer);
        if (result) |bytes_read| {
            session.last_activity = std.time.timestamp();
            return bytes_read;
        } else |err| {
            if (err == error.WouldBlock) {
                return 0; // No data available
            }
            return PTYError.ReadFailed;
        }
    }

    /// Write input to a session
    pub fn writeInput(self: *PTYManager, session_id: u32, data: []const u8) !usize {
        const session = self.sessions.get(session_id) orelse return PTYError.SessionNotFound;

        if (!session.isRunning()) {
            return PTYError.InvalidSession;
        }

        const result = posix.write(@intCast(session.master_fd), data);
        if (result) |bytes_written| {
            session.last_activity = std.time.timestamp();
            return bytes_written;
        } else |_| {
            return PTYError.WriteFailed;
        }
    }

    /// Get session status
    pub fn getStatus(self: *PTYManager, session_id: u32) !*Session {
        const session = self.sessions.get(session_id) orelse return PTYError.SessionNotFound;
        self.updateStatus(session);
        return session;
    }

    /// Close a session
    pub fn closeSession(self: *PTYManager, session_id: u32, force: bool) !void {
        const session = self.sessions.get(session_id) orelse return PTYError.SessionNotFound;

        if (session.isRunning()) {
            // Send signal
            const sig: c_int = if (force) c.SIGKILL else c.SIGTERM;
            _ = c.kill(session.pid, sig);

            if (!force) {
                // Wait a bit for graceful termination
                std.Thread.sleep(100 * std.time.ns_per_ms);
                self.updateStatus(session);

                if (session.isRunning()) {
                    // Force kill
                    _ = c.kill(session.pid, c.SIGKILL);
                }
            }
        }

        self.closeSessionInternal(session);
        _ = self.sessions.remove(session_id);
        self.allocator.free(session.command);
        self.allocator.destroy(session);
    }

    fn closeSessionInternal(self: *PTYManager, session: *Session) void {
        _ = self;
        // Close master FD
        posix.close(@intCast(session.master_fd));

        // Reap zombie process
        var status: c_int = 0;
        _ = c.waitpid(session.pid, &status, c.WNOHANG);
    }

    fn updateStatus(self: *PTYManager, session: *Session) void {
        _ = self;
        if (session.state != .running) return;

        var status: c_int = 0;
        const result = c.waitpid(session.pid, &status, c.WNOHANG);

        if (result == session.pid) {
            if (c.WIFEXITED(status)) {
                session.state = .exited;
                session.exit_code = c.WEXITSTATUS(status);
            } else if (c.WIFSIGNALED(status)) {
                session.state = .signaled;
                session.exit_code = c.WTERMSIG(status);
            }
        }
    }

    /// List all sessions
    pub fn listSessions(self: *PTYManager, allocator: Allocator) ![]const *Session {
        var list = std.ArrayList(*Session).init(allocator);
        errdefer list.deinit();

        var iter = self.sessions.valueIterator();
        while (iter.next()) |session_ptr| {
            self.updateStatus(session_ptr.*);
            try list.append(session_ptr.*);
        }

        return list.toOwnedSlice();
    }

    /// Get session count
    pub fn sessionCount(self: *PTYManager) u32 {
        return @intCast(self.sessions.count());
    }
};

// ============================================================================
// C FFI Interface for Bun
// ============================================================================

var global_manager: ?*PTYManager = null;
var gpa = std.heap.GeneralPurposeAllocator(.{}){};

/// Initialize the PTY manager
export fn pty_init(max_sessions: u32) bool {
    if (global_manager != null) return true;

    const allocator = gpa.allocator();
    const manager = allocator.create(PTYManager) catch return false;
    manager.* = PTYManager.init(allocator, max_sessions);
    global_manager = manager;
    return true;
}

/// Cleanup the PTY manager
export fn pty_cleanup() void {
    if (global_manager) |manager| {
        manager.deinit();
        gpa.allocator().destroy(manager);
        global_manager = null;
    }
}

/// Create a new PTY session
export fn pty_create_session(command: [*:0]const u8) i32 {
    const manager = global_manager orelse return -1;
    const session = manager.createSession(std.mem.span(command), null) catch return -1;
    return @intCast(session.id);
}

/// Read output from a session
export fn pty_read(session_id: u32, buffer: [*]u8, buffer_len: usize) i32 {
    const manager = global_manager orelse return -1;
    const bytes = manager.readOutput(session_id, buffer[0..buffer_len]) catch return -1;
    return @intCast(bytes);
}

/// Write input to a session
export fn pty_write(session_id: u32, data: [*]const u8, data_len: usize) i32 {
    const manager = global_manager orelse return -1;
    const bytes = manager.writeInput(session_id, data[0..data_len]) catch return -1;
    return @intCast(bytes);
}

/// Check if session is running
export fn pty_is_running(session_id: u32) bool {
    const manager = global_manager orelse return false;
    const session = manager.getStatus(session_id) catch return false;
    return session.isRunning();
}

/// Get session exit code (-1 if still running or not found)
export fn pty_exit_code(session_id: u32) i32 {
    const manager = global_manager orelse return -1;
    const session = manager.getStatus(session_id) catch return -1;
    return session.exit_code orelse -1;
}

/// Close a session
export fn pty_close(session_id: u32, force: bool) bool {
    const manager = global_manager orelse return false;
    manager.closeSession(session_id, force) catch return false;
    return true;
}

/// Get number of active sessions
export fn pty_session_count() u32 {
    const manager = global_manager orelse return 0;
    return manager.sessionCount();
}
