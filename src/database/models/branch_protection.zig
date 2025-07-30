const std = @import("std");

pub const BranchProtectionRule = struct {
    id: i64,
    repo_id: i64,
    branch_name: []const u8,
    require_reviews: bool,
    required_review_count: i32,
    dismiss_stale_reviews: bool,
    require_code_owner_reviews: bool,
    require_status_checks: bool,
    required_status_checks: ?[]const u8, // JSON array of required check names
    enforce_admins: bool,
    allow_force_pushes: bool,
    allow_deletions: bool,
    created_unix: i64,
    updated_unix: i64,
};

pub const StatusCheck = struct {
    id: i64,
    repo_id: i64,
    pull_request_id: i64,
    context: []const u8, // Name of the check (e.g., "ci/travis", "coverage/codecov")
    state: StatusState,
    target_url: ?[]const u8,
    description: ?[]const u8,
    created_unix: i64,
    updated_unix: i64,
};

pub const StatusState = enum(i16) {
    pending = 1,
    success = 2,
    failure = 3,
    err = 4,
};

pub const MergeConflict = struct {
    id: i64,
    repo_id: i64,
    pull_request_id: i64,
    base_sha: []const u8,
    head_sha: []const u8,
    conflicted_files: []const u8, // JSON array of file paths
    conflict_detected: bool,
    last_checked_unix: i64,
};

// Tests for branch protection models following TDD
test "BranchProtectionRule model basic creation" {
    const rule = BranchProtectionRule{
        .id = 1,
        .repo_id = 123,
        .branch_name = "main",
        .require_reviews = true,
        .required_review_count = 2,
        .dismiss_stale_reviews = true,
        .require_code_owner_reviews = false,
        .require_status_checks = true,
        .required_status_checks = "[\"ci/tests\", \"security/scan\"]",
        .enforce_admins = false,
        .allow_force_pushes = false,
        .allow_deletions = false,
        .created_unix = 1640995200,
        .updated_unix = 1640995200,
    };
    
    try std.testing.expectEqual(@as(i64, 123), rule.repo_id);
    try std.testing.expectEqualStrings("main", rule.branch_name);
    try std.testing.expectEqual(true, rule.require_reviews);
    try std.testing.expectEqual(@as(i32, 2), rule.required_review_count);
    try std.testing.expectEqual(true, rule.require_status_checks);
}

test "StatusCheck model with different states" {
    const pending_check = StatusCheck{
        .id = 1,
        .repo_id = 123,
        .pull_request_id = 456,
        .context = "ci/tests",
        .state = .pending,
        .target_url = "https://ci.example.com/123",
        .description = "Running tests...",
        .created_unix = std.time.timestamp(),
        .updated_unix = std.time.timestamp(),
    };
    
    const success_check = StatusCheck{
        .id = 2,
        .repo_id = 123,
        .pull_request_id = 456,
        .context = "security/scan",
        .state = .success,
        .target_url = null,
        .description = "Security scan passed",
        .created_unix = std.time.timestamp(),
        .updated_unix = std.time.timestamp(),
    };
    
    try std.testing.expectEqual(StatusState.pending, pending_check.state);
    try std.testing.expectEqual(StatusState.success, success_check.state);
    try std.testing.expectEqualStrings("ci/tests", pending_check.context);
    try std.testing.expectEqualStrings("security/scan", success_check.context);
}

test "StatusState enum operations" {
    // Test enum values
    try std.testing.expectEqual(@as(i16, 1), @intFromEnum(StatusState.pending));
    try std.testing.expectEqual(@as(i16, 2), @intFromEnum(StatusState.success));
    try std.testing.expectEqual(@as(i16, 3), @intFromEnum(StatusState.failure));
    try std.testing.expectEqual(@as(i16, 4), @intFromEnum(StatusState.err));
    
    // Test enum conversion
    const pending_state: StatusState = @enumFromInt(1);
    const success_state: StatusState = @enumFromInt(2);
    
    try std.testing.expectEqual(StatusState.pending, pending_state);
    try std.testing.expectEqual(StatusState.success, success_state);
}

test "MergeConflict model" {
    const conflict = MergeConflict{
        .id = 1,
        .repo_id = 123,
        .pull_request_id = 456,
        .base_sha = "abc123def456",
        .head_sha = "def456ghi789",
        .conflicted_files = "[\"src/main.zig\", \"README.md\"]",
        .conflict_detected = true,
        .last_checked_unix = std.time.timestamp(),
    };
    
    try std.testing.expectEqual(@as(i64, 456), conflict.pull_request_id);
    try std.testing.expectEqualStrings("abc123def456", conflict.base_sha);
    try std.testing.expectEqualStrings("def456ghi789", conflict.head_sha);
    try std.testing.expectEqual(true, conflict.conflict_detected);
}