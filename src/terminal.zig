const std = @import("std");
const builtin = @import("builtin");

// Minimal PTY implementation for macOS that actually works
// Uses posix_openpt which is available in Zig's standard library

// Error codes for better error handling
pub const PtyError = enum(c_int) {
    SUCCESS = 0,
    ALREADY_INITIALIZED = -1,
    NOT_INITIALIZED = -2,
    ALREADY_RUNNING = -3,
    NOT_RUNNING = -4,
    OPEN_FAILED = -5,
    FORK_FAILED = -6,
    EXEC_FAILED = -7,
    READ_ERROR = -8,
    WRITE_ERROR = -9,
    INVALID_FD = -10,
};

const PtyState = struct {
    master_fd: ?std.posix.fd_t = null,
    slave_fd: ?std.posix.fd_t = null,
    child_pid: ?std.posix.pid_t = null,
    initialized: bool = false,
    running: bool = false,
};

var pty_state = PtyState{};
var gpa = std.heap.GeneralPurposeAllocator(.{}){};

// Thread-safe access mutex
var pty_mutex = std.Thread.Mutex{};

// macOS specific constants
const TIOCPTYGRANT: c_uint = 0x20007454;
const TIOCPTYUNLK: c_uint = 0x20007452;
const TIOCSCTTY: c_uint = 0x20007461;

/// Initialize the PTY
export fn terminal_init() c_int {
    if (pty_state.initialized) return 0;
    
    pty_state.initialized = true;
    std.log.info("PTY initialized", .{});
    return 0;
}

/// Start the PTY with a shell
export fn terminal_start() c_int {
    if (!pty_state.initialized or pty_state.running) return -1;
    
    // On macOS, use /dev/ptmx directly
    const master_fd = std.posix.open("/dev/ptmx", .{ .ACCMODE = .RDWR }, 0) catch |err| {
        std.log.err("Failed to open PTY master: {}", .{err});
        return -1;
    };
    
    // Use ioctl to grant and unlock - macOS specific
    // TIOCPTYGRANT
    _ = std.c.ioctl(master_fd, TIOCPTYGRANT, @as(c_int, 0));
    
    // TIOCPTYUNLK
    _ = std.c.ioctl(master_fd, TIOCPTYUNLK, @as(c_int, 0));
    
    // Get slave name using ioctl
    var slave_name_buf: [128]u8 = undefined;
    // TIOCPTYGNAME = 0x40807453
    if (std.c.ioctl(master_fd, 0x40807453, &slave_name_buf) != 0) {
        std.log.err("Failed to get PTY slave name", .{});
        _ = std.posix.close(master_fd);
        return -1;
    }
    
    // Find null terminator
    const slave_name_len = std.mem.indexOfScalar(u8, &slave_name_buf, 0) orelse slave_name_buf.len;
    const slave_name = slave_name_buf[0..slave_name_len];
    
    // Open slave
    const slave_fd = std.posix.open(slave_name, .{ .ACCMODE = .RDWR }, 0) catch |err| {
        std.log.err("Failed to open PTY slave: {}", .{err});
        _ = std.posix.close(master_fd);
        return -1;
    };
    
    // Fork child process
    const pid = std.posix.fork() catch |err| {
        std.log.err("Failed to fork: {}", .{err});
        _ = std.posix.close(master_fd);
        _ = std.posix.close(slave_fd);
        return -1;
    };
    
    if (pid == 0) {
        // Child process
        _ = std.posix.close(master_fd);
        
        // Create new session
        // setsid is not exposed in std.c, we need to declare it
        const c = @cImport({
            @cInclude("unistd.h");
        });
        _ = c.setsid();
        
        // Make slave the controlling terminal
        _ = std.c.ioctl(slave_fd, TIOCSCTTY, @as(c_int, 0));
        
        // Set up standard I/O
        _ = std.posix.dup2(slave_fd, std.posix.STDIN_FILENO) catch {};
        _ = std.posix.dup2(slave_fd, std.posix.STDOUT_FILENO) catch {};
        _ = std.posix.dup2(slave_fd, std.posix.STDERR_FILENO) catch {};
        
        if (slave_fd > 2) {
            _ = std.posix.close(slave_fd);
        }
        
        // Get shell from environment or use default
        const shell = std.posix.getenv("SHELL") orelse "/bin/zsh";
        
        // Execute shell
        const argv = [_:null]?[*:0]const u8{ shell, null };
        _ = std.posix.execveZ(shell, &argv, std.c.environ) catch {
            std.log.err("Failed to exec shell", .{});
            std.posix.exit(1);
        };
    }
    
    // Parent process
    _ = std.posix.close(slave_fd);
    
    // Set non-blocking mode on master
    const flags = std.posix.fcntl(master_fd, std.posix.F.GETFL, 0) catch 0;
    _ = std.posix.fcntl(master_fd, std.posix.F.SETFL, flags | 0x0004) catch {}; // O_NONBLOCK
    
    pty_state.master_fd = master_fd;
    pty_state.child_pid = pid;
    pty_state.running = true;
    
    std.log.info("macOS PTY started with PID {}", .{pid});
    return 0;
}

/// Stop the PTY
export fn terminal_stop() void {
    if (!pty_state.running) return;
    
    // Close master FD
    if (pty_state.master_fd) |fd| {
        _ = std.posix.close(fd);
        pty_state.master_fd = null;
    }
    
    // Kill child process
    if (pty_state.child_pid) |pid| {
        _ = std.posix.kill(pid, std.posix.SIG.TERM) catch {};
        _ = std.posix.waitpid(pid, 0);
        pty_state.child_pid = null;
    }
    
    pty_state.running = false;
    std.log.info("macOS PTY stopped", .{});
}

/// Write data to the PTY
export fn terminal_write(data: [*]const u8, len: usize) isize {
    pty_mutex.lock();
    defer pty_mutex.unlock();
    
    if (!pty_state.running or pty_state.master_fd == null) return -1;
    
    const bytes_written = std.posix.write(pty_state.master_fd.?, data[0..len]) catch |err| {
        std.log.err("Failed to write to PTY: {}", .{err});
        return -1;
    };
    
    return @intCast(bytes_written);
}

/// Read data from the PTY
export fn terminal_read(buffer: [*]u8, buffer_len: usize) isize {
    pty_mutex.lock();
    defer pty_mutex.unlock();
    
    if (!pty_state.running or pty_state.master_fd == null) return -1;
    
    const bytes_read = std.posix.read(pty_state.master_fd.?, buffer[0..buffer_len]) catch |err| {
        if (err == error.WouldBlock) return 0;
        std.log.err("Failed to read from PTY: {}", .{err});
        return -1;
    };
    
    return @intCast(bytes_read);
}

/// Send text to the PTY
export fn terminal_send_text(text: [*:0]const u8) void {
    const len = std.mem.len(text);
    _ = terminal_write(@ptrCast(text), len);
}

/// Get the master file descriptor
export fn terminal_get_fd() c_int {
    if (pty_state.master_fd) |fd| {
        return @intCast(fd);
    }
    return -1;
}

/// Resize the PTY
export fn terminal_resize(cols: u16, rows: u16) void {
    if (!pty_state.running or pty_state.master_fd == null) return;
    
    // Create winsize struct
    const winsize = extern struct {
        ws_row: u16,
        ws_col: u16,
        ws_xpixel: u16,
        ws_ypixel: u16,
    };
    
    var ws = winsize{
        .ws_row = rows,
        .ws_col = cols,
        .ws_xpixel = 0,
        .ws_ypixel = 0,
    };
    
    // TIOCSWINSZ = 0x80087467 on macOS
    // Cast to signed int to avoid overflow
    const TIOCSWINSZ = @as(c_int, @bitCast(@as(u32, 0x80087467)));
    _ = std.c.ioctl(pty_state.master_fd.?, TIOCSWINSZ, &ws);
    
    std.log.info("PTY resized to {}x{}", .{ cols, rows });
}

/// Deinitialize the PTY
export fn terminal_deinit() void {
    terminal_stop();
    pty_state = PtyState{};
    _ = gpa.deinit();
}

