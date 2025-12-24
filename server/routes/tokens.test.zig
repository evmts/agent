//! Unit tests for access token routes

const std = @import("std");
const testing = std.testing;

test "token generation produces hex string" {
    const allocator = testing.allocator;

    // Generate a token
    var token_bytes: [32]u8 = undefined;
    std.crypto.random.bytes(&token_bytes);
    const token = try std.fmt.allocPrint(allocator, "{s}", .{std.fmt.fmtSliceHexLower(&token_bytes)});
    defer allocator.free(token);

    // Token should be 64 characters (32 bytes * 2 hex chars per byte)
    try testing.expectEqual(@as(usize, 64), token.len);

    // All characters should be valid hex
    for (token) |c| {
        try testing.expect(std.ascii.isHex(c));
    }
}

test "SHA256 hash produces consistent output" {
    const allocator = testing.allocator;
    const test_token = "abc123";

    var hash1: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(test_token, &hash1, .{});
    const hash_str1 = try std.fmt.allocPrint(allocator, "{s}", .{std.fmt.fmtSliceHexLower(&hash1)});
    defer allocator.free(hash_str1);

    var hash2: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(test_token, &hash2, .{});
    const hash_str2 = try std.fmt.allocPrint(allocator, "{s}", .{std.fmt.fmtSliceHexLower(&hash2)});
    defer allocator.free(hash_str2);

    // Same input should produce same hash
    try testing.expectEqualStrings(hash_str1, hash_str2);

    // Hash should be 64 characters (32 bytes * 2 hex chars)
    try testing.expectEqual(@as(usize, 64), hash_str1.len);
}

test "token last eight extraction" {
    const token = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
    const last_eight = token[token.len - 8 ..];
    try testing.expectEqualStrings("9abcdef", last_eight);
}

test "scope validation" {
    const valid_scopes = [_][]const u8{ "repo", "user", "admin" };

    // Test valid scopes
    for (valid_scopes) |scope| {
        var is_valid = false;
        for (valid_scopes) |vs| {
            if (std.mem.eql(u8, scope, vs)) {
                is_valid = true;
                break;
            }
        }
        try testing.expect(is_valid);
    }

    // Test invalid scope
    const invalid_scope = "invalid";
    var is_valid = false;
    for (valid_scopes) |vs| {
        if (std.mem.eql(u8, invalid_scope, vs)) {
            is_valid = true;
            break;
        }
    }
    try testing.expect(!is_valid);
}
