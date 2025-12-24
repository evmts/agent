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

    // Timing-safe comparison - XOR all bytes and check if result is zero
    if (provided_sig.len != 32) {
        return JWTError.InvalidSignature;
    }
    var diff: u8 = 0;
    for (expected_sig, 0..) |expected_byte, i| {
        diff |= expected_byte ^ provided_sig[i];
    }
    if (diff != 0) {
        return JWTError.InvalidSignature;
    }

    // Decode payload
    const payload_json = try base64UrlDecode(allocator, payload_b64);
    defer allocator.free(payload_json);

    const parsed = try std.json.parseFromSlice(JWTPayload, allocator, payload_json, .{});
    defer parsed.deinit();

    // Check expiration
    const now = std.time.timestamp();
    if (parsed.value.exp < now) {
        return JWTError.ExpiredToken;
    }

    // Duplicate string fields to ensure they're not dangling pointers after deinit
    const result = JWTPayload{
        .user_id = parsed.value.user_id,
        .username = try allocator.dupe(u8, parsed.value.username),
        .is_admin = parsed.value.is_admin,
        .iat = parsed.value.iat,
        .exp = parsed.value.exp,
    };

    return result;
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
    defer allocator.free(payload.username);

    try std.testing.expectEqual(@as(i64, 123), payload.user_id);
    try std.testing.expectEqualStrings("testuser", payload.username);
    try std.testing.expectEqual(false, payload.is_admin);
}

test "jwt sign and verify admin user" {
    const allocator = std.testing.allocator;
    const secret = "admin-secret-key";

    const token = try create(allocator, 999, "adminuser", true, secret);
    defer allocator.free(token);

    const payload = try verify(allocator, token, secret);
    defer allocator.free(payload.username);

    try std.testing.expectEqual(@as(i64, 999), payload.user_id);
    try std.testing.expectEqualStrings("adminuser", payload.username);
    try std.testing.expectEqual(true, payload.is_admin);
}

test "jwt invalid signature" {
    const allocator = std.testing.allocator;

    const token = try create(allocator, 123, "testuser", false, "secret1");
    defer allocator.free(token);

    // Try to verify with wrong secret
    const result = verify(allocator, token, "wrong-secret");
    try std.testing.expectError(JWTError.InvalidSignature, result);
}

test "jwt token format" {
    const allocator = std.testing.allocator;
    const secret = "test-secret";

    const token = try create(allocator, 1, "user", false, secret);
    defer allocator.free(token);

    // JWT should have 3 parts separated by dots
    var parts = std.mem.splitScalar(u8, token, '.');
    var count: usize = 0;
    while (parts.next()) |_| {
        count += 1;
    }
    try std.testing.expectEqual(@as(usize, 3), count);
}

test "jwt invalid token format" {
    const allocator = std.testing.allocator;

    // Missing parts
    try std.testing.expectError(JWTError.InvalidToken, verify(allocator, "onlyonepart", "secret"));
    try std.testing.expectError(JWTError.InvalidToken, verify(allocator, "two.parts", "secret"));
    try std.testing.expectError(JWTError.InvalidToken, verify(allocator, "too.many.parts.here", "secret"));
}

test "base64UrlEncode" {
    const allocator = std.testing.allocator;

    const result = try base64UrlEncode(allocator, "hello");
    defer allocator.free(result);

    // Should produce base64url encoded output
    try std.testing.expectEqualStrings("aGVsbG8", result);
}

test "base64UrlDecode" {
    const allocator = std.testing.allocator;

    const result = try base64UrlDecode(allocator, "aGVsbG8");
    defer allocator.free(result);

    try std.testing.expectEqualStrings("hello", result);
}

test "base64Url roundtrip" {
    const allocator = std.testing.allocator;
    const original = "The quick brown fox jumps over the lazy dog";

    const encoded = try base64UrlEncode(allocator, original);
    defer allocator.free(encoded);

    const decoded = try base64UrlDecode(allocator, encoded);
    defer allocator.free(decoded);

    try std.testing.expectEqualStrings(original, decoded);
}

test "getFromCookie" {
    // Test with valid cookie
    const cookie1 = "other=value; plue_token=abc123; another=test";
    const token1 = getFromCookie(cookie1);
    try std.testing.expectEqualStrings("abc123", token1.?);

    // Test with missing cookie
    const cookie2 = "other=value; another=test";
    const token2 = getFromCookie(cookie2);
    try std.testing.expect(token2 == null);

    // Test with null header
    const token3 = getFromCookie(null);
    try std.testing.expect(token3 == null);

    // Test with plue_token as first cookie
    const cookie4 = "plue_token=firsttoken; other=value";
    const token4 = getFromCookie(cookie4);
    try std.testing.expectEqualStrings("firsttoken", token4.?);

    // Test with plue_token as only cookie
    const cookie5 = "plue_token=onlytoken";
    const token5 = getFromCookie(cookie5);
    try std.testing.expectEqualStrings("onlytoken", token5.?);
}
