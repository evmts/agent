//! Repository integration tests
//!
//! Tests repository CRUD operations and related functionality:
//! - Repository creation
//! - Repository listing and searching
//! - Repository updates
//! - Repository deletion
//! - Issue management
//! - Milestone management

const std = @import("std");
const testing = std.testing;
const mod = @import("mod.zig");
const db = @import("db");

const log = std.log.scoped(.repo_test);

// =============================================================================
// Repository CRUD Tests
// =============================================================================

test "repo: create repository" {
    log.info("Testing repository creation", .{});

    const allocator = testing.allocator;
    const test_config = mod.TestConfig{
        .database_url = mod.getTestDatabaseUrl(),
        .cleanup_on_success = true,
    };

    var ctx = try mod.TestContext.init(allocator, test_config);
    defer ctx.deinit(true);

    // Create user
    const user_id = try ctx.createTestUser("repoowner", "owner@example.com");

    // Create repository
    const repo_id = try ctx.createTestRepo(user_id, "test-repo");

    // Verify repository exists
    var conn = try ctx.pool.acquire();
    defer conn.release();

    var result = try conn.query(
        \\SELECT id, name, is_public, default_branch FROM repositories WHERE id = $1
    , .{repo_id});
    defer result.deinit();

    const row = try result.next();
    try testing.expect(row != null);
    try testing.expectEqualStrings("test-repo", row.?.get([]const u8, 1));
    try testing.expect(row.?.get(bool, 2)); // is_public
    try testing.expectEqualStrings("main", row.?.get([]const u8, 3)); // default_branch

    log.info("✓ Repository creation test passed", .{});
}

test "repo: list user repositories" {
    log.info("Testing repository listing", .{});

    const allocator = testing.allocator;
    const test_config = mod.TestConfig{
        .database_url = mod.getTestDatabaseUrl(),
        .cleanup_on_success = true,
    };

    var ctx = try mod.TestContext.init(allocator, test_config);
    defer ctx.deinit(true);

    // Create user
    const user_id = try ctx.createTestUser("repoowner", "owner@example.com");

    // Create multiple repositories
    _ = try ctx.createTestRepo(user_id, "repo1");
    _ = try ctx.createTestRepo(user_id, "repo2");
    _ = try ctx.createTestRepo(user_id, "repo3");

    // List repositories
    var conn = try ctx.pool.acquire();
    defer conn.release();

    var result = try conn.query(
        \\SELECT COUNT(*) FROM repositories WHERE user_id = $1
    , .{user_id});
    defer result.deinit();

    const row = try result.next();
    try testing.expect(row != null);
    const count = row.?.get(i64, 0);
    try testing.expectEqual(@as(i64, 3), count);

    log.info("✓ Repository listing test passed", .{});
}

test "repo: duplicate repository name fails" {
    log.info("Testing duplicate repository name handling", .{});

    const allocator = testing.allocator;
    const test_config = mod.TestConfig{
        .database_url = mod.getTestDatabaseUrl(),
        .cleanup_on_success = true,
    };

    var ctx = try mod.TestContext.init(allocator, test_config);
    defer ctx.deinit(true);

    // Create user
    const user_id = try ctx.createTestUser("repoowner", "owner@example.com");

    // Create repository
    _ = try ctx.createTestRepo(user_id, "duplicate-repo");

    // Try to create duplicate
    var conn = try ctx.pool.acquire();
    defer conn.release();

    const result = conn.exec(
        \\INSERT INTO repositories (user_id, name) VALUES ($1, $2)
    , .{ user_id, "duplicate-repo" });

    // Should fail with unique constraint violation
    try testing.expectError(error.PG, result);

    log.info("✓ Duplicate repository name test passed", .{});
}

test "repo: update repository description" {
    log.info("Testing repository description update", .{});

    const allocator = testing.allocator;
    const test_config = mod.TestConfig{
        .database_url = mod.getTestDatabaseUrl(),
        .cleanup_on_success = true,
    };

    var ctx = try mod.TestContext.init(allocator, test_config);
    defer ctx.deinit(true);

    // Create user and repository
    const user_id = try ctx.createTestUser("repoowner", "owner@example.com");
    const repo_id = try ctx.createTestRepo(user_id, "test-repo");

    // Update description
    var conn = try ctx.pool.acquire();
    defer conn.release();

    _ = try conn.exec(
        \\UPDATE repositories SET description = $1, updated_at = NOW() WHERE id = $2
    , .{ "A test repository", repo_id });

    // Verify update
    var result = try conn.query(
        \\SELECT description FROM repositories WHERE id = $1
    , .{repo_id});
    defer result.deinit();

    const row = try result.next();
    try testing.expect(row != null);
    try testing.expectEqualStrings("A test repository", row.?.get([]const u8, 0));

    log.info("✓ Repository description update test passed", .{});
}

test "repo: delete repository cascades to issues" {
    log.info("Testing repository deletion cascade", .{});

    const allocator = testing.allocator;
    const test_config = mod.TestConfig{
        .database_url = mod.getTestDatabaseUrl(),
        .cleanup_on_success = true,
    };

    var ctx = try mod.TestContext.init(allocator, test_config);
    defer ctx.deinit(true);

    // Create user and repository
    const user_id = try ctx.createTestUser("repoowner", "owner@example.com");
    const repo_id = try ctx.createTestRepo(user_id, "test-repo");

    // Create issue
    var conn = try ctx.pool.acquire();
    defer conn.release();

    var result = try conn.query(
        \\INSERT INTO issues (repository_id, author_id, issue_number, title, body)
        \\VALUES ($1, $2, 1, 'Test Issue', 'Test body')
        \\RETURNING id
    , .{ repo_id, user_id });
    defer result.deinit();

    const issue_row = try result.next();
    try testing.expect(issue_row != null);
    const issue_id = issue_row.?.get(i64, 0);

    // Delete repository
    _ = try conn.exec("DELETE FROM repositories WHERE id = $1", .{repo_id});

    // Verify issue was deleted
    var check_result = try conn.query("SELECT id FROM issues WHERE id = $1", .{issue_id});
    defer check_result.deinit();

    const check_row = try check_result.next();
    try testing.expect(check_row == null);

    log.info("✓ Repository deletion cascade test passed", .{});
}

// =============================================================================
// Issue Management Tests
// =============================================================================

test "issue: create issue" {
    log.info("Testing issue creation", .{});

    const allocator = testing.allocator;
    const test_config = mod.TestConfig{
        .database_url = mod.getTestDatabaseUrl(),
        .cleanup_on_success = true,
    };

    var ctx = try mod.TestContext.init(allocator, test_config);
    defer ctx.deinit(true);

    // Create user and repository
    const user_id = try ctx.createTestUser("issueauthor", "author@example.com");
    const repo_id = try ctx.createTestRepo(user_id, "issue-repo");

    // Create issue
    var conn = try ctx.pool.acquire();
    defer conn.release();

    var result = try conn.query(
        \\INSERT INTO issues (repository_id, author_id, issue_number, title, body, state)
        \\VALUES ($1, $2, 1, 'Bug Report', 'Something is broken', 'open')
        \\RETURNING id
    , .{ repo_id, user_id });
    defer result.deinit();

    const row = try result.next();
    try testing.expect(row != null);
    const issue_id = row.?.get(i64, 0);

    // Verify issue
    var verify_result = try conn.query(
        \\SELECT title, body, state, issue_number FROM issues WHERE id = $1
    , .{issue_id});
    defer verify_result.deinit();

    const verify_row = try verify_result.next();
    try testing.expect(verify_row != null);
    try testing.expectEqualStrings("Bug Report", verify_row.?.get([]const u8, 0));
    try testing.expectEqualStrings("Something is broken", verify_row.?.get([]const u8, 1));
    try testing.expectEqualStrings("open", verify_row.?.get([]const u8, 2));
    try testing.expectEqual(@as(i64, 1), verify_row.?.get(i64, 3));

    log.info("✓ Issue creation test passed", .{});
}

test "issue: issue numbers are sequential per repository" {
    log.info("Testing sequential issue numbers", .{});

    const allocator = testing.allocator;
    const test_config = mod.TestConfig{
        .database_url = mod.getTestDatabaseUrl(),
        .cleanup_on_success = true,
    };

    var ctx = try mod.TestContext.init(allocator, test_config);
    defer ctx.deinit(true);

    // Create user and repository
    const user_id = try ctx.createTestUser("issueauthor", "author@example.com");
    const repo_id = try ctx.createTestRepo(user_id, "issue-repo");

    // Create multiple issues
    var conn = try ctx.pool.acquire();
    defer conn.release();

    for (1..6) |i| {
        _ = try conn.exec(
            \\INSERT INTO issues (repository_id, author_id, issue_number, title)
            \\VALUES ($1, $2, $3, $4)
        , .{ repo_id, user_id, @as(i64, @intCast(i)), "Issue" });
    }

    // Verify issue numbers
    var result = try conn.query(
        \\SELECT issue_number FROM issues WHERE repository_id = $1 ORDER BY issue_number
    , .{repo_id});
    defer result.deinit();

    var expected: i64 = 1;
    while (try result.next()) |row| {
        try testing.expectEqual(expected, row.get(i64, 0));
        expected += 1;
    }

    try testing.expectEqual(@as(i64, 6), expected);

    log.info("✓ Sequential issue numbers test passed", .{});
}

test "issue: close and reopen issue" {
    log.info("Testing issue state changes", .{});

    const allocator = testing.allocator;
    const test_config = mod.TestConfig{
        .database_url = mod.getTestDatabaseUrl(),
        .cleanup_on_success = true,
    };

    var ctx = try mod.TestContext.init(allocator, test_config);
    defer ctx.deinit(true);

    // Create user, repository, and issue
    const user_id = try ctx.createTestUser("issueauthor", "author@example.com");
    const repo_id = try ctx.createTestRepo(user_id, "issue-repo");

    var conn = try ctx.pool.acquire();
    defer conn.release();

    var result = try conn.query(
        \\INSERT INTO issues (repository_id, author_id, issue_number, title, state)
        \\VALUES ($1, $2, 1, 'Test Issue', 'open')
        \\RETURNING id
    , .{ repo_id, user_id });
    defer result.deinit();

    const row = try result.next();
    try testing.expect(row != null);
    const issue_id = row.?.get(i64, 0);

    // Close issue
    _ = try conn.exec(
        \\UPDATE issues SET state = 'closed', closed_at = NOW() WHERE id = $1
    , .{issue_id});

    // Verify closed
    var check1 = try conn.query("SELECT state FROM issues WHERE id = $1", .{issue_id});
    defer check1.deinit();

    const closed_row = try check1.next();
    try testing.expect(closed_row != null);
    try testing.expectEqualStrings("closed", closed_row.?.get([]const u8, 0));

    // Reopen issue
    _ = try conn.exec(
        \\UPDATE issues SET state = 'open', closed_at = NULL WHERE id = $1
    , .{issue_id});

    // Verify reopened
    var check2 = try conn.query("SELECT state FROM issues WHERE id = $1", .{issue_id});
    defer check2.deinit();

    const open_row = try check2.next();
    try testing.expect(open_row != null);
    try testing.expectEqualStrings("open", open_row.?.get([]const u8, 0));

    log.info("✓ Issue state change test passed", .{});
}

test "issue: add comment to issue" {
    log.info("Testing issue comments", .{});

    const allocator = testing.allocator;
    const test_config = mod.TestConfig{
        .database_url = mod.getTestDatabaseUrl(),
        .cleanup_on_success = true,
    };

    var ctx = try mod.TestContext.init(allocator, test_config);
    defer ctx.deinit(true);

    // Create user, repository, and issue
    const user_id = try ctx.createTestUser("commenter", "commenter@example.com");
    const repo_id = try ctx.createTestRepo(user_id, "comment-repo");

    var conn = try ctx.pool.acquire();
    defer conn.release();

    var result = try conn.query(
        \\INSERT INTO issues (repository_id, author_id, issue_number, title)
        \\VALUES ($1, $2, 1, 'Issue with comments')
        \\RETURNING id
    , .{ repo_id, user_id });
    defer result.deinit();

    const issue_row = try result.next();
    try testing.expect(issue_row != null);
    const issue_id = issue_row.?.get(i64, 0);

    // Add comments
    _ = try conn.exec(
        \\INSERT INTO comments (issue_id, author_id, body) VALUES ($1, $2, $3)
    , .{ issue_id, user_id, "First comment" });

    _ = try conn.exec(
        \\INSERT INTO comments (issue_id, author_id, body) VALUES ($1, $2, $3)
    , .{ issue_id, user_id, "Second comment" });

    // Count comments
    var count_result = try conn.query(
        \\SELECT COUNT(*) FROM comments WHERE issue_id = $1
    , .{issue_id});
    defer count_result.deinit();

    const count_row = try count_result.next();
    try testing.expect(count_row != null);
    try testing.expectEqual(@as(i64, 2), count_row.?.get(i64, 0));

    log.info("✓ Issue comments test passed", .{});
}

// =============================================================================
// Milestone Tests
// =============================================================================

test "milestone: create and assign to issue" {
    log.info("Testing milestone creation and assignment", .{});

    const allocator = testing.allocator;
    const test_config = mod.TestConfig{
        .database_url = mod.getTestDatabaseUrl(),
        .cleanup_on_success = true,
    };

    var ctx = try mod.TestContext.init(allocator, test_config);
    defer ctx.deinit(true);

    // Create user and repository
    const user_id = try ctx.createTestUser("milestoneuser", "milestone@example.com");
    const repo_id = try ctx.createTestRepo(user_id, "milestone-repo");

    var conn = try ctx.pool.acquire();
    defer conn.release();

    // Create milestone
    var milestone_result = try conn.query(
        \\INSERT INTO milestones (repository_id, title, description, state)
        \\VALUES ($1, 'v1.0', 'First release', 'open')
        \\RETURNING id
    , .{repo_id});
    defer milestone_result.deinit();

    const milestone_row = try milestone_result.next();
    try testing.expect(milestone_row != null);
    const milestone_id = milestone_row.?.get(i64, 0);

    // Create issue with milestone
    var issue_result = try conn.query(
        \\INSERT INTO issues (repository_id, author_id, issue_number, title, milestone_id)
        \\VALUES ($1, $2, 1, 'Issue for v1.0', $3)
        \\RETURNING id
    , .{ repo_id, user_id, milestone_id });
    defer issue_result.deinit();

    const issue_row = try issue_result.next();
    try testing.expect(issue_row != null);
    const issue_id = issue_row.?.get(i64, 0);

    // Verify assignment
    var verify_result = try conn.query(
        \\SELECT milestone_id FROM issues WHERE id = $1
    , .{issue_id});
    defer verify_result.deinit();

    const verify_row = try verify_result.next();
    try testing.expect(verify_row != null);
    try testing.expectEqual(milestone_id, verify_row.?.get(i64, 0));

    log.info("✓ Milestone test passed", .{});
}

// =============================================================================
// Labels Tests
// =============================================================================

test "labels: create and assign to issue" {
    log.info("Testing label creation and assignment", .{});

    const allocator = testing.allocator;
    const test_config = mod.TestConfig{
        .database_url = mod.getTestDatabaseUrl(),
        .cleanup_on_success = true,
    };

    var ctx = try mod.TestContext.init(allocator, test_config);
    defer ctx.deinit(true);

    // Create user and repository
    const user_id = try ctx.createTestUser("labeluser", "label@example.com");
    const repo_id = try ctx.createTestRepo(user_id, "label-repo");

    var conn = try ctx.pool.acquire();
    defer conn.release();

    // Create labels
    var bug_result = try conn.query(
        \\INSERT INTO labels (repository_id, name, color, description)
        \\VALUES ($1, 'bug', '#ff0000', 'Something is not working')
        \\RETURNING id
    , .{repo_id});
    defer bug_result.deinit();

    const bug_row = try bug_result.next();
    try testing.expect(bug_row != null);
    const bug_label_id = bug_row.?.get(i64, 0);

    var feature_result = try conn.query(
        \\INSERT INTO labels (repository_id, name, color, description)
        \\VALUES ($1, 'feature', '#00ff00', 'New feature request')
        \\RETURNING id
    , .{repo_id});
    defer feature_result.deinit();

    const feature_row = try feature_result.next();
    try testing.expect(feature_row != null);
    const feature_label_id = feature_row.?.get(i64, 0);

    // Create issue
    var issue_result = try conn.query(
        \\INSERT INTO issues (repository_id, author_id, issue_number, title)
        \\VALUES ($1, $2, 1, 'Labeled Issue')
        \\RETURNING id
    , .{ repo_id, user_id });
    defer issue_result.deinit();

    const issue_row = try issue_result.next();
    try testing.expect(issue_row != null);
    const issue_id = issue_row.?.get(i64, 0);

    // Assign labels
    _ = try conn.exec(
        \\INSERT INTO issue_labels (issue_id, label_id) VALUES ($1, $2)
    , .{ issue_id, bug_label_id });

    _ = try conn.exec(
        \\INSERT INTO issue_labels (issue_id, label_id) VALUES ($1, $2)
    , .{ issue_id, feature_label_id });

    // Verify labels
    var count_result = try conn.query(
        \\SELECT COUNT(*) FROM issue_labels WHERE issue_id = $1
    , .{issue_id});
    defer count_result.deinit();

    const count_row = try count_result.next();
    try testing.expect(count_row != null);
    try testing.expectEqual(@as(i64, 2), count_row.?.get(i64, 0));

    log.info("✓ Labels test passed", .{});
}

// =============================================================================
// Integration Tests
// =============================================================================

test "integration: full repository workflow" {
    log.info("Testing full repository workflow", .{});

    const allocator = testing.allocator;
    const test_config = mod.TestConfig{
        .database_url = mod.getTestDatabaseUrl(),
        .cleanup_on_success = true,
    };

    var ctx = try mod.TestContext.init(allocator, test_config);
    defer ctx.deinit(true);

    // 1. Create user
    const user_id = try ctx.createTestUser("workflowuser", "workflow@example.com");

    // 2. Create repository
    const repo_id = try ctx.createTestRepo(user_id, "workflow-repo");

    var conn = try ctx.pool.acquire();
    defer conn.release();

    // 3. Create milestone
    var milestone_result = try conn.query(
        \\INSERT INTO milestones (repository_id, title) VALUES ($1, 'v1.0') RETURNING id
    , .{repo_id});
    defer milestone_result.deinit();

    const milestone_row = try milestone_result.next();
    try testing.expect(milestone_row != null);
    const milestone_id = milestone_row.?.get(i64, 0);

    // 4. Create label
    var label_result = try conn.query(
        \\INSERT INTO labels (repository_id, name, color) VALUES ($1, 'bug', '#ff0000') RETURNING id
    , .{repo_id});
    defer label_result.deinit();

    const label_row = try label_result.next();
    try testing.expect(label_row != null);
    const label_id = label_row.?.get(i64, 0);

    // 5. Create issue with milestone
    var issue_result = try conn.query(
        \\INSERT INTO issues (repository_id, author_id, issue_number, title, milestone_id)
        \\VALUES ($1, $2, 1, 'Critical Bug', $3) RETURNING id
    , .{ repo_id, user_id, milestone_id });
    defer issue_result.deinit();

    const issue_row = try issue_result.next();
    try testing.expect(issue_row != null);
    const issue_id = issue_row.?.get(i64, 0);

    // 6. Assign label to issue
    _ = try conn.exec(
        \\INSERT INTO issue_labels (issue_id, label_id) VALUES ($1, $2)
    , .{ issue_id, label_id });

    // 7. Add comment
    _ = try conn.exec(
        \\INSERT INTO comments (issue_id, author_id, body) VALUES ($1, $2, 'Working on fix')
    , .{ issue_id, user_id });

    // 8. Close issue
    _ = try conn.exec(
        \\UPDATE issues SET state = 'closed', closed_at = NOW() WHERE id = $1
    , .{issue_id});

    // Verify final state
    var verify_result = try conn.query(
        \\SELECT i.state, m.title, COUNT(c.id) as comment_count
        \\FROM issues i
        \\LEFT JOIN milestones m ON i.milestone_id = m.id
        \\LEFT JOIN comments c ON c.issue_id = i.id
        \\WHERE i.id = $1
        \\GROUP BY i.state, m.title
    , .{issue_id});
    defer verify_result.deinit();

    const verify_row = try verify_result.next();
    try testing.expect(verify_row != null);
    try testing.expectEqualStrings("closed", verify_row.?.get([]const u8, 0));
    try testing.expectEqualStrings("v1.0", verify_row.?.get([]const u8, 1));
    try testing.expectEqual(@as(i64, 1), verify_row.?.get(i64, 2));

    log.info("✓ Full repository workflow test passed", .{});
}
