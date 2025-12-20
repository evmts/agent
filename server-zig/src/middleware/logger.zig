//! HTTP request logging middleware
//!
//! Logs method, path, status code, and response time for each request.

const std = @import("std");
const httpz = @import("httpz");
const Context = @import("../main.zig").Context;

const log = std.log.scoped(.http);

/// Request context for tracking timing
const RequestContext = struct {
    start_time: i64,
    request_id: []const u8,
};

/// Logger middleware - logs request details
/// Note: This should be the first middleware in the chain to capture all requests
pub fn loggerMiddleware(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !bool {
    // Generate request ID
    var request_id_buf: [16]u8 = undefined;
    std.crypto.random.bytes(&request_id_buf);
    const request_id = std.fmt.bytesToHex(request_id_buf, .lower);

    // Store request ID in context (if we had a place for it)
    // For now, we'll just use it in the log

    // Record start time
    const start_time = std.time.milliTimestamp();

    // Store in arena for cleanup
    const req_ctx = try ctx.allocator.create(RequestContext);
    req_ctx.* = .{
        .start_time = start_time,
        .request_id = &request_id,
    };

    // Continue to next handler
    const continue_chain = true;

    // Calculate response time (approximation - in real impl, we'd need to hook into response completion)
    const end_time = std.time.milliTimestamp();
    const duration_ms = end_time - start_time;

    // Log request
    const method = req.method;
    const path = req.url.path;
    const status = @intFromEnum(res.status);

    // Format: [REQUEST_ID] METHOD /path STATUS TIMEms
    log.info("[{s}] {s} {s} {d} {d}ms", .{
        req_ctx.request_id,
        method,
        path,
        status,
        duration_ms,
    });

    // Note: In a production implementation, we would need a way to hook into
    // the response completion to log the actual response time and status.
    // httpz may provide hooks for this, or we could use a response wrapper.

    return continue_chain;
}

/// Logger middleware with timing (captures response details)
/// This is a more sophisticated version that requires response interception
pub fn timedLoggerMiddleware() fn (*Context, *httpz.Request, *httpz.Response) anyerror!bool {
    return struct {
        fn handler(ctx: *Context, req: *httpz.Request, _: *httpz.Response) !bool {
            // Generate request ID
            var request_id_buf: [16]u8 = undefined;
            std.crypto.random.bytes(&request_id_buf);
            const request_id_hex = std.fmt.bytesToHex(request_id_buf, .lower);

            // Copy to heap for persistence
            const request_id = try ctx.allocator.dupe(u8, &request_id_hex);

            // Record start time
            const start_time = std.time.milliTimestamp();

            // Store timing info (would need context support in real impl)
            const req_ctx = try ctx.allocator.create(RequestContext);
            req_ctx.* = .{
                .start_time = start_time,
                .request_id = request_id,
            };

            // Note: We cannot accurately measure response time here because
            // middleware executes before the handler runs. A real implementation
            // would need to wrap the response or use httpz hooks.

            // For now, just log the incoming request
            log.info("[{s}] --> {s} {s}", .{
                request_id,
                req.method,
                req.url.path,
            });

            return true; // Continue to next handler
        }
    }.handler;
}

/// Simple logger that just logs incoming requests
pub fn simpleLoggerMiddleware(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !bool {
    _ = ctx;
    _ = res;

    // Generate simple request ID
    var request_id_buf: [8]u8 = undefined;
    std.crypto.random.bytes(&request_id_buf);
    const request_id = std.fmt.bytesToHex(request_id_buf, .lower);

    // Log request
    log.info("[{s}] {s} {s}", .{
        &request_id,
        req.method,
        req.url.path,
    });

    return true; // Continue to next handler
}

// ============================================================================
// Tests
// ============================================================================

test "request id generation" {
    // Test that we can generate unique request IDs
    var buf1: [16]u8 = undefined;
    var buf2: [16]u8 = undefined;

    std.crypto.random.bytes(&buf1);
    std.crypto.random.bytes(&buf2);

    const id1 = std.fmt.bytesToHex(buf1, .lower);
    const id2 = std.fmt.bytesToHex(buf2, .lower);

    // IDs should be different (with overwhelming probability)
    try std.testing.expect(!std.mem.eql(u8, &id1, &id2));
}

test "request id format" {
    var buf: [16]u8 = undefined;
    std.crypto.random.bytes(&buf);

    const request_id = std.fmt.bytesToHex(buf, .lower);

    // Should be 32 characters (16 bytes * 2 hex chars)
    try std.testing.expectEqual(@as(usize, 32), request_id.len);

    // Should only contain hex characters
    for (request_id) |c| {
        const is_hex = (c >= '0' and c <= '9') or (c >= 'a' and c <= 'f');
        try std.testing.expect(is_hex);
    }
}
