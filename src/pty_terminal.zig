const std = @import("std");
const builtin = @import("builtin");

// PTY Terminal implementation using standard process spawning
// This provides a terminal-like interface for running shell commands

const PtyState = struct {
    process: ?std.process.Child = null,
    initialized: bool = false,
    running: bool = false,
    allocator: std.mem.Allocator,
};

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var pty_state: ?PtyState = null;

/// Initialize the PTY terminal
export fn pty_terminal_init() c_int {
    if (pty_state != null and pty_state.?.initialized) return 0;
    
    const allocator = gpa.allocator();
    pty_state = PtyState{
        .allocator = allocator,
        .initialized = true,
    };
    
    std.log.info("PTY terminal initialized", .{});
    return 0;
}

/// Start the PTY terminal with a shell
export fn pty_terminal_start() c_int {
    const state = &(pty_state orelse return -1);
    if (!state.initialized or state.running) return -1;
    
    // Get shell from environment or use default
    const shell = std.process.getEnvVarOwned(state.allocator, "SHELL") catch blk: {
        break :blk state.allocator.dupe(u8, "/bin/bash") catch return -1;
    };
    defer state.allocator.free(shell);
    
    // Create process with pipes for stdin/stdout/stderr
    var process = std.process.Child.init(&.{shell}, state.allocator);
    process.stdin_behavior = .Pipe;
    process.stdout_behavior = .Pipe;
    process.stderr_behavior = .Pipe;
    
    // Set environment to indicate we're in a terminal
    var env_map = std.process.getEnvMap(state.allocator) catch return -1;
    defer env_map.deinit();
    env_map.put("TERM", "xterm-256color") catch return -1;
    process.env_map = &env_map;
    
    // Spawn the process
    process.spawn() catch |err| {
        std.log.err("Failed to spawn shell process: {}", .{err});
        return -1;
    };
    
    // Set non-blocking on stdout/stderr
    if (process.stdout) |stdout| {
        const flags = std.posix.fcntl(stdout.handle, std.posix.F.GETFL, 0) catch 0;
        // O_NONBLOCK = 0x0004 on macOS
        _ = std.posix.fcntl(stdout.handle, std.posix.F.SETFL, flags | 0x0004) catch {};
    }
    if (process.stderr) |stderr| {
        const flags = std.posix.fcntl(stderr.handle, std.posix.F.GETFL, 0) catch 0;
        // O_NONBLOCK = 0x0004 on macOS
        _ = std.posix.fcntl(stderr.handle, std.posix.F.SETFL, flags | 0x0004) catch {};
    }
    
    state.process = process;
    state.running = true;
    
    std.log.info("PTY terminal started with shell: {s}", .{shell});
    return 0;
}

/// Stop the PTY terminal
export fn pty_terminal_stop() void {
    const state = &(pty_state orelse return);
    if (!state.running) return;
    
    if (state.process) |*proc| {
        // Close pipes
        if (proc.stdin) |*stdin| stdin.close();
        if (proc.stdout) |*stdout| stdout.close(); 
        if (proc.stderr) |*stderr| stderr.close();
        
        // Terminate the process
        _ = proc.kill() catch {};
        _ = proc.wait() catch {};
        
        state.process = null;
    }
    
    state.running = false;
    std.log.info("PTY terminal stopped", .{});
}

/// Write data to the PTY
export fn pty_terminal_write(data: [*]const u8, len: usize) isize {
    const state = &(pty_state orelse return -1);
    if (!state.running or state.process == null) return -1;
    
    if (state.process.?.stdin) |stdin| {
        stdin.writeAll(data[0..len]) catch |err| {
            std.log.err("Failed to write to PTY: {}", .{err});
            return -1;
        };
        return @intCast(len);
    }
    
    return -1;
}

/// Read data from the PTY
export fn pty_terminal_read(buffer: [*]u8, buffer_len: usize) isize {
    const state = &(pty_state orelse return -1);
    if (!state.running or state.process == null) return -1;
    
    var total_read: usize = 0;
    
    // Try to read from stdout first
    if (state.process.?.stdout) |stdout| {
        const bytes_read = stdout.read(buffer[0..buffer_len]) catch |err| {
            if (err == error.WouldBlock) return 0;
            std.log.err("Failed to read from PTY stdout: {}", .{err});
            return -1;
        };
        total_read += bytes_read;
    }
    
    // Also check stderr (if there's room)
    if (total_read < buffer_len) {
        if (state.process.?.stderr) |stderr| {
            const remaining = buffer_len - total_read;
            const bytes_read = stderr.read(buffer[total_read..][0..remaining]) catch |err| {
                if (err != error.WouldBlock) {
                    std.log.err("Failed to read from PTY stderr: {}", .{err});
                }
                // Don't fail the whole operation for stderr errors
                return @intCast(total_read);
            };
            total_read += bytes_read;
        }
    }
    
    return @intCast(total_read);
}

/// Send text to the PTY (convenience function)
export fn pty_terminal_send_text(text: [*:0]const u8) void {
    const len = std.mem.len(text);
    _ = pty_terminal_write(@ptrCast(text), len);
}

/// Resize the PTY (not supported in this implementation)
export fn pty_terminal_resize(cols: u16, rows: u16) void {
    // This implementation doesn't support true PTY resizing
    // since we're using pipes instead of a real PTY
    _ = cols;
    _ = rows;
}

/// Deinitialize the PTY terminal
export fn pty_terminal_deinit() void {
    pty_terminal_stop();
    pty_state = null;
    _ = gpa.deinit();
}