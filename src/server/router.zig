const std = @import("std");
const zap = @import("zap");

// Route handler that wraps error handling
pub fn callHandler(r: zap.Request, comptime handler: anytype, context: anytype) void {
    handler(r, context) catch |err| {
        std.log.err("Handler error: {}", .{err});
        r.setStatus(.internal_server_error) catch {};
        r.sendBody("Internal Server Error") catch {};
    };
}