const std = @import("std");
const httpz = @import("httpz");

pub fn writeJson(res: *httpz.Response, allocator: std.mem.Allocator, value: anytype) !void {
    var json_builder = std.ArrayList(u8).init(allocator);
    try std.json.stringify(value, .{}, json_builder.writer());
    res.content_type = .JSON;
    res.body = try allocator.dupe(u8, json_builder.items);
    json_builder.deinit();
}

pub fn writeError(res: *httpz.Response, allocator: std.mem.Allocator, status: u16, message: []const u8) !void {
    res.status = status;
    try writeJson(res, allocator, .{ .@"error" = message });
}