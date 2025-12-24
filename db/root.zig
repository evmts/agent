//! Database Access Layer
//!
//! Unified DAO (Data Access Object) module for all PostgreSQL operations.
//! This module re-exports domain-specific DAOs and shared types.

const std = @import("std");
const pg = @import("pg");

// =============================================================================
// Re-exported pg types
// =============================================================================

pub const Pool = pg.Pool;
pub const Conn = pg.Conn;
pub const Result = pg.Result;
pub const QueryRow = pg.QueryRow;

// =============================================================================
// Duration constants (in milliseconds)
// =============================================================================

/// Session validity duration (30 days)
pub const SESSION_DURATION_MS: i64 = 30 * 24 * 60 * 60 * 1000;

/// Session auto-refresh threshold - refresh if expires within 7 days
pub const SESSION_REFRESH_THRESHOLD_MS: i64 = 7 * 24 * 60 * 60 * 1000;

/// Password reset token validity (1 hour)
pub const PASSWORD_RESET_TOKEN_DURATION_MS: i64 = 1 * 60 * 60 * 1000;

/// Email verification token validity (24 hours)
pub const EMAIL_VERIFICATION_TOKEN_DURATION_MS: i64 = 24 * 60 * 60 * 1000;

// =============================================================================
// Domain DAOs
// =============================================================================

pub const users = @import("daos/users.zig");
pub const sessions = @import("daos/sessions.zig");
pub const tokens = @import("daos/tokens.zig");
pub const ssh_keys = @import("daos/ssh_keys.zig");
pub const repositories = @import("daos/repositories.zig");
pub const issues = @import("daos/issues.zig");
pub const labels = @import("daos/labels.zig");
pub const reactions = @import("daos/reactions.zig");
pub const milestones = @import("daos/milestones.zig");
pub const workflows = @import("daos/workflows.zig");
pub const changes = @import("daos/changes.zig");
pub const agent = @import("daos/agent.zig");
pub const stars = @import("daos/stars.zig");
pub const landing = @import("daos/landing.zig");

// =============================================================================
// Convenience re-exports for common types
// =============================================================================

// User types
pub const UserRecord = users.UserRecord;
pub const getUserById = users.getById;
pub const getUserByUsername = users.getByUsername;
pub const getUserByWallet = users.getByWallet;
pub const createUser = users.create;
pub const updateUserProfile = users.updateProfile;
pub const updateLastLogin = users.updateLastLogin;

// Session types
pub const SessionData = sessions.SessionData;
pub const createSession = sessions.create;
pub const getSession = sessions.get;
pub const refreshSession = sessions.refresh;
pub const deleteSession = sessions.delete;
pub const cleanupExpiredSessions = sessions.cleanupExpired;

// Nonce operations
pub const createNonce = sessions.createNonce;
pub const validateNonce = sessions.validateNonce;
pub const markNonceUsed = sessions.markNonceUsed;
pub const cleanupExpiredNonces = sessions.cleanupExpiredNonces;

// Token types
pub const AccessTokenRecord = tokens.AccessTokenRecord;
pub const TokenValidationResult = tokens.TokenValidationResult;
pub const createAccessToken = tokens.createAccessToken;
pub const deleteAccessToken = tokens.delete;
pub const validateAccessToken = tokens.validate;

// SSH key types
pub const SshKeyRecord = ssh_keys.SshKeyRecord;
pub const createSshKey = ssh_keys.create;
pub const getSshKeyByFingerprint = ssh_keys.getByFingerprint;
pub const getSshKeyById = ssh_keys.getById;
pub const deleteSshKey = ssh_keys.delete;

// Repository types
pub const Repository = repositories.Repository;
pub const getRepositoryByUserAndName = repositories.getByUserAndName;
pub const createRepository = repositories.create;
pub const repositoryExists = repositories.exists;
pub const updateRepositoryTopics = repositories.updateTopics;
pub const getRepositoryId = repositories.getId;

// Agent session types
pub const AgentSessionRecord = agent.SessionRecord;
pub const MessageRecord = agent.MessageRecord;
pub const PartRecord = agent.PartRecord;
pub const getAllAgentSessions = agent.getAllSessions;
pub const getAgentSessionById = agent.getSessionById;
pub const createAgentSession = agent.createSession;
pub const updateAgentSession = agent.updateSession;
pub const deleteAgentSession = agent.deleteSession;
pub const getAgentSessionMessages = agent.getSessionMessages;
pub const getMessageById = agent.getMessageById;
pub const createMessage = agent.createMessage;
pub const updateMessage = agent.updateMessage;
pub const deleteMessage = agent.deleteMessage;
pub const getMessageParts = agent.getMessageParts;
pub const getPartById = agent.getPartById;
pub const createPart = agent.createPart;
pub const updatePart = agent.updatePart;
pub const deletePart = agent.deletePart;

// Star types
pub const Stargazer = stars.Stargazer;
pub const getStargazers = stars.getStargazers;
pub const hasStarred = stars.hasStarred;
pub const createStar = stars.create;
pub const deleteStar = stars.delete;
pub const getStarCount = stars.getCount;
pub const upsertWatch = stars.upsertWatch;
pub const deleteWatch = stars.deleteWatch;

// Bookmark types (jj)
pub const Bookmark = changes.Bookmark;
pub const listBookmarks = changes.listBookmarks;
pub const getBookmarkByName = changes.getBookmarkByName;
pub const createBookmark = changes.createBookmark;

// =============================================================================
// Backward-compatible re-exports (from old db_issues.zig)
// =============================================================================

// Repository (old db_issues names)
pub const RepositoryRecord = repositories.Repository;
pub const getRepositoryByName = repositories.getByUserAndName;

// Issues (old db_issues names)
pub const IssueRecord = issues.IssueRecord;
pub const listIssues = issues.list;
pub const getIssue = issues.get;
pub const createIssue = issues.create;
pub const updateIssue = issues.update;
pub const closeIssue = issues.close;
pub const reopenIssue = issues.reopen;
pub const getIssueCounts = issues.getCounts;
pub const deleteIssue = issues.delete;
pub const pinIssue = issues.pin;
pub const unpinIssue = issues.unpin;
pub const getPinnedIssues = issues.getPinned;

// Comments (old db_issues names)
pub const CommentRecord = issues.CommentRecord;
pub const getComments = issues.getComments;
pub const addComment = issues.addComment;
pub const updateComment = issues.updateComment;
pub const deleteComment = issues.deleteComment;

// Assignees (old db_issues names)
pub const addAssignee = issues.addAssignee;
pub const removeAssignee = issues.removeAssignee;
pub const getAssignees = issues.getAssignees;

// Dependencies (old db_issues names)
pub const DependencyRecord = issues.DependencyRecord;
pub const addDependency = issues.addDependency;
pub const removeDependency = issues.removeDependency;
pub const getBlockingIssues = issues.getBlockingIssues;
pub const getBlockedByIssues = issues.getBlockedByIssues;

// Labels (old db_issues names)
pub const LabelRecord = labels.LabelRecord;
pub const getLabels = labels.list;
pub const createLabel = labels.create;
pub const getLabelByName = labels.getByName;
pub const updateLabel = labels.updateByName;
pub const deleteLabel = labels.deleteByName;
pub const addLabelToIssue = labels.addToIssue;
pub const removeLabelFromIssue = labels.removeFromIssue;
pub const getIssueLabels = labels.getForIssue;

// Reactions (old db_issues names)
pub const ReactionRecord = reactions.ReactionRecord;
pub const addReaction = reactions.add;
pub const removeReaction = reactions.remove;
pub const getReactions = reactions.getForTarget;

// Milestones (old db_issues names)
pub const MilestoneRecord = milestones.MilestoneRecord;
pub const listMilestones = milestones.list;
pub const getMilestone = milestones.get;
pub const createMilestone = milestones.create;
pub const updateMilestone = milestones.updateFull;
pub const closeMilestone = milestones.close;
pub const reopenMilestone = milestones.reopen;
pub const deleteMilestone = milestones.deleteByRepoAndId;
pub const assignMilestoneToIssue = milestones.assignToIssue;
pub const removeMilestoneFromIssue = milestones.removeFromIssue;

// Issue history and due dates (old db_issues names)
pub const IssueEventRecord = issues.IssueEventRecord;
pub const getIssueHistory = issues.getHistory;
pub const getDueDate = issues.getDueDate;
pub const setDueDate = issues.setDueDate;
pub const removeDueDate = issues.removeDueDate;

// =============================================================================
// Landing Queue (backward-compatible)
// =============================================================================

pub const LandingRequest = landing.LandingRequest;
pub const LandingReview = landing.LandingReview;
pub const LineComment = landing.LineComment;
pub const listLandingRequests = landing.list;
pub const getLandingRequestById = landing.getById;
pub const findLandingRequestByChangeId = landing.findByChangeId;
pub const countLandingRequests = landing.count;
pub const createLandingRequest = landing.create;
pub const updateLandingRequestStatus = landing.updateStatus;
pub const updateLandingRequestConflicts = landing.updateConflicts;
pub const markLandingRequestLanded = landing.markLanded;
pub const getLandingReviews = landing.getReviews;
pub const createLandingReview = landing.createReview;
pub const getLineCommentById = landing.getLineCommentById;
pub const getLineComments = landing.getLineComments;
pub const createLineComment = landing.createLineComment;
pub const updateLineComment = landing.updateLineComment;
pub const deleteLineComment = landing.deleteLineComment;

// =============================================================================
// Bookmark operations (backward-compatible)
// =============================================================================

pub const updateBookmark = changes.updateBookmark;
pub const deleteBookmark = changes.deleteBookmark;
pub const setDefaultBookmark = changes.setDefaultBookmark;
pub const getChangeById = changes.getChangeById;


// =============================================================================
// Workflow operations (backward-compatible)
// TODO: Migrate routes to use workflows.zig types, then remove these legacy types
// =============================================================================

pub const WorkflowRunLegacy = struct {
    id: i64,
    run_number: i32,
    title: []const u8,
    status: []const u8,
    trigger_event: []const u8,
    created_at: []const u8,
};

pub const WorkflowJobLegacy = struct {
    id: i64,
    name: []const u8,
    job_id: []const u8,
    status: []const u8,
};

pub const WorkflowTaskLegacy = struct {
    id: i64,
    job_id: i64,
    attempt: i32,
    repository_id: i64,
    commit_sha: ?[]const u8,
    workflow_content: []const u8,
    workflow_path: []const u8,
};

pub const WorkflowLogLegacy = struct {
    content: []const u8,
};

pub const Runner = struct {
    id: i64,
    name: []const u8,
};

pub const JjOperation = struct {
    id: i64,
    repository_id: i64,
    operation_id: []const u8,
    operation_type: []const u8,
    description: []const u8,
    timestamp: i64,
    is_undone: bool,
};

pub fn getWorkflowRun(pool: *Pool, allocator: std.mem.Allocator, run_id: i64) !?WorkflowRunLegacy {
    const row = try pool.row(
        \\SELECT id, run_number, title, status::text, trigger_event,
        \\       to_char(created_at, 'YYYY-MM-DD"T"HH24:MI:SS"Z"') as created_at
        \\FROM workflow_runs
        \\WHERE id = $1
    , .{run_id});

    if (row) |r| {
        return WorkflowRunLegacy{
            .id = r.get(i64, 0),
            .run_number = r.get(i32, 1),
            .title = try allocator.dupe(u8, r.get([]const u8, 2)),
            .status = try allocator.dupe(u8, r.get([]const u8, 3)),
            .trigger_event = try allocator.dupe(u8, r.get([]const u8, 4)),
            .created_at = try allocator.dupe(u8, r.get([]const u8, 5)),
        };
    }
    return null;
}

pub fn getWorkflowJobs(pool: *Pool, allocator: std.mem.Allocator, run_id: i64) ![]WorkflowJobLegacy {
    var conn = try pool.acquire();
    defer conn.release();

    var result = try conn.query(
        \\SELECT id, name, job_id, status::text
        \\FROM workflow_jobs
        \\WHERE run_id = $1
        \\ORDER BY id
    , .{run_id});
    defer result.deinit();

    var jobs = std.ArrayList(WorkflowJobLegacy){};
    errdefer jobs.deinit(allocator);

    while (try result.next()) |row| {
        try jobs.append(allocator, .{
            .id = row.get(i64, 0),
            .name = try allocator.dupe(u8, row.get([]const u8, 1)),
            .job_id = try allocator.dupe(u8, row.get([]const u8, 2)),
            .status = try allocator.dupe(u8, row.get([]const u8, 3)),
        });
    }

    return try jobs.toOwnedSlice(allocator);
}

pub fn updateWorkflowRunStatus(pool: *Pool, run_id: i64, status: i32) !void {
    _ = try pool.exec(
        \\UPDATE workflow_runs
        \\SET status = $1,
        \\    stopped_at = CASE WHEN $1 IN (1, 2, 3, 4) THEN NOW() ELSE stopped_at END,
        \\    updated_at = NOW()
        \\WHERE id = $2
    , .{ status, run_id });
}

pub fn getWorkflowLogs(
    pool: *Pool,
    allocator: std.mem.Allocator,
    run_id: i64,
    step_filter: ?i32,
) ![]WorkflowLogLegacy {
    var conn = try pool.acquire();
    defer conn.release();

    var result = if (step_filter) |step|
        try conn.query(
            \\SELECT l.content FROM workflow_logs l
            \\JOIN workflow_tasks t ON l.task_id = t.id
            \\JOIN workflow_jobs j ON t.job_id = j.id
            \\WHERE j.run_id = $1 AND l.step_index = $2
            \\ORDER BY l.task_id, l.line_number
        , .{ run_id, step })
    else
        try conn.query(
            \\SELECT l.content FROM workflow_logs l
            \\JOIN workflow_tasks t ON l.task_id = t.id
            \\JOIN workflow_jobs j ON t.job_id = j.id
            \\WHERE j.run_id = $1
            \\ORDER BY l.task_id, l.step_index, l.line_number
        , .{run_id});
    defer result.deinit();

    var logs = std.ArrayList(WorkflowLogLegacy){};
    errdefer logs.deinit(allocator);

    while (try result.next()) |row| {
        try logs.append(allocator, .{
            .content = try allocator.dupe(u8, row.get([]const u8, 0)),
        });
    }

    return try logs.toOwnedSlice(allocator);
}

// =============================================================================
// JSON Utility Functions
// =============================================================================

/// Write a properly escaped JSON string value to a writer
/// Escapes: quotes, backslashes, newlines, tabs, carriage returns, and control characters
fn writeJsonString(writer: anytype, str: []const u8) !void {
    for (str) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            '\x08' => try writer.writeAll("\\b"), // backspace
            '\x0C' => try writer.writeAll("\\f"), // form feed
            0x00...0x07, 0x0B, 0x0E...0x1F => {
                // Other control characters: escape as \uXXXX
                try writer.print("\\u{x:0>4}", .{c});
            },
            else => try writer.writeByte(c),
        }
    }
}

// =============================================================================
// Runner operations
// =============================================================================

pub fn createRunner(
    pool: *Pool,
    name: []const u8,
    version: ?[]const u8,
    label_list: ?[]const []const u8,
    token_hash: []const u8,
) !i64 {
    // Convert labels array to JSON string
    var json_buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&json_buf);
    const writer = stream.writer();

    try writer.writeByte('[');
    if (label_list) |runner_labels| {
        for (runner_labels, 0..) |label, i| {
            if (i > 0) try writer.writeByte(',');
            try writer.writeByte('"');
            try writeJsonString(writer, label);
            try writer.writeByte('"');
        }
    }
    try writer.writeByte(']');

    const labels_json = stream.getWritten();

    const row = try pool.row(
        \\INSERT INTO workflow_runners (name, version, labels, token_hash, status)
        \\VALUES ($1, $2, $3::jsonb, $4, 'offline')
        \\RETURNING id
    , .{ name, version, labels_json, token_hash });

    if (row) |r| {
        return r.get(i64, 0);
    }
    return error.InsertFailed;
}

pub fn updateRunnerHeartbeat(pool: *Pool, token_hash: []const u8) !void {
    _ = try pool.exec(
        \\UPDATE workflow_runners SET last_seen = NOW(), status = 'online' WHERE token_hash = $1
    , .{token_hash});
}

pub fn freeWorkflowTask(allocator: std.mem.Allocator, task: *const WorkflowTaskLegacy) void {
    allocator.free(task.workflow_content);
    allocator.free(task.workflow_path);
}

pub fn findAvailableTask(pool: *Pool, allocator: std.mem.Allocator, runner_id: i64) !?WorkflowTaskLegacy {
    _ = runner_id; // TODO: filter by runner labels
    const row = try pool.row(
        \\SELECT id, job_id, attempt, repository_id, commit_sha,
        \\       COALESCE(workflow_content, '') as workflow_content,
        \\       COALESCE(workflow_path, '') as workflow_path
        \\FROM workflow_tasks
        \\WHERE status = 'pending'
        \\ORDER BY created_at ASC
        \\LIMIT 1
    , .{});

    if (row) |r| {
        return WorkflowTaskLegacy{
            .id = r.get(i64, 0),
            .job_id = r.get(i64, 1),
            .attempt = r.get(i32, 2),
            .repository_id = r.get(i64, 3),
            .commit_sha = r.get(?[]const u8, 4),
            .workflow_content = try allocator.dupe(u8, r.get([]const u8, 5)),
            .workflow_path = try allocator.dupe(u8, r.get([]const u8, 6)),
        };
    }
    return null;
}

pub fn updateTaskStatus(pool: *Pool, task_id: i64, status: i32) !void {
    _ = try pool.exec(
        \\UPDATE workflow_tasks SET status = $2, updated_at = NOW() WHERE id = $1
    , .{ task_id, status });
}

pub fn appendWorkflowLogs(pool: *Pool, task_id: i64, step_index: i32, lines: []const []const u8) !void {
    for (lines, 0..) |line, i| {
        _ = try pool.exec(
            \\INSERT INTO workflow_logs (task_id, step_index, line_number, content)
            \\VALUES ($1, $2, $3, $4)
        , .{ task_id, step_index, @as(i32, @intCast(i)), line });
    }
}

pub fn assignTaskToRunner(pool: *Pool, task_id: i64, runner_id: i64, token_hash: []const u8) !void {
    _ = try pool.exec(
        \\UPDATE workflow_tasks
        \\SET runner_id = $2, token_hash = $3, status = 'running', started_at = NOW(), updated_at = NOW()
        \\WHERE id = $1
    , .{ task_id, runner_id, token_hash });
}

pub fn updateJobStatusFromTask(pool: *Pool, job_id: i64, status: i32) !void {
    _ = try pool.exec(
        \\UPDATE workflow_jobs SET status = $2, updated_at = NOW() WHERE id = $1
    , .{ job_id, status });
}

pub fn createWorkflowRun(
    pool: *Pool,
    repo_id: i64,
    workflow_id: ?i64,
    title: []const u8,
    trigger_event: []const u8,
    trigger_user_id: i64,
    ref_name: ?[]const u8,
    commit_sha: ?[]const u8,
) !i64 {
    const row = try pool.row(
        \\INSERT INTO workflow_runs (repository_id, workflow_id, title, trigger_event, ref, commit_sha, trigger_user_id, status)
        \\VALUES ($1, $2, $3, $4, $5, $6, $7, 'waiting')
        \\RETURNING id
    , .{ repo_id, workflow_id, title, trigger_event, ref_name, commit_sha, trigger_user_id });

    if (row) |r| {
        return r.get(i64, 0);
    }
    return error.InsertFailed;
}

pub fn listWorkflowRuns(
    pool: *Pool,
    allocator: std.mem.Allocator,
    repo_id: i64,
    status_filter: ?i32,
    per_page: i32,
    offset: i32,
) ![]WorkflowRunLegacy {
    var conn = try pool.acquire();
    defer conn.release();

    var result = if (status_filter) |status|
        try conn.query(
            \\SELECT id, run_number, title, status::text, trigger_event,
            \\       to_char(created_at, 'YYYY-MM-DD"T"HH24:MI:SS"Z"') as created_at
            \\FROM workflow_runs
            \\WHERE repository_id = $1 AND status = $2
            \\ORDER BY created_at DESC
            \\LIMIT $3 OFFSET $4
        , .{ repo_id, status, per_page, offset })
    else
        try conn.query(
            \\SELECT id, run_number, title, status::text, trigger_event,
            \\       to_char(created_at, 'YYYY-MM-DD"T"HH24:MI:SS"Z"') as created_at
            \\FROM workflow_runs
            \\WHERE repository_id = $1
            \\ORDER BY created_at DESC
            \\LIMIT $2 OFFSET $3
        , .{ repo_id, per_page, offset });
    defer result.deinit();

    var runs = std.ArrayList(WorkflowRunLegacy){};
    errdefer runs.deinit(allocator);

    while (try result.next()) |row| {
        try runs.append(allocator, .{
            .id = row.get(i64, 0),
            .run_number = row.get(i32, 1),
            .title = try allocator.dupe(u8, row.get([]const u8, 2)),
            .status = try allocator.dupe(u8, row.get([]const u8, 3)),
            .trigger_event = try allocator.dupe(u8, row.get([]const u8, 4)),
            .created_at = try allocator.dupe(u8, row.get([]const u8, 5)),
        });
    }

    return try runs.toOwnedSlice(allocator);
}

pub fn getRunnerByToken(pool: *Pool, token_hash: []const u8) !?Runner {
    const row = try pool.row(
        \\SELECT id, name FROM workflow_runners WHERE token_hash = $1
    , .{token_hash});

    if (row) |r| {
        return Runner{
            .id = r.get(i64, 0),
            .name = r.get([]const u8, 1),
        };
    }
    return null;
}

pub fn getTaskByToken(pool: *Pool, allocator: std.mem.Allocator, token_hash: []const u8) !?WorkflowTaskLegacy {
    const row = try pool.row(
        \\SELECT id, job_id, attempt, repository_id, commit_sha,
        \\       COALESCE(workflow_content, '') as workflow_content,
        \\       COALESCE(workflow_path, '') as workflow_path
        \\FROM workflow_tasks
        \\WHERE token_hash = $1
    , .{token_hash});

    if (row) |r| {
        return WorkflowTaskLegacy{
            .id = r.get(i64, 0),
            .job_id = r.get(i64, 1),
            .attempt = r.get(i32, 2),
            .repository_id = r.get(i64, 3),
            .commit_sha = r.get(?[]const u8, 4),
            .workflow_content = try allocator.dupe(u8, r.get([]const u8, 5)),
            .workflow_path = try allocator.dupe(u8, r.get([]const u8, 6)),
        };
    }
    return null;
}

// =============================================================================
// JJ Operations
// =============================================================================

pub fn getOperationById(
    pool: *Pool,
    repository_id: i64,
    operation_id: []const u8,
) !?JjOperation {
    const row = try pool.row(
        \\SELECT id, repository_id, operation_id, operation_type, description,
        \\       EXTRACT(EPOCH FROM created_at)::bigint as timestamp,
        \\       false as is_undone
        \\FROM jj_operations
        \\WHERE repository_id = $1 AND operation_id = $2
    , .{ repository_id, operation_id });

    if (row) |r| {
        return JjOperation{
            .id = r.get(i64, 0),
            .repository_id = r.get(i64, 1),
            .operation_id = r.get([]const u8, 2),
            .operation_type = r.get([]const u8, 3),
            .description = r.get([]const u8, 4),
            .timestamp = r.get(i64, 5),
            .is_undone = r.get(bool, 6),
        };
    }
    return null;
}

pub fn createOperation(
    pool: *Pool,
    repository_id: i64,
    operation_id: []const u8,
    operation_type: []const u8,
    description: []const u8,
    timestamp: i64,
) !void {
    _ = try pool.exec(
        \\INSERT INTO jj_operations (repository_id, operation_id, operation_type, description, created_at)
        \\VALUES ($1, $2, $3, $4, to_timestamp($5))
        \\ON CONFLICT (repository_id, operation_id) DO NOTHING
    , .{ repository_id, operation_id, operation_type, description, timestamp });
}

pub fn getOperationsByRepository(
    pool: *Pool,
    allocator: std.mem.Allocator,
    repository_id: i64,
    limit: i32,
) !std.ArrayList(JjOperation) {
    var conn = try pool.acquire();
    defer conn.release();

    var result = try conn.query(
        \\SELECT id, repository_id, operation_id, operation_type, description,
        \\       EXTRACT(EPOCH FROM created_at)::bigint as timestamp,
        \\       false as is_undone
        \\FROM jj_operations
        \\WHERE repository_id = $1
        \\ORDER BY created_at DESC
        \\LIMIT $2
    , .{ repository_id, limit });
    defer result.deinit();

    var operations = std.ArrayList(JjOperation){};
    errdefer operations.deinit(allocator);

    while (try result.next()) |row| {
        try operations.append(allocator, JjOperation{
            .id = row.get(i64, 0),
            .repository_id = row.get(i64, 1),
            .operation_id = row.get([]const u8, 2),
            .operation_type = row.get([]const u8, 3),
            .description = row.get([]const u8, 4),
            .timestamp = row.get(i64, 5),
            .is_undone = row.get(bool, 6),
        });
    }

    return operations;
}

pub fn markOperationsAsUndone(pool: *Pool, repository_id: i64, after_timestamp: i64) !void {
    _ = try pool.exec(
        \\UPDATE jj_operations
        \\SET is_undone = true
        \\WHERE repository_id = $1 AND EXTRACT(EPOCH FROM created_at)::bigint > $2
    , .{ repository_id, after_timestamp });
}

// =============================================================================
// Rate Limiting
// =============================================================================

/// Cleanup expired rate limit entries
/// Should be called periodically (e.g., every 5 minutes)
pub fn cleanupExpiredRateLimits(pool: *Pool) !?i64 {
    return try pool.exec(
        \\DELETE FROM rate_limits WHERE expires_at < NOW()
    , .{});
}

// =============================================================================
// Logging
// =============================================================================

pub const log = std.log.scoped(.db);
