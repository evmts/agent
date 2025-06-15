const std = @import("std");

// Mini terminal - simplified terminal emulator inspired by libghostty
// Uses Zig's ChildProcess for cross-platform compatibility

pub const MiniTerminal = struct {
    allocator: std.mem.Allocator,
    process: ?std.process.Child = null,
    output_buffer: std.ArrayList(u8),
    input_buffer: std.ArrayList(u8),
    
    // Terminal dimensions
    cols: u16 = 80,
    rows: u16 = 24,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator) !*Self {
        const terminal = try allocator.create(Self);
        terminal.* = .{
            .allocator = allocator,
            .output_buffer = std.ArrayList(u8).init(allocator),
            .input_buffer = std.ArrayList(u8).init(allocator),
        };
        return terminal;
    }
    
    pub fn deinit(self: *Self) void {
        self.stop();
        self.output_buffer.deinit();
        self.input_buffer.deinit();
        self.allocator.destroy(self);
    }
    
    pub fn start(self: *Self) !void {
        if (self.process != null) return;
        
        // Create child process with shell
        var child = std.process.Child.init(&.{"/bin/sh"}, self.allocator);
        
        // Set up pipes for communication
        child.stdin_behavior = .Pipe;
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;
        
        // Spawn the process
        try child.spawn();
        self.process = child;
        
        // Set non-blocking mode on stdout and stderr
        if (self.process) |*proc| {
            if (proc.stdout) |stdout| {
                const flags = try std.posix.fcntl(stdout.handle, std.posix.F.GETFL, 0);
                _ = try std.posix.fcntl(stdout.handle, std.posix.F.SETFL, flags | 0x0004); // O_NONBLOCK = 0x0004 on macOS
            }
            if (proc.stderr) |stderr| {
                const flags = try std.posix.fcntl(stderr.handle, std.posix.F.GETFL, 0);
                _ = try std.posix.fcntl(stderr.handle, std.posix.F.SETFL, flags | 0x0004); // O_NONBLOCK = 0x0004 on macOS
            }
        }
        
        std.log.info("Terminal process started", .{});
    }
    
    pub fn stop(self: *Self) void {
        if (self.process) |*proc| {
            _ = proc.kill() catch {};
            self.process = null;
        }
    }
    
    pub fn write(self: *Self, data: []const u8) !void {
        if (self.process) |*proc| {
            if (proc.stdin) |stdin| {
                try stdin.writeAll(data);
            }
        }
    }
    
    pub fn read(self: *Self) ![]const u8 {
        self.output_buffer.clearRetainingCapacity();
        
        if (self.process) |*proc| {
            // Read from stdout
            if (proc.stdout) |stdout| {
                var buf: [1024]u8 = undefined;
                const n = stdout.read(&buf) catch |err| switch (err) {
                    error.WouldBlock => 0,
                    else => return err,
                };
                if (n > 0) {
                    try self.output_buffer.appendSlice(buf[0..n]);
                }
            }
            
            // Read from stderr
            if (proc.stderr) |stderr| {
                var buf: [1024]u8 = undefined;
                const n = stderr.read(&buf) catch |err| switch (err) {
                    error.WouldBlock => 0,
                    else => return err,
                };
                if (n > 0) {
                    try self.output_buffer.appendSlice(buf[0..n]);
                }
            }
        }
        
        return self.output_buffer.items;
    }
    
    pub fn sendCommand(self: *Self, cmd: []const u8) !void {
        try self.write(cmd);
        try self.write("\n");
    }
    
    pub fn resize(self: *Self, cols: u16, rows: u16) void {
        self.cols = cols;
        self.rows = rows;
        // Note: Real terminal would send SIGWINCH to process
    }
};

// Global instance for FFI
var g_terminal: ?*MiniTerminal = null;
var g_allocator = std.heap.GeneralPurposeAllocator(.{}){};

// FFI exports

export fn mini_terminal_init() c_int {
    if (g_terminal != null) return 0;
    
    const allocator = g_allocator.allocator();
    g_terminal = MiniTerminal.init(allocator) catch {
        return -1;
    };
    return 0;
}

export fn mini_terminal_start() c_int {
    if (g_terminal) |term| {
        term.start() catch return -1;
        return 0;
    }
    return -1;
}

export fn mini_terminal_stop() void {
    if (g_terminal) |term| {
        term.deinit();
        g_terminal = null;
    }
}

export fn mini_terminal_write(text: [*:0]const u8) c_int {
    if (g_terminal) |term| {
        const data = std.mem.span(text);
        term.write(data) catch return -1;
        return 0;
    }
    return -1;
}

export fn mini_terminal_read(buffer: [*]u8, size: usize) usize {
    if (g_terminal) |term| {
        const output = term.read() catch return 0;
        const copy_size = @min(output.len, size);
        @memcpy(buffer[0..copy_size], output[0..copy_size]);
        return copy_size;
    }
    return 0;
}

export fn mini_terminal_send_command(cmd: [*:0]const u8) c_int {
    if (g_terminal) |term| {
        const data = std.mem.span(cmd);
        term.sendCommand(data) catch return -1;
        return 0;
    }
    return -1;
}