//! Security headers middleware
//!
//! Sets security-related HTTP headers to protect against common attacks.

const std = @import("std");
const httpz = @import("httpz");
const Context = @import("../main.zig").Context;

const log = std.log.scoped(.security);

pub const SecurityConfig = struct {
    /// X-Content-Type-Options
    x_content_type_options: []const u8 = "nosniff",
    /// X-Frame-Options
    x_frame_options: []const u8 = "DENY",
    /// X-XSS-Protection
    x_xss_protection: []const u8 = "1; mode=block",
    /// Referrer-Policy
    referrer_policy: []const u8 = "strict-origin-when-cross-origin",
    /// Strict-Transport-Security (HSTS) - only in production
    hsts_enabled: bool = true,
    hsts_max_age: u32 = 31536000, // 1 year
    hsts_include_subdomains: bool = true,
    hsts_preload: bool = true,
    /// Content-Security-Policy
    csp_enabled: bool = true,
    csp_default_src: []const []const u8 = &.{"'self'"},
    csp_script_src: []const []const u8 = &.{ "'self'", "'unsafe-inline'" },
    csp_style_src: []const []const u8 = &.{ "'self'", "'unsafe-inline'" },
    csp_img_src: []const []const u8 = &.{ "'self'", "data:", "https:" },
    csp_connect_src: []const []const u8 = &.{ "'self'", "http://localhost:3000" },
    csp_font_src: []const []const u8 = &.{ "'self'", "data:" },
    csp_object_src: []const []const u8 = &.{"'none'"},
    csp_media_src: []const []const u8 = &.{"'self'"},
    csp_frame_src: []const []const u8 = &.{"'none'"},
};

/// Default security configuration
pub const default_config = SecurityConfig{};

/// Security headers middleware
pub fn securityMiddleware(config: SecurityConfig) fn (*Context, *httpz.Request, *httpz.Response) anyerror!bool {
    return struct {
        fn handler(ctx: *Context, _: *httpz.Request, res: *httpz.Response) !bool {
            // X-Content-Type-Options
            res.headers.put("X-Content-Type-Options", config.x_content_type_options);

            // X-Frame-Options
            res.headers.put("X-Frame-Options", config.x_frame_options);

            // X-XSS-Protection
            res.headers.put("X-XSS-Protection", config.x_xss_protection);

            // Referrer-Policy
            res.headers.put("Referrer-Policy", config.referrer_policy);

            // Strict-Transport-Security (HSTS) - only in production
            if (config.hsts_enabled and ctx.config.is_production) {
                var hsts_buf: [256]u8 = undefined;
                const hsts = try std.fmt.bufPrint(&hsts_buf, "max-age={d}{s}{s}", .{
                    config.hsts_max_age,
                    if (config.hsts_include_subdomains) "; includeSubDomains" else "",
                    if (config.hsts_preload) "; preload" else "",
                });
                res.headers.put("Strict-Transport-Security", hsts);
            }

            // Content-Security-Policy
            if (config.csp_enabled) {
                const allocator = ctx.allocator;

                // Build CSP string
                var csp_list = std.ArrayList(u8).init(allocator);
                defer csp_list.deinit();
                const writer = csp_list.writer();

                // default-src
                try writer.writeAll("default-src ");
                try writeCSPValues(writer, config.csp_default_src);

                // script-src
                try writer.writeAll("; script-src ");
                try writeCSPValues(writer, config.csp_script_src);

                // style-src
                try writer.writeAll("; style-src ");
                try writeCSPValues(writer, config.csp_style_src);

                // img-src
                try writer.writeAll("; img-src ");
                try writeCSPValues(writer, config.csp_img_src);

                // connect-src
                try writer.writeAll("; connect-src ");
                try writeCSPValues(writer, config.csp_connect_src);

                // font-src
                try writer.writeAll("; font-src ");
                try writeCSPValues(writer, config.csp_font_src);

                // object-src
                try writer.writeAll("; object-src ");
                try writeCSPValues(writer, config.csp_object_src);

                // media-src
                try writer.writeAll("; media-src ");
                try writeCSPValues(writer, config.csp_media_src);

                // frame-src
                try writer.writeAll("; frame-src ");
                try writeCSPValues(writer, config.csp_frame_src);

                const csp = try csp_list.toOwnedSlice();
                res.headers.put("Content-Security-Policy", csp);
            }

            return true; // Continue to next handler
        }
    }.handler;
}

/// Write CSP values to writer (space-separated)
fn writeCSPValues(writer: anytype, values: []const []const u8) !void {
    for (values, 0..) |value, i| {
        if (i > 0) try writer.writeAll(" ");
        try writer.writeAll(value);
    }
}

// ============================================================================
// Tests
// ============================================================================

test "writeCSPValues" {
    const allocator = std.testing.allocator;

    var list = std.ArrayList(u8).init(allocator);
    defer list.deinit();

    const values = &.{ "'self'", "https:" };
    try writeCSPValues(list.writer(), values);

    try std.testing.expectEqualStrings("'self' https:", list.items);
}

test "writeCSPValues single" {
    const allocator = std.testing.allocator;

    var list = std.ArrayList(u8).init(allocator);
    defer list.deinit();

    const values = &.{"'self'"};
    try writeCSPValues(list.writer(), values);

    try std.testing.expectEqualStrings("'self'", list.items);
}

test "writeCSPValues empty" {
    const allocator = std.testing.allocator;

    var list = std.ArrayList(u8).init(allocator);
    defer list.deinit();

    const values: []const []const u8 = &.{};
    try writeCSPValues(list.writer(), values);

    try std.testing.expectEqualStrings("", list.items);
}
