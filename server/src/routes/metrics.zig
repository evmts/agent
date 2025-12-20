//! Prometheus metrics endpoint handler.
//!
//! Exposes application metrics in Prometheus text format at /metrics.

const std = @import("std");
const httpz = @import("httpz");
const Context = @import("../main.zig").Context;
const metrics = @import("../lib/metrics.zig");

const log = std.log.scoped(.metrics_route);

/// Handle GET /metrics
/// Returns Prometheus-formatted metrics
pub fn getMetrics(ctx: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    const output = metrics.global.format(ctx.allocator) catch |err| {
        log.err("Failed to format metrics: {}", .{err});
        res.status = 500;
        res.content_type = .JSON;
        try res.writer().writeAll("{\"error\":\"Failed to format metrics\"}");
        return;
    };
    defer ctx.allocator.free(output);

    res.status = 200;
    // Set content type to Prometheus text format
    res.content_type = .TEXT;
    try res.writer().writeAll(output);
}
