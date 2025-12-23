//! Workflows Data Access Object
//!
//! SQL operations for the Python-based workflow system:
//! - workflow_definitions: Parsed .py workflow files
//! - prompt_definitions: Parsed .prompt.md files
//! - workflow_runs: Workflow execution instances
//! - workflow_steps: Individual steps within a run
//! - workflow_logs: Streaming output logs
//! - llm_usage: LLM API usage tracking

const std = @import("std");
const pg = @import("pg");

pub const Pool = pg.Pool;

// =============================================================================
// Types
// =============================================================================

pub const WorkflowDefinition = struct {
    id: i32,
    repository_id: ?i32,
    name: []const u8,
    file_path: []const u8,
    triggers: []const u8, // JSONB as string
    image: ?[]const u8,
    dockerfile: ?[]const u8,
    plan: []const u8, // JSONB as string
    content_hash: []const u8,
    parsed_at: i64, // Unix timestamp (EXTRACT(EPOCH) returns bigint)
};

pub const PromptDefinition = struct {
    id: i32,
    repository_id: ?i32,
    name: []const u8,
    file_path: []const u8,
    client: []const u8,
    prompt_type: []const u8, // "llm" or "agent"
    inputs_schema: []const u8, // JSONB as string
    output_schema: []const u8, // JSONB as string
    tools: ?[]const u8, // JSONB as string or null
    max_turns: ?i32,
    body_template: []const u8,
    content_hash: []const u8,
    parsed_at: i64, // Unix timestamp (EXTRACT(EPOCH) returns bigint)
};

pub const WorkflowRun = struct {
    id: i32,
    workflow_definition_id: ?i32,
    trigger_type: []const u8,
    trigger_payload: []const u8, // JSONB as string
    inputs: ?[]const u8, // JSONB as string or null
    status: []const u8, // pending, running, completed, failed, cancelled
    started_at: ?i64, // Unix timestamp or null (EXTRACT(EPOCH) returns bigint)
    completed_at: ?i64, // Unix timestamp or null (EXTRACT(EPOCH) returns bigint)
    outputs: ?[]const u8, // JSONB as string or null
    error_message: ?[]const u8,
    created_at: i64, // Unix timestamp (EXTRACT(EPOCH) returns bigint)
};

pub const WorkflowStep = struct {
    id: i32,
    run_id: i32,
    step_id: []const u8,
    name: []const u8,
    step_type: []const u8, // shell, llm, agent, parallel
    config: []const u8, // JSONB as string
    status: []const u8, // pending, running, completed, failed
    started_at: ?i64, // Unix timestamp or null (EXTRACT(EPOCH) returns bigint)
    completed_at: ?i64, // Unix timestamp or null (EXTRACT(EPOCH) returns bigint)
    exit_code: ?i32,
    output: ?[]const u8, // JSONB as string or null
    error_message: ?[]const u8,
    turns_used: ?i32, // Agent-specific
    tokens_in: ?i32, // Agent-specific
    tokens_out: ?i32, // Agent-specific
};

pub const WorkflowLog = struct {
    id: i32,
    step_id: i32,
    log_type: []const u8, // stdout, stderr, token, tool_call, tool_result
    content: []const u8,
    sequence: i32,
    created_at: i64, // Unix timestamp (EXTRACT(EPOCH) returns bigint)
};

pub const LlmUsage = struct {
    id: i32,
    step_id: i32,
    prompt_name: ?[]const u8,
    model: []const u8,
    input_tokens: i32,
    output_tokens: i32,
    latency_ms: i32,
    created_at: i64, // Unix timestamp (EXTRACT(EPOCH) returns bigint)
};

// =============================================================================
// Workflow Definition Operations
// =============================================================================

pub fn upsertWorkflowDefinition(
    pool: *Pool,
    repo_id: ?i32,
    name: []const u8,
    file_path: []const u8,
    triggers: []const u8, // JSONB string
    image: ?[]const u8,
    dockerfile: ?[]const u8,
    plan: []const u8, // JSONB string
    content_hash: []const u8,
) !i32 {
    const row = try pool.row(
        \\INSERT INTO workflow_definitions
        \\  (repository_id, name, file_path, triggers, image, dockerfile, plan, content_hash, parsed_at)
        \\VALUES ($1, $2, $3, $4::jsonb, $5, $6, $7::jsonb, $8, NOW())
        \\ON CONFLICT (repository_id, name) DO UPDATE SET
        \\  file_path = $3, triggers = $4::jsonb, image = $5, dockerfile = $6,
        \\  plan = $7::jsonb, content_hash = $8, parsed_at = NOW()
        \\RETURNING id
    , .{ repo_id, name, file_path, triggers, image, dockerfile, plan, content_hash });

    if (row) |r| {
        return r.get(i32, 0);
    }
    return error.UpsertFailed;
}

pub fn getWorkflowDefinition(pool: *Pool, id: i32) !?WorkflowDefinition {
    const row = try pool.row(
        \\SELECT id, repository_id, name, file_path, triggers::text, image, dockerfile,
        \\       plan::text, content_hash, EXTRACT(EPOCH FROM parsed_at)::bigint
        \\FROM workflow_definitions WHERE id = $1
    , .{id});

    if (row) |r| {
        return WorkflowDefinition{
            .id = r.get(i32, 0),
            .repository_id = r.get(?i32, 1),
            .name = r.get([]const u8, 2),
            .file_path = r.get([]const u8, 3),
            .triggers = r.get([]const u8, 4),
            .image = r.get(?[]const u8, 5),
            .dockerfile = r.get(?[]const u8, 6),
            .plan = r.get([]const u8, 7),
            .content_hash = r.get([]const u8, 8),
            .parsed_at = r.get(i64, 9),
        };
    }
    return null;
}

pub fn getWorkflowDefinitionByName(pool: *Pool, repo_id: ?i32, name: []const u8) !?WorkflowDefinition {
    // If repo_id is null, search all repos. Otherwise, search specific repo.
    const row = if (repo_id) |rid|
        try pool.row(
            \\SELECT id, repository_id, name, file_path, triggers::text, image, dockerfile,
            \\       plan::text, content_hash, EXTRACT(EPOCH FROM parsed_at)::bigint
            \\FROM workflow_definitions WHERE repository_id = $1 AND name = $2
        , .{ rid, name })
    else
        try pool.row(
            \\SELECT id, repository_id, name, file_path, triggers::text, image, dockerfile,
            \\       plan::text, content_hash, EXTRACT(EPOCH FROM parsed_at)::bigint
            \\FROM workflow_definitions WHERE name = $1 LIMIT 1
        , .{name});

    if (row) |r| {
        return WorkflowDefinition{
            .id = r.get(i32, 0),
            .repository_id = r.get(?i32, 1),
            .name = r.get([]const u8, 2),
            .file_path = r.get([]const u8, 3),
            .triggers = r.get([]const u8, 4),
            .image = r.get(?[]const u8, 5),
            .dockerfile = r.get(?[]const u8, 6),
            .plan = r.get([]const u8, 7),
            .content_hash = r.get([]const u8, 8),
            .parsed_at = r.get(i64, 9),
        };
    }
    return null;
}

pub fn getWorkflowDefinitionByPath(pool: *Pool, repo_id: ?i32, file_path: []const u8) !?WorkflowDefinition {
    const row = try pool.row(
        \\SELECT id, repository_id, name, file_path, triggers::text, image, dockerfile,
        \\       plan::text, content_hash, EXTRACT(EPOCH FROM parsed_at)::bigint
        \\FROM workflow_definitions WHERE repository_id = $1 AND file_path = $2
    , .{ repo_id, file_path });

    if (row) |r| {
        return WorkflowDefinition{
            .id = r.get(i32, 0),
            .repository_id = r.get(?i32, 1),
            .name = r.get([]const u8, 2),
            .file_path = r.get([]const u8, 3),
            .triggers = r.get([]const u8, 4),
            .image = r.get(?[]const u8, 5),
            .dockerfile = r.get(?[]const u8, 6),
            .plan = r.get([]const u8, 7),
            .content_hash = r.get([]const u8, 8),
            .parsed_at = r.get(i64, 9),
        };
    }
    return null;
}

pub fn listWorkflowDefinitions(pool: *Pool, allocator: std.mem.Allocator, repo_id: ?i32) ![]WorkflowDefinition {
    var conn = try pool.acquire();
    defer conn.release();

    var result = try conn.query(
        \\SELECT id, repository_id, name, file_path, triggers::text, image, dockerfile,
        \\       plan::text, content_hash, EXTRACT(EPOCH FROM parsed_at)::bigint
        \\FROM workflow_definitions WHERE repository_id = $1
        \\ORDER BY name
    , .{repo_id});
    defer result.deinit();

    var defs: std.ArrayList(WorkflowDefinition) = .{};
    while (try result.next()) |row| {
        try defs.append(allocator, WorkflowDefinition{
            .id = row.get(i32, 0),
            .repository_id = row.get(?i32, 1),
            .name = row.get([]const u8, 2),
            .file_path = row.get([]const u8, 3),
            .triggers = row.get([]const u8, 4),
            .image = row.get(?[]const u8, 5),
            .dockerfile = row.get(?[]const u8, 6),
            .plan = row.get([]const u8, 7),
            .content_hash = row.get([]const u8, 8),
            .parsed_at = row.get(i64, 9),
        });
    }

    return try defs.toOwnedSlice(allocator);
}

// =============================================================================
// Prompt Definition Operations
// =============================================================================

pub fn upsertPromptDefinition(
    pool: *Pool,
    repo_id: ?i32,
    name: []const u8,
    file_path: []const u8,
    client: []const u8,
    prompt_type: []const u8,
    inputs_schema: []const u8, // JSONB string
    output_schema: []const u8, // JSONB string
    tools: ?[]const u8, // JSONB string or null
    max_turns: ?i32,
    body_template: []const u8,
    content_hash: []const u8,
) !i32 {
    const row = try pool.row(
        \\INSERT INTO prompt_definitions
        \\  (repository_id, name, file_path, client, prompt_type, inputs_schema, output_schema,
        \\   tools, max_turns, body_template, content_hash, parsed_at)
        \\VALUES ($1, $2, $3, $4, $5, $6::jsonb, $7::jsonb, $8::jsonb, $9, $10, $11, NOW())
        \\ON CONFLICT (repository_id, name) DO UPDATE SET
        \\  file_path = $3, client = $4, prompt_type = $5, inputs_schema = $6::jsonb,
        \\  output_schema = $7::jsonb, tools = $8::jsonb, max_turns = $9,
        \\  body_template = $10, content_hash = $11, parsed_at = NOW()
        \\RETURNING id
    , .{ repo_id, name, file_path, client, prompt_type, inputs_schema, output_schema, tools, max_turns, body_template, content_hash });

    if (row) |r| {
        return r.get(i32, 0);
    }
    return error.UpsertFailed;
}

pub fn getPromptDefinition(pool: *Pool, id: i32) !?PromptDefinition {
    const row = try pool.row(
        \\SELECT id, repository_id, name, file_path, client, prompt_type,
        \\       inputs_schema::text, output_schema::text, tools::text, max_turns,
        \\       body_template, content_hash, EXTRACT(EPOCH FROM parsed_at)::bigint
        \\FROM prompt_definitions WHERE id = $1
    , .{id});

    if (row) |r| {
        return PromptDefinition{
            .id = r.get(i32, 0),
            .repository_id = r.get(?i32, 1),
            .name = r.get([]const u8, 2),
            .file_path = r.get([]const u8, 3),
            .client = r.get([]const u8, 4),
            .prompt_type = r.get([]const u8, 5),
            .inputs_schema = r.get([]const u8, 6),
            .output_schema = r.get([]const u8, 7),
            .tools = r.get(?[]const u8, 8),
            .max_turns = r.get(?i32, 9),
            .body_template = r.get([]const u8, 10),
            .content_hash = r.get([]const u8, 11),
            .parsed_at = r.get(i64, 12),
        };
    }
    return null;
}

pub fn getPromptDefinitionByName(pool: *Pool, repo_id: ?i32, name: []const u8) !?PromptDefinition {
    const row = try pool.row(
        \\SELECT id, repository_id, name, file_path, client, prompt_type,
        \\       inputs_schema::text, output_schema::text, tools::text, max_turns,
        \\       body_template, content_hash, EXTRACT(EPOCH FROM parsed_at)::bigint
        \\FROM prompt_definitions WHERE repository_id = $1 AND name = $2
    , .{ repo_id, name });

    if (row) |r| {
        return PromptDefinition{
            .id = r.get(i32, 0),
            .repository_id = r.get(?i32, 1),
            .name = r.get([]const u8, 2),
            .file_path = r.get([]const u8, 3),
            .client = r.get([]const u8, 4),
            .prompt_type = r.get([]const u8, 5),
            .inputs_schema = r.get([]const u8, 6),
            .output_schema = r.get([]const u8, 7),
            .tools = r.get(?[]const u8, 8),
            .max_turns = r.get(?i32, 9),
            .body_template = r.get([]const u8, 10),
            .content_hash = r.get([]const u8, 11),
            .parsed_at = r.get(i64, 12),
        };
    }
    return null;
}

pub fn getPromptDefinitionByPath(pool: *Pool, repo_id: ?i32, file_path: []const u8) !?PromptDefinition {
    const row = try pool.row(
        \\SELECT id, repository_id, name, file_path, client, prompt_type,
        \\       inputs_schema::text, output_schema::text, tools::text, max_turns,
        \\       body_template, content_hash, EXTRACT(EPOCH FROM parsed_at)::bigint
        \\FROM prompt_definitions WHERE repository_id = $1 AND file_path = $2
    , .{ repo_id, file_path });

    if (row) |r| {
        return PromptDefinition{
            .id = r.get(i32, 0),
            .repository_id = r.get(?i32, 1),
            .name = r.get([]const u8, 2),
            .file_path = r.get([]const u8, 3),
            .client = r.get([]const u8, 4),
            .prompt_type = r.get([]const u8, 5),
            .inputs_schema = r.get([]const u8, 6),
            .output_schema = r.get([]const u8, 7),
            .tools = r.get(?[]const u8, 8),
            .max_turns = r.get(?i32, 9),
            .body_template = r.get([]const u8, 10),
            .content_hash = r.get([]const u8, 11),
            .parsed_at = r.get(i64, 12),
        };
    }
    return null;
}

// =============================================================================
// Workflow Run Operations
// =============================================================================

pub fn createWorkflowRun(
    pool: *Pool,
    workflow_definition_id: ?i32,
    trigger_type: []const u8,
    trigger_payload: []const u8, // JSONB string
    inputs: ?[]const u8, // JSONB string or null
) !i32 {
    const row = try pool.row(
        \\INSERT INTO workflow_runs
        \\  (workflow_definition_id, trigger_type, trigger_payload, inputs, status, created_at)
        \\VALUES ($1, $2, $3::jsonb, $4::jsonb, 'pending', NOW())
        \\RETURNING id
    , .{ workflow_definition_id, trigger_type, trigger_payload, inputs });

    if (row) |r| {
        return r.get(i32, 0);
    }
    return error.InsertFailed;
}

pub fn getWorkflowRun(pool: *Pool, id: i32) !?WorkflowRun {
    const row = try pool.row(
        \\SELECT id, workflow_definition_id, trigger_type, trigger_payload::text,
        \\       inputs::text, status,
        \\       EXTRACT(EPOCH FROM started_at)::bigint,
        \\       EXTRACT(EPOCH FROM completed_at)::bigint,
        \\       outputs::text, error_message, EXTRACT(EPOCH FROM created_at)::bigint
        \\FROM workflow_runs WHERE id = $1
    , .{id});

    if (row) |r| {
        return WorkflowRun{
            .id = r.get(i32, 0),
            .workflow_definition_id = r.get(?i32, 1),
            .trigger_type = r.get([]const u8, 2),
            .trigger_payload = r.get([]const u8, 3),
            .inputs = r.get(?[]const u8, 4),
            .status = r.get([]const u8, 5),
            .started_at = r.get(?i64, 6),
            .completed_at = r.get(?i64, 7),
            .outputs = r.get(?[]const u8, 8),
            .error_message = r.get(?[]const u8, 9),
            .created_at = r.get(i64, 10),
        };
    }
    return null;
}

pub fn updateWorkflowRunStatus(pool: *Pool, id: i32, status: []const u8) !void {
    if (std.mem.eql(u8, status, "running")) {
        _ = try pool.exec(
            \\UPDATE workflow_runs SET status = $2, started_at = NOW() WHERE id = $1
        , .{ id, status });
    } else if (std.mem.eql(u8, status, "completed") or std.mem.eql(u8, status, "failed") or std.mem.eql(u8, status, "cancelled")) {
        _ = try pool.exec(
            \\UPDATE workflow_runs SET status = $2, completed_at = NOW() WHERE id = $1
        , .{ id, status });
    } else {
        _ = try pool.exec(
            \\UPDATE workflow_runs SET status = $2 WHERE id = $1
        , .{ id, status });
    }
}

pub fn completeWorkflowRun(pool: *Pool, id: i32, outputs: ?[]const u8, error_message: ?[]const u8) !void {
    const status = if (error_message != null) "failed" else "completed";
    _ = try pool.exec(
        \\UPDATE workflow_runs
        \\SET status = $2, outputs = $3::jsonb, error_message = $4, completed_at = NOW()
        \\WHERE id = $1
    , .{ id, status, outputs, error_message });
}

pub fn listWorkflowRuns(pool: *Pool, allocator: std.mem.Allocator, workflow_definition_id: ?i32, limit: i32) ![]WorkflowRun {
    var conn = try pool.acquire();
    defer conn.release();

    var result = try conn.query(
        \\SELECT id, workflow_definition_id, trigger_type, trigger_payload::text,
        \\       inputs::text, status,
        \\       EXTRACT(EPOCH FROM started_at)::bigint,
        \\       EXTRACT(EPOCH FROM completed_at)::bigint,
        \\       outputs::text, error_message, EXTRACT(EPOCH FROM created_at)::bigint
        \\FROM workflow_runs
        \\WHERE ($1::bigint IS NULL OR workflow_definition_id = $1)
        \\ORDER BY created_at DESC LIMIT $2
    , .{ workflow_definition_id, limit });
    defer result.deinit();

    var runs: std.ArrayList(WorkflowRun) = .{};
    while (try result.next()) |row| {
        try runs.append(allocator, WorkflowRun{
            .id = row.get(i32, 0),
            .workflow_definition_id = row.get(?i32, 1),
            .trigger_type = row.get([]const u8, 2),
            .trigger_payload = row.get([]const u8, 3),
            .inputs = row.get(?[]const u8, 4),
            .status = row.get([]const u8, 5),
            .started_at = row.get(?i64, 6),
            .completed_at = row.get(?i64, 7),
            .outputs = row.get(?[]const u8, 8),
            .error_message = row.get(?[]const u8, 9),
            .created_at = row.get(i64, 10),
        });
    }

    return try runs.toOwnedSlice(allocator);
}

// =============================================================================
// Workflow Step Operations
// =============================================================================

pub fn createWorkflowStep(
    pool: *Pool,
    run_id: i32,
    step_id: []const u8,
    name: []const u8,
    step_type: []const u8,
    config: []const u8, // JSONB string
) !i32 {
    const row = try pool.row(
        \\INSERT INTO workflow_steps
        \\  (run_id, step_id, name, step_type, config, status)
        \\VALUES ($1, $2, $3, $4, $5::jsonb, 'pending')
        \\RETURNING id
    , .{ run_id, step_id, name, step_type, config });

    if (row) |r| {
        return r.get(i32, 0);
    }
    return error.InsertFailed;
}

pub fn getWorkflowStep(pool: *Pool, id: i32) !?WorkflowStep {
    const row = try pool.row(
        \\SELECT id, run_id, step_id, name, step_type, config::text, status,
        \\       EXTRACT(EPOCH FROM started_at)::bigint,
        \\       EXTRACT(EPOCH FROM completed_at)::bigint,
        \\       exit_code, output::text, error_message,
        \\       turns_used, tokens_in, tokens_out
        \\FROM workflow_steps WHERE id = $1
    , .{id});

    if (row) |r| {
        return WorkflowStep{
            .id = r.get(i32, 0),
            .run_id = r.get(i32, 1),
            .step_id = r.get([]const u8, 2),
            .name = r.get([]const u8, 3),
            .step_type = r.get([]const u8, 4),
            .config = r.get([]const u8, 5),
            .status = r.get([]const u8, 6),
            .started_at = r.get(?i64, 7),
            .completed_at = r.get(?i64, 8),
            .exit_code = r.get(?i32, 9),
            .output = r.get(?[]const u8, 10),
            .error_message = r.get(?[]const u8, 11),
            .turns_used = r.get(?i32, 12),
            .tokens_in = r.get(?i32, 13),
            .tokens_out = r.get(?i32, 14),
        };
    }
    return null;
}

pub fn updateWorkflowStepStatus(pool: *Pool, id: i32, status: []const u8) !void {
    if (std.mem.eql(u8, status, "running")) {
        _ = try pool.exec(
            \\UPDATE workflow_steps SET status = $2, started_at = NOW() WHERE id = $1
        , .{ id, status });
    } else if (std.mem.eql(u8, status, "completed") or std.mem.eql(u8, status, "failed")) {
        _ = try pool.exec(
            \\UPDATE workflow_steps SET status = $2, completed_at = NOW() WHERE id = $1
        , .{ id, status });
    } else {
        _ = try pool.exec(
            \\UPDATE workflow_steps SET status = $2 WHERE id = $1
        , .{ id, status });
    }
}

pub fn completeWorkflowStep(
    pool: *Pool,
    id: i64,
    exit_code: ?i32,
    output: ?[]const u8, // JSONB string or null
    error_message: ?[]const u8,
    turns_used: ?i32,
    tokens_in: ?i32,
    tokens_out: ?i32,
) !void {
    const status = if (error_message != null or (exit_code != null and exit_code.? != 0)) "failed" else "completed";
    _ = try pool.exec(
        \\UPDATE workflow_steps
        \\SET status = $2, exit_code = $3, output = $4::jsonb, error_message = $5,
        \\    turns_used = $6, tokens_in = $7, tokens_out = $8, completed_at = NOW()
        \\WHERE id = $1
    , .{ id, status, exit_code, output, error_message, turns_used, tokens_in, tokens_out });
}

pub fn listWorkflowSteps(pool: *Pool, allocator: std.mem.Allocator, run_id: i32) ![]WorkflowStep {
    var conn = try pool.acquire();
    defer conn.release();

    var result = try conn.query(
        \\SELECT id, run_id, step_id, name, step_type, config::text, status,
        \\       EXTRACT(EPOCH FROM started_at)::bigint,
        \\       EXTRACT(EPOCH FROM completed_at)::bigint,
        \\       exit_code, output::text, error_message,
        \\       turns_used, tokens_in, tokens_out
        \\FROM workflow_steps WHERE run_id = $1
        \\ORDER BY id
    , .{run_id});
    defer result.deinit();

    var steps: std.ArrayList(WorkflowStep) = .{};
    while (try result.next()) |row| {
        try steps.append(allocator, WorkflowStep{
            .id = row.get(i32, 0),
            .run_id = row.get(i32, 1),
            .step_id = row.get([]const u8, 2),
            .name = row.get([]const u8, 3),
            .step_type = row.get([]const u8, 4),
            .config = row.get([]const u8, 5),
            .status = row.get([]const u8, 6),
            .started_at = row.get(?i64, 7),
            .completed_at = row.get(?i64, 8),
            .exit_code = row.get(?i32, 9),
            .output = row.get(?[]const u8, 10),
            .error_message = row.get(?[]const u8, 11),
            .turns_used = row.get(?i32, 12),
            .tokens_in = row.get(?i32, 13),
            .tokens_out = row.get(?i32, 14),
        });
    }

    return try steps.toOwnedSlice(allocator);
}

// =============================================================================
// Workflow Log Operations
// =============================================================================

pub fn appendWorkflowLog(
    pool: *Pool,
    step_id: i32,
    log_type: []const u8,
    content: []const u8,
    sequence: i32,
) !i32 {
    const row = try pool.row(
        \\INSERT INTO workflow_logs (step_id, log_type, content, sequence, created_at)
        \\VALUES ($1, $2, $3, $4, NOW())
        \\RETURNING id
    , .{ step_id, log_type, content, sequence });

    if (row) |r| {
        return r.get(i32, 0);
    }
    return error.InsertFailed;
}

pub fn listWorkflowLogs(pool: *Pool, allocator: std.mem.Allocator, step_id: i32) ![]WorkflowLog {
    var conn = try pool.acquire();
    defer conn.release();

    var result = try conn.query(
        \\SELECT id, step_id, log_type, content, sequence, EXTRACT(EPOCH FROM created_at)::bigint
        \\FROM workflow_logs WHERE step_id = $1
        \\ORDER BY sequence
    , .{step_id});
    defer result.deinit();

    var logs: std.ArrayList(WorkflowLog) = .{};
    while (try result.next()) |row| {
        try logs.append(allocator, WorkflowLog{
            .id = row.get(i32, 0),
            .step_id = row.get(i32, 1),
            .log_type = row.get([]const u8, 2),
            .content = row.get([]const u8, 3),
            .sequence = row.get(i32, 4),
            .created_at = row.get(i64, 5),
        });
    }

    return try logs.toOwnedSlice(allocator);
}

// =============================================================================
// LLM Usage Operations
// =============================================================================

pub fn recordLlmUsage(
    pool: *Pool,
    step_id: i32,
    prompt_name: ?[]const u8,
    model: []const u8,
    input_tokens: i32,
    output_tokens: i32,
    latency_ms: i32,
) !i32 {
    const row = try pool.row(
        \\INSERT INTO llm_usage
        \\  (step_id, prompt_name, model, input_tokens, output_tokens, latency_ms, created_at)
        \\VALUES ($1, $2, $3, $4, $5, $6, NOW())
        \\RETURNING id
    , .{ step_id, prompt_name, model, input_tokens, output_tokens, latency_ms });

    if (row) |r| {
        return r.get(i32, 0);
    }
    return error.InsertFailed;
}

pub fn getLlmUsageForStep(pool: *Pool, allocator: std.mem.Allocator, step_id: i32) ![]LlmUsage {
    var conn = try pool.acquire();
    defer conn.release();

    var result = try conn.query(
        \\SELECT id, step_id, prompt_name, model, input_tokens, output_tokens,
        \\       latency_ms, EXTRACT(EPOCH FROM created_at)::bigint
        \\FROM llm_usage WHERE step_id = $1
        \\ORDER BY created_at
    , .{step_id});
    defer result.deinit();

    var usage: std.ArrayList(LlmUsage) = .{};
    while (try result.next()) |row| {
        try usage.append(allocator, LlmUsage{
            .id = row.get(i32, 0),
            .step_id = row.get(i32, 1),
            .prompt_name = row.get(?[]const u8, 2),
            .model = row.get([]const u8, 3),
            .input_tokens = row.get(i32, 4),
            .output_tokens = row.get(i32, 5),
            .latency_ms = row.get(i32, 6),
            .created_at = row.get(i64, 7),
        });
    }

    return try usage.toOwnedSlice(allocator);
}

// =============================================================================
// Runner Pool Operations
// =============================================================================

pub const RunnerPoolEntry = struct {
    id: i32,
    pod_name: []const u8,
    pod_ip: []const u8,
    node_name: ?[]const u8,
    status: []const u8, // available, claimed, terminated
    registered_at: i64, // Unix timestamp
    last_heartbeat: i64, // Unix timestamp
    claimed_at: ?i64, // Unix timestamp or null
    claimed_by_task_id: ?i32,
};

/// Register a new runner in the pool
pub fn registerRunner(
    pool: *Pool,
    pod_name: []const u8,
    pod_ip: []const u8,
    node_name: ?[]const u8,
) !i32 {
    const row = try pool.row(
        \\INSERT INTO runner_pool (pod_name, pod_ip, node_name, status, registered_at, last_heartbeat)
        \\VALUES ($1, $2, $3, 'available', NOW(), NOW())
        \\ON CONFLICT (pod_name) DO UPDATE SET
        \\  pod_ip = $2, node_name = $3, status = 'available',
        \\  registered_at = NOW(), last_heartbeat = NOW(),
        \\  claimed_at = NULL, claimed_by_task_id = NULL
        \\RETURNING id
    , .{ pod_name, pod_ip, node_name });

    if (row) |r| {
        return r.get(i32, 0);
    }
    return error.RegisterFailed;
}

/// Update runner heartbeat timestamp
pub fn updateRunnerHeartbeat(
    pool: *Pool,
    runner_id: i32,
) !void {
    const affected = try pool.exec(
        \\UPDATE runner_pool
        \\SET last_heartbeat = NOW()
        \\WHERE id = $1 AND status != 'terminated'
    , .{runner_id});

    if (affected == 0) {
        return error.RunnerNotFound;
    }
}

/// Claim an available runner atomically for a task
/// Returns runner_id if successful, null if no runners available
pub fn claimAvailableRunner(
    pool: *Pool,
    task_id: i32,
) !?i32 {
    // Use SELECT FOR UPDATE SKIP LOCKED for atomic claiming
    const row = try pool.row(
        \\WITH available_runner AS (
        \\  SELECT id FROM runner_pool
        \\  WHERE status = 'available'
        \\    AND last_heartbeat > NOW() - INTERVAL '30 seconds'
        \\  ORDER BY registered_at
        \\  FOR UPDATE SKIP LOCKED
        \\  LIMIT 1
        \\)
        \\UPDATE runner_pool r
        \\SET status = 'claimed',
        \\    claimed_at = NOW(),
        \\    claimed_by_task_id = $1
        \\FROM available_runner a
        \\WHERE r.id = a.id
        \\RETURNING r.id
    , .{task_id});

    if (row) |r| {
        return r.get(i32, 0);
    }
    return null; // No available runners
}

/// Release a runner back to the available pool
pub fn releaseRunner(
    pool: *Pool,
    runner_id: i32,
) !void {
    const affected = try pool.exec(
        \\UPDATE runner_pool
        \\SET status = 'available',
        \\    claimed_at = NULL,
        \\    claimed_by_task_id = NULL,
        \\    last_heartbeat = NOW()
        \\WHERE id = $1
    , .{runner_id});

    if (affected == 0) {
        return error.RunnerNotFound;
    }
}

/// Mark a runner as terminated (removed from pool)
pub fn terminateRunner(
    pool: *Pool,
    runner_id: i32,
) !void {
    _ = try pool.exec(
        \\UPDATE runner_pool
        \\SET status = 'terminated'
        \\WHERE id = $1
    , .{runner_id});
}

/// Get runner by ID
pub fn getRunner(pool: *Pool, runner_id: i32) !?RunnerPoolEntry {
    const row = try pool.row(
        \\SELECT id, pod_name, pod_ip, node_name, status,
        \\       EXTRACT(EPOCH FROM registered_at)::bigint,
        \\       EXTRACT(EPOCH FROM last_heartbeat)::bigint,
        \\       EXTRACT(EPOCH FROM claimed_at)::bigint,
        \\       claimed_by_task_id
        \\FROM runner_pool WHERE id = $1
    , .{runner_id});

    if (row) |r| {
        return RunnerPoolEntry{
            .id = r.get(i32, 0),
            .pod_name = r.get([]const u8, 1),
            .pod_ip = r.get([]const u8, 2),
            .node_name = r.get(?[]const u8, 3),
            .status = r.get([]const u8, 4),
            .registered_at = r.get(i64, 5),
            .last_heartbeat = r.get(i64, 6),
            .claimed_at = r.get(?i64, 7),
            .claimed_by_task_id = r.get(?i32, 8),
        };
    }
    return null;
}

/// List all runners with optional status filter
pub fn listRunners(
    pool: *Pool,
    allocator: std.mem.Allocator,
    status_filter: ?[]const u8,
) ![]RunnerPoolEntry {
    const query = if (status_filter) |_|
        \\SELECT id, pod_name, pod_ip, node_name, status,
        \\       EXTRACT(EPOCH FROM registered_at)::bigint,
        \\       EXTRACT(EPOCH FROM last_heartbeat)::bigint,
        \\       EXTRACT(EPOCH FROM claimed_at)::bigint,
        \\       claimed_by_task_id
        \\FROM runner_pool
        \\WHERE status = $1
        \\ORDER BY registered_at
    else
        \\SELECT id, pod_name, pod_ip, node_name, status,
        \\       EXTRACT(EPOCH FROM registered_at)::bigint,
        \\       EXTRACT(EPOCH FROM last_heartbeat)::bigint,
        \\       EXTRACT(EPOCH FROM claimed_at)::bigint,
        \\       claimed_by_task_id
        \\FROM runner_pool
        \\ORDER BY registered_at
    ;

    const result = if (status_filter) |status|
        try pool.query(query, .{status})
    else
        try pool.query(query, .{});
    defer result.deinit();

    var runners: std.ArrayList(RunnerPoolEntry) = .{};
    while (try result.next()) |row| {
        try runners.append(allocator, RunnerPoolEntry{
            .id = row.get(i32, 0),
            .pod_name = row.get([]const u8, 1),
            .pod_ip = row.get([]const u8, 2),
            .node_name = row.get(?[]const u8, 3),
            .status = row.get([]const u8, 4),
            .registered_at = row.get(i64, 5),
            .last_heartbeat = row.get(i64, 6),
            .claimed_at = row.get(?i64, 7),
            .claimed_by_task_id = row.get(?i32, 8),
        });
    }

    return try runners.toOwnedSlice(allocator);
}

/// Count available runners (healthy and unclaimed)
pub fn countAvailableRunners(pool: *Pool) !i32 {
    const row = try pool.row(
        \\SELECT COUNT(*)::int
        \\FROM runner_pool
        \\WHERE status = 'available'
        \\  AND last_heartbeat > NOW() - INTERVAL '30 seconds'
    , .{});

    if (row) |r| {
        return r.get(i32, 0);
    }
    return 0;
}

/// Clean up stale runners (no heartbeat for > 60 seconds)
pub fn cleanupStaleRunners(pool: *Pool) !i32 {
    return @intCast(try pool.exec(
        \\UPDATE runner_pool
        \\SET status = 'terminated'
        \\WHERE status != 'terminated'
        \\  AND last_heartbeat < NOW() - INTERVAL '60 seconds'
    , .{}));
}
