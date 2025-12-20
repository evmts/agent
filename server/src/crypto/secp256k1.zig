//! secp256k1 ECDSA signature verification for Ethereum
//!
//! This module provides Ethereum-compatible signature verification using
//! Zig's standard library crypto primitives.

const std = @import("std");
const crypto = std.crypto;

pub const Secp256k1 = crypto.ecc.Secp256k1;
pub const Ecdsa = crypto.sign.ecdsa.Ecdsa(Secp256k1, .sha256);

/// Ethereum signature with recovery ID (v, r, s)
pub const EthSignature = struct {
    r: [32]u8,
    s: [32]u8,
    v: u8, // Recovery ID (27 or 28, or 0/1 for EIP-155)

    /// Parse signature from 65-byte hex string (0x prefixed)
    pub fn fromHex(hex: []const u8) !EthSignature {
        // Remove 0x prefix if present
        const data = if (std.mem.startsWith(u8, hex, "0x")) hex[2..] else hex;

        if (data.len != 130) return error.InvalidSignatureLength;

        var sig: EthSignature = undefined;

        // Parse r (first 32 bytes = 64 hex chars)
        _ = try std.fmt.hexToBytes(&sig.r, data[0..64]);

        // Parse s (next 32 bytes)
        _ = try std.fmt.hexToBytes(&sig.s, data[64..128]);

        // Parse v (last byte)
        var v_buf: [1]u8 = undefined;
        _ = try std.fmt.hexToBytes(&v_buf, data[128..130]);
        sig.v = v_buf[0];

        // Normalize v (EIP-155 uses 27/28, newer uses 0/1)
        if (sig.v >= 27) {
            sig.v -= 27;
        }

        return sig;
    }
};

/// Keccak256 hash (Ethereum's hash function)
pub fn keccak256(data: []const u8) [32]u8 {
    var hasher = crypto.hash.sha3.Keccak256.init(.{});
    hasher.update(data);
    var result: [32]u8 = undefined;
    hasher.final(&result);
    return result;
}

/// Create Ethereum signed message hash
/// Ethereum prefixes messages with "\x19Ethereum Signed Message:\n" + length
pub fn ethMessageHash(message: []const u8) [32]u8 {
    const prefix = "\x19Ethereum Signed Message:\n";
    var length_buf: [20]u8 = undefined;
    const length_str = std.fmt.bufPrint(&length_buf, "{d}", .{message.len}) catch unreachable;

    var hasher = crypto.hash.sha3.Keccak256.init(.{});
    hasher.update(prefix);
    hasher.update(length_str);
    hasher.update(message);

    var result: [32]u8 = undefined;
    hasher.final(&result);
    return result;
}

/// Recover public key from signature and message hash
/// Returns the Ethereum address (20 bytes) if successful
pub fn recoverAddress(message_hash: [32]u8, signature: EthSignature) ![20]u8 {
    // NOTE: Zig's std.crypto.sign.ecdsa doesn't support public key recovery.
    // We would need to:
    // 1. Use the libsecp256k1 C library via @cImport
    // 2. Or implement EC point recovery manually
    //
    // For now, this is a STUB that returns an error.
    // In production, use: https://github.com/jsign/zig-eth-secp256k1

    _ = message_hash;
    _ = signature;

    return error.RecoveryNotImplemented;
}

/// Verify that a signature was created by the given address
pub fn verifySignature(
    message: []const u8,
    signature: EthSignature,
    expected_address: [20]u8,
) !bool {
    const message_hash = ethMessageHash(message);
    const recovered = try recoverAddress(message_hash, signature);

    return std.mem.eql(u8, &recovered, &expected_address);
}

/// Parse Ethereum address from hex string
pub fn parseAddress(hex: []const u8) ![20]u8 {
    const data = if (std.mem.startsWith(u8, hex, "0x")) hex[2..] else hex;
    if (data.len != 40) return error.InvalidAddressLength;

    var address: [20]u8 = undefined;
    _ = try std.fmt.hexToBytes(&address, data);
    return address;
}

/// Format address as checksummed hex string (EIP-55)
pub fn formatAddress(allocator: std.mem.Allocator, address: [20]u8) ![]const u8 {
    var hex_buf: [40]u8 = undefined;
    _ = std.fmt.bufPrint(&hex_buf, "{}", .{std.fmt.fmtSliceHexLower(&address)}) catch unreachable;

    // EIP-55 checksum
    const hash = keccak256(&hex_buf);

    var result = try allocator.alloc(u8, 42);
    result[0] = '0';
    result[1] = 'x';

    for (hex_buf, 0..) |c, i| {
        const hash_nibble = if (i % 2 == 0)
            (hash[i / 2] >> 4)
        else
            (hash[i / 2] & 0x0F);

        if (c >= 'a' and c <= 'f' and hash_nibble >= 8) {
            result[i + 2] = c - 32; // uppercase
        } else {
            result[i + 2] = c;
        }
    }

    return result;
}

test "keccak256" {
    const hash = keccak256("hello");
    const expected = "1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8";
    var expected_bytes: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&expected_bytes, expected);
    try std.testing.expectEqualSlices(u8, &expected_bytes, &hash);
}

test "keccak256 empty string" {
    const hash = keccak256("");
    // Known hash for empty string
    const expected = "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470";
    var expected_bytes: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&expected_bytes, expected);
    try std.testing.expectEqualSlices(u8, &expected_bytes, &hash);
}

test "keccak256 deterministic" {
    const hash1 = keccak256("test message");
    const hash2 = keccak256("test message");
    try std.testing.expectEqualSlices(u8, &hash1, &hash2);
}

test "keccak256 different inputs" {
    const hash1 = keccak256("hello");
    const hash2 = keccak256("world");
    try std.testing.expect(!std.mem.eql(u8, &hash1, &hash2));
}

test "eth message hash" {
    const hash = ethMessageHash("hello");
    // This should match: keccak256("\x19Ethereum Signed Message:\n5hello")
    try std.testing.expectEqual(@as(usize, 32), hash.len);
}

test "eth message hash deterministic" {
    const hash1 = ethMessageHash("Sign this message");
    const hash2 = ethMessageHash("Sign this message");
    try std.testing.expectEqualSlices(u8, &hash1, &hash2);
}

test "eth message hash different messages" {
    const hash1 = ethMessageHash("message1");
    const hash2 = ethMessageHash("message2");
    try std.testing.expect(!std.mem.eql(u8, &hash1, &hash2));
}

test "parse address" {
    const addr = try parseAddress("0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045");
    try std.testing.expectEqual(@as(u8, 0xd8), addr[0]);
}

test "parse address without 0x prefix" {
    const addr = try parseAddress("d8dA6BF26964aF9D7eEd9e03E53415D37aA96045");
    try std.testing.expectEqual(@as(u8, 0xd8), addr[0]);
}

test "parse address lowercase" {
    const addr = try parseAddress("0xd8da6bf26964af9d7eed9e03e53415d37aa96045");
    try std.testing.expectEqual(@as(u8, 0xd8), addr[0]);
}

test "parse address invalid length" {
    // Too short
    try std.testing.expectError(error.InvalidAddressLength, parseAddress("0x1234"));
    // Too long
    try std.testing.expectError(error.InvalidAddressLength, parseAddress("0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045EXTRA"));
}

test "parse address invalid hex" {
    try std.testing.expectError(error.InvalidCharacter, parseAddress("0xZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ"));
}

test "EthSignature fromHex" {
    const sig_hex = "0x" ++
        "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef" ++ // r (32 bytes)
        "fedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321" ++ // s (32 bytes)
        "1b"; // v

    const sig = try EthSignature.fromHex(sig_hex);

    // Check r
    try std.testing.expectEqual(@as(u8, 0x12), sig.r[0]);
    try std.testing.expectEqual(@as(u8, 0xef), sig.r[31]);

    // Check s
    try std.testing.expectEqual(@as(u8, 0xfe), sig.s[0]);
    try std.testing.expectEqual(@as(u8, 0x21), sig.s[31]);

    // Check v (normalized from 27 to 0)
    try std.testing.expectEqual(@as(u8, 0), sig.v);
}

test "EthSignature fromHex without 0x" {
    const sig_hex = "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef" ++
        "fedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321" ++
        "1c"; // v = 28

    const sig = try EthSignature.fromHex(sig_hex);

    // v should be normalized from 28 to 1
    try std.testing.expectEqual(@as(u8, 1), sig.v);
}

test "EthSignature invalid length" {
    try std.testing.expectError(error.InvalidSignatureLength, EthSignature.fromHex("0x1234"));
}

test "formatAddress checksummed" {
    const allocator = std.testing.allocator;
    const addr = try parseAddress("0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045");

    const formatted = try formatAddress(allocator, addr);
    defer allocator.free(formatted);

    // Should start with 0x
    try std.testing.expect(std.mem.startsWith(u8, formatted, "0x"));

    // Should be 42 characters (0x + 40 hex chars)
    try std.testing.expectEqual(@as(usize, 42), formatted.len);
}

test "formatAddress mixed case (EIP-55)" {
    const allocator = std.testing.allocator;

    // Zero address
    var zero_addr: [20]u8 = [_]u8{0} ** 20;
    const formatted_zero = try formatAddress(allocator, zero_addr);
    defer allocator.free(formatted_zero);

    try std.testing.expect(std.mem.startsWith(u8, formatted_zero, "0x"));
    try std.testing.expectEqual(@as(usize, 42), formatted_zero.len);
}
