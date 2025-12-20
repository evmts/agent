//! Plue JWT - JSON Web Token signing and verification
//!
//! A native Zig library for JWT operations using HS256 (HMAC-SHA256).
//! Designed to be called from Bun via FFI.

const std = @import("std");
const HmacSha256 = std.crypto.auth.hmac.sha2.HmacSha256;
const base64url = std.base64.url_safe_no_pad;
const Allocator = std.mem.Allocator;

pub const JWTError = error{
    InvalidToken,
    InvalidHeader,
    InvalidPayload,
    InvalidSignature,
    TokenExpired,
    SignatureMismatch,
    SecretNotSet,
    EncodingError,
    DecodingError,
    AllocationError,
};

/// JWT Header structure
pub const Header = struct {
    alg: []const u8 = "HS256",
    typ: []const u8 = "JWT",
};

/// JWT Manager - handles signing and verification
pub const JWTManager = struct {
    secret: []const u8,
    allocator: Allocator,

    pub fn init(allocator: Allocator, secret: []const u8) JWTManager {
        return .{
            .secret = secret,
            .allocator = allocator,
        };
    }

    /// Sign a JSON payload and return a JWT token
    pub fn sign(self: *const JWTManager, payload_json: []const u8) ![]const u8 {
        // Create header JSON
        const header_json = "{\"alg\":\"HS256\",\"typ\":\"JWT\"}";

        // Base64URL encode header
        const header_len = base64url.Encoder.calcSize(header_json.len);
        const header_b64 = try self.allocator.alloc(u8, header_len);
        defer self.allocator.free(header_b64);
        _ = base64url.Encoder.encode(header_b64, header_json);

        // Base64URL encode payload
        const payload_len = base64url.Encoder.calcSize(payload_json.len);
        const payload_b64 = try self.allocator.alloc(u8, payload_len);
        defer self.allocator.free(payload_b64);
        _ = base64url.Encoder.encode(payload_b64, payload_json);

        // Create signing input: header.payload
        const signing_input_len = header_len + 1 + payload_len;
        const signing_input = try self.allocator.alloc(u8, signing_input_len);
        defer self.allocator.free(signing_input);

        @memcpy(signing_input[0..header_len], header_b64);
        signing_input[header_len] = '.';
        @memcpy(signing_input[header_len + 1 ..][0..payload_len], payload_b64);

        // Compute HMAC-SHA256 signature
        var mac: [HmacSha256.mac_length]u8 = undefined;
        HmacSha256.create(&mac, signing_input, self.secret);

        // Base64URL encode signature
        const sig_len = base64url.Encoder.calcSize(HmacSha256.mac_length);
        const sig_b64 = try self.allocator.alloc(u8, sig_len);
        defer self.allocator.free(sig_b64);
        _ = base64url.Encoder.encode(sig_b64, &mac);

        // Build final token: header.payload.signature
        const token_len = header_len + 1 + payload_len + 1 + sig_len;
        const token = try self.allocator.alloc(u8, token_len);

        @memcpy(token[0..header_len], header_b64);
        token[header_len] = '.';
        @memcpy(token[header_len + 1 ..][0..payload_len], payload_b64);
        token[header_len + 1 + payload_len] = '.';
        @memcpy(token[header_len + 1 + payload_len + 1 ..][0..sig_len], sig_b64);

        return token;
    }

    /// Verify a JWT token and return the decoded payload
    pub fn verify(self: *const JWTManager, token: []const u8) ![]const u8 {
        // Split token into parts
        var parts: [3][]const u8 = undefined;
        var part_count: usize = 0;
        var start: usize = 0;

        for (token, 0..) |char, i| {
            if (char == '.') {
                if (part_count >= 3) return JWTError.InvalidToken;
                parts[part_count] = token[start..i];
                part_count += 1;
                start = i + 1;
            }
        }
        if (part_count == 2) {
            parts[2] = token[start..];
            part_count = 3;
        }

        if (part_count != 3) return JWTError.InvalidToken;

        const header_b64 = parts[0];
        const payload_b64 = parts[1];
        const sig_b64 = parts[2];

        // Verify header is valid base64
        const header_decoded_len = base64url.Decoder.calcSizeForSlice(header_b64) catch return JWTError.InvalidHeader;
        const header_decoded = try self.allocator.alloc(u8, header_decoded_len);
        defer self.allocator.free(header_decoded);
        base64url.Decoder.decode(header_decoded, header_b64) catch return JWTError.InvalidHeader;

        // Verify it's HS256
        const parsed_header = std.json.parseFromSlice(Header, self.allocator, header_decoded, .{}) catch return JWTError.InvalidHeader;
        defer parsed_header.deinit();

        if (!std.mem.eql(u8, parsed_header.value.alg, "HS256")) {
            return JWTError.InvalidHeader;
        }

        // Recompute signature
        const signing_input_len = header_b64.len + 1 + payload_b64.len;
        const signing_input = try self.allocator.alloc(u8, signing_input_len);
        defer self.allocator.free(signing_input);

        @memcpy(signing_input[0..header_b64.len], header_b64);
        signing_input[header_b64.len] = '.';
        @memcpy(signing_input[header_b64.len + 1 ..][0..payload_b64.len], payload_b64);

        var expected_mac: [HmacSha256.mac_length]u8 = undefined;
        HmacSha256.create(&expected_mac, signing_input, self.secret);

        // Decode provided signature
        const sig_decoded_len = base64url.Decoder.calcSizeForSlice(sig_b64) catch return JWTError.InvalidSignature;
        if (sig_decoded_len != HmacSha256.mac_length) return JWTError.InvalidSignature;

        var sig_decoded: [HmacSha256.mac_length]u8 = undefined;
        base64url.Decoder.decode(&sig_decoded, sig_b64) catch return JWTError.InvalidSignature;

        // Constant-time comparison
        if (!std.crypto.timing_safe.eql([HmacSha256.mac_length]u8, sig_decoded, expected_mac)) {
            return JWTError.SignatureMismatch;
        }

        // Decode and return payload
        const payload_decoded_len = base64url.Decoder.calcSizeForSlice(payload_b64) catch return JWTError.InvalidPayload;
        const payload_decoded = try self.allocator.alloc(u8, payload_decoded_len);
        base64url.Decoder.decode(payload_decoded, payload_b64) catch {
            self.allocator.free(payload_decoded);
            return JWTError.InvalidPayload;
        };

        // Optionally check expiration
        if (self.checkExpiration(payload_decoded)) |expired| {
            if (expired) {
                self.allocator.free(payload_decoded);
                return JWTError.TokenExpired;
            }
        }

        return payload_decoded;
    }

    /// Check if token is expired based on "exp" claim
    fn checkExpiration(self: *const JWTManager, payload: []const u8) ?bool {
        _ = self;
        const parsed = std.json.parseFromSlice(struct { exp: ?i64 = null }, std.heap.page_allocator, payload, .{}) catch return null;
        defer parsed.deinit();

        if (parsed.value.exp) |exp| {
            const now = std.time.timestamp();
            return now > exp;
        }
        return null;
    }

    /// Free memory allocated by sign/verify
    pub fn free(self: *const JWTManager, ptr: []const u8) void {
        self.allocator.free(ptr);
    }
};

// ============================================================================
// C FFI Interface for Bun
// ============================================================================

var global_manager: ?*JWTManager = null;
var global_secret: ?[]u8 = null;
var gpa = std.heap.GeneralPurposeAllocator(.{}){};

/// Initialize the JWT manager with a secret
export fn jwt_init(secret: [*]const u8, secret_len: usize) bool {
    if (global_manager != null) return true;

    const allocator = gpa.allocator();

    // Copy secret so we own it
    const secret_copy = allocator.alloc(u8, secret_len) catch return false;
    @memcpy(secret_copy, secret[0..secret_len]);
    global_secret = secret_copy;

    const manager = allocator.create(JWTManager) catch return false;
    manager.* = JWTManager.init(allocator, secret_copy);
    global_manager = manager;
    return true;
}

/// Cleanup the JWT manager
export fn jwt_cleanup() void {
    const allocator = gpa.allocator();
    if (global_manager) |manager| {
        allocator.destroy(manager);
        global_manager = null;
    }
    if (global_secret) |secret| {
        allocator.free(secret);
        global_secret = null;
    }
}

/// Sign a JSON payload and return a JWT token (null-terminated)
/// Returns null on error. Caller must free with jwt_free.
export fn jwt_sign(payload_json: [*:0]const u8) ?[*:0]u8 {
    const manager = global_manager orelse return null;
    const payload = std.mem.span(payload_json);

    const token = manager.sign(payload) catch return null;

    // Create null-terminated copy for C
    const allocator = gpa.allocator();
    const result = allocator.allocSentinel(u8, token.len, 0) catch {
        allocator.free(token);
        return null;
    };
    @memcpy(result[0..token.len], token);
    allocator.free(token);

    return result.ptr;
}

/// Verify a JWT token and return the decoded payload (null-terminated)
/// Returns null on error (invalid token, expired, etc). Caller must free with jwt_free.
export fn jwt_verify(token: [*:0]const u8) ?[*:0]u8 {
    const manager = global_manager orelse return null;
    const token_slice = std.mem.span(token);

    const payload = manager.verify(token_slice) catch return null;

    // Create null-terminated copy for C
    const allocator = gpa.allocator();
    const result = allocator.allocSentinel(u8, payload.len, 0) catch {
        allocator.free(payload);
        return null;
    };
    @memcpy(result[0..payload.len], payload);
    allocator.free(payload);

    return result.ptr;
}

/// Free memory allocated by jwt_sign or jwt_verify
export fn jwt_free(ptr: [*]u8) void {
    // We need to find the length to free properly
    // Since we use sentinel-terminated allocations, find the null
    var len: usize = 0;
    while (ptr[len] != 0) : (len += 1) {}
    const allocator = gpa.allocator();
    allocator.free(ptr[0 .. len + 1]); // +1 for sentinel
}

// ============================================================================
// Tests
// ============================================================================

test "sign and verify JWT" {
    const allocator = std.testing.allocator;

    var manager = JWTManager.init(allocator, "test-secret-key");

    const payload = "{\"userId\":123,\"username\":\"testuser\"}";
    const token = try manager.sign(payload);
    defer manager.free(token);

    // Token should have 3 parts
    var dot_count: usize = 0;
    for (token) |c| {
        if (c == '.') dot_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), dot_count);

    // Verify should return original payload
    const decoded = try manager.verify(token);
    defer manager.free(decoded);

    try std.testing.expectEqualStrings(payload, decoded);
}

test "verify fails with wrong secret" {
    const allocator = std.testing.allocator;

    var manager1 = JWTManager.init(allocator, "secret1");
    var manager2 = JWTManager.init(allocator, "secret2");

    const payload = "{\"test\":true}";
    const token = try manager1.sign(payload);
    defer manager1.free(token);

    // Should fail verification with different secret
    const result = manager2.verify(token);
    try std.testing.expectError(JWTError.SignatureMismatch, result);
}

test "verify fails with tampered payload" {
    const allocator = std.testing.allocator;

    var manager = JWTManager.init(allocator, "test-secret");

    const token = try manager.sign("{\"userId\":1}");
    defer manager.free(token);

    // Tamper with the token (change a character in payload)
    var tampered = try allocator.dupe(u8, token);
    defer allocator.free(tampered);

    // Find second dot and modify a byte before it
    var dots: usize = 0;
    for (tampered, 0..) |c, i| {
        if (c == '.') {
            dots += 1;
            if (dots == 2 and i > 0) {
                tampered[i - 1] = if (tampered[i - 1] == 'a') 'b' else 'a';
                break;
            }
        }
    }

    const result = manager.verify(tampered);
    try std.testing.expectError(JWTError.SignatureMismatch, result);
}

test "verify fails with invalid token format" {
    const allocator = std.testing.allocator;

    var manager = JWTManager.init(allocator, "test-secret");

    try std.testing.expectError(JWTError.InvalidToken, manager.verify("not.a.valid.token.toomanyparts"));
    try std.testing.expectError(JWTError.InvalidToken, manager.verify("onlyonepart"));
    try std.testing.expectError(JWTError.InvalidToken, manager.verify("two.parts"));
}

test "expired token" {
    const allocator = std.testing.allocator;

    var manager = JWTManager.init(allocator, "test-secret");

    // Create a payload with expired timestamp (1 second in the past)
    const expired_payload = "{\"exp\":0}";
    const token = try manager.sign(expired_payload);
    defer manager.free(token);

    const result = manager.verify(token);
    try std.testing.expectError(JWTError.TokenExpired, result);
}
