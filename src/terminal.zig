const std = @import("std");
const c = @cImport({
    @cInclude("unistd.h");
    @cInclude("termios.h");
    @cInclude("sys/ioctl.h");
    @cInclude("util.h");
    @cInclude("signal.h");
});

// Terminal state
var master_fd: c_int = -1;
var slave_fd: c_int = -1;
var pid: c.pid_t = -1;
var initialized = false;

/// Initialize terminal
pub fn terminal_init() c_int {
    if (initialized) return 0;
    initialized = true;
    return 0;
}

/// Start terminal
pub fn terminal_start() c_int {
    if (master_fd >= 0) return 0;
    
    // Create pseudo-terminal
    var winsize = c.winsize{
        .ws_row = 24,
        .ws_col = 80,
        .ws_xpixel = 0,
        .ws_ypixel = 0,
    };
    
    pid = c.forkpty(&master_fd, null, null, &winsize);
    if (pid < 0) {
        return -1;
    }
    
    if (pid == 0) {
        // Child process - exec shell
        const shell_args = [_:null]?[*:0]const u8{ "/bin/zsh", "-l", null };
        _ = c.execvp("/bin/zsh", @ptrCast(&shell_args));
        std.c.exit(1);
    }
    
    return 0;
}

/// Stop terminal
pub fn terminal_stop() void {
    if (master_fd >= 0) {
        _ = c.close(master_fd);
        master_fd = -1;
    }
    if (pid > 0) {
        _ = c.kill(pid, c.SIGTERM);
        pid = -1;
    }
}

/// Deinitialize terminal
pub fn terminal_deinit() void {
    terminal_stop();
    initialized = false;
}

/// Send text to terminal
pub fn terminal_send_text(text: [*:0]const u8) void {
    if (master_fd < 0) return;
    
    const len = std.mem.len(text);
    _ = c.write(master_fd, text, len);
}

/// Resize terminal
pub fn terminal_resize(cols: c_ushort, rows: c_ushort) void {
    if (master_fd < 0) return;
    
    var winsize = c.winsize{
        .ws_row = rows,
        .ws_col = cols,
        .ws_xpixel = 0,
        .ws_ypixel = 0,
    };
    
    _ = c.ioctl(master_fd, c.TIOCSWINSZ, &winsize);
}

/// Get terminal file descriptor
pub fn terminal_get_fd() c_int {
    return master_fd;
}

/// Read from terminal
pub fn terminal_read(buffer: [*]u8, size: usize) isize {
    if (master_fd < 0) return -1;
    return @intCast(c.read(master_fd, buffer, size));
}