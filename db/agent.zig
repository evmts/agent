//! Agent Data Access Object
//!
//! SQL operations for the sessions (agent), messages, parts, subtasks, file_trackers, and snapshot_history tables.

const std = @import("std");
const pg = @import("pg");

pub const Pool = pg.Pool;

// =============================================================================
// Types
// =============================================================================

pub const SessionRecord = struct {
    id: []const u8,
    project_id: []const u8,
    directory: []const u8,
    title: []const u8,
    version: []const u8,
    time_created: i64,
    time_updated: i64,
    time_archived: ?i64,
    parent_id: ?[]const u8,
    fork_point: ?[]const u8,
    summary: ?[]const u8, // JSONB as string
    revert: ?[]const u8, // JSONB as string
    compaction: ?[]const u8, // JSONB as string
    token_count: i32,
    bypass_mode: bool,
    model: ?[]const u8,
    reasoning_effort: ?[]const u8,
    ghost_commit: ?[]const u8, // JSONB as string
    plugins: []const u8, // JSONB as string
};

pub const MessageRecord = struct {
    id: []const u8,
    session_id: []const u8,
    role: []const u8,
    time_created: i64,
    time_completed: ?i64,
    status: []const u8,
    thinking_text: ?[]const u8,
    error_message: ?[]const u8,
};

pub const PartRecord = struct {
    id: []const u8,
    session_id: []const u8,
    message_id: []const u8,
    type_: []const u8,
    text: ?[]const u8,
    tool_name: ?[]const u8,
    tool_state: ?[]const u8,
    mime: ?[]const u8,
    url: ?[]const u8,
    filename: ?[]const u8,
    time_start: ?i64,
    time_end: ?i64,
    sort_order: i32,
};

// =============================================================================
// Session Operations
// =============================================================================

pub fn getAllSessions(pool: *Pool, allocator: std.mem.Allocator) !std.ArrayList(SessionRecord) {
    var sessions = try std.ArrayList(SessionRecord).initCapacity(allocator, 0);

    var result = try pool.query(
        \\SELECT id, project_id, directory, title, version, time_created, time_updated,
        \\       time_archived, parent_id, fork_point, summary::text, revert::text,
        \\       compaction::text, token_count, bypass_mode, model, reasoning_effort,
        \\       ghost_commit::text, plugins::text
        \\FROM sessions
        \\ORDER BY time_updated DESC
    , .{});
    defer result.deinit();

    while (try result.next()) |row| {
        try sessions.append(allocator, SessionRecord{
            .id = row.get([]const u8, 0),
            .project_id = row.get([]const u8, 1),
            .directory = row.get([]const u8, 2),
            .title = row.get([]const u8, 3),
            .version = row.get([]const u8, 4),
            .time_created = row.get(i64, 5),
            .time_updated = row.get(i64, 6),
            .time_archived = row.get(?i64, 7),
            .parent_id = row.get(?[]const u8, 8),
            .fork_point = row.get(?[]const u8, 9),
            .summary = row.get(?[]const u8, 10),
            .revert = row.get(?[]const u8, 11),
            .compaction = row.get(?[]const u8, 12),
            .token_count = row.get(i32, 13),
            .bypass_mode = row.get(bool, 14),
            .model = row.get(?[]const u8, 15),
            .reasoning_effort = row.get(?[]const u8, 16),
            .ghost_commit = row.get(?[]const u8, 17),
            .plugins = row.get([]const u8, 18),
        });
    }

    return sessions;
}

pub fn getSessionById(pool: *Pool, session_id: []const u8) !?SessionRecord {
    const row = try pool.row(
        \\SELECT id, project_id, directory, title, version, time_created, time_updated,
        \\       time_archived, parent_id, fork_point, summary::text, revert::text,
        \\       compaction::text, token_count, bypass_mode, model, reasoning_effort,
        \\       ghost_commit::text, plugins::text
        \\FROM sessions
        \\WHERE id = $1
    , .{session_id});

    if (row) |r| {
        return SessionRecord{
            .id = r.get([]const u8, 0),
            .project_id = r.get([]const u8, 1),
            .directory = r.get([]const u8, 2),
            .title = r.get([]const u8, 3),
            .version = r.get([]const u8, 4),
            .time_created = r.get(i64, 5),
            .time_updated = r.get(i64, 6),
            .time_archived = r.get(?i64, 7),
            .parent_id = r.get(?[]const u8, 8),
            .fork_point = r.get(?[]const u8, 9),
            .summary = r.get(?[]const u8, 10),
            .revert = r.get(?[]const u8, 11),
            .compaction = r.get(?[]const u8, 12),
            .token_count = r.get(i32, 13),
            .bypass_mode = r.get(bool, 14),
            .model = r.get(?[]const u8, 15),
            .reasoning_effort = r.get(?[]const u8, 16),
            .ghost_commit = r.get(?[]const u8, 17),
            .plugins = r.get([]const u8, 18),
        };
    }
    return null;
}

pub fn createSession(
    pool: *Pool,
    id: []const u8,
    directory: []const u8,
    title: []const u8,
    parent_id: ?[]const u8,
    bypass_mode: bool,
    model: ?[]const u8,
    reasoning_effort: ?[]const u8,
    plugins: []const u8,
) !void {
    const now = std.time.milliTimestamp();

    _ = try pool.exec(
        \\INSERT INTO sessions (
        \\  id, project_id, directory, title, version, time_created, time_updated,
        \\  parent_id, bypass_mode, model, reasoning_effort, plugins, token_count
        \\) VALUES ($1, 'default', $2, $3, '1.0.0', $4, $4, $5, $6, $7, $8, $9::jsonb, 0)
    , .{ id, directory, title, now, parent_id, bypass_mode, model, reasoning_effort, plugins });
}

pub fn updateSession(
    pool: *Pool,
    session_id: []const u8,
    title: ?[]const u8,
    archived: ?bool,
    model: ?[]const u8,
    reasoning_effort: ?[]const u8,
) !void {
    const now = std.time.milliTimestamp();

    if (title) |t| {
        _ = try pool.exec(
            \\UPDATE sessions SET title = $1, time_updated = $2 WHERE id = $3
        , .{ t, now, session_id });
    }

    if (archived) |is_archived| {
        if (is_archived) {
            _ = try pool.exec(
                \\UPDATE sessions SET time_archived = $1, time_updated = $1 WHERE id = $2
            , .{ now, session_id });
        } else {
            _ = try pool.exec(
                \\UPDATE sessions SET time_archived = NULL, time_updated = $1 WHERE id = $2
            , .{ now, session_id });
        }
    }

    if (model) |m| {
        _ = try pool.exec(
            \\UPDATE sessions SET model = $1, time_updated = $2 WHERE id = $3
        , .{ m, now, session_id });
    }

    if (reasoning_effort) |re| {
        _ = try pool.exec(
            \\UPDATE sessions SET reasoning_effort = $1, time_updated = $2 WHERE id = $3
        , .{ re, now, session_id });
    }
}

pub fn deleteSession(pool: *Pool, session_id: []const u8) !void {
    _ = try pool.exec(
        \\DELETE FROM sessions WHERE id = $1
    , .{session_id});
}

// =============================================================================
// Message Operations
// =============================================================================

pub fn getSessionMessages(pool: *Pool, allocator: std.mem.Allocator, session_id: []const u8) !std.ArrayList(MessageRecord) {
    var messages = try std.ArrayList(MessageRecord).initCapacity(allocator, 0);

    var result = try pool.query(
        \\SELECT id, session_id, role, time_created, time_completed, status,
        \\       thinking_text, error_message
        \\FROM messages
        \\WHERE session_id = $1
        \\ORDER BY time_created ASC
    , .{session_id});
    defer result.deinit();

    while (try result.next()) |row| {
        try messages.append(allocator, MessageRecord{
            .id = row.get([]const u8, 0),
            .session_id = row.get([]const u8, 1),
            .role = row.get([]const u8, 2),
            .time_created = row.get(i64, 3),
            .time_completed = row.get(?i64, 4),
            .status = row.get([]const u8, 5),
            .thinking_text = row.get(?[]const u8, 6),
            .error_message = row.get(?[]const u8, 7),
        });
    }

    return messages;
}

pub fn getMessageById(pool: *Pool, message_id: []const u8) !?MessageRecord {
    const row = try pool.row(
        \\SELECT id, session_id, role, time_created, time_completed, status,
        \\       thinking_text, error_message
        \\FROM messages
        \\WHERE id = $1
    , .{message_id});

    if (row) |r| {
        return MessageRecord{
            .id = r.get([]const u8, 0),
            .session_id = r.get([]const u8, 1),
            .role = r.get([]const u8, 2),
            .time_created = r.get(i64, 3),
            .time_completed = r.get(?i64, 4),
            .status = r.get([]const u8, 5),
            .thinking_text = r.get(?[]const u8, 6),
            .error_message = r.get(?[]const u8, 7),
        };
    }
    return null;
}

pub fn createMessage(
    pool: *Pool,
    id: []const u8,
    session_id: []const u8,
    role: []const u8,
    status: []const u8,
    thinking_text: ?[]const u8,
    error_message: ?[]const u8,
) !void {
    const now = std.time.milliTimestamp();

    _ = try pool.exec(
        \\INSERT INTO messages (
        \\  id, session_id, role, time_created, status, thinking_text, error_message
        \\) VALUES ($1, $2, $3, $4, $5, $6, $7)
    , .{ id, session_id, role, now, status, thinking_text, error_message });
}

pub fn updateMessage(
    pool: *Pool,
    message_id: []const u8,
    status: ?[]const u8,
    thinking_text: ?[]const u8,
    error_message: ?[]const u8,
    time_completed: ?i64,
) !void {
    if (status) |s| {
        _ = try pool.exec(
            \\UPDATE messages SET status = $1 WHERE id = $2
        , .{ s, message_id });
    }

    if (thinking_text) |tt| {
        _ = try pool.exec(
            \\UPDATE messages SET thinking_text = $1 WHERE id = $2
        , .{ tt, message_id });
    }

    if (error_message) |em| {
        _ = try pool.exec(
            \\UPDATE messages SET error_message = $1 WHERE id = $2
        , .{ em, message_id });
    }

    if (time_completed) |tc| {
        _ = try pool.exec(
            \\UPDATE messages SET time_completed = $1 WHERE id = $2
        , .{ tc, message_id });
    }
}

pub fn deleteMessage(pool: *Pool, message_id: []const u8) !void {
    _ = try pool.exec(
        \\DELETE FROM messages WHERE id = $1
    , .{message_id});
}

// =============================================================================
// Part Operations
// =============================================================================

pub fn getMessageParts(pool: *Pool, allocator: std.mem.Allocator, message_id: []const u8) !std.ArrayList(PartRecord) {
    var parts = try std.ArrayList(PartRecord).initCapacity(allocator, 0);

    var result = try pool.query(
        \\SELECT id, session_id, message_id, type, text, tool_name,
        \\       tool_state::text, mime, url, filename, time_start, time_end, sort_order
        \\FROM parts
        \\WHERE message_id = $1
        \\ORDER BY sort_order ASC
    , .{message_id});
    defer result.deinit();

    while (try result.next()) |row| {
        try parts.append(allocator, PartRecord{
            .id = row.get([]const u8, 0),
            .session_id = row.get([]const u8, 1),
            .message_id = row.get([]const u8, 2),
            .type_ = row.get([]const u8, 3),
            .text = row.get(?[]const u8, 4),
            .tool_name = row.get(?[]const u8, 5),
            .tool_state = row.get(?[]const u8, 6),
            .mime = row.get(?[]const u8, 7),
            .url = row.get(?[]const u8, 8),
            .filename = row.get(?[]const u8, 9),
            .time_start = row.get(?i64, 10),
            .time_end = row.get(?i64, 11),
            .sort_order = row.get(i32, 12),
        });
    }

    return parts;
}

pub fn getPartById(pool: *Pool, part_id: []const u8) !?PartRecord {
    const row = try pool.row(
        \\SELECT id, session_id, message_id, type, text, tool_name,
        \\       tool_state::text, mime, url, filename, time_start, time_end, sort_order
        \\FROM parts
        \\WHERE id = $1
    , .{part_id});

    if (row) |r| {
        return PartRecord{
            .id = r.get([]const u8, 0),
            .session_id = r.get([]const u8, 1),
            .message_id = r.get([]const u8, 2),
            .type_ = r.get([]const u8, 3),
            .text = r.get(?[]const u8, 4),
            .tool_name = r.get(?[]const u8, 5),
            .tool_state = r.get(?[]const u8, 6),
            .mime = r.get(?[]const u8, 7),
            .url = r.get(?[]const u8, 8),
            .filename = r.get(?[]const u8, 9),
            .time_start = r.get(?i64, 10),
            .time_end = r.get(?i64, 11),
            .sort_order = r.get(i32, 12),
        };
    }
    return null;
}

pub fn createPart(
    pool: *Pool,
    id: []const u8,
    session_id: []const u8,
    message_id: []const u8,
    type_: []const u8,
    text: ?[]const u8,
    tool_name: ?[]const u8,
    tool_state: ?[]const u8,
    mime: ?[]const u8,
    url: ?[]const u8,
    filename: ?[]const u8,
    sort_order: i32,
    time_start: ?i64,
    time_end: ?i64,
) !void {
    _ = try pool.exec(
        \\INSERT INTO parts (
        \\  id, session_id, message_id, type, text, tool_name, tool_state,
        \\  mime, url, filename, sort_order, time_start, time_end
        \\) VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb, $8, $9, $10, $11, $12, $13)
    , .{ id, session_id, message_id, type_, text, tool_name, tool_state, mime, url, filename, sort_order, time_start, time_end });
}

pub fn updatePart(
    pool: *Pool,
    part_id: []const u8,
    text: ?[]const u8,
    tool_state: ?[]const u8,
    time_start: ?i64,
    time_end: ?i64,
) !void {
    if (text) |t| {
        _ = try pool.exec(
            \\UPDATE parts SET text = $1 WHERE id = $2
        , .{ t, part_id });
    }

    if (tool_state) |ts| {
        _ = try pool.exec(
            \\UPDATE parts SET tool_state = $1::jsonb WHERE id = $2
        , .{ ts, part_id });
    }

    if (time_start) |ts| {
        _ = try pool.exec(
            \\UPDATE parts SET time_start = $1 WHERE id = $2
        , .{ ts, part_id });
    }

    if (time_end) |te| {
        _ = try pool.exec(
            \\UPDATE parts SET time_end = $1 WHERE id = $2
        , .{ te, part_id });
    }
}

pub fn deletePart(pool: *Pool, part_id: []const u8) !void {
    _ = try pool.exec(
        \\DELETE FROM parts WHERE id = $1
    , .{part_id});
}
