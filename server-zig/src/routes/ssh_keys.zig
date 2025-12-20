//! SSH Keys routes
//!
//! Handles SSH key management:
//! - GET /api/ssh-keys - List user's SSH keys
//! - POST /api/ssh-keys - Add new SSH key
//! - DELETE /api/ssh-keys/:id - Delete SSH key

const std = @import("std");
const httpz = @import("httpz");
const Context = @import("../main.zig").Context;
const db = @import("../lib/db.zig");
const auth = @import("../middleware/auth.zig");

const log = std.log.scoped(.ssh_keys);

/// Calculate SHA256 fingerprint from SSH public key
/// Format: "SHA256:base64hash"
pub fn calculateFingerprint(allocator: std.mem.Allocator, public_key: []const u8) ![]const u8 {
    // Parse key format: "ssh-rsa AAAAB3Nza... [comment]"
    var parts = std.mem.splitSequence(u8, public_key, " ");
    _ = parts.next() orelse return error.InvalidKeyFormat; // key type
    const key_data_b64 = parts.next() orelse return error.InvalidKeyFormat; // base64 data

    // Decode base64
    const decoder = std.base64.standard.Decoder;
    const decoded_size = try decoder.calcSizeForSlice(key_data_b64);
    const key_data = try allocator.alloc(u8, decoded_size);
    defer allocator.free(key_data);
    try decoder.decode(key_data, key_data_b64);

    // Calculate SHA256 hash
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(key_data, &hash, .{});

    // Encode to base64 (no padding)
    const encoder = std.base64.standard.Encoder;
    const encoded_size = encoder.calcSize(hash.len);
    const hash_b64 = try allocator.alloc(u8, encoded_size);
    defer allocator.free(hash_b64);
    const encoded = encoder.encode(hash_b64, &hash);

    // Remove padding '=' characters
    const trimmed = std.mem.trimRight(u8, encoded, "=");

    // Return "SHA256:hash"
    return try std.fmt.allocPrint(allocator, "SHA256:{s}", .{trimmed});
}

/// Parse key type from public key
pub fn parseKeyType(public_key: []const u8) ![]const u8 {
    var parts = std.mem.splitSequence(u8, public_key, " ");
    return parts.next() orelse error.InvalidKeyFormat;
}

/// Validate key type
pub fn isValidKeyType(key_type: []const u8) bool {
    const valid_types = [_][]const u8{
        "ssh-rsa",
        "ssh-ed25519",
        "ecdsa-sha2-nistp256",
        "ecdsa-sha2-nistp384",
        "ecdsa-sha2-nistp521",
    };

    for (valid_types) |valid| {
        if (std.mem.eql(u8, key_type, valid)) return true;
    }
    return false;
}

/// GET /api/ssh-keys - List user's SSH keys
pub fn list(ctx: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Require authentication
    const user = ctx.user orelse {
        res.status = .unauthorized;
        try res.writer().writeAll("{\"error\":\"Authentication required\"}");
        return;
    };

    if (!user.is_active) {
        res.status = 403;
        try res.writer().writeAll("{\"error\":\"Account not activated\"}");
        return;
    }

    // Query SSH keys
    var conn = try ctx.pool.acquire();
    defer conn.release();

    var result = try conn.query(
        \\SELECT id, name, fingerprint, key_type, created_at::text
        \\FROM ssh_keys
        \\WHERE user_id = $1
        \\ORDER BY created_at DESC
    , .{user.id});
    defer result.deinit();

    // Build JSON response
    var writer = res.writer();
    try writer.writeAll("{\"keys\":[");

    var first = true;
    while (try result.next()) |row| {
        if (!first) try writer.writeAll(",");
        first = false;

        const id = row.get(i64, 0);
        const name = row.get([]const u8, 1);
        const fingerprint = row.get([]const u8, 2);
        const key_type = row.get([]const u8, 3);
        const created_at = row.get([]const u8, 4);

        try writer.print(
            \\{{"id":{d},"name":"{s}","fingerprint":"{s}","keyType":"{s}","createdAt":"{s}"}}
        , .{ id, name, fingerprint, key_type, created_at });
    }

    try writer.writeAll("]}");
}

/// POST /api/ssh-keys - Add new SSH key
pub fn create(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Require authentication
    const user = ctx.user orelse {
        res.status = .unauthorized;
        try res.writer().writeAll("{\"error\":\"Authentication required\"}");
        return;
    };

    if (!user.is_active) {
        res.status = 403;
        try res.writer().writeAll("{\"error\":\"Account not activated\"}");
        return;
    }

    // Parse JSON body
    const body = req.body() orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing request body\"}");
        return;
    };

    const parsed = std.json.parseFromSlice(struct {
        name: []const u8,
        publicKey: []const u8,
    }, ctx.allocator, body, .{}) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid JSON\"}");
        return;
    };
    defer parsed.deinit();

    const name = std.mem.trim(u8, parsed.value.name, " \t\n\r");
    const public_key = std.mem.trim(u8, parsed.value.publicKey, " \t\n\r");

    // Validate inputs
    if (name.len == 0) {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Name is required\"}");
        return;
    }

    if (name.len > 255) {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Name must be at most 255 characters\"}");
        return;
    }

    if (public_key.len == 0) {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Public key is required\"}");
        return;
    }

    // Parse key type
    const key_type = parseKeyType(public_key) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid public key format\"}");
        return;
    };

    if (!isValidKeyType(key_type)) {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid key type. Must be ssh-rsa, ssh-ed25519, or ecdsa-sha2-nistp*\"}");
        return;
    }

    // Calculate fingerprint
    const fingerprint = calculateFingerprint(ctx.allocator, public_key) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Failed to parse public key\"}");
        return;
    };
    defer ctx.allocator.free(fingerprint);

    // Check for duplicate fingerprint
    const existing = try db.getSshKeyByFingerprint(ctx.pool, fingerprint);
    if (existing != null) {
        res.status = 409;
        try res.writer().writeAll("{\"error\":\"SSH key already exists\"}");
        return;
    }

    // Insert the key
    const key_id = db.createSshKey(
        ctx.pool,
        user.id,
        name,
        public_key,
        fingerprint,
        key_type,
    ) catch {
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to create SSH key\"}");
        return;
    };

    // Return created key
    res.status = 201;
    var writer = res.writer();
    try writer.print(
        \\{{"key":{{"id":{d},"name":"{s}","fingerprint":"{s}","keyType":"{s}"}}}}
    , .{ key_id, name, fingerprint, key_type });
}

/// DELETE /api/ssh-keys/:id - Delete SSH key
pub fn delete(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Require authentication
    const user = ctx.user orelse {
        res.status = .unauthorized;
        try res.writer().writeAll("{\"error\":\"Authentication required\"}");
        return;
    };

    if (!user.is_active) {
        res.status = 403;
        try res.writer().writeAll("{\"error\":\"Account not activated\"}");
        return;
    }

    // Parse key ID from path
    const key_id_str = req.param("id") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing key ID\"}");
        return;
    };

    const key_id = std.fmt.parseInt(i64, key_id_str, 10) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid key ID\"}");
        return;
    };

    // Check if key exists and belongs to user
    const existing = try db.getSshKeyById(ctx.pool, key_id, user.id);
    if (existing == null) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"SSH key not found\"}");
        return;
    }

    // Delete the key
    const deleted = try db.deleteSshKey(ctx.pool, key_id, user.id);
    if (!deleted) {
        res.status = 404;
        try res.writer().writeAll("{\"error\":\"SSH key not found\"}");
        return;
    }

    try res.writer().writeAll("{\"message\":\"SSH key deleted\"}");
}
