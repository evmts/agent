//! Body size limit middleware
//!
//! Limits the size of incoming request bodies to prevent memory exhaustion.

const std = @import("std");
const httpz = @import("httpz");
const Context = @import("../main.zig").Context;

const log = std.log.scoped(.body_limit);

pub const BodyLimitConfig = struct {
    /// Maximum body size in bytes (default 10MB)
    max_size: usize = 10 * 1024 * 1024,
};

/// Default body limit configuration (10MB)
pub const default_config = BodyLimitConfig{};

/// Body limit middleware - checks Content-Length header
pub fn bodyLimitMiddleware(config: BodyLimitConfig) fn (*Context, *httpz.Request, *httpz.Response) anyerror!bool {
    return struct {
        fn handler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !bool {
            _ = ctx;

            // Check Content-Length header
            const content_length_header = req.headers.get("content-length");

            if (content_length_header) |cl_str| {
                const content_length = std.fmt.parseInt(usize, cl_str, 10) catch {
                    // Invalid Content-Length header
                    res.status = 400;
                    res.content_type = .JSON;
                    try res.writer().writeAll("{\"error\":\"Invalid Content-Length header\"}");
                    return false;
                };

                // Check if content length exceeds limit
                if (content_length > config.max_size) {
                    res.status = 413;
                    res.content_type = .JSON;

                    var buf: [256]u8 = undefined;
                    const max_size_mb = formatBytes(config.max_size, &buf) catch "10MB";

                    var response_buf: [512]u8 = undefined;
                    const response = try std.fmt.bufPrint(&response_buf, "{{\"error\":\"Request body too large\",\"code\":\"PAYLOAD_TOO_LARGE\",\"maxSize\":\"{s}\"}}", .{max_size_mb});

                    try res.writer().writeAll(response);
                    return false;
                }
            }

            // Note: httpz may also enforce its own limits at a lower level
            // This middleware provides application-level control and better error messages

            return true; // Continue to next handler
        }
    }.handler;
}

/// Format bytes to human-readable string (e.g., "10MB", "1.5GB")
fn formatBytes(bytes: usize, buf: []u8) ![]const u8 {
    const kb = 1024;
    const mb = kb * 1024;
    const gb = mb * 1024;

    if (bytes >= gb) {
        const gb_value = @as(f64, @floatFromInt(bytes)) / @as(f64, @floatFromInt(gb));
        return std.fmt.bufPrint(buf, "{d:.1}GB", .{gb_value});
    } else if (bytes >= mb) {
        const mb_value = @as(f64, @floatFromInt(bytes)) / @as(f64, @floatFromInt(mb));
        return std.fmt.bufPrint(buf, "{d:.1}MB", .{mb_value});
    } else if (bytes >= kb) {
        const kb_value = @as(f64, @floatFromInt(bytes)) / @as(f64, @floatFromInt(kb));
        return std.fmt.bufPrint(buf, "{d:.1}KB", .{kb_value});
    } else {
        return std.fmt.bufPrint(buf, "{d}B", .{bytes});
    }
}

// ============================================================================
// Tests
// ============================================================================

test "formatBytes" {
    var buf: [64]u8 = undefined;

    // Bytes
    {
        const result = try formatBytes(512, &buf);
        try std.testing.expectEqualStrings("512B", result);
    }

    // Kilobytes
    {
        const result = try formatBytes(1536, &buf);
        try std.testing.expectEqualStrings("1.5KB", result);
    }

    // Megabytes
    {
        const result = try formatBytes(10 * 1024 * 1024, &buf);
        try std.testing.expectEqualStrings("10.0MB", result);
    }

    // Gigabytes
    {
        const result = try formatBytes(2 * 1024 * 1024 * 1024, &buf);
        try std.testing.expectEqualStrings("2.0GB", result);
    }
}

test "formatBytes edge cases" {
    var buf: [64]u8 = undefined;

    // Zero bytes
    {
        const result = try formatBytes(0, &buf);
        try std.testing.expectEqualStrings("0B", result);
    }

    // 1KB exactly
    {
        const result = try formatBytes(1024, &buf);
        try std.testing.expectEqualStrings("1.0KB", result);
    }

    // 1MB exactly
    {
        const result = try formatBytes(1024 * 1024, &buf);
        try std.testing.expectEqualStrings("1.0MB", result);
    }
}
