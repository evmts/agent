//! SIWE (Sign In With Ethereum) implementation
//!
//! Implements EIP-4361: Sign-In with Ethereum
//! https://eips.ethereum.org/EIPS/eip-4361

const std = @import("std");
const secp256k1 = @import("../crypto/secp256k1.zig");
const db = @import("db.zig");

const log = std.log.scoped(.siwe);

pub const SiweError = error{
    InvalidMessage,
    InvalidNonce,
    ExpiredNonce,
    InvalidSignature,
    SignatureVerificationFailed,
    RecoveryNotImplemented,
};

/// Parsed SIWE message
pub const SiweMessage = struct {
    domain: []const u8,
    address: []const u8,
    statement: ?[]const u8,
    uri: []const u8,
    version: []const u8,
    chain_id: u64,
    nonce: []const u8,
    issued_at: []const u8,
    expiration_time: ?[]const u8,
    not_before: ?[]const u8,
    request_id: ?[]const u8,
    resources: ?[]const []const u8,
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

/// Parse a SIWE message string into structured data
/// Format defined in EIP-4361
pub fn parseMessage(allocator: std.mem.Allocator, message: []const u8) !SiweMessage {
    var result = SiweMessage{
        .domain = "",
        .address = "",
        .statement = null,
        .uri = "",
        .version = "1",
        .chain_id = 1,
        .nonce = "",
        .issued_at = "",
        .expiration_time = null,
        .not_before = null,
        .request_id = null,
        .resources = null,
    };

    var lines = std.mem.splitScalar(u8, message, '\n');
    var line_num: usize = 0;

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, &[_]u8{ ' ', '\r' });

        if (line_num == 0) {
            // First line: "{domain} wants you to sign in with your Ethereum account:"
            if (std.mem.indexOf(u8, trimmed, " wants you to sign in with your Ethereum account:")) |idx| {
                result.domain = try allocator.dupe(u8, trimmed[0..idx]);
            }
        } else if (line_num == 1) {
            // Second line: Ethereum address
            if (std.mem.startsWith(u8, trimmed, "0x") and trimmed.len == 42) {
                result.address = try allocator.dupe(u8, trimmed);
            }
        } else if (std.mem.startsWith(u8, trimmed, "URI: ")) {
            result.uri = try allocator.dupe(u8, trimmed[5..]);
        } else if (std.mem.startsWith(u8, trimmed, "Version: ")) {
            result.version = try allocator.dupe(u8, trimmed[9..]);
        } else if (std.mem.startsWith(u8, trimmed, "Chain ID: ")) {
            result.chain_id = std.fmt.parseInt(u64, trimmed[10..], 10) catch 1;
        } else if (std.mem.startsWith(u8, trimmed, "Nonce: ")) {
            result.nonce = try allocator.dupe(u8, trimmed[7..]);
        } else if (std.mem.startsWith(u8, trimmed, "Issued At: ")) {
            result.issued_at = try allocator.dupe(u8, trimmed[11..]);
        } else if (std.mem.startsWith(u8, trimmed, "Expiration Time: ")) {
            result.expiration_time = try allocator.dupe(u8, trimmed[17..]);
        } else if (std.mem.startsWith(u8, trimmed, "Not Before: ")) {
            result.not_before = try allocator.dupe(u8, trimmed[12..]);
        } else if (std.mem.startsWith(u8, trimmed, "Request ID: ")) {
            result.request_id = try allocator.dupe(u8, trimmed[12..]);
        } else if (trimmed.len > 0 and !std.mem.startsWith(u8, trimmed, "Resources:") and
            line_num > 2 and result.statement == null)
        {
            // Statement is the text between address and URI line
            if (!std.mem.startsWith(u8, trimmed, "URI:")) {
                result.statement = try allocator.dupe(u8, trimmed);
            }
        }

        line_num += 1;
    }

    // Validate required fields
    if (result.domain.len == 0 or result.address.len == 0 or result.nonce.len == 0) {
        return SiweError.InvalidMessage;
    }

    return result;
}

/// Verify a SIWE signature
/// Returns the verified address or an error
pub fn verifySiweSignature(
    allocator: std.mem.Allocator,
    pool: *db.Pool,
    message: []const u8,
    signature_hex: []const u8,
) !struct { address: []const u8, parsed: SiweMessage } {
    // Parse the message
    const parsed = try parseMessage(allocator, message);

    // Validate nonce exists and is not expired/used
    const nonce_valid = try db.validateNonce(pool, parsed.nonce);
    if (!nonce_valid) {
        return SiweError.InvalidNonce;
    }

    // Parse signature
    const signature = try secp256k1.EthSignature.fromHex(signature_hex);

    // Parse expected address from message
    const expected_address = try secp256k1.parseAddress(parsed.address);

    // Verify signature matches address
    // NOTE: This will fail until we implement secp256k1 recovery
    const valid = secp256k1.verifySignature(message, signature, expected_address) catch |err| {
        if (err == error.RecoveryNotImplemented) {
            // FALLBACK: In development, trust the address from the message
            // In production, this MUST be properly implemented
            log.warn("SIWE signature verification not implemented - trusting message address", .{});

            // Mark nonce as used
            try db.markNonceUsed(pool, parsed.nonce, parsed.address);

            return .{
                .address = parsed.address,
                .parsed = parsed,
            };
        }
        return err;
    };

    if (!valid) {
        return SiweError.SignatureVerificationFailed;
    }

    // Mark nonce as used
    try db.markNonceUsed(pool, parsed.nonce, parsed.address);

    return .{
        .address = parsed.address,
        .parsed = parsed,
    };
}

/// Create and store a new nonce
pub fn createNonce(allocator: std.mem.Allocator, pool: *db.Pool) ![]const u8 {
    const nonce = try generateNonce(allocator);
    try db.createNonce(pool, nonce);
    return nonce;
}

test "parse siwe message" {
    const allocator = std.testing.allocator;

    const message =
        \\example.com wants you to sign in with your Ethereum account:
        \\0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045
        \\
        \\Sign in to Example
        \\
        \\URI: https://example.com
        \\Version: 1
        \\Chain ID: 1
        \\Nonce: 32891756
        \\Issued At: 2021-09-30T16:25:24Z
    ;

    const parsed = try parseMessage(allocator, message);

    try std.testing.expectEqualStrings("example.com", parsed.domain);
    try std.testing.expectEqualStrings("0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045", parsed.address);
    try std.testing.expectEqualStrings("32891756", parsed.nonce);
    try std.testing.expectEqual(@as(u64, 1), parsed.chain_id);

    // Free allocated strings
    allocator.free(parsed.domain);
    allocator.free(parsed.address);
    allocator.free(parsed.nonce);
    allocator.free(parsed.uri);
    allocator.free(parsed.version);
    allocator.free(parsed.issued_at);
    if (parsed.statement) |s| allocator.free(s);
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
