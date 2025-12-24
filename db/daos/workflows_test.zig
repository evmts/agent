//! Integration tests for workflows DAO
//!
//! These tests require a running PostgreSQL instance with the schema applied.
//! Set TEST_DATABASE_URL environment variable to point to your test database.

const std = @import("std");
const pg = @import("pg");
const workflows = @import("workflows.zig");

test "workflow_definitions CRUD" {
    const allocator = std.testing.allocator;

    // Get database URL from environment
    _ = std.posix.getenv("TEST_DATABASE_URL") orelse {
        std.debug.print("Skipping test: TEST_DATABASE_URL not set\n", .{});
        return error.SkipZigTest;
    };

    // Connect to database
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

    // Test data
    const repo_id: ?i32 = 1;
    const name = "test-workflow";
    const file_path = ".plue/workflows/test.py";
    const triggers = "[{\"type\":\"push\"}]";
    const image: ?[]const u8 = "ubuntu:22.04";
    const dockerfile: ?[]const u8 = null;
    const plan = "{\"steps\":[]}";
    const content_hash = "abc123def456";

    // Test upsert (insert)
    const def_id = try workflows.upsertWorkflowDefinition(
        pool,
        repo_id,
        name,
        file_path,
        triggers,
        image,
        dockerfile,
        plan,
        content_hash,
    );
    try std.testing.expect(def_id > 0);

    // Test get by ID
    const def = try workflows.getWorkflowDefinition(pool, def_id);
    try std.testing.expect(def != null);
    try std.testing.expectEqual(def_id, def.?.id);
    try std.testing.expectEqualStrings(name, def.?.name);
    try std.testing.expectEqualStrings(file_path, def.?.file_path);

    // Test get by name
    const def_by_name = try workflows.getWorkflowDefinitionByName(pool, repo_id, name);
    try std.testing.expect(def_by_name != null);
    try std.testing.expectEqual(def_id, def_by_name.?.id);

    // Test list
    const defs = try workflows.listWorkflowDefinitions(pool, allocator, repo_id);
    defer allocator.free(defs);
    try std.testing.expect(defs.len > 0);

    // Cleanup
    _ = try pool.exec("DELETE FROM workflow_definitions WHERE id = $1", .{def_id});
}

test "workflow_runs CRUD" {
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

    // Test data
    const workflow_definition_id: ?i32 = null;
    const trigger_type = "push";
    const trigger_payload = "{\"ref\":\"refs/heads/main\"}";
    const inputs: ?[]const u8 = null;

    // Test create
    const run_id = try workflows.createWorkflowRun(
        pool,
        workflow_definition_id,
        trigger_type,
        trigger_payload,
        inputs,
    );
    try std.testing.expect(run_id > 0);

    // Test get
    const run = try workflows.getWorkflowRun(pool, run_id);
    try std.testing.expect(run != null);
    try std.testing.expectEqual(run_id, run.?.id);
    try std.testing.expectEqualStrings("pending", run.?.status);
    try std.testing.expectEqualStrings(trigger_type, run.?.trigger_type);

    // Test update status
    try workflows.updateWorkflowRunStatus(pool, run_id, "running");
    const run2 = try workflows.getWorkflowRun(pool, run_id);
    try std.testing.expectEqualStrings("running", run2.?.status);
    try std.testing.expect(run2.?.started_at != null);

    // Test complete
    try workflows.completeWorkflowRun(pool, run_id, "{\"result\":\"success\"}", null);
    const run3 = try workflows.getWorkflowRun(pool, run_id);
    try std.testing.expectEqualStrings("completed", run3.?.status);
    try std.testing.expect(run3.?.completed_at != null);

    // Test list
    const runs = try workflows.listWorkflowRuns(pool, allocator, null, 10);
    defer allocator.free(runs);
    try std.testing.expect(runs.len > 0);

    // Cleanup
    _ = try pool.exec("DELETE FROM workflow_runs WHERE id = $1", .{run_id});
}

test "workflow_steps CRUD" {
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

    // Create a workflow run first
    const run_id = try workflows.createWorkflowRun(pool, null, "manual", "{}", null);
    defer _ = pool.exec("DELETE FROM workflow_runs WHERE id = $1", .{run_id}) catch {};

    // Test data
    const step_id_str = "step_1";
    const name = "build";
    const step_type = "shell";
    const config = "{\"cmd\":\"zig build\"}";

    // Test create
    const step_id = try workflows.createWorkflowStep(
        pool,
        run_id,
        step_id_str,
        name,
        step_type,
        config,
    );
    try std.testing.expect(step_id > 0);

    // Test get
    const step = try workflows.getWorkflowStep(pool, step_id);
    try std.testing.expect(step != null);
    try std.testing.expectEqual(step_id, step.?.id);
    try std.testing.expectEqualStrings(name, step.?.name);
    try std.testing.expectEqualStrings("pending", step.?.status);

    // Test update status
    try workflows.updateWorkflowStepStatus(pool, step_id, "running");
    const step2 = try workflows.getWorkflowStep(pool, step_id);
    try std.testing.expectEqualStrings("running", step2.?.status);

    // Test complete
    try workflows.completeWorkflowStep(pool, step_id, 0, "{\"output\":\"success\"}", null, null, 100, 200);
    const step3 = try workflows.getWorkflowStep(pool, step_id);
    try std.testing.expectEqualStrings("completed", step3.?.status);
    try std.testing.expectEqual(@as(?i32, 0), step3.?.exit_code);
    try std.testing.expectEqual(@as(?i32, 100), step3.?.tokens_in);
    try std.testing.expectEqual(@as(?i32, 200), step3.?.tokens_out);

    // Test list
    const steps = try workflows.listWorkflowSteps(pool, allocator, run_id);
    defer allocator.free(steps);
    try std.testing.expectEqual(@as(usize, 1), steps.len);
}

test "workflow_logs CRUD" {
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

    // Create workflow run and step
    const run_id = try workflows.createWorkflowRun(pool, null, "manual", "{}", null);
    defer _ = pool.exec("DELETE FROM workflow_runs WHERE id = $1", .{run_id}) catch {};

    const step_id = try workflows.createWorkflowStep(pool, run_id, "step_1", "test", "shell", "{}");

    // Test append logs
    const log_id1 = try workflows.appendWorkflowLog(pool, step_id, "stdout", "Building project...", 0);
    try std.testing.expect(log_id1 > 0);

    const log_id2 = try workflows.appendWorkflowLog(pool, step_id, "stdout", "Build succeeded", 1);
    try std.testing.expect(log_id2 > 0);

    // Test list logs
    const logs = try workflows.listWorkflowLogs(pool, allocator, step_id);
    defer allocator.free(logs);
    try std.testing.expectEqual(@as(usize, 2), logs.len);
    try std.testing.expectEqualStrings("Building project...", logs[0].content);
    try std.testing.expectEqualStrings("Build succeeded", logs[1].content);
}

test "llm_usage CRUD" {
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

    // Create workflow run and step
    const run_id = try workflows.createWorkflowRun(pool, null, "manual", "{}", null);
    defer _ = pool.exec("DELETE FROM workflow_runs WHERE id = $1", .{run_id}) catch {};

    const step_id = try workflows.createWorkflowStep(pool, run_id, "step_1", "agent", "agent", "{}");

    // Test record usage
    const usage_id = try workflows.recordLlmUsage(
        pool,
        step_id,
        "CodeReview",
        "claude-sonnet-4-20250514",
        1000,
        500,
        1500,
    );
    try std.testing.expect(usage_id > 0);

    // Test get usage
    const usage = try workflows.getLlmUsageForStep(pool, allocator, step_id);
    defer allocator.free(usage);
    try std.testing.expectEqual(@as(usize, 1), usage.len);
    try std.testing.expectEqualStrings("claude-sonnet-4-20250514", usage[0].model);
    try std.testing.expectEqual(@as(i32, 1000), usage[0].input_tokens);
    try std.testing.expectEqual(@as(i32, 500), usage[0].output_tokens);
    try std.testing.expectEqual(@as(i32, 1500), usage[0].latency_ms);
}
