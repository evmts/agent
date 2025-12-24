//! Runner Pool Manager
//!
//! Manages a warm pool of standby runners for fast workflow execution.
//! Handles:
//! - Runner registration and heartbeat tracking
//! - Atomic runner claiming for task assignment
//! - Stale runner cleanup
//! - Pool capacity monitoring
//!
//! Architecture:
//! - Runners register on startup and send periodic heartbeats
//! - Executor claims runners atomically using database transactions
//! - Background cleanup task removes stale runners (no heartbeat > 60s)
//! - FIFO selection: oldest registered runner is claimed first

const std = @import("std");
const db = @import("db");

pub const RunnerPool = struct {
    allocator: std.mem.Allocator,
    db_pool: *db.Pool,
    cleanup_interval_ms: u64,

    /// Initialize runner pool manager
    pub fn init(allocator: std.mem.Allocator, db_pool: *db.Pool) RunnerPool {
        return .{
            .allocator = allocator,
            .db_pool = db_pool,
            .cleanup_interval_ms = 60_000, // 60 seconds
        };
    }

    /// Register a new runner in the pool
    /// If runner with same pod_name exists, it will be reset to available state
    pub fn registerRunner(
        self: *RunnerPool,
        pod_name: []const u8,
        pod_ip: []const u8,
        node_name: ?[]const u8,
    ) !i32 {
        return try db.workflows.registerRunner(self.db_pool, pod_name, pod_ip, node_name);
    }

    /// Update heartbeat for a runner
    pub fn updateHeartbeat(self: *RunnerPool, runner_id: i32) !void {
        return try db.workflows.updateRunnerHeartbeat(self.db_pool, runner_id);
    }

    /// Claim an available runner for a task
    /// Returns runner_id if successful, null if no runners available
    /// Uses atomic database transaction with SELECT FOR UPDATE SKIP LOCKED
    pub fn claimRunner(self: *RunnerPool, task_id: i32) !?RunnerInfo {
        const runner_id = try db.workflows.claimAvailableRunner(self.db_pool, task_id) orelse return null;

        // Get full runner info
        const runner_entry = try db.workflows.getRunner(self.db_pool, runner_id) orelse return error.RunnerNotFound;

        return RunnerInfo{
            .id = runner_entry.id,
            .pod_name = runner_entry.pod_name,
            .pod_ip = runner_entry.pod_ip,
            .node_name = runner_entry.node_name,
        };
    }

    /// Release a runner back to the available pool
    pub fn releaseRunner(self: *RunnerPool, runner_id: i32) !void {
        return try db.workflows.releaseRunner(self.db_pool, runner_id);
    }

    /// Mark a runner as terminated
    pub fn terminateRunner(self: *RunnerPool, runner_id: i32) !void {
        return try db.workflows.terminateRunner(self.db_pool, runner_id);
    }

    /// Get current number of available runners
    pub fn getAvailableCount(self: *RunnerPool) !i32 {
        return try db.workflows.countAvailableRunners(self.db_pool);
    }

    /// Clean up stale runners (no heartbeat for > 60 seconds)
    /// Returns number of runners marked as terminated
    pub fn cleanupStaleRunners(self: *RunnerPool) !i32 {
        return try db.workflows.cleanupStaleRunners(self.db_pool);
    }

    /// List all runners with optional status filter
    pub fn listRunners(
        self: *RunnerPool,
        status_filter: ?[]const u8,
    ) ![]db.workflows.RunnerPoolEntry {
        return try db.workflows.listRunners(self.db_pool, self.allocator, status_filter);
    }

    /// Get runner info by ID
    pub fn getRunner(self: *RunnerPool, runner_id: i32) !?db.workflows.RunnerPoolEntry {
        return try db.workflows.getRunner(self.db_pool, runner_id);
    }
};

/// Information about a claimed runner
pub const RunnerInfo = struct {
    id: i32,
    pod_name: []const u8,
    pod_ip: []const u8,
    node_name: ?[]const u8,
};

/// Runner pool statistics
pub const PoolStats = struct {
    total: i32,
    available: i32,
    claimed: i32,
    terminated: i32,
};

// =============================================================================
// Tests
// =============================================================================

test "runner_pool - init" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Create mock db pool (null for this test)
    const pool = RunnerPool.init(allocator, undefined);

    try testing.expect(pool.cleanup_interval_ms == 60_000);
}

test "runner_pool - runner info structure" {
    const testing = std.testing;

    const info = RunnerInfo{
        .id = 1,
        .pod_name = "runner-pod-1",
        .pod_ip = "10.0.0.1",
        .node_name = "node-1",
    };

    try testing.expectEqual(@as(i32, 1), info.id);
    try testing.expectEqualStrings("runner-pod-1", info.pod_name);
    try testing.expectEqualStrings("10.0.0.1", info.pod_ip);
    try testing.expect(info.node_name != null);
    try testing.expectEqualStrings("node-1", info.node_name.?);
}
