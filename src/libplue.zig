const std = @import("std");
const ghostty_terminal = @import("ghostty_terminal");
const mini_terminal = @import("mini_terminal");
const pty_terminal = @import("pty_terminal");

/// Simple global state - just use GPA directly
var gpa = std.heap.GeneralPurposeAllocator(.{}){};

/// Initialize the global state
export fn plue_init() c_int {
    return 0;
}

/// Cleanup all resources
export fn plue_deinit() void {
    _ = gpa.deinit();
}

/// Process message and return response
/// Returns: owned null-terminated string - caller MUST call plue_free_string()
export fn plue_process_message(message: ?[*:0]const u8) ?[*:0]const u8 {
    const msg_ptr = message orelse return null;
    const msg = std.mem.span(msg_ptr);
    if (msg.len == 0 or msg.len > 10 * 1024) {
        return null;
    }
    const allocator = gpa.allocator();
    const response = std.fmt.allocPrintZ(allocator, "Echo: {s}", .{msg}) catch @panic("Unable to allocate memory");
    return response.ptr;
}

/// Free string allocated by plue_process_message
export fn plue_free_string(str: [*:0]const u8) void {
    gpa.allocator().free(std.mem.span(str));
}

// Re-export Ghostty terminal functions for Swift FFI
pub usingnamespace ghostty_terminal;

// Re-export mini terminal functions for Swift FFI
pub usingnamespace mini_terminal;

// Re-export PTY terminal functions for Swift FFI
pub usingnamespace pty_terminal;
