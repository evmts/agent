const std = @import("std");
const httpz = @import("httpz");
const Context = @import("main.zig").Context;

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

fn verify(_: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;
    res.status = 501; // Not Implemented
    try res.writer().writeAll("{\"error\":\"SIWE verify not yet implemented\"}");
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
