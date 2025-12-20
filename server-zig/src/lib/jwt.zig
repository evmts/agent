const std = @import("std");
const base64 = std.base64;

const log = std.log.scoped(.jwt);

pub const JWTError = error{
    InvalidToken,
    ExpiredToken,
    InvalidSignature,
    MissingSecret,
};

pub const JWTPayload = struct {
    user_id: i64,
    username: []const u8,
    is_admin: bool,
    iat: i64, // Issued at
    exp: i64, // Expiration
};

const JWT_EXPIRY_SECONDS: i64 = 7 * 24 * 60 * 60; // 7 days

/// Sign a JWT with HS256
pub fn sign(
    allocator: std.mem.Allocator,
    payload: JWTPayload,
    secret: []const u8,
) ![]const u8 {
    // Header: {"alg":"HS256","typ":"JWT"}
    const header = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9";

    // Build payload JSON manually (avoids Zig version-specific JSON API)
    const payload_json = try std.fmt.allocPrint(allocator,
        \\{{"user_id":{d},"username":"{s}","is_admin":{s},"iat":{d},"exp":{d}}}
    , .{
        payload.user_id,
        payload.username,
        if (payload.is_admin) "true" else "false",
        payload.iat,
        payload.exp,
    });
    defer allocator.free(payload_json);

    // Base64url encode payload
    const payload_b64 = try base64UrlEncode(allocator, payload_json);
    defer allocator.free(payload_b64);

    // Create signature input: header.payload
    const sig_input = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ header, payload_b64 });
    defer allocator.free(sig_input);

    // HMAC-SHA256 signature (Zig 0.15 API)
    const HmacSha256 = std.crypto.auth.hmac.sha2.HmacSha256;
    var hmac = HmacSha256.init(secret);
    hmac.update(sig_input);
    var signature: [32]u8 = undefined;
    hmac.final(&signature);

    // Base64url encode signature
    const sig_b64 = try base64UrlEncode(allocator, &signature);
    defer allocator.free(sig_b64);

    // Return: header.payload.signature
    return std.fmt.allocPrint(allocator, "{s}.{s}.{s}", .{ header, payload_b64, sig_b64 });
}

/// Verify and decode a JWT
pub fn verify(
    allocator: std.mem.Allocator,
    token: []const u8,
    secret: []const u8,
) !JWTPayload {
    // Split token into parts
    var parts = std.mem.splitScalar(u8, token, '.');
    const header = parts.next() orelse return JWTError.InvalidToken;
    const payload_b64 = parts.next() orelse return JWTError.InvalidToken;
    const signature_b64 = parts.next() orelse return JWTError.InvalidToken;

    if (parts.next() != null) return JWTError.InvalidToken;

    // Verify signature
    const sig_input = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ header, payload_b64 });
    defer allocator.free(sig_input);

    const HmacSha256 = std.crypto.auth.hmac.sha2.HmacSha256;
    var hmac = HmacSha256.init(secret);
    hmac.update(sig_input);
    var expected_sig: [32]u8 = undefined;
    hmac.final(&expected_sig);

    // Decode provided signature
    const provided_sig = try base64UrlDecode(allocator, signature_b64);
    defer allocator.free(provided_sig);

    if (!std.crypto.utils.timingSafeEql([32]u8, expected_sig, provided_sig[0..32].*)) {
        return JWTError.InvalidSignature;
    }

    // Decode payload
    const payload_json = try base64UrlDecode(allocator, payload_b64);
    defer allocator.free(payload_json);

    const payload = try std.json.parseFromSlice(JWTPayload, allocator, payload_json, .{});
    defer payload.deinit();

    // Check expiration
    const now = std.time.timestamp();
    if (payload.value.exp < now) {
        return JWTError.ExpiredToken;
    }

    return payload.value;
}

/// Create a new JWT for a user
pub fn create(
    allocator: std.mem.Allocator,
    user_id: i64,
    username: []const u8,
    is_admin: bool,
    secret: []const u8,
) ![]const u8 {
    const now = std.time.timestamp();
    const payload = JWTPayload{
        .user_id = user_id,
        .username = username,
        .is_admin = is_admin,
        .iat = now,
        .exp = now + JWT_EXPIRY_SECONDS,
    };
    return sign(allocator, payload, secret);
}

// ============================================================================
// Base64url helpers (Zig 0.15+ API)
// ============================================================================

fn base64UrlEncode(allocator: std.mem.Allocator, data: []const u8) ![]const u8 {
    const codec = base64.url_safe_no_pad;
    const size = codec.Encoder.calcSize(data.len);
    const buffer = try allocator.alloc(u8, size);
    _ = codec.Encoder.encode(buffer, data);
    return buffer;
}

fn base64UrlDecode(allocator: std.mem.Allocator, data: []const u8) ![]const u8 {
    const codec = base64.url_safe_no_pad;
    const size = codec.Decoder.calcSizeForSlice(data) catch return error.InvalidToken;
    const buffer = try allocator.alloc(u8, size);
    codec.Decoder.decode(buffer, data) catch return error.InvalidToken;
    return buffer;
}

// ============================================================================
// Cookie helpers
// ============================================================================

pub const COOKIE_NAME = "plue_token";

pub fn setCookie(headers: *std.http.Headers, token: []const u8, is_production: bool) !void {
    var cookie_buf: [4096]u8 = undefined;
    const secure = if (is_production) "; Secure" else "";
    const cookie = try std.fmt.bufPrint(&cookie_buf, "{s}={s}; Path=/; HttpOnly; SameSite=Lax; Max-Age=604800{s}", .{ COOKIE_NAME, token, secure });
    try headers.append("Set-Cookie", cookie);
}

pub fn clearCookie(headers: *std.http.Headers, is_production: bool) !void {
    var cookie_buf: [256]u8 = undefined;
    const secure = if (is_production) "; Secure" else "";
    const cookie = try std.fmt.bufPrint(&cookie_buf, "{s}=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0{s}", .{ COOKIE_NAME, secure });
    try headers.append("Set-Cookie", cookie);
}

pub fn getFromCookie(cookie_header: ?[]const u8) ?[]const u8 {
    const header = cookie_header orelse return null;

    var cookies = std.mem.splitSequence(u8, header, "; ");
    while (cookies.next()) |cookie| {
        if (std.mem.startsWith(u8, cookie, COOKIE_NAME)) {
            const eq_pos = std.mem.indexOf(u8, cookie, "=") orelse continue;
            return cookie[eq_pos + 1 ..];
        }
    }
    return null;
}

test "jwt sign and verify" {
    const allocator = std.testing.allocator;
    const secret = "test-secret";

    const token = try create(allocator, 123, "testuser", false, secret);
    defer allocator.free(token);

    const payload = try verify(allocator, token, secret);
    try std.testing.expectEqual(@as(i64, 123), payload.user_id);
    try std.testing.expectEqualStrings("testuser", payload.username);
    try std.testing.expectEqual(false, payload.is_admin);
}
