const std = @import("std");
const app_module = @import("app.zig");

pub fn main() !void {
    app_module.App.init();
    app_module.App.run();
}
