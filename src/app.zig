const std = @import("std");
const Window = @import("webui/webui.zig");
const assets = @import("assets.zig");

const App = @This();

window: Window,

pub fn init() App {
    const window = Window.init();
    return App{ .window = window };
}

pub fn deinit(self: App) void {
    self.window.clean();
}

pub fn handler(filename: []const u8) ?[]const u8 {
    const asset = assets.get_asset(filename) orelse assets.not_found_asset;
    return asset.response;
}

pub fn run(self: *App) !void {
    self.window.set_file_handler(handler);
    try self.window.show("index.html");
    self.window.wait();
}
