//! SIWE (Sign In With Ethereum) implementation
//!
//! Wraps voltaire's SIWE module (EIP-4361)
//! https://eips.ethereum.org/EIPS/eip-4361

const std = @import("std");
const primitives = @import("primitives");
const crypto_pkg = @import("crypto");
const db = @import("db.zig");

const log = std.log.scoped(.siwe);

// Re-export voltaire's SIWE types
pub const SiweMessage = primitives.Siwe.SiweMessage;
pub const SiweError = primitives.Siwe.SiweError;
const Address = primitives.Address.Address;
const Signature = crypto_pkg.Crypto.Signature;

pub const AuthError = error{
    InvalidMessage,
    InvalidNonce,
    ExpiredNonce,
    InvalidSignature,
    SignatureVerificationFailed,
    DatabaseError,
    OutOfMemory,
};

/// Generate a cryptographically secure nonce
pub fn generateNonce(allocator: std.mem.Allocator) ![]const u8 {
    var bytes: [16]u8 = undefined;
    std.crypto.random.bytes(&bytes);

    // Convert to alphanumeric string
    const charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
    var nonce = try allocator.alloc(u8, 16);

    for (bytes, 0..) |b, i| {
        nonce[i] = charset[b % charset.len];
    }

    return nonce;
}

/// Parse a SIWE message string
pub fn parseMessage(allocator: std.mem.Allocator, message: []const u8) !SiweMessage {
    return primitives.Siwe.parseSiweMessage(allocator, message);
}

/// Verify a SIWE signature using voltaire's crypto
/// Returns the verified address or an error
pub fn verifySiweSignature(
    allocator: std.mem.Allocator,
    pool: *db.Pool,
    message_text: []const u8,
    signature_hex: []const u8,
) !struct { address: Address, parsed: SiweMessage } {
    // Parse the message using voltaire
    const parsed = try primitives.Siwe.parseSiweMessage(allocator, message_text);
    errdefer {
        allocator.free(parsed.domain);
        if (parsed.statement) |s| allocator.free(s);
        allocator.free(parsed.uri);
        allocator.free(parsed.version);
        allocator.free(parsed.nonce);
        allocator.free(parsed.issued_at);
    }

    // Validate nonce exists and is not expired/used
    const nonce_valid = db.validateNonce(pool, parsed.nonce) catch {
        return AuthError.DatabaseError;
    };
    if (!nonce_valid) {
        return AuthError.InvalidNonce;
    }

    // Parse signature from hex (remove 0x prefix if present)
    const sig_data = if (std.mem.startsWith(u8, signature_hex, "0x"))
        signature_hex[2..]
    else
        signature_hex;

    if (sig_data.len != 130) {
        return AuthError.InvalidSignature;
    }

    // Decode hex to bytes
    var sig_bytes: [65]u8 = undefined;
    _ = std.fmt.hexToBytes(&sig_bytes, sig_data) catch {
        return AuthError.InvalidSignature;
    };

    // Convert r and s to u256 (big-endian)
    const r: u256 = std.mem.readInt(u256, sig_bytes[0..32], .big);
    const s: u256 = std.mem.readInt(u256, sig_bytes[32..64], .big);

    // Create Signature struct
    const signature = Signature{
        .r = r,
        .s = s,
        .v = sig_bytes[64],
    };

    // Verify using voltaire's verifySiweMessage
    const verified = primitives.Siwe.verifySiweMessage(allocator, &parsed, signature) catch |err| {
        log.warn("SIWE verification failed: {}", .{err});
        return AuthError.SignatureVerificationFailed;
    };

    if (!verified) {
        return AuthError.SignatureVerificationFailed;
    }

    // Convert address to hex for DB
    const addr_hex = try primitives.Hex.toHex(allocator, &parsed.address.bytes);
    defer allocator.free(addr_hex);

    // Mark nonce as used
    db.markNonceUsed(pool, parsed.nonce, addr_hex) catch {
        return AuthError.DatabaseError;
    };

    return .{
        .address = parsed.address,
        .parsed = parsed,
    };
}

/// Create and store a new nonce
pub fn createNonce(allocator: std.mem.Allocator, pool: *db.Pool) ![]const u8 {
    const nonce = try generateNonce(allocator);
    db.createNonce(pool, nonce) catch {
        allocator.free(nonce);
        return AuthError.DatabaseError;
    };
    return nonce;
}

/// Get address as hex string
pub fn addressToHex(allocator: std.mem.Allocator, addr: Address) ![]const u8 {
    return primitives.Hex.toHex(allocator, &addr.bytes);
}

test "generate nonce" {
    const allocator = std.testing.allocator;

    const nonce1 = try generateNonce(allocator);
    defer allocator.free(nonce1);

    const nonce2 = try generateNonce(allocator);
    defer allocator.free(nonce2);

    // Nonces should be different
    try std.testing.expect(!std.mem.eql(u8, nonce1, nonce2));

    // Nonces should be 16 characters
    try std.testing.expectEqual(@as(usize, 16), nonce1.len);
}

test "generate nonce contains only alphanumeric" {
    const allocator = std.testing.allocator;

    const nonce = try generateNonce(allocator);
    defer allocator.free(nonce);

    // All characters should be alphanumeric
    for (nonce) |c| {
        const is_valid = (c >= 'A' and c <= 'Z') or
            (c >= 'a' and c <= 'z') or
            (c >= '0' and c <= '9');
        try std.testing.expect(is_valid);
    }
}

test "generate nonce uniqueness" {
    const allocator = std.testing.allocator;

    // Generate multiple nonces and ensure they're all unique
    var nonces: [10][]const u8 = undefined;
    var count: usize = 0;
    defer {
        for (nonces[0..count]) |n| {
            allocator.free(n);
        }
    }

    for (&nonces) |*n| {
        n.* = try generateNonce(allocator);
        count += 1;
    }

    // Check all pairs are different
    for (0..count) |i| {
        for (i + 1..count) |j| {
            try std.testing.expect(!std.mem.eql(u8, nonces[i], nonces[j]));
        }
    }
}
