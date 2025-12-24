//! Workflow API Routes (Phase 09)
//!
//! Implements the workflow management API from docs/workflows-engineering.md:
//! - POST   /api/workflows/parse           # Parse .py file, return plan
//! - POST   /api/workflows/run             # Trigger workflow run
//! - GET    /api/workflows/runs            # List runs
//! - GET    /api/workflows/runs/:id        # Get run details
//! - GET    /api/workflows/runs/:id/stream # SSE stream for live run
//! - POST   /api/workflows/runs/:id/cancel # Cancel run

const std = @import("std");
const httpz = @import("httpz");
const Context = @import("../main.zig").Context;
const db = @import("db");
const workflows = @import("../workflows/mod.zig");
const queue = @import("../dispatch/queue.zig");

const log = std.log.scoped(.workflow_api);

// ============================================================================
// Request/Response Types
// ============================================================================

const ParseWorkflowRequest = struct {
    source: []const u8, // Python workflow source code
    file_path: ?[]const u8 = null, // Optional file path for error messages
};

const ParseWorkflowResponse = struct {
    plan: std.json.Value, // JSON representation of WorkflowDefinition
    errors: []const []const u8 = &[_][]const u8{},
};

const RunWorkflowRequest = struct {
    workflow_name: []const u8, // Name of workflow to run
    trigger_type: []const u8, // "push", "pull_request", "manual", etc.
    trigger_payload: std.json.Value, // Event data
    inputs: ?std.json.Value = null, // Manual trigger inputs
};

const RunWorkflowResponse = struct {
    run_id: i32,
};

// ============================================================================
// POST /api/workflows/parse
// ============================================================================

/// Parse a workflow .py file and return the generated plan
pub fn parse(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Parse request body
    const body = req.body() orelse {
        res.status = 400;
        try res.json(.{ .@"error" = "Missing request body" }, .{});
        return;
    };

    const parsed = std.json.parseFromSlice(
        ParseWorkflowRequest,
        ctx.allocator,
        body,
        .{},
    ) catch {
        res.status = 400;
        try res.json(.{ .@"error" = "Invalid JSON" }, .{});
        return;
    };
    defer parsed.deinit();

    const request = parsed.value;

    // Create evaluator
    var evaluator = workflows.Evaluator.init(ctx.allocator);

    // Evaluate source
    const plan_set = evaluator.evaluateSource(request.source, "<inline>") catch |err| {
        res.status = 400;
        const err_msg = @errorName(err);
        try res.json(.{ .@"error" = err_msg }, .{});
        return;
    };

    // Get first workflow (evaluator can return multiple workflows from one file)
    if (plan_set.workflows.len == 0) {
        res.status = 400;
        try res.json(.{ .@"error" = "No workflows found in source" }, .{});
        return;
    }

    const workflow_def = plan_set.workflows[0];

    // Validate plan
    var validation_result = try workflows.validateWorkflow(ctx.allocator, &workflow_def);
    defer validation_result.deinit();

    if (!validation_result.valid) {
        // Return validation errors
        res.status = 400;
        try res.json(.{
            .@"error" = "Workflow validation failed",
            .errors = validation_result.errors,
        }, .{});
        return;
    }

    // Return simplified workflow info
    // TODO: Full JSON serialization requires manual construction or alternative approach
    // See Phase 09 memories for details on Zig 0.15 JSON serialization limitations
    try res.json(.{
        .name = workflow_def.name,
        .step_count = workflow_def.steps.len,
        .trigger_count = workflow_def.triggers.len,
        .valid = true,
    }, .{});
}

// ============================================================================
// POST /api/workflows/run
// ============================================================================

/// Trigger a workflow run
pub fn runWorkflow(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // TODO: Re-enable authentication after Phase 10 testing
    // Require authentication
    // if (ctx.user == null) {
    //     res.status = 401;
    //     try res.json(.{ .@"error" = "Authentication required" }, .{});
    //     return;
    // }

    // Parse request body
    const body = req.body() orelse {
        res.status = 400;
        try res.json(.{ .@"error" = "Missing request body" }, .{});
        return;
    };

    const parsed = std.json.parseFromSlice(
        RunWorkflowRequest,
        ctx.allocator,
        body,
        .{},
    ) catch {
        res.status = 400;
        try res.json(.{ .@"error" = "Invalid JSON" }, .{});
        return;
    };
    defer parsed.deinit();

    const request = parsed.value;

    log.info("DEBUG: Step 1 - Starting workflow execution", .{});

    // Get workflow definition from database
    // TODO: Get repo_id from request or context
    const repo_id: ?i32 = null; // For now, search all repos
    log.info("DEBUG: Step 2 - About to call getWorkflowDefinitionByName", .{});
    const workflow_def_opt = db.workflows.getWorkflowDefinitionByName(
        ctx.pool,
        repo_id,
        request.workflow_name,
    ) catch |err| {
        log.err("Failed to get workflow definition: {}", .{err});
        res.status = 500;
        try res.json(.{ .@"error" = "Database error" }, .{});
        return;
    };

    log.info("DEBUG: Step 3 - Got workflow definition", .{});

    const workflow_def = workflow_def_opt orelse {
        res.status = 404;
        try res.json(.{ .@"error" = "Workflow not found" }, .{});
        return;
    };
    // NOTE: workflow_def strings are owned by pg library Row object, not us.
    // Do NOT free them here - they're freed when the Row is freed after this function returns.

    log.info("DEBUG: Step 4 - workflow_def.id={d} (type=i32)", .{workflow_def.id});

    // Create workflow_run record
    log.info("DEBUG: Step 5 - About to call createWorkflowRun with id={d}", .{workflow_def.id});
    const run_id = db.workflows.createWorkflowRun(
        ctx.pool,
        workflow_def.id,
        request.trigger_type,
        "{}", // trigger_payload (empty for manual runs)
        null, // inputs
    ) catch |err| {
        log.err("Failed to create workflow run: {}", .{err});
        res.status = 500;
        try res.json(.{ .@"error" = "Failed to create run" }, .{});
        return;
    };

    log.info("DEBUG: Step 6 - Created workflow run, run_id={d} (type=i32)", .{run_id});

    // Submit to queue for execution
    log.info("DEBUG: Step 7 - About to call submitWorkload with run_id={d}", .{run_id});
    const task_id = queue.submitWorkload(
        ctx.allocator,
        ctx.pool,
        .{
            .type = .workflow,
            .workflow_run_id = run_id,
            .session_id = null,
            .priority = .normal,
            .config_json = null, // TODO: Serialize workflow plan as JSON
        },
    ) catch |err| {
        log.err("Failed to submit workload: {}", .{err});
        res.status = 500;
        try res.json(.{ .@"error" = "Failed to queue workflow" }, .{});
        return;
    };

    log.info("DEBUG: Step 8 - Submitted workload, task_id={d}", .{task_id});

    log.info("Workflow run created: run_id={d}, task_id={d}", .{ run_id, task_id });

    res.status = 201;
    try res.json(.{
        .run_id = run_id,
        .task_id = task_id,
        .status = "queued",
    }, .{});
}

// ============================================================================
// GET /api/workflows/runs
// ============================================================================

/// List workflow runs (optionally filtered by status, repo, etc.)
pub fn listRuns(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Parse query parameters
    const query = req.url.query;

    // Extract status filter
    var status_str: ?[]const u8 = null;
    if (std.mem.indexOf(u8, query, "status=")) |idx| {
        const start = idx + 7;
        const end = std.mem.indexOfPos(u8, query, start, "&") orelse query.len;
        status_str = query[start..end];
    }

    // Extract pagination
    var page_str: []const u8 = "1";
    var per_page_str: []const u8 = "20";

    if (std.mem.indexOf(u8, query, "page=")) |idx| {
        const start = idx + 5;
        const end = std.mem.indexOfPos(u8, query, start, "&") orelse query.len;
        page_str = query[start..end];
    }

    if (std.mem.indexOf(u8, query, "per_page=")) |idx| {
        const start = idx + 9;
        const end = std.mem.indexOfPos(u8, query, start, "&") orelse query.len;
        per_page_str = query[start..end];
    }

    // TODO: implement pagination
    _ = std.fmt.parseInt(i32, page_str, 10) catch 1;
    const per_page = std.fmt.parseInt(i32, per_page_str, 10) catch 20;

    // Get runs from database using new workflow_runs table
    const runs = try db.workflows.listWorkflowRuns(
        ctx.pool,
        ctx.allocator,
        null, // workflow_definition_id filter
        per_page,
    );
    defer ctx.allocator.free(runs);

    // Build response - for now return runs with basic info
    // Full serialization of runs array will be implemented in Phase 14 (UI)
    try res.json(.{
        .runs = runs,
        .count = runs.len,
        .per_page = per_page,
    }, .{});
}

// ============================================================================
// GET /api/workflows/runs/:id
// ============================================================================

/// Get details for a specific workflow run
pub fn getRun(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Extract run ID from path
    const run_id_str = req.param("id") orelse {
        res.status = 400;
        try res.json(.{ .@"error" = "Missing run ID" }, .{});
        return;
    };

    const run_id = std.fmt.parseInt(i32, run_id_str, 10) catch {
        res.status = 400;
        try res.json(.{ .@"error" = "Invalid run ID" }, .{});
        return;
    };

    // Get run from database
    const workflow_run = try db.workflows.getWorkflowRun(ctx.pool, run_id);
    if (workflow_run == null) {
        res.status = 404;
        try res.json(.{ .@"error" = "Workflow run not found" }, .{});
        return;
    }

    // Get steps for this run
    const steps = try db.workflows.listWorkflowSteps(ctx.pool, ctx.allocator, run_id);
    defer ctx.allocator.free(steps);

    // Build response with run + steps
    try res.json(.{
        .run = workflow_run.?,
        .steps = steps,
    }, .{});
}

// ============================================================================
// GET /api/workflows/runs/:id/stream
// ============================================================================

/// SSE stream for live workflow run updates
pub fn streamRun(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    // Extract run ID
    const run_id_str = req.param("id") orelse {
        res.status = 400;
        res.content_type = .JSON;
        try res.json(.{ .@"error" = "Missing run ID" }, .{});
        return;
    };

    const run_id = std.fmt.parseInt(i32, run_id_str, 10) catch {
        res.status = 400;
        res.content_type = .JSON;
        try res.json(.{ .@"error" = "Invalid run ID" }, .{});
        return;
    };

    // Check if run exists
    const workflow_run = try db.workflows.getWorkflowRun(ctx.pool, run_id);
    if (workflow_run == null) {
        res.status = 404;
        res.content_type = .JSON;
        try res.json(.{ .@"error" = "Workflow run not found" }, .{});
        return;
    }

    // Set up SSE headers
    res.headers.add("Content-Type", "text/event-stream");
    res.headers.add("Cache-Control", "no-cache");
    res.headers.add("Connection", "keep-alive");
    res.headers.add("X-Accel-Buffering", "no"); // Disable nginx buffering

    const writer = res.writer();

    // Send connected event
    try writer.writeAll("data: {\"type\":\"connected\",\"run_id\":");
    try writer.print("{d}", .{run_id});
    try writer.writeAll("}\n\n");

    // For Phase 10 (local development), implement simple polling-based streaming
    // In production (Phase 15), this would use an event bus for real-time updates
    var is_complete = false;

    while (!is_complete) {
        // Check run status
        const run = try db.workflows.getWorkflowRun(ctx.pool, run_id);
        if (run) |r| {
            const status = r.status;
            if (std.mem.eql(u8, status, "completed") or
                std.mem.eql(u8, status, "failed") or
                std.mem.eql(u8, status, "cancelled")) {
                is_complete = true;
            }
        }

        // Get workflow steps
        const steps = try db.workflows.listWorkflowSteps(ctx.pool, ctx.allocator, run_id);
        defer ctx.allocator.free(steps);

        for (steps) |step| {
            // Send step status update
            try writer.writeAll("data: {\"type\":\"step_status\",\"step_id\":\"");
            try writer.writeAll(step.step_id);
            try writer.writeAll("\",\"status\":\"");
            try writer.writeAll(step.status);
            try writer.writeAll("\"}\n\n");

            // Get logs for this step (simplified - would need proper log tracking)
            if (step.output) |output| {
                try writer.writeAll("data: {\"type\":\"step_output\",\"step_id\":\"");
                try writer.writeAll(step.step_id);
                try writer.writeAll("\",\"output\":");
                try writer.writeAll(output);
                try writer.writeAll("}\n\n");
            }
        }

        if (is_complete) {
            // Send completion event
            if (run) |r| {
                try writer.writeAll("data: {\"type\":\"completed\",\"status\":\"");
                try writer.writeAll(r.status);
                try writer.writeAll("\"}\n\n");
            }
            break;
        }

        // Sleep briefly before next poll (100ms)
        std.Thread.sleep(100 * std.time.ns_per_ms);
    }
}

// ============================================================================
// POST /api/workflows/runs/:id/cancel
// ============================================================================

/// Cancel a running workflow
pub fn cancelRun(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;

    // Require authentication
    if (ctx.user == null) {
        res.status = 401;
        try res.json(.{ .@"error" = "Authentication required" }, .{});
        return;
    }

    // Extract run ID
    const run_id_str = req.param("id") orelse {
        res.status = 400;
        try res.json(.{ .@"error" = "Missing run ID" }, .{});
        return;
    };

    const run_id = std.fmt.parseInt(i32, run_id_str, 10) catch {
        res.status = 400;
        try res.json(.{ .@"error" = "Invalid run ID" }, .{});
        return;
    };

    // Get run to check status
    const workflow_run = try db.workflows.getWorkflowRun(ctx.pool, run_id);
    if (workflow_run == null) {
        res.status = 404;
        try res.json(.{ .@"error" = "Workflow run not found" }, .{});
        return;
    }

    // Check if cancellable (running or pending)
    const current_status = workflow_run.?.status;
    if (!std.mem.eql(u8, current_status, "running") and !std.mem.eql(u8, current_status, "pending")) {
        res.status = 400;
        try res.json(.{ .@"error" = "Workflow is not running" }, .{});
        return;
    }

    // Update status to cancelled
    try db.workflows.updateWorkflowRunStatus(ctx.pool, run_id, "cancelled");

    // TODO: Signal runner to stop execution

    try res.json(.{ .ok = true }, .{});
}
