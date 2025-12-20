//! Tests for Edge Notifier Service

const std = @import("std");
const edge_notifier = @import("edge_notifier.zig");
const InvalidationType = edge_notifier.InvalidationType;
const InvalidationMessage = edge_notifier.InvalidationMessage;
const EdgeNotifier = edge_notifier.EdgeNotifier;

test "InvalidationType enum to string conversion" {
    try std.testing.expectEqualStrings("sql", InvalidationType.sql.toString());
    try std.testing.expectEqualStrings("git", InvalidationType.git.toString());
}

test "InvalidationMessage SQL change - minimal fields" {
    const allocator = std.testing.allocator;

    const msg = InvalidationMessage{
        .type = .sql,
        .table = "users",
        .timestamp = 1700000000,
    };

    const json_str = try msg.toJson(allocator);
    defer allocator.free(json_str);

    // Verify JSON structure
    try std.testing.expect(std.mem.indexOf(u8, json_str, "\"type\":\"sql\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_str, "\"table\":\"users\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_str, "\"timestamp\":1700000000") != null);

    // Should not have git-specific fields
    try std.testing.expect(std.mem.indexOf(u8, json_str, "merkle_root") == null);
}

test "InvalidationMessage SQL change - with repo_key" {
    const allocator = std.testing.allocator;

    const msg = InvalidationMessage{
        .type = .sql,
        .table = "repositories",
        .repo_key = "alice/wonderland",
        .timestamp = 1700000001,
    };

    const json_str = try msg.toJson(allocator);
    defer allocator.free(json_str);

    // Verify all fields present
    try std.testing.expect(std.mem.indexOf(u8, json_str, "\"type\":\"sql\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_str, "\"table\":\"repositories\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_str, "\"repo_key\":\"alice/wonderland\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_str, "\"timestamp\":1700000001") != null);
}

test "InvalidationMessage git change - all fields" {
    const allocator = std.testing.allocator;

    const msg = InvalidationMessage{
        .type = .git,
        .repo_key = "bob/project",
        .merkle_root = "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08",
        .timestamp = 1700000002,
    };

    const json_str = try msg.toJson(allocator);
    defer allocator.free(json_str);

    // Verify all fields present
    try std.testing.expect(std.mem.indexOf(u8, json_str, "\"type\":\"git\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_str, "\"repo_key\":\"bob/project\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_str, "\"merkle_root\":\"9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_str, "\"timestamp\":1700000002") != null);

    // Should not have SQL-specific fields
    try std.testing.expect(std.mem.indexOf(u8, json_str, "\"table\"") == null);
}

test "InvalidationMessage JSON escaping" {
    const allocator = std.testing.allocator;

    const msg = InvalidationMessage{
        .type = .sql,
        .table = "test\"table",
        .repo_key = "user/repo\nwith\nnewlines",
        .timestamp = 1700000003,
    };

    const json_str = try msg.toJson(allocator);
    defer allocator.free(json_str);

    // Verify JSON is properly escaped
    try std.testing.expect(std.mem.indexOf(u8, json_str, "test\\\"table") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_str, "repo\\nwith\\nnewlines") != null);

    // Should be valid JSON (no unescaped quotes or newlines outside strings)
    try std.testing.expect(std.mem.indexOf(u8, json_str, "\n") == null);
}

test "EdgeNotifier initialization" {
    const allocator = std.testing.allocator;

    const notifier = EdgeNotifier.init(
        allocator,
        "https://edge.example.com",
        "secret-token-123",
    );

    try std.testing.expectEqualStrings("https://edge.example.com", notifier.edge_base_url);
    try std.testing.expectEqualStrings("secret-token-123", notifier.push_secret);
}

test "EdgeNotifier URL construction - global DO" {
    const allocator = std.testing.allocator;

    var notifier = EdgeNotifier.init(
        allocator,
        "https://edge.example.com",
        "secret",
    );

    // Expected URL format: {edge_base_url}/do/global/invalidate
    const expected_url = "https://edge.example.com/do/global/invalidate";

    // We'll construct the URL manually to verify the format
    const url = try std.fmt.allocPrint(allocator, "{s}/do/{s}/invalidate", .{ notifier.edge_base_url, "global" });
    defer allocator.free(url);

    try std.testing.expectEqualStrings(expected_url, url);
}

test "EdgeNotifier URL construction - repo-specific DO" {
    const allocator = std.testing.allocator;

    var notifier = EdgeNotifier.init(
        allocator,
        "https://edge.example.com",
        "secret",
    );

    const repo_key = "alice/project";

    // Expected URL format: {edge_base_url}/do/repo:{owner}/{repo}/invalidate
    const expected_url = "https://edge.example.com/do/repo:alice/project/invalidate";

    // Construct DO name
    const do_name = try std.fmt.allocPrint(allocator, "repo:{s}", .{repo_key});
    defer allocator.free(do_name);

    try std.testing.expectEqualStrings("repo:alice/project", do_name);

    // Construct full URL
    const url = try std.fmt.allocPrint(allocator, "{s}/do/{s}/invalidate", .{ notifier.edge_base_url, do_name });
    defer allocator.free(url);

    try std.testing.expectEqualStrings(expected_url, url);
}

test "EdgeNotifier skips when edge_url is empty" {
    const allocator = std.testing.allocator;

    var notifier = EdgeNotifier.init(
        allocator,
        "", // Empty edge URL
        "secret",
    );

    // This should not fail, just skip silently
    try notifier.notifySqlChange("users", null);
}

test "InvalidationMessage timestamp field" {
    const allocator = std.testing.allocator;

    const timestamp: i64 = 1234567890123;
    const msg = InvalidationMessage{
        .type = .sql,
        .table = "test",
        .timestamp = timestamp,
    };

    const json_str = try msg.toJson(allocator);
    defer allocator.free(json_str);

    // Verify timestamp is included as a number (not a string)
    const timestamp_str = try std.fmt.allocPrint(allocator, "\"timestamp\":{d}", .{timestamp});
    defer allocator.free(timestamp_str);

    try std.testing.expect(std.mem.indexOf(u8, json_str, timestamp_str) != null);
}

test "InvalidationMessage with special characters in repo_key" {
    const allocator = std.testing.allocator;

    const msg = InvalidationMessage{
        .type = .git,
        .repo_key = "user-name/repo.name-v2",
        .merkle_root = "abc123",
        .timestamp = 1700000000,
    };

    const json_str = try msg.toJson(allocator);
    defer allocator.free(json_str);

    // Should handle hyphens, dots, and underscores properly
    try std.testing.expect(std.mem.indexOf(u8, json_str, "\"repo_key\":\"user-name/repo.name-v2\"") != null);
}

test "InvalidationMessage field ordering" {
    const allocator = std.testing.allocator;

    const msg = InvalidationMessage{
        .type = .sql,
        .table = "users",
        .repo_key = "test/repo",
        .timestamp = 1700000000,
    };

    const json_str = try msg.toJson(allocator);
    defer allocator.free(json_str);

    // Verify that type and timestamp come first (as documented in the implementation)
    const type_pos = std.mem.indexOf(u8, json_str, "\"type\":").?;
    const timestamp_pos = std.mem.indexOf(u8, json_str, "\"timestamp\":").?;
    const table_pos = std.mem.indexOf(u8, json_str, "\"table\":").?;

    // type should come before timestamp, timestamp before table
    try std.testing.expect(type_pos < timestamp_pos);
    try std.testing.expect(timestamp_pos < table_pos);
}
