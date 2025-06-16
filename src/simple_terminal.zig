const std = @import("std");
const builtin = @import("builtin");

// Simple terminal implementation inspired by libghostty patterns
// Cross-platform support for macOS and Linux

// Terminal configuration
pub const Config = struct {
    cols: u16 = 80,
    rows: u16 = 24,
    shell: []const u8 = if (builtin.os.tag == .macos) "/bin/zsh" else "/bin/bash",
};

// Terminal state
pub const Terminal = struct {
    // Core state
    master_fd: ?std.posix.fd_t = null,
    child_pid: ?std.posix.pid_t = null,
    config: Config,
    
    // Output buffer for display
    output_buffer: std.ArrayList(u8),
    
    // Allocator
    allocator: std.mem.Allocator,
    
    const Self = @This();
    
    /// Create a new terminal instance
    pub fn init(allocator: std.mem.Allocator, config: Config) !*Self {
        const terminal = try allocator.create(Self);
        terminal.* = .{
            .config = config,
            .output_buffer = std.ArrayList(u8).init(allocator),
            .allocator = allocator,
        };
        return terminal;
    }
    
    /// Cleanup and free resources
    pub fn deinit(self: *Self) void {
        self.stop();
        self.output_buffer.deinit();
        self.allocator.destroy(self);
    }
    
    /// Start the terminal with a shell
    pub fn start(self: *Self) !void {
        // Create pseudo-terminal
        const pty_result = try self.createPty();
        self.master_fd = pty_result.master;
        
        // Fork process
        const pid = try std.posix.fork();
        
        if (pid == 0) {
            // Child process - set up shell
            try self.setupChild(pty_result.slave);
        } else {
            // Parent process
            self.child_pid = pid;
            std.posix.close(pty_result.slave);
            
            // Set non-blocking mode on master
            if (builtin.os.tag == .macos or builtin.os.tag == .linux) {
                const flags = try std.os.fcntl(self.master_fd.?, std.os.F.GETFL, 0);
                // O_NONBLOCK = 0x0004 on macOS
                const nonblock_flag: c_int = if (builtin.os.tag == .macos) 0x0004 else std.os.O.NONBLOCK;
                _ = try std.os.fcntl(self.master_fd.?, std.os.F.SETFL, flags | nonblock_flag);
            }
        }
    }
    
    /// Stop the terminal
    pub fn stop(self: *Self) void {
        // Kill child process
        if (self.child_pid) |pid| {
            _ = std.posix.kill(pid, std.posix.SIG.TERM) catch {};
            _ = std.posix.waitpid(pid, 0);
            self.child_pid = null;
        }
        
        // Close master FD
        if (self.master_fd) |fd| {
            std.posix.close(fd);
            self.master_fd = null;
        }
    }
    
    /// Write data to the terminal
    pub fn write(self: *Self, data: []const u8) !usize {
        if (self.master_fd) |fd| {
            return try std.posix.write(fd, data);
        }
        return 0;
    }
    
    /// Read available data from terminal
    pub fn read(self: *Self, buffer: []u8) !usize {
        if (self.master_fd) |fd| {
            return std.posix.read(fd, buffer) catch |err| switch (err) {
                error.WouldBlock => return 0,
                else => return err,
            };
        }
        return 0;
    }
    
    /// Process terminal output and update buffer
    pub fn processOutput(self: *Self) !bool {
        var temp_buffer: [4096]u8 = undefined;
        const bytes_read = try self.read(&temp_buffer);
        
        if (bytes_read > 0) {
            try self.output_buffer.appendSlice(temp_buffer[0..bytes_read]);
            return true;
        }
        return false;
    }
    
    /// Get output buffer contents
    pub fn getOutput(self: *Self) []const u8 {
        return self.output_buffer.items;
    }
    
    /// Clear output buffer
    pub fn clearOutput(self: *Self) void {
        self.output_buffer.clearRetainingCapacity();
    }
    
    /// Resize terminal
    pub fn resize(self: *Self, cols: u16, rows: u16) !void {
        self.config.cols = cols;
        self.config.rows = rows;
        
        if (self.master_fd) |fd| {
            if (builtin.os.tag == .macos or builtin.os.tag == .linux) {
                var ws = std.posix.winsize{
                    .row = rows,
                    .col = cols,
                    .xpixel = 0,
                    .ypixel = 0,
                };
                if (builtin.os.tag == .macos) {
                    // TIOCSWINSZ = 0x80087467 on macOS
                    _ = std.c.ioctl(fd, @bitCast(@as(c_int, -2147199097)), @intFromPtr(&ws));
                } else {
                    _ = std.c.ioctl(fd, @as(c_uint, 0x5414), @intFromPtr(&ws));
                }
            }
        }
    }
    
    // Private helper methods
    
    const PtyResult = struct {
        master: std.posix.fd_t,
        slave: std.posix.fd_t,
    };
    
    fn createPty(self: *Self) !PtyResult {
        _ = self;
        
        if (builtin.os.tag == .macos) {
            // macOS: Use openpty
            var master: std.posix.fd_t = undefined;
            var slave: std.posix.fd_t = undefined;
            
            // On macOS, use open to create PTY
            master = std.posix.open("/dev/ptmx", .{ .ACCMODE = .RDWR }, 0) catch return error.PtyCreationFailed;
            
            // Unlock slave
            var unlock: c_int = 0;
            // TIOCSPTLCK = 0x40045431
            _ = std.c.ioctl(master, @as(c_uint, 0x40045431), @intFromPtr(&unlock));
            
            // Get slave number
            var pts_num: c_int = undefined;
            // TIOCGPTN = 0x80045430
            _ = std.c.ioctl(master, @bitCast(@as(c_int, -2147216336)), @intFromPtr(&pts_num));
            
            // Open slave
            var pts_name_buf: [32]u8 = undefined;
            const pts_name = try std.fmt.bufPrint(&pts_name_buf, "/dev/pts/{d}", .{pts_num});
            slave = try std.posix.open(pts_name, .{ .ACCMODE = .RDWR }, 0);
            
            return PtyResult{ .master = master, .slave = slave };
        } else {
            // Linux: Use /dev/ptmx
            const master = try std.posix.open("/dev/ptmx", .{ .ACCMODE = .RDWR }, 0);
            
            // Unlock slave
            var unlock: c_int = 0;
            // TIOCSPTLCK = 0x40045431
            _ = std.c.ioctl(master, @as(c_uint, 0x40045431), @intFromPtr(&unlock));
            
            // Get slave number
            var pts_num: c_int = undefined;
            // TIOCGPTN = 0x80045430
            _ = std.c.ioctl(master, @bitCast(@as(c_int, -2147216336)), @intFromPtr(&pts_num));
            
            // Open slave
            var pts_name_buf: [32]u8 = undefined;
            const pts_name = try std.fmt.bufPrint(&pts_name_buf, "/dev/pts/{d}", .{pts_num});
            const slave = try std.posix.open(pts_name, .{ .ACCMODE = .RDWR }, 0);
            
            return PtyResult{ .master = master, .slave = slave };
        }
    }
    
    fn setupChild(self: *Self, slave_fd: std.posix.fd_t) !void {
        // Create new session
        _ = std.os.system.setsid();
        
        // Set slave as controlling terminal
        if (builtin.os.tag == .macos) {
            // TIOCSCTTY = 0x20007461 on macOS
            _ = std.os.system.ioctl(slave_fd, 0x20007461, 0);
        } else if (builtin.os.tag == .linux) {
            _ = std.os.system.ioctl(slave_fd, std.os.system.T.IOCSCTTY, 0);
        }
        
        // Duplicate slave to stdin/stdout/stderr
        try std.os.dup2(slave_fd, std.os.STDIN_FILENO);
        try std.os.dup2(slave_fd, std.os.STDOUT_FILENO);
        try std.os.dup2(slave_fd, std.os.STDERR_FILENO);
        
        // Close original slave fd
        if (slave_fd > 2) {
            std.os.close(slave_fd);
        }
        
        // Set terminal size
        var ws = std.posix.winsize{
            .row = self.config.rows,
            .col = self.config.cols,
            .xpixel = 0,
            .ypixel = 0,
        };
        if (builtin.os.tag == .macos) {
            // TIOCSWINSZ = 0x80087467 on macOS
            _ = std.c.ioctl(std.posix.STDIN_FILENO, @bitCast(@as(c_int, -2147199097)), @intFromPtr(&ws));
        } else {
            // Linux TIOCSWINSZ
            _ = std.c.ioctl(std.posix.STDIN_FILENO, @as(c_uint, 0x5414), @intFromPtr(&ws));
        }
        
        // Execute shell
        const argv = [_:null]?[*:0]const u8{
            self.config.shell,
            null,
        };
        
        const envp = [_:null]?[*:0]const u8{
            "TERM=xterm-256color",
            "PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            null,
        };
        
        _ = std.os.execvpeZ(self.config.shell, &argv, &envp) catch std.os.exit(1);
    }
};

// Global state for C FFI
var global_terminal: ?*Terminal = null;
var global_allocator = std.heap.GeneralPurposeAllocator(.{}){};

// C FFI exports for Swift

export fn simple_terminal_init() c_int {
    if (global_terminal != null) return 0;
    
    const allocator = global_allocator.allocator();
    
    global_terminal = Terminal.init(allocator, .{}) catch |err| {
        std.log.err("Failed to initialize terminal: {}", .{err});
        return -1;
    };
    
    return 0;
}

export fn simple_terminal_start() c_int {
    if (global_terminal) |terminal| {
        terminal.start() catch |err| {
            std.log.err("Failed to start terminal: {}", .{err});
            return -1;
        };
        return 0;
    }
    return -1;
}

export fn simple_terminal_stop() void {
    if (global_terminal) |terminal| {
        terminal.deinit();
        global_terminal = null;
    }
}

export fn simple_terminal_write(text: [*:0]const u8) c_int {
    if (global_terminal) |terminal| {
        const data = std.mem.span(text);
        _ = terminal.write(data) catch |err| {
            std.log.err("Failed to write: {}", .{err});
            return -1;
        };
        return 0;
    }
    return -1;
}

export fn simple_terminal_process() c_int {
    if (global_terminal) |terminal| {
        _ = terminal.processOutput() catch |err| {
            std.log.err("Failed to process output: {}", .{err});
            return -1;
        };
        return 0;
    }
    return -1;
}

export fn simple_terminal_get_output(buffer: [*]u8, size: usize) usize {
    if (global_terminal) |terminal| {
        const output = terminal.getOutput();
        const copy_size = @min(output.len, size);
        @memcpy(buffer[0..copy_size], output[0..copy_size]);
        return copy_size;
    }
    return 0;
}

export fn simple_terminal_clear() void {
    if (global_terminal) |terminal| {
        terminal.clearOutput();
    }
}

export fn simple_terminal_resize(cols: u16, rows: u16) c_int {
    if (global_terminal) |terminal| {
        terminal.resize(cols, rows) catch |err| {
            std.log.err("Failed to resize: {}", .{err});
            return -1;
        };
        return 0;
    }
    return -1;
}