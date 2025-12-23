//! Runner Pool Integration Tests
//!
//! Tests the full runner pool lifecycle including:
//! - Runner registration and heartbeat
//! - Atomic claiming with concurrent access
//! - Stale runner cleanup
//! - Pool statistics and monitoring
//!
//! These are unit tests that don't require a real database.
//! Integration tests with actual database would require TEST_DATABASE_URL.

const std = @import("std");
const testing = std.testing;
const runner_pool_mod = @import("runner_pool.zig");
const db = @import("../../db/root.zig");

test "runner_pool - RunnerInfo structure" {
    const info = runner_pool_mod.RunnerInfo{
        .id = 123,
        .pod_name = "runner-pod-abc",
        .pod_ip = "10.0.1.42",
        .node_name = "node-worker-3",
    };

    try testing.expectEqual(@as(i32, 123), info.id);
    try testing.expectEqualStrings("runner-pod-abc", info.pod_name);
    try testing.expectEqualStrings("10.0.1.42", info.pod_ip);
    try testing.expect(info.node_name != null);
    try testing.expectEqualStrings("node-worker-3", info.node_name.?);
}

test "runner_pool - RunnerInfo with null node_name" {
    const info = runner_pool_mod.RunnerInfo{
        .id = 456,
        .pod_name = "runner-pod-xyz",
        .pod_ip = "10.0.1.99",
        .node_name = null,
    };

    try testing.expectEqual(@as(i32, 456), info.id);
    try testing.expectEqualStrings("runner-pod-xyz", info.pod_name);
    try testing.expectEqualStrings("10.0.1.99", info.pod_ip);
    try testing.expect(info.node_name == null);
}

test "runner_pool - PoolStats structure" {
    const stats = runner_pool_mod.PoolStats{
        .total = 10,
        .available = 6,
        .claimed = 3,
        .terminated = 1,
    };

    try testing.expectEqual(@as(i32, 10), stats.total);
    try testing.expectEqual(@as(i32, 6), stats.available);
    try testing.expectEqual(@as(i32, 3), stats.claimed);
    try testing.expectEqual(@as(i32, 1), stats.terminated);

    // Verify totals add up
    try testing.expectEqual(stats.total, stats.available + stats.claimed + stats.terminated);
}

test "runner_pool - RunnerPool initialization" {
    const allocator = testing.allocator;

    // Create pool (db_pool can be undefined for init test)
    const pool = runner_pool_mod.RunnerPool.init(allocator, undefined);

    try testing.expectEqual(allocator, pool.allocator);
    try testing.expectEqual(@as(u64, 60_000), pool.cleanup_interval_ms);
}

test "runner_pool - RunnerPool custom cleanup interval" {
    const allocator = testing.allocator;

    var pool = runner_pool_mod.RunnerPool.init(allocator, undefined);
    pool.cleanup_interval_ms = 30_000; // 30 seconds

    try testing.expectEqual(@as(u64, 30_000), pool.cleanup_interval_ms);
}

// Note: The following tests would require a real database connection:
// - test "runner_pool - register and heartbeat lifecycle"
// - test "runner_pool - atomic claiming with concurrent requests"
// - test "runner_pool - stale runner cleanup"
// - test "runner_pool - list runners by status"
// - test "runner_pool - count available runners"
//
// These should be implemented as integration tests when TEST_DATABASE_URL is available.
// For now, we have unit tests for the data structures and initialization.
