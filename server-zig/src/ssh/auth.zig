/// SSH Public Key Authentication
/// Validates SSH public keys against the database
const std = @import("std");
const types = @import("types.zig");
const db = @import("../lib/db.zig");
const crypto = @import("crypto");

const log = std.log.scoped(.ssh_auth);

/// The SSH username must be 'git' (like GitHub)
const ALLOWED_USER = "git";

/// Calculate SSH key fingerprint (SHA256)
pub fn calculateFingerprint(allocator: std.mem.Allocator, public_key: []const u8) ![]u8 {
    // Parse the SSH public key format
    // Format: "ssh-rsa AAAAB3NzaC1yc2E... comment"
    var parts = std.mem.tokenizeScalar(u8, public_key, ' ');
    _ = parts.next() orelse return error.InvalidKeyFormat; // key type
    const key_data_b64 = parts.next() orelse return error.InvalidKeyFormat;

    // Decode base64
    const decoder = std.base64.standard.Decoder;
    const max_size = try decoder.calcSizeForSlice(key_data_b64);
    const key_data = try allocator.alloc(u8, max_size);
    defer allocator.free(key_data);

    const decoded_len = try decoder.decode(key_data, key_data_b64);
    const decoded = key_data[0..decoded_len];

    // Calculate SHA256 hash
    var hash: [32]u8 = undefined;
    crypto.sha256.hash(decoded, &hash, .{});

    // Encode to base64 and format as "SHA256:..."
    const b64_encoder = std.base64.standard.Encoder;
    const b64_len = b64_encoder.calcSize(hash.len);
    const b64_buf = try allocator.alloc(u8, b64_len);
    const encoded = b64_encoder.encode(b64_buf, &hash);

    // Remove trailing '=' padding
    var end = encoded.len;
    while (end > 0 and encoded[end - 1] == '=') : (end -= 1) {}

    // Format as "SHA256:hash"
    const result = try std.fmt.allocPrint(allocator, "SHA256:{s}", .{encoded[0..end]});
    allocator.free(b64_buf);

    return result;
}

/// Authenticate SSH public key against database
pub fn authenticatePublicKey(
    allocator: std.mem.Allocator,
    pool: *db.Pool,
    username: []const u8,
    public_key_blob: []const u8,
) !?types.AuthUser {
    // Validate username is 'git'
    if (!std.mem.eql(u8, username, ALLOWED_USER)) {
        log.warn("SSH auth rejected: username must be '{s}', got '{s}'", .{ ALLOWED_USER, username });
        return null;
    }

    // We need to match the key blob against stored keys
    // For now, we'll use a fingerprint-based approach
    // In production, you'd want to parse the blob and compare directly

    // Get a connection from the pool
    var conn = try pool.acquire();
    defer conn.release();

    // Calculate fingerprint from the blob
    // The blob is in SSH wire format, we need to convert it to OpenSSH format first
    // For simplicity, we'll query all keys and compare
    const query =
        \\SELECT k.id, k.user_id, k.fingerprint, k.public_key, u.username
        \\FROM ssh_keys k
        \\JOIN users u ON k.user_id = u.id
        \\WHERE u.is_active = true
    ;

    var result = try conn.query(query, .{});
    defer result.deinit();

    while (try result.next()) |row| {
        const key_id = row.get(i64, 0);
        const user_id = row.get(i64, 1);
        const stored_fingerprint = try row.get([]const u8, 2);
        const stored_public_key = try row.get([]const u8, 3);
        const user_username = try row.get([]const u8, 4);

        // Try to match the key blob against this stored key
        if (try matchPublicKey(allocator, public_key_blob, stored_public_key)) {
            log.info("SSH auth success: user_id={d}, key_id={d}, username={s}", .{ user_id, key_id, user_username });

            return types.AuthUser{
                .user_id = user_id,
                .username = try allocator.dupe(u8, user_username),
                .key_id = key_id,
            };
        }
    }

    log.warn("SSH auth failed: no matching key found", .{});
    return null;
}

/// Match SSH public key blob against stored OpenSSH format key
fn matchPublicKey(allocator: std.mem.Allocator, blob: []const u8, stored_key: []const u8) !bool {
    // Parse stored key to get the key data
    var parts = std.mem.tokenizeScalar(u8, stored_key, ' ');
    _ = parts.next() orelse return false; // key type
    const key_data_b64 = parts.next() orelse return false;

    // Decode base64
    const decoder = std.base64.standard.Decoder;
    const max_size = try decoder.calcSizeForSlice(key_data_b64);
    const key_data = try allocator.alloc(u8, max_size);
    defer allocator.free(key_data);

    const decoded_len = try decoder.decode(key_data, key_data_b64);
    const decoded = key_data[0..decoded_len];

    // Compare blob with decoded key data
    if (blob.len != decoded.len) return false;

    return std.mem.eql(u8, blob, decoded);
}

/// Validate public key format
pub fn validatePublicKeyFormat(public_key: []const u8) !void {
    var parts = std.mem.tokenizeScalar(u8, public_key, ' ');

    // Must have at least key type and data
    const key_type = parts.next() orelse return error.InvalidKeyFormat;
    _ = parts.next() orelse return error.InvalidKeyFormat;

    // Validate key type
    const valid_types = [_][]const u8{
        "ssh-rsa",
        "ssh-ed25519",
        "ecdsa-sha2-nistp256",
        "ecdsa-sha2-nistp384",
        "ecdsa-sha2-nistp521",
    };

    for (valid_types) |valid_type| {
        if (std.mem.eql(u8, key_type, valid_type)) return;
    }

    return error.UnsupportedKeyType;
}

/// Parse key type from public key
pub fn parseKeyType(allocator: std.mem.Allocator, public_key: []const u8) ![]u8 {
    var parts = std.mem.tokenizeScalar(u8, public_key, ' ');
    const key_type = parts.next() orelse return error.InvalidKeyFormat;
    return allocator.dupe(u8, key_type);
}

test "calculateFingerprint" {
    const allocator = std.testing.allocator;

    // Example RSA public key (truncated for brevity)
    const test_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDKz test@example.com";

    const fingerprint = try calculateFingerprint(allocator, test_key);
    defer allocator.free(fingerprint);

    try std.testing.expect(std.mem.startsWith(u8, fingerprint, "SHA256:"));
}

test "validatePublicKeyFormat" {
    // Valid keys
    try validatePublicKeyFormat("ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQ comment");
    try validatePublicKeyFormat("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK comment");

    // Invalid keys
    try std.testing.expectError(error.InvalidKeyFormat, validatePublicKeyFormat("invalid"));
    try std.testing.expectError(error.InvalidKeyFormat, validatePublicKeyFormat("ssh-rsa"));
    try std.testing.expectError(error.UnsupportedKeyType, validatePublicKeyFormat("ssh-invalid AAAAB3 comment"));
}
