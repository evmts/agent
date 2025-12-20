//! Authentication integration tests
//!
//! Tests the complete authentication flow including:
//! - Session creation and validation
//! - User registration
//! - Login/logout operations
//! - Token validation
//! - Session expiration

const std = @import("std");
const testing = std.testing;
const mod = @import("mod.zig");
const db = @import("../../lib/db.zig");

const log = std.log.scoped(.auth_test);

// =============================================================================
// Session Management Tests
// =============================================================================

test "session: create and retrieve session" {
    log.info("Testing session creation and retrieval", .{});

    const allocator = testing.allocator;
    const test_config = mod.TestConfig{
        .database_url = mod.getTestDatabaseUrl(),
        .cleanup_on_success = true,
    };

    var ctx = try mod.TestContext.init(allocator, test_config);
    defer ctx.deinit(true);

    // Create test user
    const user_id = try ctx.createTestUser("testuser", "test@example.com");

    // Create session
    const session_key = try db.createSession(ctx.pool, allocator, user_id, "testuser", false);
    defer allocator.free(session_key);

    // Verify session was created
    try testing.expect(session_key.len == 64); // 32 bytes as hex = 64 chars

    // Retrieve session
    const session = try db.getSession(ctx.pool, session_key);
    try testing.expect(session != null);
    try testing.expectEqual(user_id, session.?.user_id);
    try testing.expectEqualStrings("testuser", session.?.username);
    try testing.expectEqual(false, session.?.is_admin);

    log.info("✓ Session creation and retrieval test passed", .{});
}

test "session: invalid session key returns null" {
    log.info("Testing invalid session key handling", .{});

    const allocator = testing.allocator;
    const test_config = mod.TestConfig{
        .database_url = mod.getTestDatabaseUrl(),
        .cleanup_on_success = true,
    };

    var ctx = try mod.TestContext.init(allocator, test_config);
    defer ctx.deinit(true);

    // Try to get non-existent session
    const session = try db.getSession(ctx.pool, "invalid_session_key_12345678901234567890123456789012");
    try testing.expect(session == null);

    log.info("✓ Invalid session test passed", .{});
}

test "session: delete session" {
    log.info("Testing session deletion", .{});

    const allocator = testing.allocator;
    const test_config = mod.TestConfig{
        .database_url = mod.getTestDatabaseUrl(),
        .cleanup_on_success = true,
    };

    var ctx = try mod.TestContext.init(allocator, test_config);
    defer ctx.deinit(true);

    // Create test user and session
    const user_id = try ctx.createTestUser("testuser", "test@example.com");
    const session_key = try db.createSession(ctx.pool, allocator, user_id, "testuser", false);
    defer allocator.free(session_key);

    // Verify session exists
    var session = try db.getSession(ctx.pool, session_key);
    try testing.expect(session != null);

    // Delete session
    try db.deleteSession(ctx.pool, session_key);

    // Verify session no longer exists
    session = try db.getSession(ctx.pool, session_key);
    try testing.expect(session == null);

    log.info("✓ Session deletion test passed", .{});
}

test "session: refresh session extends expiration" {
    log.info("Testing session refresh", .{});

    const allocator = testing.allocator;
    const test_config = mod.TestConfig{
        .database_url = mod.getTestDatabaseUrl(),
        .cleanup_on_success = true,
    };

    var ctx = try mod.TestContext.init(allocator, test_config);
    defer ctx.deinit(true);

    // Create test user and session
    const user_id = try ctx.createTestUser("testuser", "test@example.com");
    const session_key = try db.createSession(ctx.pool, allocator, user_id, "testuser", false);
    defer allocator.free(session_key);

    // Get initial session data
    const session1 = try db.getSession(ctx.pool, session_key);
    try testing.expect(session1 != null);
    const expires_at1 = session1.?.expires_at;

    // Wait a moment
    std.time.sleep(100 * std.time.ns_per_ms);

    // Refresh session
    try db.refreshSession(ctx.pool, session_key);

    // Get updated session data
    const session2 = try db.getSession(ctx.pool, session_key);
    try testing.expect(session2 != null);
    const expires_at2 = session2.?.expires_at;

    // Verify expiration was extended
    try testing.expect(expires_at2 > expires_at1);

    log.info("✓ Session refresh test passed", .{});
}

test "session: cleanup expired sessions" {
    log.info("Testing expired session cleanup", .{});

    const allocator = testing.allocator;
    const test_config = mod.TestConfig{
        .database_url = mod.getTestDatabaseUrl(),
        .cleanup_on_success = true,
    };

    var ctx = try mod.TestContext.init(allocator, test_config);
    defer ctx.deinit(true);

    // Create test user
    const user_id = try ctx.createTestUser("testuser", "test@example.com");

    // Create an expired session manually (bypass createSession)
    var conn = try ctx.pool.acquire();
    defer conn.release();

    var key_bytes: [32]u8 = undefined;
    std.crypto.random.bytes(&key_bytes);
    const session_key = try std.fmt.allocPrint(allocator, "{s}", .{
        &std.fmt.bytesToHex(key_bytes, .lower),
    });
    defer allocator.free(session_key);

    // Set expiration to the past
    const expired_at = std.time.milliTimestamp() - 1000;
    _ = try conn.exec(
        \\INSERT INTO auth_sessions (session_key, user_id, username, is_admin, expires_at)
        \\VALUES ($1, $2, $3, $4, to_timestamp($5::bigint / 1000.0))
    , .{ session_key, user_id, "testuser", false, expired_at });

    // Verify session exists but is expired (getSession should return null)
    const session = try db.getSession(ctx.pool, session_key);
    try testing.expect(session == null);

    // Run cleanup
    const deleted = try db.cleanupExpiredSessions(ctx.pool);
    try testing.expect(deleted != null);
    try testing.expect(deleted.? >= 1);

    log.info("✓ Expired session cleanup test passed", .{});
}

// =============================================================================
// User Management Tests
// =============================================================================

test "user: create and retrieve by id" {
    log.info("Testing user creation and retrieval by ID", .{});

    const allocator = testing.allocator;
    const test_config = mod.TestConfig{
        .database_url = mod.getTestDatabaseUrl(),
        .cleanup_on_success = true,
    };

    var ctx = try mod.TestContext.init(allocator, test_config);
    defer ctx.deinit(true);

    // Create test user
    const user_id = try ctx.createTestUser("johndoe", "john@example.com");

    // Retrieve by ID
    const user = try db.getUserById(ctx.pool, user_id);
    try testing.expect(user != null);
    try testing.expectEqualStrings("johndoe", user.?.username);
    try testing.expectEqualStrings("john@example.com", user.?.email.?);
    try testing.expect(user.?.is_active);
    try testing.expect(!user.?.prohibit_login);

    log.info("✓ User creation and retrieval test passed", .{});
}

test "user: retrieve by username" {
    log.info("Testing user retrieval by username", .{});

    const allocator = testing.allocator;
    const test_config = mod.TestConfig{
        .database_url = mod.getTestDatabaseUrl(),
        .cleanup_on_success = true,
    };

    var ctx = try mod.TestContext.init(allocator, test_config);
    defer ctx.deinit(true);

    // Create test user
    _ = try ctx.createTestUser("janedoe", "jane@example.com");

    // Retrieve by username
    const user = try db.getUserByUsername(ctx.pool, "janedoe");
    try testing.expect(user != null);
    try testing.expectEqualStrings("janedoe", user.?.username);
    try testing.expectEqualStrings("jane@example.com", user.?.email.?);

    log.info("✓ User retrieval by username test passed", .{});
}

test "user: case-insensitive username lookup" {
    log.info("Testing case-insensitive username lookup", .{});

    const allocator = testing.allocator;
    const test_config = mod.TestConfig{
        .database_url = mod.getTestDatabaseUrl(),
        .cleanup_on_success = true,
    };

    var ctx = try mod.TestContext.init(allocator, test_config);
    defer ctx.deinit(true);

    // Create test user with mixed case
    _ = try ctx.createTestUser("TestUser", "test@example.com");

    // Retrieve with different casing
    const user1 = try db.getUserByUsername(ctx.pool, "testuser");
    const user2 = try db.getUserByUsername(ctx.pool, "TESTUSER");
    const user3 = try db.getUserByUsername(ctx.pool, "TestUser");

    try testing.expect(user1 != null);
    try testing.expect(user2 != null);
    try testing.expect(user3 != null);
    try testing.expectEqual(user1.?.id, user2.?.id);
    try testing.expectEqual(user1.?.id, user3.?.id);

    log.info("✓ Case-insensitive username lookup test passed", .{});
}

test "user: non-existent user returns null" {
    log.info("Testing non-existent user lookup", .{});

    const allocator = testing.allocator;
    const test_config = mod.TestConfig{
        .database_url = mod.getTestDatabaseUrl(),
        .cleanup_on_success = true,
    };

    var ctx = try mod.TestContext.init(allocator, test_config);
    defer ctx.deinit(true);

    // Try to retrieve non-existent user
    const user = try db.getUserByUsername(ctx.pool, "nonexistent");
    try testing.expect(user == null);

    log.info("✓ Non-existent user test passed", .{});
}

test "user: update profile" {
    log.info("Testing user profile update", .{});

    const allocator = testing.allocator;
    const test_config = mod.TestConfig{
        .database_url = mod.getTestDatabaseUrl(),
        .cleanup_on_success = true,
    };

    var ctx = try mod.TestContext.init(allocator, test_config);
    defer ctx.deinit(true);

    // Create test user
    const user_id = try ctx.createTestUser("testuser", "test@example.com");

    // Update profile
    try db.updateUserProfile(ctx.pool, user_id, "Test User", "A test bio", "newemail@example.com");

    // Verify update
    const user = try db.getUserById(ctx.pool, user_id);
    try testing.expect(user != null);
    try testing.expectEqualStrings("Test User", user.?.display_name.?);
    try testing.expectEqualStrings("newemail@example.com", user.?.email.?);

    log.info("✓ User profile update test passed", .{});
}

// =============================================================================
// Access Token Tests
// =============================================================================

test "token: create and validate access token" {
    log.info("Testing access token creation and validation", .{});

    const allocator = testing.allocator;
    const test_config = mod.TestConfig{
        .database_url = mod.getTestDatabaseUrl(),
        .cleanup_on_success = true,
    };

    var ctx = try mod.TestContext.init(allocator, test_config);
    defer ctx.deinit(true);

    // Create test user
    const user_id = try ctx.createTestUser("testuser", "test@example.com");

    // Create access token
    const token_name = "test-token";
    const token = try db.createAccessToken(ctx.pool, allocator, user_id, token_name, "all");
    defer allocator.free(token);

    try testing.expect(token.len > 0);

    // Validate token
    const token_data = try db.validateAccessToken(ctx.pool, token);
    try testing.expect(token_data != null);
    try testing.expectEqual(user_id, token_data.?.user_id);
    try testing.expectEqualStrings("all", token_data.?.scopes);

    log.info("✓ Access token test passed", .{});
}

test "token: invalid token returns null" {
    log.info("Testing invalid access token", .{});

    const allocator = testing.allocator;
    const test_config = mod.TestConfig{
        .database_url = mod.getTestDatabaseUrl(),
        .cleanup_on_success = true,
    };

    var ctx = try mod.TestContext.init(allocator, test_config);
    defer ctx.deinit(true);

    // Try to validate invalid token
    const token_data = try db.validateAccessToken(ctx.pool, "invalid_token_12345");
    try testing.expect(token_data == null);

    log.info("✓ Invalid token test passed", .{});
}

// =============================================================================
// Integration Tests
// =============================================================================

test "integration: complete login flow" {
    log.info("Testing complete login flow", .{});

    const allocator = testing.allocator;
    const test_config = mod.TestConfig{
        .database_url = mod.getTestDatabaseUrl(),
        .cleanup_on_success = true,
    };

    var ctx = try mod.TestContext.init(allocator, test_config);
    defer ctx.deinit(true);

    // 1. Create user
    const user_id = try ctx.createTestUser("loginuser", "login@example.com");

    // 2. Create session (simulating login)
    const session_key = try db.createSession(ctx.pool, allocator, user_id, "loginuser", false);
    defer allocator.free(session_key);

    // 3. Validate session
    const session = try db.getSession(ctx.pool, session_key);
    try testing.expect(session != null);
    try testing.expectEqual(user_id, session.?.user_id);

    // 4. Get user from session
    const user = try db.getUserById(ctx.pool, session.?.user_id);
    try testing.expect(user != null);
    try testing.expectEqualStrings("loginuser", user.?.username);

    // 5. Logout (delete session)
    try db.deleteSession(ctx.pool, session_key);

    // 6. Verify session is gone
    const deleted_session = try db.getSession(ctx.pool, session_key);
    try testing.expect(deleted_session == null);

    log.info("✓ Complete login flow test passed", .{});
}

test "integration: concurrent sessions" {
    log.info("Testing concurrent sessions for same user", .{});

    const allocator = testing.allocator;
    const test_config = mod.TestConfig{
        .database_url = mod.getTestDatabaseUrl(),
        .cleanup_on_success = true,
    };

    var ctx = try mod.TestContext.init(allocator, test_config);
    defer ctx.deinit(true);

    // Create user
    const user_id = try ctx.createTestUser("multiuser", "multi@example.com");

    // Create multiple sessions
    const session1 = try db.createSession(ctx.pool, allocator, user_id, "multiuser", false);
    defer allocator.free(session1);

    const session2 = try db.createSession(ctx.pool, allocator, user_id, "multiuser", false);
    defer allocator.free(session2);

    const session3 = try db.createSession(ctx.pool, allocator, user_id, "multiuser", false);
    defer allocator.free(session3);

    // Verify all sessions work
    const s1 = try db.getSession(ctx.pool, session1);
    const s2 = try db.getSession(ctx.pool, session2);
    const s3 = try db.getSession(ctx.pool, session3);

    try testing.expect(s1 != null);
    try testing.expect(s2 != null);
    try testing.expect(s3 != null);

    try testing.expectEqual(user_id, s1.?.user_id);
    try testing.expectEqual(user_id, s2.?.user_id);
    try testing.expectEqual(user_id, s3.?.user_id);

    // Delete one session, others should remain
    try db.deleteSession(ctx.pool, session2);

    const s1_after = try db.getSession(ctx.pool, session1);
    const s2_after = try db.getSession(ctx.pool, session2);
    const s3_after = try db.getSession(ctx.pool, session3);

    try testing.expect(s1_after != null);
    try testing.expect(s2_after == null);
    try testing.expect(s3_after != null);

    log.info("✓ Concurrent sessions test passed", .{});
}
