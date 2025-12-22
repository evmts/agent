//! Webhook Handlers
//!
//! HTTP handlers for incoming webhooks from git operations and external services.
//! Converts webhook payloads into events for the trigger system.

const std = @import("std");
const httpz = @import("httpz");
const trigger = @import("trigger.zig");
const db = @import("../lib/db.zig");

const log = std.log.scoped(.webhook);

const Context = @import("../main.zig").Context;

// =============================================================================
// Push Webhook Handler
// =============================================================================

/// Handle push webhooks (git push events)
pub fn handlePush(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;
    const allocator = ctx.allocator;

    // Parse request body
    const body = req.body() orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing request body\"}");
        return;
    };

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid JSON\"}");
        return;
    };
    defer parsed.deinit();

    const root = parsed.value.object;

    // Extract push event data
    const repository_id = blk: {
        if (root.get("repository_id")) |v| {
            break :blk @as(i32, @intCast(v.integer));
        }
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repository_id\"}");
        return;
    };

    const ref = if (root.get("ref")) |v| v.string else null;
    const commit_sha = if (root.get("after")) |v| v.string else null;
    const actor_id = if (root.get("pusher_id")) |v| @as(i32, @intCast(v.integer)) else 0;

    // Create and process event
    const event = trigger.Event{
        .event_type = .push,
        .repository_id = repository_id,
        .ref = ref,
        .commit_sha = commit_sha,
        .actor_id = actor_id,
        .pr_number = null,
        .pr_action = null,
        .issue_number = null,
        .session_id = null,
        .message = null,
        .payload = body,
    };

    const run_ids = trigger.processEvent(allocator, ctx.pool, event) catch |err| {
        log.err("Failed to process push event: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to process event\"}");
        return;
    };
    defer allocator.free(run_ids);

    // Return created workflow run IDs
    var writer = res.writer();
    try writer.writeAll("{\"workflow_runs\":[");
    for (run_ids, 0..) |run_id, i| {
        if (i > 0) try writer.writeAll(",");
        try writer.print("{d}", .{run_id});
    }
    try writer.writeAll("]}");
}

// =============================================================================
// Pull Request Webhook Handler
// =============================================================================

/// Handle pull request webhooks
pub fn handlePullRequest(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;
    const allocator = ctx.allocator;

    const body = req.body() orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing request body\"}");
        return;
    };

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid JSON\"}");
        return;
    };
    defer parsed.deinit();

    const root = parsed.value.object;

    const repository_id = blk: {
        if (root.get("repository_id")) |v| {
            break :blk @as(i32, @intCast(v.integer));
        }
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repository_id\"}");
        return;
    };

    const action = if (root.get("action")) |v| v.string else "opened";
    const pr = root.get("pull_request") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing pull_request object\"}");
        return;
    };

    const pr_number = if (pr.object.get("number")) |v| @as(i32, @intCast(v.integer)) else null;
    const head_sha = if (pr.object.get("head")) |head|
        if (head.object.get("sha")) |sha| sha.string else null
    else
        null;
    const actor_id = if (root.get("sender")) |sender|
        if (sender.object.get("id")) |id| @as(i32, @intCast(id.integer)) else 0
    else
        0;

    const event = trigger.Event{
        .event_type = .pull_request,
        .repository_id = repository_id,
        .ref = null,
        .commit_sha = head_sha,
        .actor_id = actor_id,
        .pr_number = pr_number,
        .pr_action = action,
        .issue_number = null,
        .session_id = null,
        .message = null,
        .payload = body,
    };

    const run_ids = trigger.processEvent(allocator, ctx.pool, event) catch |err| {
        log.err("Failed to process PR event: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to process event\"}");
        return;
    };
    defer allocator.free(run_ids);

    var writer = res.writer();
    try writer.writeAll("{\"workflow_runs\":[");
    for (run_ids, 0..) |run_id, i| {
        if (i > 0) try writer.writeAll(",");
        try writer.print("{d}", .{run_id});
    }
    try writer.writeAll("]}");
}

// =============================================================================
// Issue Webhook Handler
// =============================================================================

/// Handle issue webhooks (including comments)
pub fn handleIssue(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;
    const allocator = ctx.allocator;

    const body = req.body() orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing request body\"}");
        return;
    };

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid JSON\"}");
        return;
    };
    defer parsed.deinit();

    const root = parsed.value.object;

    const repository_id = blk: {
        if (root.get("repository_id")) |v| {
            break :blk @as(i32, @intCast(v.integer));
        }
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repository_id\"}");
        return;
    };

    const action = if (root.get("action")) |v| v.string else "opened";
    const issue = root.get("issue") orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing issue object\"}");
        return;
    };

    const issue_number = if (issue.object.get("number")) |v| @as(i32, @intCast(v.integer)) else null;
    const actor_id = if (root.get("sender")) |sender|
        if (sender.object.get("id")) |id| @as(i32, @intCast(id.integer)) else 0
    else
        0;

    // Determine event type based on action
    const event_type: trigger.EventType = if (std.mem.eql(u8, action, "opened"))
        .issue_opened
    else if (std.mem.eql(u8, action, "closed"))
        .issue_closed
    else
        .issue_comment;

    // Check for @plue mention in comments
    var message: ?[]const u8 = null;
    var is_mention = false;

    if (root.get("comment")) |comment| {
        if (comment.object.get("body")) |comment_body| {
            message = comment_body.string;
            if (std.mem.indexOf(u8, comment_body.string, "@plue") != null) {
                is_mention = true;
            }
        }
    }

    const event = trigger.Event{
        .event_type = if (is_mention) .mention else event_type,
        .repository_id = repository_id,
        .ref = null,
        .commit_sha = null,
        .actor_id = actor_id,
        .pr_number = null,
        .pr_action = null,
        .issue_number = issue_number,
        .session_id = null,
        .message = message,
        .payload = body,
    };

    const run_ids = trigger.processEvent(allocator, ctx.pool, event) catch |err| {
        log.err("Failed to process issue event: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to process event\"}");
        return;
    };
    defer allocator.free(run_ids);

    var writer = res.writer();
    try writer.writeAll("{\"workflow_runs\":[");
    for (run_ids, 0..) |run_id, i| {
        if (i > 0) try writer.writeAll(",");
        try writer.print("{d}", .{run_id});
    }
    try writer.writeAll("]}");
}

// =============================================================================
// Chat/Agent Event Handler
// =============================================================================

/// Handle chat message events (user prompts)
pub fn handleChatMessage(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JSON;
    const allocator = ctx.allocator;

    const body = req.body() orelse {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing request body\"}");
        return;
    };

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch {
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Invalid JSON\"}");
        return;
    };
    defer parsed.deinit();

    const root = parsed.value.object;

    const repository_id = blk: {
        if (root.get("repository_id")) |v| {
            break :blk @as(i32, @intCast(v.integer));
        }
        res.status = 400;
        try res.writer().writeAll("{\"error\":\"Missing repository_id\"}");
        return;
    };

    const session_id = if (root.get("session_id")) |v| v.string else null;
    const message = if (root.get("message")) |v| v.string else null;
    const actor_id = if (root.get("user_id")) |v| @as(i32, @intCast(v.integer)) else 0;

    const event = trigger.Event{
        .event_type = .user_prompt,
        .repository_id = repository_id,
        .ref = null,
        .commit_sha = null,
        .actor_id = actor_id,
        .pr_number = null,
        .pr_action = null,
        .issue_number = null,
        .session_id = session_id,
        .message = message,
        .payload = body,
    };

    const run_ids = trigger.processEvent(allocator, ctx.pool, event) catch |err| {
        log.err("Failed to process chat event: {}", .{err});
        res.status = 500;
        try res.writer().writeAll("{\"error\":\"Failed to process event\"}");
        return;
    };
    defer allocator.free(run_ids);

    var writer = res.writer();
    try writer.writeAll("{\"workflow_runs\":[");
    for (run_ids, 0..) |run_id, i| {
        if (i > 0) try writer.writeAll(",");
        try writer.print("{d}", .{run_id});
    }
    try writer.writeAll("]}");
}

// =============================================================================
// Tests
// =============================================================================

test "webhook module compiles" {
    // Basic compile test
    _ = handlePush;
    _ = handlePullRequest;
    _ = handleIssue;
    _ = handleChatMessage;
}
