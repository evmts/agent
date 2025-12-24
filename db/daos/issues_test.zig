//! Integration tests for issues DAO
//!
//! These tests require a running PostgreSQL instance with the schema applied.
//! Set TEST_DATABASE_URL environment variable to point to your test database.

const std = @import("std");
const pg = @import("pg");
const issues = @import("issues.zig");
const repositories = @import("repositories.zig");
const users = @import("users.zig");

test "concurrent issue creation - no duplicate numbers" {
    const allocator = std.testing.allocator;

    // Get database URL from environment
    _ = std.posix.getenv("TEST_DATABASE_URL") orelse {
        std.debug.print("Skipping test: TEST_DATABASE_URL not set\n", .{});
        return error.SkipZigTest;
    };

    // Connect to database
    const pool = try pg.Pool.init(allocator, .{
        .size = 10, // Need multiple connections for concurrency
        .connect = .{
            .host = "localhost",
            .port = 54321,
        },
        .auth = .{
            .database = "plue_test",
            .username = "postgres",
            .password = "password",
            .timeout = 5_000,
        },
    });
    defer pool.deinit();

    // Create test user
    const user_id = try users.create(
        pool,
        "test_concurrent_user",
        null,
        null,
    );
    defer users.delete(pool, user_id) catch {};

    // Create test repository
    const repo_id = try repositories.create(
        pool,
        user_id,
        "test_concurrent_repo",
        "Test repository for concurrent issue creation",
        true,
    );
    defer repositories.delete(pool, repo_id) catch {};

    // Create multiple issues concurrently
    const num_issues = 20;
    var threads: [num_issues]std.Thread = undefined;
    var issue_numbers: [num_issues]?i64 = [_]?i64{null} ** num_issues;

    // Thread function to create an issue
    const ThreadContext = struct {
        pool: *pg.Pool,
        repo_id: i64,
        author_id: i64,
        index: usize,
        result: *?i64,
        allocator: std.mem.Allocator,
    };

    const createIssueThread = struct {
        fn run(ctx: ThreadContext) void {
            const title = std.fmt.allocPrint(
                ctx.allocator,
                "Concurrent Issue {d}",
                .{ctx.index},
            ) catch |err| {
                std.debug.print("Failed to format title: {}\n", .{err});
                return;
            };
            defer ctx.allocator.free(title);

            const issue = issues.create(
                ctx.pool,
                ctx.repo_id,
                ctx.author_id,
                title,
                null,
            ) catch |err| {
                std.debug.print("Failed to create issue: {}\n", .{err});
                return;
            };

            ctx.result.* = issue.issue_number;
        }
    }.run;

    // Spawn all threads
    for (0..num_issues) |i| {
        const ctx = ThreadContext{
            .pool = pool,
            .repo_id = repo_id,
            .author_id = user_id,
            .index = i,
            .result = &issue_numbers[i],
            .allocator = allocator,
        };
        threads[i] = try std.Thread.spawn(.{}, createIssueThread, .{ctx});
    }

    // Wait for all threads to complete
    for (threads) |thread| {
        thread.join();
    }

    // Verify all issues were created with unique numbers
    var seen_numbers = std.AutoHashMap(i64, void).init(allocator);
    defer seen_numbers.deinit();

    var successful_creates: usize = 0;
    for (issue_numbers) |maybe_num| {
        if (maybe_num) |num| {
            successful_creates += 1;

            // Check for duplicates
            const gop = try seen_numbers.getOrPut(num);
            if (gop.found_existing) {
                std.debug.print("DUPLICATE ISSUE NUMBER FOUND: {d}\n", .{num});
                try std.testing.expect(false); // Fail the test
            }
        }
    }

    // All issues should have been created successfully
    try std.testing.expectEqual(num_issues, successful_creates);

    // Verify issue numbers are sequential from 1 to num_issues
    for (1..num_issues + 1) |expected_num| {
        const has_number = seen_numbers.contains(@intCast(expected_num));
        if (!has_number) {
            std.debug.print("Missing issue number: {d}\n", .{expected_num});
        }
        try std.testing.expect(has_number);
    }

    std.debug.print("✓ Successfully created {d} concurrent issues with unique numbers\n", .{num_issues});
}

test "issue creation - sequential numbers" {
    const allocator = std.testing.allocator;

    _ = std.posix.getenv("TEST_DATABASE_URL") orelse {
        std.debug.print("Skipping test: TEST_DATABASE_URL not set\n", .{});
        return error.SkipZigTest;
    };

    const pool = try pg.Pool.init(allocator, .{
        .size = 1,
        .connect = .{
            .host = "localhost",
            .port = 54321,
        },
        .auth = .{
            .database = "plue_test",
            .username = "postgres",
            .password = "password",
            .timeout = 5_000,
        },
    });
    defer pool.deinit();

    // Create test user
    const user_id = try users.create(
        pool,
        "test_sequential_user",
        null,
        null,
    );
    defer users.delete(pool, user_id) catch {};

    // Create test repository
    const repo_id = try repositories.create(
        pool,
        user_id,
        "test_sequential_repo",
        "Test repository for sequential issue numbers",
        true,
    );
    defer repositories.delete(pool, repo_id) catch {};

    // Create issues and verify they get sequential numbers
    const issue1 = try issues.create(pool, repo_id, user_id, "Issue 1", null);
    try std.testing.expectEqual(@as(i64, 1), issue1.issue_number);

    const issue2 = try issues.create(pool, repo_id, user_id, "Issue 2", null);
    try std.testing.expectEqual(@as(i64, 2), issue2.issue_number);

    const issue3 = try issues.create(pool, repo_id, user_id, "Issue 3", null);
    try std.testing.expectEqual(@as(i64, 3), issue3.issue_number);

    std.debug.print("✓ Issue numbers are sequential: 1, 2, 3\n", .{});
}
