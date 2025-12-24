//! CORS (Cross-Origin Resource Sharing) middleware
//!
//! Handles CORS headers and preflight OPTIONS requests.

const std = @import("std");
const httpz = @import("httpz");
const Context = @import("../main.zig").Context;

const log = std.log.scoped(.cors);

pub const CorsConfig = struct {
    /// Allowed origins (use "*" for all, or specific origins)
    allowed_origins: []const []const u8 = &.{"*"},
    /// Allowed HTTP methods
    allowed_methods: []const []const u8 = &.{ "GET", "POST", "PUT", "DELETE", "PATCH" },
    /// Allowed headers
    allowed_headers: []const []const u8 = &.{ "Content-Type", "Authorization" },
    /// Headers to expose to client
    exposed_headers: []const []const u8 = &.{},
    /// Max age for preflight cache (seconds)
    max_age: u32 = 600,
    /// Allow credentials
    credentials: bool = true,
    /// Allow localhost in development
    allow_localhost_dev: bool = true,
};

/// Default CORS configuration
pub const default_config = CorsConfig{};

/// CORS middleware - sets CORS headers on all responses
pub fn corsMiddleware(config: CorsConfig) fn (*Context, *httpz.Request, *httpz.Response) anyerror!bool {
    return struct {
        fn handler(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !bool {
            const origin = req.headers.get("origin");

            // Determine if origin is allowed
            const allowed_origin = if (origin) |o| blk: {
                // Check if wildcard is allowed
                if (config.allowed_origins.len > 0 and std.mem.eql(u8, config.allowed_origins[0], "*")) {
                    break :blk o;
                }

                // Check if origin is in allowed list
                for (config.allowed_origins) |allowed| {
                    if (std.mem.eql(u8, allowed, o)) {
                        break :blk o;
                    }
                }

                // In development, allow localhost with any port
                if (config.allow_localhost_dev and !ctx.config.is_production) {
                    if (std.mem.startsWith(u8, o, "http://localhost:")) {
                        break :blk o;
                    }
                }

                // Origin not allowed
                break :blk null;
            } else null;

            // Set CORS headers if origin is allowed
            if (allowed_origin) |ao| {
                res.headers.add("Access-Control-Allow-Origin", ao);

                if (config.credentials) {
                    res.headers.add("Access-Control-Allow-Credentials", "true");
                }

                // Set exposed headers
                if (config.exposed_headers.len > 0) {
                    var buf: [512]u8 = undefined;
                    var fbs = std.io.fixedBufferStream(&buf);
                    const writer = fbs.writer();

                    for (config.exposed_headers, 0..) |header, i| {
                        if (i > 0) try writer.writeAll(", ");
                        try writer.writeAll(header);
                    }

                    const exposed_str = fbs.getWritten();
                    res.headers.add("Access-Control-Expose-Headers", exposed_str);
                }
            }

            // Handle preflight OPTIONS request
            if (std.mem.eql(u8, req.method, "OPTIONS")) {
                if (allowed_origin == null) {
                    // Origin not allowed, return 403
                    res.status = 403;
                    res.content_type = .JSON;
                    try res.writer().writeAll("{\"error\":\"Origin not allowed\"}");
                    return false;
                }

                // Set preflight headers
                res.headers.add("Access-Control-Allow-Methods", try joinStrings(config.allowed_methods, ctx.allocator));
                res.headers.add("Access-Control-Allow-Headers", try joinStrings(config.allowed_headers, ctx.allocator));

                var buf: [32]u8 = undefined;
                const max_age_str = try std.fmt.bufPrint(&buf, "{d}", .{config.max_age});
                res.headers.add("Access-Control-Max-Age", max_age_str);

                res.status = 204;
                return false; // Stop handler chain for preflight
            }

            return true; // Continue to next handler
        }
    }.handler;
}

/// Join strings with ", " separator
fn joinStrings(strings: []const []const u8, allocator: std.mem.Allocator) ![]const u8 {
    if (strings.len == 0) return "";

    var total_len: usize = 0;
    for (strings, 0..) |s, i| {
        total_len += s.len;
        if (i < strings.len - 1) total_len += 2; // ", "
    }

    const result = try allocator.alloc(u8, total_len);
    var pos: usize = 0;
    for (strings, 0..) |s, i| {
        @memcpy(result[pos .. pos + s.len], s);
        pos += s.len;
        if (i < strings.len - 1) {
            result[pos] = ',';
            result[pos + 1] = ' ';
            pos += 2;
        }
    }

    return result;
}

// ============================================================================
// Tests
// ============================================================================

test "joinStrings" {
    const allocator = std.testing.allocator;

    const strings = &.{ "GET", "POST", "PUT" };
    const result = try joinStrings(strings, allocator);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("GET, POST, PUT", result);
}

test "joinStrings empty" {
    const allocator = std.testing.allocator;

    const strings: []const []const u8 = &.{};
    const result = try joinStrings(strings, allocator);

    try std.testing.expectEqualStrings("", result);
}

test "joinStrings single" {
    const allocator = std.testing.allocator;

    const strings = &.{"GET"};
    const result = try joinStrings(strings, allocator);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("GET", result);
}
