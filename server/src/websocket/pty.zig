const std = @import("std");
const posix = std.posix;

const log = std.log.scoped(.pty);

// External C function for ptsname
extern "c" fn ptsname(fd: c_int) [*:0]const u8;

pub const PtyError = error{
    SessionNotFound,
    SessionAlreadyExists,
    ForkFailed,
    OpenPtyFailed,
    ExecFailed,
    InvalidState,
    WriteError,
    ReadError,
};

pub const SessionInfo = struct {
    id: []const u8,
    command: []const u8,
    workdir: []const u8,
    pid: i32,
    running: bool,
};

/// PTY session that manages a pseudo-terminal and shell process
pub const Session = struct {
    id: []const u8,
    command: []const u8,
    workdir: []const u8,
    master_fd: posix.fd_t,
    slave_fd: posix.fd_t,
    pid: std.posix.pid_t,
    running: bool,
    allocator: std.mem.Allocator,
    // Buffer for reading output
    read_buffer: [4096]u8,

    pub fn init(
        allocator: std.mem.Allocator,
        id: []const u8,
        command: []const u8,
        workdir: []const u8,
    ) !*Session {
        // Open pseudo-terminal
        var master: posix.fd_t = undefined;
        var slave: posix.fd_t = undefined;

        // Try to open PTY using openpt
        master = posix.open("/dev/ptmx", .{ .ACCMODE = .RDWR, .NOCTTY = true }, 0) catch |err| {
            log.err("Failed to open /dev/ptmx: {}", .{err});
            return PtyError.OpenPtyFailed;
        };
        errdefer posix.close(master);

        // Grant access to slave PTY
        // Note: grantpt/unlockpt are handled automatically on macOS when opening /dev/ptmx

        // Get slave PTY name
        const slave_name_ptr = ptsname(@intCast(master));
        const slave_name_slice = std.mem.span(slave_name_ptr);

        // Open slave PTY
        slave = posix.open(slave_name_slice, .{ .ACCMODE = .RDWR, .NOCTTY = true }, 0) catch |err| {
            log.err("Failed to open slave PTY {s}: {}", .{ slave_name_slice, err });
            return PtyError.OpenPtyFailed;
        };
        errdefer posix.close(slave);

        // Set master FD to non-blocking mode
        const O_NONBLOCK: u32 = 0x0004; // macOS O_NONBLOCK flag
        const flags = posix.fcntl(master, posix.F.GETFL, 0) catch 0;
        _ = posix.fcntl(master, posix.F.SETFL, flags | O_NONBLOCK) catch {};

        // Fork the process
        const pid = posix.fork() catch |err| {
            log.err("Fork failed: {}", .{err});
            return PtyError.ForkFailed;
        };

        if (pid == 0) {
            // Child process
            childProcess(slave, command, workdir) catch {
                posix.exit(1);
            };
            unreachable;
        }

        // Parent process
        posix.close(slave);

        const session = try allocator.create(Session);
        session.* = .{
            .id = try allocator.dupe(u8, id),
            .command = try allocator.dupe(u8, command),
            .workdir = try allocator.dupe(u8, workdir),
            .master_fd = master,
            .slave_fd = -1, // Closed in parent
            .pid = pid,
            .running = true,
            .allocator = allocator,
            .read_buffer = undefined,
        };

        log.info("PTY session created: id={s}, pid={d}, command={s}", .{ id, pid, command });

        return session;
    }

    pub fn deinit(self: *Session) void {
        if (self.master_fd >= 0) {
            posix.close(self.master_fd);
        }
        self.allocator.free(self.id);
        self.allocator.free(self.command);
        self.allocator.free(self.workdir);
        self.allocator.destroy(self);
    }

    /// Write input to the PTY
    pub fn write(self: *Session, data: []const u8) !void {
        if (!self.running) {
            return PtyError.InvalidState;
        }

        const written = posix.write(self.master_fd, data) catch |err| {
            log.err("Failed to write to PTY: {}", .{err});
            return PtyError.WriteError;
        };

        if (written != data.len) {
            log.warn("Partial write to PTY: {d}/{d} bytes", .{ written, data.len });
        }
    }

    /// Read output from the PTY (non-blocking)
    pub fn read(self: *Session) !?[]const u8 {
        if (!self.running) {
            return null;
        }

        const bytes_read = posix.read(self.master_fd, &self.read_buffer) catch |err| {
            if (err == error.WouldBlock) {
                return null;
            }
            log.err("Failed to read from PTY: {}", .{err});
            return PtyError.ReadError;
        };

        if (bytes_read == 0) {
            return null;
        }

        return self.read_buffer[0..bytes_read];
    }

    /// Check if the process is still running
    pub fn checkStatus(self: *Session) void {
        if (!self.running) return;

        const result = posix.waitpid(self.pid, posix.W.NOHANG);

        if (result.pid == self.pid) {
            self.running = false;
            log.info("PTY process exited: pid={d}, status={}", .{ self.pid, result.status });
        }
    }

    /// Resize the PTY terminal
    pub fn resize(self: *Session, cols: u16, rows: u16) !void {
        if (!self.running) {
            return PtyError.InvalidState;
        }

        // Define winsize struct for ioctl
        const winsize = extern struct {
            ws_row: u16,
            ws_col: u16,
            ws_xpixel: u16,
            ws_ypixel: u16,
        };

        const ws = winsize{
            .ws_row = rows,
            .ws_col = cols,
            .ws_xpixel = 0,
            .ws_ypixel = 0,
        };

        // TIOCSWINSZ ioctl constant for macOS
        const TIOCSWINSZ: c_int = @bitCast(@as(u32, 0x80087467));

        const result = std.c.ioctl(self.master_fd, TIOCSWINSZ, @intFromPtr(&ws));
        if (result < 0) {
            log.err("Failed to resize PTY: ioctl returned {d}", .{result});
            return error.ResizeFailed;
        }

        log.info("PTY resized: id={s}, cols={d}, rows={d}", .{ self.id, cols, rows });
    }

    /// Terminate the PTY process
    pub fn terminate(self: *Session) !void {
        if (!self.running) return;

        // Send SIGTERM
        posix.kill(self.pid, posix.SIG.TERM) catch |err| {
            log.err("Failed to send SIGTERM to pid {d}: {}", .{ self.pid, err });
        };

        // Wait a bit for graceful shutdown
        std.Thread.sleep(100 * std.time.ns_per_ms);

        // Check if still running
        self.checkStatus();

        if (self.running) {
            // Send SIGKILL if still running
            posix.kill(self.pid, posix.SIG.KILL) catch |err| {
                log.err("Failed to send SIGKILL to pid {d}: {}", .{ self.pid, err });
            };

            // Wait for process to exit
            _ = posix.waitpid(self.pid, 0);
            self.running = false;
        }
    }
};

/// Child process setup for PTY
fn childProcess(slave_fd: posix.fd_t, command: []const u8, workdir: []const u8) !void {
    // Create new session
    _ = std.c.setsid();

    // Set controlling terminal (using raw ioctl)
    const TIOCSCTTY: u32 = 0x20007461; // macOS value
    _ = std.c.ioctl(slave_fd, TIOCSCTTY, @as(c_int, 0));

    // Redirect stdin, stdout, stderr to slave PTY
    try posix.dup2(slave_fd, posix.STDIN_FILENO);
    try posix.dup2(slave_fd, posix.STDOUT_FILENO);
    try posix.dup2(slave_fd, posix.STDERR_FILENO);

    if (slave_fd > 2) {
        posix.close(slave_fd);
    }

    // Change working directory
    posix.chdir(workdir) catch |err| {
        log.err("Failed to chdir to {s}: {}", .{ workdir, err });
    };

    // Execute shell
    const shell = std.process.getEnvVarOwned(std.heap.page_allocator, "SHELL") catch "/bin/bash";
    defer std.heap.page_allocator.free(shell);

    // Build argv - shell with -c and command
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const argv: [*:null]?[*:0]const u8 = @ptrCast(try alloc.alloc(?[*:0]const u8, 4));
    const argv_slice: []?[*:0]const u8 = @constCast(argv[0..4]);
    argv_slice[0] = try alloc.dupeZ(u8, shell);
    argv_slice[1] = try alloc.dupeZ(u8, "-c");
    argv_slice[2] = try alloc.dupeZ(u8, command);
    argv_slice[3] = null;

    // Use execve with default environment
    const err = posix.execveZ(argv_slice[0].?, argv, @ptrCast(std.c.environ));
    log.err("Failed to exec {s}: {}", .{ shell, err });
    return PtyError.ExecFailed;
}

/// PTY session manager
pub const Manager = struct {
    allocator: std.mem.Allocator,
    sessions: std.StringHashMap(*Session),
    mutex: std.Thread.Mutex,
    next_id: usize,

    pub fn init(allocator: std.mem.Allocator) Manager {
        return .{
            .allocator = allocator,
            .sessions = std.StringHashMap(*Session).init(allocator),
            .mutex = .{},
            .next_id = 1,
        };
    }

    pub fn deinit(self: *Manager) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var it = self.sessions.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.*.terminate() catch {};
            entry.value_ptr.*.deinit();
        }
        self.sessions.deinit();
    }

    /// Create a new PTY session
    pub fn createSession(
        self: *Manager,
        command: []const u8,
        workdir: []const u8,
    ) !*Session {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Generate session ID
        const id = try std.fmt.allocPrint(self.allocator, "pty-{d}", .{self.next_id});
        defer self.allocator.free(id);
        self.next_id += 1;

        // Check if session already exists (shouldn't happen with sequential IDs)
        if (self.sessions.contains(id)) {
            return PtyError.SessionAlreadyExists;
        }

        // Create session
        const session = try Session.init(self.allocator, id, command, workdir);
        errdefer session.deinit();

        // Store session
        try self.sessions.put(session.id, session);

        return session;
    }

    /// Get a session by ID
    pub fn getSession(self: *Manager, id: []const u8) !*Session {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.sessions.get(id) orelse PtyError.SessionNotFound;
    }

    /// Close a session
    pub fn closeSession(self: *Manager, id: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const session = self.sessions.get(id) orelse return PtyError.SessionNotFound;

        // Remove from map
        _ = self.sessions.remove(id);

        // Terminate and cleanup
        try session.terminate();
        session.deinit();

        log.info("PTY session closed: id={s}", .{id});
    }

    /// List all sessions
    pub fn listSessions(self: *Manager, allocator: std.mem.Allocator) ![]SessionInfo {
        self.mutex.lock();
        defer self.mutex.unlock();

        var list = std.ArrayList(SessionInfo){};

        var it = self.sessions.iterator();
        while (it.next()) |entry| {
            const session = entry.value_ptr.*;
            session.checkStatus();

            try list.append(allocator, .{
                .id = session.id,
                .command = session.command,
                .workdir = session.workdir,
                .pid = session.pid,
                .running = session.running,
            });
        }

        return list.toOwnedSlice(allocator);
    }

    /// Cleanup dead sessions
    pub fn cleanupDeadSessions(self: *Manager) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var to_remove: std.ArrayList([]const u8) = .init(self.allocator);

        var it = self.sessions.iterator();
        while (it.next()) |entry| {
            const session = entry.value_ptr.*;
            session.checkStatus();

            if (!session.running) {
                to_remove.append(session.id) catch continue;
            }
        }

        for (to_remove.items) |id| {
            if (self.sessions.fetchRemove(id)) |kv| {
                kv.value.deinit();
            }
        }
    }
};

test "PTY session manager" {
    var manager = Manager.init(std.testing.allocator);
    defer manager.deinit();

    // Create session
    const session = try manager.createSession("echo 'Hello, PTY!'", "/tmp");
    try std.testing.expect(session.running);

    // Wait a bit for command to execute
    std.Thread.sleep(100 * std.time.ns_per_ms);

    // Read output
    var output: std.ArrayList(u8) = .init(std.testing.allocator);

    for (0..10) |_| {
        if (try session.read()) |data| {
            try output.appendSlice(data);
        }
        std.time.sleep(50 * std.time.ns_per_ms);
    }

    // Check we got some output
    try std.testing.expect(output.items.len > 0);

    // Close session
    try manager.closeSession(session.id);
}
