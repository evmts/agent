const std = @import("std");

pub const MilestoneState = enum(i16) {
    open = 1,
    closed = 2,
};

pub const Milestone = struct {
    id: i64,
    repo_id: i64,
    name: []const u8,
    description: ?[]const u8,
    state: MilestoneState,
    due_date: ?i64,
    created_unix: i64,
    updated_unix: i64,
    closed_unix: ?i64,
    open_issues: i32,
    closed_issues: i32,
};

pub const IssueMilestone = struct {
    id: i64,
    issue_id: i64,
    milestone_id: i64,
};

// Tests for milestone models following TDD
test "Milestone model basic creation" {
    const milestone = Milestone{
        .id = 1,
        .repo_id = 123,
        .name = "v1.0.0",
        .description = "First major release",
        .state = .open,
        .due_date = 1672531200, // 2023-01-01
        .created_unix = 1640995200, // 2022-01-01
        .updated_unix = 1640995200,
        .closed_unix = null,
        .open_issues = 5,
        .closed_issues = 3,
    };
    
    try std.testing.expectEqual(@as(i64, 1), milestone.id);
    try std.testing.expectEqualStrings("v1.0.0", milestone.name);
    try std.testing.expectEqualStrings("First major release", milestone.description.?);
    try std.testing.expectEqual(MilestoneState.open, milestone.state);
    try std.testing.expectEqual(@as(i32, 5), milestone.open_issues);
    try std.testing.expectEqual(@as(i32, 3), milestone.closed_issues);
}

test "Milestone state transitions" {
    const allocator = std.testing.allocator;
    
    // Test open milestone
    const open_milestone = Milestone{
        .id = 1,
        .repo_id = 123,
        .name = "Sprint 1",
        .description = null,
        .state = .open,
        .due_date = null,
        .created_unix = std.time.timestamp(),
        .updated_unix = std.time.timestamp(),
        .closed_unix = null,
        .open_issues = 0,
        .closed_issues = 0,
    };
    
    try std.testing.expectEqual(MilestoneState.open, open_milestone.state);
    try std.testing.expect(open_milestone.closed_unix == null);
    
    // Test closed milestone
    const closed_milestone = Milestone{
        .id = 2,
        .repo_id = 123,
        .name = "Sprint 2",
        .description = null,
        .state = .closed,
        .due_date = null,
        .created_unix = std.time.timestamp(),
        .updated_unix = std.time.timestamp(),
        .closed_unix = std.time.timestamp(),
        .open_issues = 0,
        .closed_issues = 5,
    };
    
    try std.testing.expectEqual(MilestoneState.closed, closed_milestone.state);
    try std.testing.expect(closed_milestone.closed_unix != null);
    
    _ = allocator;
}

test "IssueMilestone association model" {
    const issue_milestone = IssueMilestone{
        .id = 1,
        .issue_id = 42,
        .milestone_id = 7,
    };
    
    try std.testing.expectEqual(@as(i64, 42), issue_milestone.issue_id);
    try std.testing.expectEqual(@as(i64, 7), issue_milestone.milestone_id);
}

test "MilestoneState enum operations" {
    // Test enum values
    try std.testing.expectEqual(@as(i16, 1), @intFromEnum(MilestoneState.open));
    try std.testing.expectEqual(@as(i16, 2), @intFromEnum(MilestoneState.closed));
    
    // Test enum conversion
    const open_state: MilestoneState = @enumFromInt(1);
    const closed_state: MilestoneState = @enumFromInt(2);
    
    try std.testing.expectEqual(MilestoneState.open, open_state);
    try std.testing.expectEqual(MilestoneState.closed, closed_state);
}

test "Milestone database operations" {
    const allocator = std.testing.allocator;
    const DataAccessObject = @import("../dao.zig");
    
    const test_db_url = std.posix.getenv("TEST_DATABASE_URL") orelse "postgresql://plue:plue_password@localhost:5432/plue";
    
    var dao = DataAccessObject.init(test_db_url) catch |err| switch (err) {
        error.ConnectionRefused => {
            std.log.warn("Database not available for testing, skipping", .{});
            return;
        },
        else => return err,
    };
    defer dao.deinit();
    
    // Clean up test data
    dao.deleteUser(allocator, "test_milestone_user") catch {};
    
    // Create test user and repository
    const user = DataAccessObject.User{
        .id = 0,
        .name = "test_milestone_user",
        .email = "milestone@test.com",
        .passwd = null,
        .type = .individual,
        .is_admin = false,
        .avatar = null,
        .created_unix = 0,
        .updated_unix = 0,
    };
    try dao.createUser(allocator, user);
    
    const test_user = try dao.getUserByName(allocator, "test_milestone_user");
    defer if (test_user) |u| {
        allocator.free(u.name);
        if (u.email) |e| allocator.free(e);
        if (u.passwd) |p| allocator.free(p);
        if (u.avatar) |a| allocator.free(a);
    };
    
    // Create repository
    const repo = DataAccessObject.Repository{
        .id = 0,
        .owner_id = test_user.?.id,
        .lower_name = "test-milestone-repo",
        .name = "test-milestone-repo",
        .description = null,
        .default_branch = "main",
        .is_private = false,
        .is_fork = false,
        .fork_id = null,
        .created_unix = 0,
        .updated_unix = 0,
    };
    const repo_id = try dao.createRepository(allocator, repo);
    
    // Test milestone operations
    const milestone = Milestone{
        .id = 0,
        .repo_id = repo_id,
        .name = "v1.0.0 Release",
        .description = "First stable release",
        .state = .open,
        .due_date = 1672531200, // 2023-01-01
        .created_unix = 0,
        .updated_unix = 0,
        .closed_unix = null,
        .open_issues = 0,
        .closed_issues = 0,
    };
    
    // Create milestone
    const milestone_id = try dao.createMilestone(allocator, milestone);
    try std.testing.expect(milestone_id > 0);
    
    // Get milestone
    const retrieved = try dao.getMilestone(allocator, milestone_id);
    defer if (retrieved) |m| {
        allocator.free(m.name);
        if (m.description) |d| allocator.free(d);
    };
    
    try std.testing.expect(retrieved != null);
    try std.testing.expectEqualStrings("v1.0.0 Release", retrieved.?.name);
    try std.testing.expectEqualStrings("First stable release", retrieved.?.description.?);
    try std.testing.expectEqual(MilestoneState.open, retrieved.?.state);
    try std.testing.expectEqual(@as(i64, 1672531200), retrieved.?.due_date.?);
    
    // Update milestone
    var updated_milestone = retrieved.?;
    updated_milestone.state = .closed;
    updated_milestone.closed_unix = std.time.timestamp();
    updated_milestone.closed_issues = 5;
    
    try dao.updateMilestone(allocator, updated_milestone);
    
    // Verify update
    const updated_retrieved = try dao.getMilestone(allocator, milestone_id);
    defer if (updated_retrieved) |m| {
        allocator.free(m.name);
        if (m.description) |d| allocator.free(d);
    };
    
    try std.testing.expect(updated_retrieved != null);
    try std.testing.expectEqual(MilestoneState.closed, updated_retrieved.?.state);
    try std.testing.expect(updated_retrieved.?.closed_unix != null);
    try std.testing.expectEqual(@as(i32, 5), updated_retrieved.?.closed_issues);
    
    // List milestones for repository
    const milestones = try dao.getMilestones(allocator, repo_id);
    defer {
        for (milestones) |m| {
            allocator.free(m.name);
            if (m.description) |d| allocator.free(d);
        }
        allocator.free(milestones);
    }
    
    try std.testing.expectEqual(@as(usize, 1), milestones.len);
    try std.testing.expectEqualStrings("v1.0.0 Release", milestones[0].name);
    
    // Delete milestone
    try dao.deleteMilestone(allocator, milestone_id);
    
    // Verify deletion
    const deleted_milestone = try dao.getMilestone(allocator, milestone_id);
    try std.testing.expect(deleted_milestone == null);
    
    // Clean up
    dao.deleteUser(allocator, "test_milestone_user") catch {};
}