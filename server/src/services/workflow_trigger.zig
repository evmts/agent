//! Workflow Trigger Service
//!
//! Automatically triggers workflows when repository events occur.
//! Discovers workflow files in .plue/workflows/*.py and creates database records
//! for workflow_runs, workflow_jobs, and workflow_tasks.

const std = @import("std");
const db = @import("../lib/db.zig");

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

/// Workflow status (matches database enum)
pub const WorkflowStatus = enum(i32) {
    unknown = 0,
    success = 1,
    failure = 2,
    cancelled = 3,
    skipped = 4,
    waiting = 5,
    running = 6,
    blocked = 7,
};

/// Discovered workflow metadata
pub const WorkflowMetadata = struct {
    name: []const u8,
    file_path: []const u8,
    events: []const []const u8,
    is_agent_workflow: bool,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *WorkflowMetadata) void {
        self.allocator.free(self.name);
        self.allocator.free(self.file_path);
        for (self.events) |event| {
            self.allocator.free(event);
        }
        self.allocator.free(self.events);
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

        // Get repository path
        const repo_path = try self.getRepositoryPath(repo_id);
        defer self.allocator.free(repo_path);

        // Discover workflows in .plue/workflows/
        const workflows = try self.discoverWorkflows(repo_path);
        defer {
            for (workflows) |*wf| {
                wf.deinit();
            }
            self.allocator.free(workflows);
        }

        log.info("Discovered {d} workflow(s)", .{workflows.len});

        // Trigger matching workflows
        var triggered_count: usize = 0;
        for (workflows) |workflow| {
            if (try self.shouldTrigger(&workflow, event)) {
                try self.createWorkflowRun(
                    repo_id,
                    &workflow,
                    event,
                    ref,
                    commit_sha,
                    trigger_user_id,
                );
                triggered_count += 1;
            }
        }

        log.info("Triggered {d} workflow(s) for event: {s}", .{ triggered_count, event });
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

        // Get current working directory
        const cwd = try std.process.getCwdAlloc(self.allocator);
        defer self.allocator.free(cwd);

        return std.fmt.allocPrint(
            self.allocator,
            "{s}/repos/{s}/{s}",
            .{ cwd, username, repo_name },
        );
    }

    /// Discover workflow files in .plue/workflows/
    fn discoverWorkflows(self: *WorkflowTrigger, repo_path: []const u8) ![]WorkflowMetadata {
        const workflows_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}/.plue/workflows",
            .{repo_path},
        );
        defer self.allocator.free(workflows_path);

        // Check if workflows directory exists
        var workflows_dir = std.fs.cwd().openDir(workflows_path, .{ .iterate = true }) catch |err| {
            if (err == error.FileNotFound) {
                log.debug("No .plue/workflows directory found", .{});
                return &[_]WorkflowMetadata{};
            }
            return err;
        };
        defer workflows_dir.close();

        var result = std.ArrayList(WorkflowMetadata){};
        errdefer {
            for (result.items) |*wf| {
                wf.deinit();
            }
            result.deinit(self.allocator);
        }

        // Iterate through .py files
        var iter = workflows_dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind != .file) continue;
            if (!std.mem.endsWith(u8, entry.name, ".py")) continue;

            const file_path = try std.fmt.allocPrint(
                self.allocator,
                ".plue/workflows/{s}",
                .{entry.name},
            );
            errdefer self.allocator.free(file_path);

            const abs_path = try std.fmt.allocPrint(
                self.allocator,
                "{s}/{s}",
                .{ workflows_path, entry.name },
            );
            defer self.allocator.free(abs_path);

            // Parse workflow metadata
            const metadata = try self.parseWorkflowFile(abs_path, file_path);
            try result.append(self.allocator, metadata);
        }

        return result.toOwnedSlice(self.allocator);
    }

    /// Parse workflow file to extract metadata
    fn parseWorkflowFile(
        self: *WorkflowTrigger,
        abs_path: []const u8,
        rel_path: []const u8,
    ) !WorkflowMetadata {
        const file = try std.fs.cwd().openFile(abs_path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 1024 * 1024); // 1MB max
        defer self.allocator.free(content);

        var name: ?[]const u8 = null;
        var events = std.ArrayList([]const u8){};
        var is_agent_workflow = false;

        errdefer {
            if (name) |n| self.allocator.free(n);
            for (events.items) |event| {
                self.allocator.free(event);
            }
            events.deinit(self.allocator);
        }

        // Parse @workflow decorator
        // Example: @workflow(name="CI Pipeline", on=["push", "pull_request"])
        var lines = std.mem.splitScalar(u8, content, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (std.mem.startsWith(u8, trimmed, "@workflow(")) {
                // Extract name
                if (std.mem.indexOf(u8, trimmed, "name=")) |name_idx| {
                    const name_start = name_idx + 5;
                    if (name_start < trimmed.len) {
                        // Find opening quote
                        const quote_start = std.mem.indexOfPos(u8, trimmed, name_start, "\"") orelse
                            std.mem.indexOfPos(u8, trimmed, name_start, "'") orelse continue;
                        const quote_char = trimmed[quote_start];
                        const name_content_start = quote_start + 1;

                        // Find closing quote
                        const quote_end = std.mem.indexOfPos(u8, trimmed, name_content_start, &[_]u8{quote_char}) orelse continue;
                        name = try self.allocator.dupe(u8, trimmed[name_content_start..quote_end]);
                    }
                }

                // Extract on= events
                if (std.mem.indexOf(u8, trimmed, "on=")) |on_idx| {
                    const on_start = on_idx + 3;
                    if (on_start < trimmed.len) {
                        // Find opening bracket
                        const bracket_start = std.mem.indexOfPos(u8, trimmed, on_start, "[") orelse continue;
                        const bracket_end = std.mem.indexOfPos(u8, trimmed, bracket_start, "]") orelse continue;
                        const events_str = trimmed[bracket_start + 1 .. bracket_end];

                        // Split by comma
                        var event_iter = std.mem.splitScalar(u8, events_str, ',');
                        while (event_iter.next()) |event_part| {
                            const event_trimmed = std.mem.trim(u8, event_part, " \t\"'");
                            if (event_trimmed.len > 0) {
                                const event_copy = try self.allocator.dupe(u8, event_trimmed);
                                try events.append(self.allocator, event_copy);
                            }
                        }
                    }
                }

                // Check for agent=True
                if (std.mem.indexOf(u8, trimmed, "agent=True")) |_| {
                    is_agent_workflow = true;
                }

                break; // Found @workflow, stop parsing
            }
        }

        // Use filename as fallback name
        if (name == null) {
            const basename = std.fs.path.basename(rel_path);
            const name_without_ext = if (std.mem.endsWith(u8, basename, ".py"))
                basename[0 .. basename.len - 3]
            else
                basename;
            name = try self.allocator.dupe(u8, name_without_ext);
        }

        return WorkflowMetadata{
            .name = name.?,
            .file_path = try self.allocator.dupe(u8, rel_path),
            .events = try events.toOwnedSlice(self.allocator),
            .is_agent_workflow = is_agent_workflow,
            .allocator = self.allocator,
        };
    }

    /// Check if workflow should be triggered for event
    fn shouldTrigger(self: *WorkflowTrigger, workflow: *const WorkflowMetadata, event: []const u8) !bool {
        _ = self;
        // Check if event is in workflow's event list
        for (workflow.events) |wf_event| {
            if (std.mem.eql(u8, wf_event, event)) {
                return true;
            }
        }
        return false;
    }

    /// Create workflow run, jobs, and tasks
    fn createWorkflowRun(
        self: *WorkflowTrigger,
        repo_id: i64,
        workflow: *const WorkflowMetadata,
        event: []const u8,
        ref: ?[]const u8,
        commit_sha: ?[]const u8,
        trigger_user_id: ?i64,
    ) !void {
        var conn = try self.pool.acquire();
        defer conn.release();

        // Get or create workflow definition
        const workflow_def_id = try self.getOrCreateWorkflowDefinition(
            conn,
            repo_id,
            workflow,
        );

        // Get next run number for this repo
        const run_number = try self.getNextRunNumber(conn, repo_id);

        // Create workflow run
        const create_run_query =
            \\INSERT INTO workflow_runs (
            \\  repository_id, workflow_definition_id, run_number, title,
            \\  trigger_event, trigger_user_id, ref, commit_sha, status
            \\) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
            \\RETURNING id
        ;

        const title = try std.fmt.allocPrint(
            self.allocator,
            "{s} #{d}",
            .{ workflow.name, run_number },
        );
        defer self.allocator.free(title);

        const run_row = try conn.row(create_run_query, .{
            repo_id,
            workflow_def_id,
            run_number,
            title,
            event,
            trigger_user_id,
            ref,
            commit_sha,
            @as(i32, @intFromEnum(WorkflowStatus.waiting)),
        });

        const run_id = run_row.?.get(i64, 0);

        log.info("Created workflow run {d} for workflow: {s}", .{ run_id, workflow.name });

        // Create workflow job
        const job_id = try self.createWorkflowJob(conn, run_id, repo_id, workflow.name);

        // Create workflow task
        try self.createWorkflowTask(conn, job_id, repo_id, workflow, commit_sha);

        log.info("Created workflow job and task for run {d}", .{run_id});
    }

    /// Get or create workflow definition
    fn getOrCreateWorkflowDefinition(
        self: *WorkflowTrigger,
        conn: *db.Conn,
        repo_id: i64,
        workflow: *const WorkflowMetadata,
    ) !i64 {
        // Check if exists
        const check_query =
            \\SELECT id FROM workflow_definitions
            \\WHERE repository_id = $1 AND name = $2
        ;

        const existing = try conn.row(check_query, .{ repo_id, workflow.name });
        if (existing) |row| {
            return row.get(i64, 0);
        }

        // Create new definition
        const events_json = try self.eventsToJson(workflow.events);
        defer self.allocator.free(events_json);

        const create_query =
            \\INSERT INTO workflow_definitions (
            \\  repository_id, name, file_path, events, is_agent_workflow
            \\) VALUES ($1, $2, $3, $4::jsonb, $5)
            \\RETURNING id
        ;

        const row = try conn.row(create_query, .{
            repo_id,
            workflow.name,
            workflow.file_path,
            events_json,
            workflow.is_agent_workflow,
        });

        return row.?.get(i64, 0);
    }

    /// Convert events array to JSON string
    fn eventsToJson(self: *WorkflowTrigger, events: []const []const u8) ![]const u8 {
        var result = std.ArrayList(u8){};
        errdefer result.deinit(self.allocator);

        try result.appendSlice(self.allocator, "[");
        for (events, 0..) |event, i| {
            if (i > 0) try result.appendSlice(self.allocator, ",");
            try result.appendSlice(self.allocator, "\"");
            try result.appendSlice(self.allocator, event);
            try result.appendSlice(self.allocator, "\"");
        }
        try result.appendSlice(self.allocator, "]");

        return result.toOwnedSlice(self.allocator);
    }

    /// Get next run number for repository
    fn getNextRunNumber(self: *WorkflowTrigger, conn: *db.Conn, repo_id: i64) !i32 {
        _ = self;
        const query =
            \\SELECT COALESCE(MAX(run_number), 0) + 1 as next_number
            \\FROM workflow_runs
            \\WHERE repository_id = $1
        ;

        const row = try conn.row(query, .{repo_id});
        return row.?.get(i32, 0);
    }

    /// Create workflow job
    fn createWorkflowJob(
        self: *WorkflowTrigger,
        conn: *db.Conn,
        run_id: i64,
        repo_id: i64,
        job_name: []const u8,
    ) !i64 {
        _ = self;
        const query =
            \\INSERT INTO workflow_jobs (
            \\  run_id, repository_id, name, job_id, status
            \\) VALUES ($1, $2, $3, $4, $5)
            \\RETURNING id
        ;

        const row = try conn.row(query, .{
            run_id,
            repo_id,
            job_name,
            "default", // job_id
            @as(i32, @intFromEnum(WorkflowStatus.waiting)),
        });

        return row.?.get(i64, 0);
    }

    /// Create workflow task
    fn createWorkflowTask(
        self: *WorkflowTrigger,
        conn: *db.Conn,
        job_id: i64,
        repo_id: i64,
        workflow: *const WorkflowMetadata,
        commit_sha: ?[]const u8,
    ) !void {
        // Read workflow file content
        const repo_path = try self.getRepositoryPath(repo_id);
        defer self.allocator.free(repo_path);

        const workflow_abs_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}/{s}",
            .{ repo_path, workflow.file_path },
        );
        defer self.allocator.free(workflow_abs_path);

        const file = try std.fs.cwd().openFile(workflow_abs_path, .{});
        defer file.close();

        const workflow_content = try file.readToEndAlloc(self.allocator, 1024 * 1024); // 1MB max
        defer self.allocator.free(workflow_content);

        const query =
            \\INSERT INTO workflow_tasks (
            \\  job_id, repository_id, commit_sha, workflow_content,
            \\  workflow_path, status, attempt
            \\) VALUES ($1, $2, $3, $4, $5, $6, $7)
        ;

        var result = try conn.query(query, .{
            job_id,
            repo_id,
            commit_sha,
            workflow_content,
            workflow.file_path,
            @as(i32, @intFromEnum(WorkflowStatus.waiting)),
            @as(i32, 1), // attempt
        });
        result.deinit();
    }
};

test "WorkflowTrigger init" {
    const allocator = std.testing.allocator;
    var mock_pool: db.Pool = undefined;
    const trigger = WorkflowTrigger.init(allocator, &mock_pool);
    _ = trigger;
}

test "WorkflowEvent fromString" {
    try std.testing.expectEqual(WorkflowEvent.push, WorkflowEvent.fromString("push"));
    try std.testing.expectEqual(WorkflowEvent.pull_request, WorkflowEvent.fromString("pull_request"));
    try std.testing.expectEqual(null, WorkflowEvent.fromString("invalid"));
}
