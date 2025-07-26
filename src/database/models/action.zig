const std = @import("std");

pub const ActionStatus = enum(i16) {
    queued = 0,
    in_progress = 1,
    success = 2,
    failure = 3,
};

pub const ActionRun = struct {
    id: i64,
    repo_id: i64,
    workflow_id: []const u8,
    commit_sha: []const u8,
    trigger_event: []const u8,
    status: ActionStatus,
    created_unix: i64,
};

pub const ActionJob = struct {
    id: i64,
    run_id: i64,
    name: []const u8,
    runs_on: []const u8,
    status: ActionStatus,
    log: ?[]const u8,
    started: ?i64,
    stopped: ?i64,
};

pub const ActionRunner = struct {
    id: i64,
    uuid: []const u8,
    name: []const u8,
    owner_id: i64,
    repo_id: i64,
    token_hash: []const u8,
    labels: ?[]const u8,
    status: []const u8,
    last_online: ?i64,
};

pub const ActionRunnerToken = struct {
    id: i64,
    token_hash: []const u8,
    owner_id: i64,
    repo_id: i64,
};

pub const ActionArtifact = struct {
    id: i64,
    job_id: i64,
    name: []const u8,
    path: []const u8,
    file_size: i64,
};

pub const ActionSecret = struct {
    id: i64,
    owner_id: i64,
    repo_id: i64,
    name: []const u8,
    data: []const u8,
};

test "ActionRun model" {
    const run = ActionRun{
        .id = 1,
        .repo_id = 123,
        .workflow_id = "ci.yml",
        .commit_sha = "abc123def456",
        .trigger_event = "push",
        .status = .queued,
        .created_unix = 1234567890,
    };
    
    try std.testing.expectEqual(@as(i64, 123), run.repo_id);
    try std.testing.expectEqualStrings("ci.yml", run.workflow_id);
    try std.testing.expectEqual(ActionStatus.queued, run.status);
}

test "ActionJob model" {
    const job = ActionJob{
        .id = 1,
        .run_id = 456,
        .name = "build",
        .runs_on = "[\"ubuntu-latest\"]",
        .status = .in_progress,
        .log = "Building project...",
        .started = 1234567890,
        .stopped = null,
    };
    
    try std.testing.expectEqual(@as(i64, 456), job.run_id);
    try std.testing.expectEqualStrings("build", job.name);
    try std.testing.expectEqual(ActionStatus.in_progress, job.status);
}

test "ActionRunner model" {
    const runner = ActionRunner{
        .id = 1,
        .uuid = "550e8400-e29b-41d4-a716-446655440000",
        .name = "my-runner",
        .owner_id = 0,
        .repo_id = 123,
        .token_hash = "hashed_token",
        .labels = "[\"self-hosted\", \"linux\"]",
        .status = "online",
        .last_online = 1234567890,
    };
    
    try std.testing.expectEqualStrings("my-runner", runner.name);
    try std.testing.expectEqualStrings("online", runner.status);
    try std.testing.expectEqual(@as(i64, 123), runner.repo_id);
}

test "ActionArtifact and Secret models" {
    const artifact = ActionArtifact{
        .id = 1,
        .job_id = 789,
        .name = "build-output",
        .path = "/artifacts/build-output.zip",
        .file_size = 1024 * 1024 * 10,
    };
    
    const secret = ActionSecret{
        .id = 1,
        .owner_id = 0,
        .repo_id = 123,
        .name = "API_KEY",
        .data = "encrypted_data_here",
    };
    
    try std.testing.expectEqualStrings("build-output", artifact.name);
    try std.testing.expectEqual(@as(i64, 1024 * 1024 * 10), artifact.file_size);
    try std.testing.expectEqualStrings("API_KEY", secret.name);
}