//! Unit tests for repository routes

const std = @import("std");
const testing = std.testing;

// Basic test to ensure module compiles
test "repositories module compiles" {
    const repo_routes = @import("repositories.zig");
    _ = repo_routes;
}

test "extractJsonString helper" {
    const repo_routes = @import("repositories.zig");

    const json = "{\"name\":\"test-repo\",\"description\":\"A test repository\"}";

    // Test extracting name
    const name = repo_routes.extractJsonString(json, "name");
    try testing.expect(name != null);
    try testing.expectEqualStrings("test-repo", name.?);

    // Test extracting description
    const description = repo_routes.extractJsonString(json, "description");
    try testing.expect(description != null);
    try testing.expectEqualStrings("A test repository", description.?);

    // Test non-existent key
    const missing = repo_routes.extractJsonString(json, "missing");
    try testing.expect(missing == null);
}

test "parseTopicsFromJson helper" {
    const repo_routes = @import("repositories.zig");
    const allocator = testing.allocator;

    // Test with topics
    const json1 = "{\"topics\":[\"rust\",\"web\",\"api\"]}";
    const topics1 = try repo_routes.parseTopicsFromJson(allocator, json1);
    defer {
        for (topics1) |topic| allocator.free(topic);
        allocator.free(topics1);
    }

    try testing.expectEqual(@as(usize, 3), topics1.len);
    try testing.expectEqualStrings("rust", topics1[0]);
    try testing.expectEqualStrings("web", topics1[1]);
    try testing.expectEqualStrings("api", topics1[2]);

    // Test with empty topics array
    const json2 = "{\"topics\":[]}";
    const topics2 = try repo_routes.parseTopicsFromJson(allocator, json2);
    defer allocator.free(topics2);

    try testing.expectEqual(@as(usize, 0), topics2.len);

    // Test topics normalization (should be lowercase)
    const json3 = "{\"topics\":[\"Rust\",\"WEB\",\"Api\"]}";
    const topics3 = try repo_routes.parseTopicsFromJson(allocator, json3);
    defer {
        for (topics3) |topic| allocator.free(topic);
        allocator.free(topics3);
    }

    try testing.expectEqual(@as(usize, 3), topics3.len);
    try testing.expectEqualStrings("rust", topics3[0]);
    try testing.expectEqualStrings("web", topics3[1]);
    try testing.expectEqualStrings("api", topics3[2]);
}

test "parseTopicsFromJson error cases" {
    const repo_routes = @import("repositories.zig");
    const allocator = testing.allocator;

    // Missing topics field
    const bad_json1 = "{\"name\":\"test\"}";
    try testing.expectError(error.InvalidJson, repo_routes.parseTopicsFromJson(allocator, bad_json1));

    // Malformed array
    const bad_json2 = "{\"topics\":[\"rust\"";
    try testing.expectError(error.InvalidJson, repo_routes.parseTopicsFromJson(allocator, bad_json2));
}

// Integration test documentation
// Note: Full integration tests would require:
// 1. Database setup with test schema
// 2. HTTP test server
// 3. Test user authentication
// 4. Test repositories created
//
// Example integration test structure:
// test "star repository endpoint" {
//     var test_server = try setupTestServer();
//     defer test_server.deinit();
//
//     // Create test user and repository
//     const user_id = try createTestUser(test_server.pool);
//     const repo_id = try createTestRepository(test_server.pool, user_id);
//
//     // Test POST /api/:user/:repo/star
//     const response = try test_server.post("/api/testuser/testrepo/star", .{});
//     try testing.expectEqual(@as(u16, 201), response.status);
//
//     // Verify star was created
//     const count = try db.getStarCount(test_server.pool, repo_id);
//     try testing.expectEqual(@as(i64, 1), count);
// }
