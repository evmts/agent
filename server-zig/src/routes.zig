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

// Username validation
// Must be 3-39 characters, start and end with alphanumeric, allow dashes and underscores in middle
fn isValidUsername(username: []const u8) bool {
    if (username.len < 3 or username.len > 39) return false;

    // Must start and end with alphanumeric
    if (!std.ascii.isAlphanumeric(username[0])) return false;
    if (!std.ascii.isAlphanumeric(username[username.len - 1])) return false;

    // Check middle characters (alphanumeric, dash, or underscore)
    for (username) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '-' and c != '_') {
            return false;
        }
    }

    return true;
}

fn register(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;
    const allocator = ctx.allocator;

    // Parse JSON body
    const body = req.body() orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing request body\"}");
        return;
    };

    // Extract required fields from JSON
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

    const username = extractJsonString(body, "username") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing username field\"}");
        return;
    };

    // Validate username
    if (!isValidUsername(username)) {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid username. Must be 3-39 alphanumeric characters, dashes and underscores allowed in the middle\"}");
        return;
    }

    // Extract optional display name (defaults to username if not provided)
    const display_name = extractJsonString(body, "displayName") orelse username;

    // Verify SIWE signature using voltaire
    const result = siwe.verifySiweSignature(allocator, ctx.pool, message, signature) catch |err| {
        log.warn("SIWE verification failed during registration: {}", .{err});
        res.status = 401;
        try res.writer().writeAll("{\"error\":\"Signature verification failed\"}");
        return;
    };
    defer {
        allocator.free(result.parsed.domain);
        if (result.parsed.statement) |s| allocator.free(s);
        allocator.free(result.parsed.uri);
        allocator.free(result.parsed.version);
        allocator.free(result.parsed.nonce);
        allocator.free(result.parsed.issued_at);
    }

    // Get address as hex
    const addr_hex = siwe.addressToHex(allocator, result.address) catch {
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Internal error\"}");
        return;
    };
    defer allocator.free(addr_hex);

    // Check if wallet already registered
    const existing_wallet = db.getUserByWallet(ctx.pool, addr_hex) catch null;
    if (existing_wallet != null) {
        res.status = 409; // Conflict
        try res.writer().writeAll("{\"error\":\"Wallet already registered\"}");
        return;
    }

    // Check if username already taken (case-insensitive)
    const existing_username = db.getUserByUsername(ctx.pool, username) catch null;
    if (existing_username != null) {
        res.status = 409; // Conflict
        try res.writer().writeAll("{\"error\":\"Username already taken\"}");
        return;
    }

    // Create user in database
    const user_id = db.createUser(ctx.pool, username, display_name, addr_hex) catch {
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to create user\"}");
        return;
    };

    // Create JWT token for the new user
    const token = jwt.create(allocator, user_id, username, false, ctx.config.jwt_secret) catch {
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to create session token\"}");
        return;
    };
    defer allocator.free(token);

    // Return success response (201 Created)
    res.status = 201;
    var writer = res.writer();
    try writer.print(
        \\{{"message":"Registration successful","user":{{"id":{d},"username":"{s}","isActive":true,"isAdmin":false,"walletAddress":"{s}"}},"token":"{s}"}}
    , .{ user_id, username, addr_hex, token });
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
