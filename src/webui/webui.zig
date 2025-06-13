const std = @import("std");

pub const Error = error{
    ShowError,
};

/// Wrapper around the webui lib
/// C library for creating native apps using webviews or browsers
/// C library for creating native apps using webviews or browsers
const Window = @This();

window: usize,

pub extern fn webui_new_window() callconv(.C) usize;
pub fn init() Window {
    return .{
        .window = webui_new_window(),
    };
}

pub extern fn webui_clean() callconv(.C) void;
pub fn deinit(self: *Window) void {
    _ = self;
    webui_clean();
}

pub extern fn webui_show(window: usize, content: [*:0]const u8) callconv(.C) bool;
pub fn show(self: Window, content: [:0]const u8) Error!void {
    const success = webui_show(self.window, content.ptr);
    if (!success) return Error.ShowError;
}

pub extern fn webui_wait() callconv(.C) void;
pub fn wait(self: Window) void {
    _ = self;
    webui_wait();
}

// Adapted from https://github.com/webui-dev/zig-webui
pub extern fn webui_set_file_handler(
    window: usize,
    handler: *const fn (filename: [*:0]const u8, length: *c_int) callconv(.C) ?*const anyopaque,
) callconv(.C) void;
pub fn set_file_handler(self: *Window, comptime handler: fn (filename: []const u8) ?[]const u8) void {
    const handle_struct = struct {
        fn handle(tmp_filename: [*:0]const u8, length: *c_int) callconv(.C) ?*const anyopaque {
            const len = std.mem.len(tmp_filename);
            const content = handler(tmp_filename[0..len]);
            if (content) |val| {
                length.* = @intCast(val.len);
                return @ptrCast(val.ptr);
            }

            return null;
        }
    };
    webui_set_file_handler(self.window, handle_struct.handle);
}
