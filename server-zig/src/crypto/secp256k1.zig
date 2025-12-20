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

test "eth message hash" {
    const hash = ethMessageHash("hello");
    // This should match: keccak256("\x19Ethereum Signed Message:\n5hello")
    _ = hash;
}

test "parse address" {
    const addr = try parseAddress("0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045");
    try std.testing.expectEqual(@as(u8, 0xd8), addr[0]);
}
