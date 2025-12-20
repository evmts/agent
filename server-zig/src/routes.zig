const std = @import("std");
const httpz = @import("httpz");
const Context = @import("main.zig").Context;
const siwe = @import("lib/siwe.zig");
const db = @import("lib/db.zig");
const jwt = @import("lib/jwt.zig");

const log = std.log.scoped(.routes);

pub fn configure(server: *httpz.Server(*Context)) !void {
    var router = try server.router(.{});

    // Health check
    router.get("/health", healthCheck, .{});

    // ElectricSQL shape proxy
    router.get("/shape", shapeProxy, .{});

    // API routes - auth
    router.get("/api/auth/siwe/nonce", getNonce, .{});
    router.post("/api/auth/siwe/verify", verify, .{});
    router.post("/api/auth/siwe/register", register, .{});
    router.post("/api/auth/logout", logout, .{});
    router.get("/api/auth/me", me, .{});

    // API routes - users
    router.get("/api/users/search", userSearch, .{});
    router.get("/api/users/:username", userProfile, .{});

    log.info("Routes configured", .{});
}

fn healthCheck(_: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    res.status = 200;
    res.content_type = .JSON;
    try res.writer().writeAll("{\"status\":\"ok\"}");
}

fn shapeProxy(ctx: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    // Proxy request to ElectricSQL
    _ = ctx;
    res.status = 503; // Service Unavailable
    res.content_type = .JSON;
    try res.writer().writeAll("{\"error\":\"Electric proxy not yet implemented\"}");
}

// Auth handlers (stubbed for now)
fn getNonce(ctx: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    _ = ctx;
    res.content_type = .JSON;
    // Generate a random nonce
    var nonce_bytes: [16]u8 = undefined;
    std.crypto.random.bytes(&nonce_bytes);

    const hex = std.fmt.bytesToHex(nonce_bytes, .lower);

    var writer = res.writer();
    try writer.writeAll("{\"nonce\":\"");
    try writer.writeAll(&hex);
    try writer.writeAll("\"}");
}

fn verify(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;
    const allocator = ctx.allocator;

    // Parse JSON body
    const body = req.body() orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing request body\"}");
        return;
    };

    // Simple JSON parsing - extract message and signature fields
    const message = extractJsonString(body, "message") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing message field\"}");
        return;
    };
    const signature = extractJsonString(body, "signature") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing signature field\"}");
        return;
    };

    // Verify SIWE signature using voltaire
    const result = siwe.verifySiweSignature(allocator, ctx.pool, message, signature) catch |err| {
        log.warn("SIWE verification failed: {}", .{err});
        res.status = 401;
        try res.writer().writeAll("{\"error\":\"Signature verification failed\"}");
        return;
    };

    // Get address as hex
    const addr_hex = siwe.addressToHex(allocator, result.address) catch {
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Internal error\"}");
        return;
    };
    defer allocator.free(addr_hex);

    // Check if user exists or needs to register
    const user = db.getUserByWallet(ctx.pool, addr_hex) catch null;

    if (user) |u| {
        // Create session token
        const token = jwt.create(allocator, u.id, u.username, u.is_admin, ctx.config.jwt_secret) catch {
            res.status = 500;
            try res.writer().writeAll("{\"error\":\"Failed to create session\"}");
            return;
        };
        defer allocator.free(token);

        var writer = res.writer();
        try writer.print("{{\"authenticated\":true,\"user\":{{\"id\":{d},\"username\":\"{s}\"}},\"token\":\"{s}\"}}", .{ u.id, u.username, token });
    } else {
        // User needs to register
        var writer = res.writer();
        try writer.print("{{\"authenticated\":true,\"needsRegistration\":true,\"address\":\"{s}\"}}", .{addr_hex});
    }
}

// Simple JSON string extractor (avoids need for full JSON parser)
fn extractJsonString(json: []const u8, key: []const u8) ?[]const u8 {
    // Find "key":"
    var pattern_buf: [256]u8 = undefined;
    const pattern = std.fmt.bufPrint(&pattern_buf, "\"{s}\":\"", .{key}) catch return null;

    const start_idx = std.mem.indexOf(u8, json, pattern) orelse return null;
    const value_start = start_idx + pattern.len;

    // Find closing quote
    const value_end = std.mem.indexOfPos(u8, json, value_start, "\"") orelse return null;

    return json[value_start..value_end];
}

fn register(_: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;
    res.status = 501; // Not Implemented
    try res.writer().writeAll("{\"error\":\"SIWE register not yet implemented\"}");
}

fn logout(_: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;
    try res.writer().writeAll("{\"message\":\"Logout successful\"}");
}

fn me(ctx: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;
    if (ctx.user) |u| {
        var writer = res.writer();
        try writer.print(
            \\{{"user":{{"id":{d},"username":"{s}","isActive":{s},"isAdmin":{s}}}}}
        , .{
            u.id,
            u.username,
            if (u.is_active) "true" else "false",
            if (u.is_admin) "true" else "false",
        });
    } else {
        try res.writer().writeAll("{\"user\":null}");
    }
}

fn userSearch(_: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;
    try res.writer().writeAll("{\"users\":[]}");
}

fn userProfile(_: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;
    const username = req.param("username") orelse {
        res.status = 400; // Bad Request
        try res.writer().writeAll("{\"error\":\"Missing username\"}");
        return;
    };

    var writer = res.writer();
    try writer.print("{{\"username\":\"{s}\",\"error\":\"User lookup not yet implemented\"}}", .{username});
}
