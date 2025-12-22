//! Event Trigger System
//!
//! Processes events and matches them to workflow definitions.
//! Supports both traditional CI events (push, PR) and agent events (chat, mention).

const std = @import("std");
const db = @import("../lib/db.zig");
const queue = @import("queue.zig");

const log = std.log.scoped(.trigger);

/// Types of events that can trigger workflows
pub const EventType = enum {
    // Git events
    push,
    pull_request,
    pull_request_review,

    // Issue events
    issue_opened,
    issue_closed,
    issue_comment,

    // Agent events
    user_prompt, // Direct chat message
    mention, // @plue in comment

    // Manual triggers
    workflow_dispatch,
    schedule,
};

/// Event context with metadata
pub const Event = struct {
    event_type: EventType,
    repository_id: i32,
    ref: ?[]const u8, // Branch or tag name
    commit_sha: ?[]const u8,
    actor_id: i32, // User who triggered the event

    // PR-specific fields
    pr_number: ?i32,
    pr_action: ?[]const u8, // opened, closed, synchronize, etc.

    // Issue-specific fields
    issue_number: ?i32,

    // Agent-specific fields
    session_id: ?[]const u8,
    message: ?[]const u8,

    // Raw payload for custom matching
    payload: ?[]const u8,
};

/// Workflow definition with trigger configuration
pub const WorkflowDefinition = struct {
    id: i32,
    repository_id: i32,
    name: []const u8,
    file_path: []const u8,
    trigger_events: []const EventType,
    mode: WorkflowMode,

    // Agent-specific config
    model: ?[]const u8,
    system_prompt: ?[]const u8,
    tools: ?[]const []const u8,
    max_turns: i32,
};

pub const WorkflowMode = enum {
    scripted, // Traditional CI/CD
    agent, // AI-powered
};

/// Process an event and create workflow runs
pub fn processEvent(
    allocator: std.mem.Allocator,
    pool: *db.Pool,
    event: Event,
) ![]i32 {
    log.info("Processing event: {s} for repo {d}", .{
        @tagName(event.event_type),
        event.repository_id,
    });

    // Find matching workflow definitions
    const workflows = try findMatchingWorkflows(allocator, pool, event);
    defer allocator.free(workflows);

    if (workflows.len == 0) {
        log.debug("No matching workflows for event", .{});
        return &[_]i32{};
    }

    var run_ids = std.ArrayList(i32){};
    errdefer run_ids.deinit(allocator);

    for (workflows) |workflow| {
        // Create workflow run
        const run_id = try createWorkflowRun(allocator, pool, workflow, event);
        try run_ids.append(allocator, run_id);

        // Submit to queue for execution
        try queue.submitWorkload(allocator, pool, .{
            .type = if (workflow.mode == .agent) .agent else .workflow,
            .workflow_run_id = run_id,
            .session_id = event.session_id,
            .priority = getPriority(event.event_type),
        });

        log.info("Created workflow run {d} for workflow '{s}'", .{
            run_id,
            workflow.name,
        });
    }

    return run_ids.toOwnedSlice(allocator);
}

/// Find workflow definitions that match an event
fn findMatchingWorkflows(
    allocator: std.mem.Allocator,
    pool: *db.Pool,
    event: Event,
) ![]WorkflowDefinition {
    _ = allocator;

    // Query workflow definitions for this repository
    const query =
        \\SELECT id, repository_id, name, file_path, trigger_events,
        \\       is_agent_workflow, model, system_prompt, max_turns
        \\FROM workflow_definitions
        \\WHERE repository_id = $1 AND is_active = true
    ;

    const result = pool.query(query, .{event.repository_id}) catch |err| {
        log.err("Failed to query workflow definitions: {}", .{err});
        return &[_]WorkflowDefinition{};
    };
    defer result.deinit();

    var workflows = std.ArrayList(WorkflowDefinition){};
    errdefer workflows.deinit(allocator);

    while (result.next()) |row| {
        const trigger_events_str = row.get([]const u8, 4);
        const triggers = parseTriggerEvents(trigger_events_str);

        // Check if this workflow matches the event
        var matches = false;
        for (triggers) |trigger| {
            if (trigger == event.event_type) {
                matches = true;
                break;
            }
        }

        if (matches) {
            try workflows.append(allocator, .{
                .id = row.get(i32, 0),
                .repository_id = row.get(i32, 1),
                .name = row.get([]const u8, 2),
                .file_path = row.get([]const u8, 3),
                .trigger_events = triggers,
                .mode = if (row.get(bool, 5)) .agent else .scripted,
                .model = row.get(?[]const u8, 6),
                .system_prompt = row.get(?[]const u8, 7),
                .tools = null, // TODO: Parse tools array
                .max_turns = row.get(i32, 8) orelse 20,
            });
        }
    }

    return workflows.toOwnedSlice(allocator);
}

/// Parse trigger events from comma-separated string
fn parseTriggerEvents(events_str: []const u8) []const EventType {
    // Simple parsing - in production, use proper JSON/YAML parsing
    var events = std.ArrayList(EventType){};
    var iter = std.mem.splitSequence(u8, events_str, ",");

    while (iter.next()) |event_name| {
        const trimmed = std.mem.trim(u8, event_name, &std.ascii.whitespace);
        if (parseEventType(trimmed)) |event_type| {
            events.append(std.heap.page_allocator, event_type) catch continue;
        }
    }

    return events.items;
}

fn parseEventType(name: []const u8) ?EventType {
    const map = std.StaticStringMap(EventType).initComptime(.{
        .{ "push", .push },
        .{ "pull_request", .pull_request },
        .{ "pull_request_review", .pull_request_review },
        .{ "issue.opened", .issue_opened },
        .{ "issue.closed", .issue_closed },
        .{ "issue.comment", .issue_comment },
        .{ "user_prompt", .user_prompt },
        .{ "mention", .mention },
        .{ "workflow_dispatch", .workflow_dispatch },
        .{ "schedule", .schedule },
    });
    return map.get(name);
}

/// Create a workflow run record
fn createWorkflowRun(
    allocator: std.mem.Allocator,
    pool: *db.Pool,
    workflow: WorkflowDefinition,
    event: Event,
) !i32 {
    _ = allocator;

    const query =
        \\INSERT INTO workflow_runs (
        \\    repository_id, workflow_definition_id, status,
        \\    trigger_event, ref, commit_sha, actor_id,
        \\    session_id, created_at
        \\) VALUES ($1, $2, 'pending', $3, $4, $5, $6, $7, NOW())
        \\RETURNING id
    ;

    const result = try pool.query(query, .{
        event.repository_id,
        workflow.id,
        @tagName(event.event_type),
        event.ref,
        event.commit_sha,
        event.actor_id,
        event.session_id,
    });
    defer result.deinit();

    if (result.next()) |row| {
        return row.get(i32, 0);
    }

    return error.FailedToCreateWorkflowRun;
}

/// Get priority based on event type
fn getPriority(event_type: EventType) queue.Priority {
    return switch (event_type) {
        .user_prompt, .mention => .high, // Interactive agents need fast response
        .push, .pull_request => .normal,
        .schedule => .low,
        else => .normal,
    };
}

// =============================================================================
// Tests
// =============================================================================

test "parseEventType" {
    try std.testing.expectEqual(EventType.push, parseEventType("push").?);
    try std.testing.expectEqual(EventType.pull_request, parseEventType("pull_request").?);
    try std.testing.expect(parseEventType("invalid") == null);
}

test "Event struct" {
    const event = Event{
        .event_type = .push,
        .repository_id = 1,
        .ref = "refs/heads/main",
        .commit_sha = "abc123",
        .actor_id = 1,
        .pr_number = null,
        .pr_action = null,
        .issue_number = null,
        .session_id = null,
        .message = null,
        .payload = null,
    };
    try std.testing.expectEqual(EventType.push, event.event_type);
}
