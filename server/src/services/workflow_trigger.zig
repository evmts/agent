//! Workflow Trigger Service
//!
//! Triggers workflows on repository events by using the workflow registry
//! and creating workflow_runs in the new workflow schema.

const std = @import("std");
const db = @import("db");
const workflows = @import("../workflows/mod.zig");
const queue = @import("../dispatch/queue.zig");

const log = std.log.scoped(.workflow_trigger);

/// Workflow event type
pub const WorkflowEvent = enum {
    push,
    pull_request,
    issue,
    chat,

    pub fn toString(self: WorkflowEvent) []const u8 {
        return switch (self) {
            .push => "push",
            .pull_request => "pull_request",
            .issue => "issue",
            .chat => "chat",
        };
    }

    pub fn fromString(s: []const u8) ?WorkflowEvent {
        if (std.mem.eql(u8, s, "push")) return .push;
        if (std.mem.eql(u8, s, "pull_request")) return .pull_request;
        if (std.mem.eql(u8, s, "issue")) return .issue;
        if (std.mem.eql(u8, s, "chat")) return .chat;
        return null;
    }
};

/// Workflow Trigger Service
pub const WorkflowTrigger = struct {
    allocator: std.mem.Allocator,
    pool: *db.Pool,

    pub fn init(allocator: std.mem.Allocator, pool: *db.Pool) WorkflowTrigger {
        return .{
            .allocator = allocator,
            .pool = pool,
        };
    }

    /// Trigger workflows for a repository event
    pub fn triggerWorkflows(
        self: *WorkflowTrigger,
        repo_id: i64,
        event: []const u8,
        ref: ?[]const u8,
        commit_sha: ?[]const u8,
        trigger_user_id: ?i64,
    ) !void {
        log.info("Triggering workflows for repo {d}, event: {s}", .{ repo_id, event });

        const repo_path = try self.getRepositoryPath(repo_id);
        defer self.allocator.free(repo_path);

        var registry = workflows.Registry.init(self.allocator, self.pool);
        var discovery = registry.discoverAndParse(repo_path, @intCast(repo_id)) catch |err| {
            log.err("Failed to discover workflows: {}", .{err});
            return err;
        };
        defer discovery.deinit(self.allocator);

        const defs = try db.workflows.listWorkflowDefinitions(self.pool, self.allocator, @intCast(repo_id));
        defer self.allocator.free(defs);

        var triggered_count: usize = 0;
        for (defs) |def| {
            if (try self.shouldTrigger(def.triggers, event)) {
                _ = try self.createWorkflowRun(def.id, event, ref, commit_sha, trigger_user_id);
                triggered_count += 1;
            }
        }

        log.info("Triggered {d} workflow(s) for event: {s}", .{ triggered_count, event });
    }

    fn shouldTrigger(self: *WorkflowTrigger, triggers_json: []const u8, event: []const u8) !bool {
        var parsed = std.json.parseFromSlice(std.json.Value, self.allocator, triggers_json, .{}) catch |err| {
            log.err("Failed to parse workflow triggers JSON: {}", .{err});
            return false;
        };
        defer parsed.deinit();

        if (parsed.value != .array) return false;

        for (parsed.value.array.items) |item| {
            if (item != .object) continue;
            if (item.object.get("type")) |value| {
                if (value == .string and std.mem.eql(u8, value.string, event)) {
                    return true;
                }
            }
        }

        return false;
    }

    fn createWorkflowRun(
        self: *WorkflowTrigger,
        workflow_def_id: i32,
        event: []const u8,
        ref: ?[]const u8,
        commit_sha: ?[]const u8,
        trigger_user_id: ?i64,
    ) !i32 {
        const TriggerPayload = struct {
            event: []const u8,
            ref: ?[]const u8,
            commit_sha: ?[]const u8,
            trigger_user_id: ?i64,
        };

        // Zig 0.15: Use Stringify with allocating writer
        var out = std.io.Writer.Allocating.init(self.allocator);
        var write_stream = std.json.Stringify{
            .writer = &out.writer,
            .options = .{},
        };
        try write_stream.write(TriggerPayload{
            .event = event,
            .ref = ref,
            .commit_sha = commit_sha,
            .trigger_user_id = trigger_user_id,
        });
        const payload_json = try out.toOwnedSlice();
        defer self.allocator.free(payload_json);

        const run_id = try db.workflows.createWorkflowRun(
            self.pool,
            workflow_def_id,
            event,
            payload_json,
            null,
        );

        _ = queue.submitWorkload(self.allocator, self.pool, .{
            .type = .workflow,
            .workflow_run_id = run_id,
            .session_id = null,
            .priority = .normal,
            .config_json = null,
        }) catch |err| {
            log.err("Failed to queue workflow run {d}: {}", .{ run_id, err });
        };

        return run_id;
    }

    /// Get repository path from database
    fn getRepositoryPath(self: *WorkflowTrigger, repo_id: i64) ![]const u8 {
        var conn = try self.pool.acquire();
        defer conn.release();

        const query =
            \\SELECT u.username, r.name
            \\FROM repositories r
            \\JOIN users u ON r.user_id = u.id
            \\WHERE r.id = $1
        ;

        const row = try conn.row(query, .{repo_id});
        if (row == null) {
            return error.RepositoryNotFound;
        }

        const username = row.?.get([]const u8, 0);
        const repo_name = row.?.get([]const u8, 1);

        const cwd = try std.process.getCwdAlloc(self.allocator);
        defer self.allocator.free(cwd);

        return std.fmt.allocPrint(
            self.allocator,
            "{s}/repos/{s}/{s}",
            .{ cwd, username, repo_name },
        );
    }
};

// =============================================================================
// Tests
// =============================================================================

test "shouldTrigger - matching event" {
    const allocator = std.testing.allocator;
    var mock_pool: db.Pool = undefined;
    var trigger = WorkflowTrigger.init(allocator, &mock_pool);

    const triggers_json =
        "[{\"type\":\"push\",\"config\":{}},{\"type\":\"pull_request\",\"config\":{}}]";

    try std.testing.expect(try trigger.shouldTrigger(triggers_json, "push"));
    try std.testing.expect(try trigger.shouldTrigger(triggers_json, "pull_request"));
    try std.testing.expect(!try trigger.shouldTrigger(triggers_json, "issue"));
}

test "WorkflowEvent conversion" {
    try std.testing.expectEqual(WorkflowEvent.push, WorkflowEvent.fromString("push"));
    try std.testing.expectEqual(WorkflowEvent.pull_request, WorkflowEvent.fromString("pull_request"));
    try std.testing.expectEqual(WorkflowEvent.issue, WorkflowEvent.fromString("issue"));
    try std.testing.expectEqual(WorkflowEvent.chat, WorkflowEvent.fromString("chat"));
    try std.testing.expectEqual(@as(?WorkflowEvent, null), WorkflowEvent.fromString("invalid"));

    try std.testing.expectEqualStrings("push", WorkflowEvent.push.toString());
    try std.testing.expectEqualStrings("pull_request", WorkflowEvent.pull_request.toString());
    try std.testing.expectEqualStrings("issue", WorkflowEvent.issue.toString());
    try std.testing.expectEqualStrings("chat", WorkflowEvent.chat.toString());
}
