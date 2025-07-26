const std = @import("std");

pub const Issue = struct {
    id: i64,
    repo_id: i64,
    index: i64,
    poster_id: i64,
    title: []const u8,
    content: ?[]const u8,
    is_closed: bool,
    is_pull: bool,
    assignee_id: ?i64,
    created_unix: i64,
};

pub const Label = struct {
    id: i64,
    repo_id: i64,
    name: []const u8,
    color: []const u8,
};

pub const IssueLabel = struct {
    id: i64,
    issue_id: i64,
    label_id: i64,
};

pub const ReviewType = enum(i16) {
    approve = 1,
    reject = 2,
    comment = 3,
};

pub const Review = struct {
    id: i64,
    type: ReviewType,
    reviewer_id: i64,
    issue_id: i64,
    commit_id: ?[]const u8,
};

pub const Comment = struct {
    id: i64,
    poster_id: i64,
    issue_id: i64,
    review_id: ?i64,
    content: []const u8,
    commit_id: ?[]const u8,
    line: ?i32,
    created_unix: i64,
};

test "Issue model" {
    const issue = Issue{
        .id = 1,
        .repo_id = 123,
        .index = 42,
        .poster_id = 456,
        .title = "Bug: Something is broken",
        .content = "Detailed description here",
        .is_closed = false,
        .is_pull = false,
        .assignee_id = null,
        .created_unix = 1234567890,
    };
    
    try std.testing.expectEqual(@as(i64, 42), issue.index);
    try std.testing.expectEqualStrings("Bug: Something is broken", issue.title);
    try std.testing.expectEqual(false, issue.is_pull);
}

test "Label model" {
    const label = Label{
        .id = 1,
        .repo_id = 123,
        .name = "bug",
        .color = "#ff0000",
    };
    
    try std.testing.expectEqualStrings("bug", label.name);
    try std.testing.expectEqualStrings("#ff0000", label.color);
}

test "Review and Comment models" {
    const review = Review{
        .id = 1,
        .type = .approve,
        .reviewer_id = 789,
        .issue_id = 456,
        .commit_id = "abc123",
    };
    
    const comment = Comment{
        .id = 1,
        .poster_id = 789,
        .issue_id = 456,
        .review_id = 1,
        .content = "Looks good to me!",
        .commit_id = "abc123",
        .line = 42,
        .created_unix = 1234567890,
    };
    
    try std.testing.expectEqual(ReviewType.approve, review.type);
    try std.testing.expectEqualStrings("Looks good to me!", comment.content);
    try std.testing.expectEqual(@as(i32, 42), comment.line.?);
}

test "Issue database operations" {
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
    dao.deleteUser(allocator, "test_issue_owner") catch {};
    dao.deleteUser(allocator, "test_issue_poster") catch {};
    
    // Create users
    const owner = DataAccessObject.User{
        .id = 0,
        .name = "test_issue_owner",
        .email = "owner@test.com",
        .passwd = null,
        .type = .individual,
        .is_admin = false,
        .avatar = null,
        .created_unix = 0,
        .updated_unix = 0,
    };
    try dao.createUser(allocator, owner);
    
    const poster = DataAccessObject.User{
        .id = 0,
        .name = "test_issue_poster",
        .email = "poster@test.com",
        .passwd = null,
        .type = .individual,
        .is_admin = false,
        .avatar = null,
        .created_unix = 0,
        .updated_unix = 0,
    };
    try dao.createUser(allocator, poster);
    
    const owner_user = try dao.getUserByName(allocator, "test_issue_owner");
    defer if (owner_user) |u| {
        allocator.free(u.name);
        if (u.email) |e| allocator.free(e);
        if (u.passwd) |p| allocator.free(p);
        if (u.avatar) |a| allocator.free(a);
    };
    
    const poster_user = try dao.getUserByName(allocator, "test_issue_poster");
    defer if (poster_user) |u| {
        allocator.free(u.name);
        if (u.email) |e| allocator.free(e);
        if (u.passwd) |p| allocator.free(p);
        if (u.avatar) |a| allocator.free(a);
    };
    
    // Create repository
    const repo = DataAccessObject.Repository{
        .id = 0,
        .owner_id = owner_user.?.id,
        .lower_name = "test-issue-repo",
        .name = "test-issue-repo",
        .description = null,
        .default_branch = "main",
        .is_private = false,
        .is_fork = false,
        .fork_id = null,
        .created_unix = 0,
        .updated_unix = 0,
    };
    const repo_id = try dao.createRepository(allocator, repo);
    
    // Create issue
    const issue = Issue{
        .id = 0,
        .repo_id = repo_id,
        .index = 0, // Will be assigned
        .poster_id = poster_user.?.id,
        .title = "Test Issue",
        .content = "This is a test issue",
        .is_closed = false,
        .is_pull = false,
        .assignee_id = owner_user.?.id,
        .created_unix = 0,
    };
    
    const issue_id = try dao.createIssue(allocator, issue);
    try std.testing.expect(issue_id > 0);
    
    // Get issue
    const retrieved = try dao.getIssue(allocator, repo_id, 1);
    defer if (retrieved) |i| {
        allocator.free(i.title);
        if (i.content) |c| allocator.free(c);
    };
    
    try std.testing.expect(retrieved != null);
    try std.testing.expectEqualStrings("Test Issue", retrieved.?.title);
    try std.testing.expectEqual(@as(i64, 1), retrieved.?.index);
    try std.testing.expectEqual(false, retrieved.?.is_pull);
    
    // Clean up
    dao.deleteUser(allocator, "test_issue_owner") catch {};
    dao.deleteUser(allocator, "test_issue_poster") catch {};
}