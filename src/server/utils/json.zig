const std = @import("std");
const zap = @import("zap");

pub fn writeJson(r: zap.Request, allocator: std.mem.Allocator, value: anytype) !void {
    var json_builder = std.ArrayList(u8).init(allocator);
    defer json_builder.deinit();
    
    try std.json.stringify(value, .{}, json_builder.writer());
    
    r.setHeader("Content-Type", "application/json") catch {};
    try r.sendBody(json_builder.items);
}

pub fn writeError(r: zap.Request, allocator: std.mem.Allocator, status: zap.StatusCode, message: []const u8) !void {
    r.setStatus(status);
    try writeJson(r, allocator, .{ .@"error" = message });
}