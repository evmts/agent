const std = @import("std");
const builtin = @import("builtin");

// Minimal terminal implementation using libghostty patterns
// This is a simplified version focusing only on core terminal functionality

// Terminal configuration options
pub const TerminalConfig = struct {
    width: u32 = 80,
    height: u32 = 24,
    font_size: f64 = 14.0,
    shell: []const u8 = if (builtin.os.tag == .macos) "/bin/zsh" else "/bin/bash",
};

// Terminal state structure
pub const Terminal = struct {
    // Core components
    pty: ?std.os.fd_t = null,
    config: TerminalConfig,
    
    // Terminal buffer state
    buffer: std.ArrayList(u8),
    cursor_x: u32 = 0,
    cursor_y: u32 = 0,
    
    // Process management
    child_pid: ?std.os.pid_t = null,
    
    // Allocator
    allocator: std.mem.Allocator,
    
    const Self = @This();
    
    /// Initialize a new terminal instance
    pub fn init(allocator: std.mem.Allocator, config: TerminalConfig) !*Self {
        var terminal = try allocator.create(Self);
        terminal.* = .{
            .config = config,
            .buffer = std.ArrayList(u8).init(allocator),
            .allocator = allocator,
        };
        
        // Reserve buffer space
        try terminal.buffer.ensureTotalCapacity(config.width * config.height);
        
        return terminal;
    }
    
    /// Deinitialize and free resources
    pub fn deinit(self: *Self) void {
        self.stop();
        self.buffer.deinit();
        self.allocator.destroy(self);
    }
    
    /// Start the terminal with a shell process
    pub fn start(self: *Self) !void {
        // Create a PTY (pseudo-terminal)
        var master: std.os.fd_t = undefined;
        var slave: std.os.fd_t = undefined;
        
        // Open PTY master/slave pair
        try self.openPty(&master, &slave);
        self.pty = master;
        
        // Fork and exec shell
        const pid = try std.os.fork();
        if (pid == 0) {
            // Child process
            _ = std.os.linux.close(master);
            
            // Set up slave as stdin/stdout/stderr
            _ = std.os.linux.dup2(slave, 0);
            _ = std.os.linux.dup2(slave, 1);
            _ = std.os.linux.dup2(slave, 2);
            _ = std.os.linux.close(slave);
            
            // Execute shell
            const argv = [_][*:0]const u8{
                self.config.shell.ptr,
                null,
            };
            _ = std.os.linux.execve(self.config.shell.ptr, &argv, std.os.environ.ptr);
            std.os.exit(1); // If exec fails
        } else {
            // Parent process
            self.child_pid = pid;
            _ = std.os.linux.close(slave);
        }
    }
    
    /// Stop the terminal and cleanup
    pub fn stop(self: *Self) void {
        if (self.child_pid) |pid| {
            _ = std.os.linux.kill(pid, std.os.linux.SIG.TERM);
            _ = std.os.waitpid(pid, 0);
            self.child_pid = null;
        }
        
        if (self.pty) |fd| {
            std.os.close(fd);
            self.pty = null;
        }
    }
    
    /// Write data to the terminal
    pub fn write(self: *Self, data: []const u8) !usize {
        if (self.pty) |fd| {
            return try std.os.write(fd, data);
        }
        return 0;
    }
    
    /// Read data from the terminal
    pub fn read(self: *Self, buffer: []u8) !usize {
        if (self.pty) |fd| {
            // Non-blocking read
            return std.os.read(fd, buffer) catch |err| switch (err) {
                error.WouldBlock => return 0,
                else => return err,
            };
        }
        return 0;
    }
    
    /// Process terminal output and update buffer
    pub fn processOutput(self: *Self) !void {
        var temp_buffer: [4096]u8 = undefined;
        const bytes_read = try self.read(&temp_buffer);
        
        if (bytes_read > 0) {
            // For now, just append to buffer
            // In a real implementation, we'd parse ANSI escape sequences
            try self.buffer.appendSlice(temp_buffer[0..bytes_read]);
            
            // Simple newline handling
            for (temp_buffer[0..bytes_read]) |byte| {
                if (byte == '\n') {
                    self.cursor_y += 1;
                    self.cursor_x = 0;
                } else if (byte == '\r') {
                    self.cursor_x = 0;
                } else {
                    self.cursor_x += 1;
                    if (self.cursor_x >= self.config.width) {
                        self.cursor_x = 0;
                        self.cursor_y += 1;
                    }
                }
            }
        }
    }
    
    /// Get the terminal buffer as a string
    pub fn getBuffer(self: *Self) []const u8 {
        return self.buffer.items;
    }
    
    /// Clear the terminal buffer
    pub fn clear(self: *Self) void {
        self.buffer.clearRetainingCapacity();
        self.cursor_x = 0;
        self.cursor_y = 0;
    }
    
    /// Set terminal size
    pub fn setSize(self: *Self, width: u32, height: u32) !void {
        self.config.width = width;
        self.config.height = height;
        
        // Update PTY size if active
        if (self.pty) |fd| {
            var ws = std.os.linux.winsize{
                .ws_row = @intCast(height),
                .ws_col = @intCast(width),
                .ws_xpixel = 0,
                .ws_ypixel = 0,
            };
            _ = std.os.linux.ioctl(fd, std.os.linux.T.IOCSWINSZ, @intFromPtr(&ws));
        }
    }
    
    // Helper function to open PTY
    fn openPty(self: *Self, master: *std.os.fd_t, slave: *std.os.fd_t) !void {
        _ = self;
        
        // Open master PTY
        const master_fd = try std.os.open("/dev/ptmx", .{ .ACCMODE = .RDWR }, 0);
        master.* = master_fd;
        
        // Unlock slave
        var unlock: c_int = 0;
        _ = std.os.linux.ioctl(master_fd, std.os.linux.T.IOCSPTLCK, @intFromPtr(&unlock));
        
        // Get slave number
        var pts_num: c_int = undefined;
        _ = std.os.linux.ioctl(master_fd, std.os.linux.T.IOCGPTN, @intFromPtr(&pts_num));
        
        // Open slave
        var pts_name_buf: [32]u8 = undefined;
        const pts_name = try std.fmt.bufPrint(&pts_name_buf, "/dev/pts/{d}", .{pts_num});
        slave.* = try std.os.open(pts_name, .{ .ACCMODE = .RDWR }, 0);
    }
};

// Global terminal instance
var global_terminal: ?*Terminal = null;
var global_allocator = std.heap.GeneralPurposeAllocator(.{}){};

// C-compatible exported functions for Swift FFI

/// Initialize the minimal terminal
export fn minimal_terminal_init() c_int {
    if (global_terminal != null) return 0;
    
    const allocator = global_allocator.allocator();
    const config = TerminalConfig{};
    
    global_terminal = Terminal.init(allocator, config) catch |err| {
        std.log.err("Failed to initialize terminal: {}", .{err});
        return -1;
    };
    
    std.log.info("Minimal terminal initialized", .{});
    return 0;
}

/// Start the terminal with shell
export fn minimal_terminal_start() c_int {
    if (global_terminal) |terminal| {
        terminal.start() catch |err| {
            std.log.err("Failed to start terminal: {}", .{err});
            return -1;
        };
        std.log.info("Terminal started", .{});
        return 0;
    }
    return -1;
}

/// Stop and cleanup terminal
export fn minimal_terminal_stop() void {
    if (global_terminal) |terminal| {
        terminal.deinit();
        global_terminal = null;
        std.log.info("Terminal stopped", .{});
    }
}

/// Write text to terminal
export fn minimal_terminal_write(text: [*:0]const u8) c_int {
    if (global_terminal) |terminal| {
        const data = std.mem.span(text);
        _ = terminal.write(data) catch |err| {
            std.log.err("Failed to write to terminal: {}", .{err});
            return -1;
        };
        return 0;
    }
    return -1;
}

/// Read and process terminal output
export fn minimal_terminal_process() c_int {
    if (global_terminal) |terminal| {
        terminal.processOutput() catch |err| {
            std.log.err("Failed to process terminal output: {}", .{err});
            return -1;
        };
        return 0;
    }
    return -1;
}

/// Get terminal buffer content
export fn minimal_terminal_get_buffer(buffer: [*]u8, buffer_size: usize) usize {
    if (global_terminal) |terminal| {
        const content = terminal.getBuffer();
        const copy_size = @min(content.len, buffer_size);
        @memcpy(buffer[0..copy_size], content[0..copy_size]);
        return copy_size;
    }
    return 0;
}

/// Clear terminal buffer
export fn minimal_terminal_clear() void {
    if (global_terminal) |terminal| {
        terminal.clear();
    }
}

/// Set terminal size
export fn minimal_terminal_set_size(width: c_uint, height: c_uint) c_int {
    if (global_terminal) |terminal| {
        terminal.setSize(@intCast(width), @intCast(height)) catch |err| {
            std.log.err("Failed to set terminal size: {}", .{err});
            return -1;
        };
        return 0;
    }
    return -1;
}