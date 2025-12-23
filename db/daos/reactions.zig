//! Reactions Data Access Object
//!
//! SQL operations for the reactions table.

const std = @import("std");
const pg = @import("pg");

pub const Pool = pg.Pool;

// =============================================================================
// Types
// =============================================================================

pub const ReactionRecord = struct {
    id: i64,
    user_id: i64,
    username: []const u8,
    emoji: []const u8,
    created_at: i64,
};

// =============================================================================
// Operations
// =============================================================================

pub fn add(pool: *Pool, user_id: i64, target_type: []const u8, target_id: i64, emoji: []const u8) !?ReactionRecord {
    const row = try pool.row(
        \\INSERT INTO reactions (user_id, target_type, target_id, emoji)
        \\VALUES ($1, $2, $3, $4)
        \\ON CONFLICT (user_id, target_type, target_id, emoji) DO NOTHING
        \\RETURNING id, user_id, target_type, target_id, emoji, EXTRACT(EPOCH FROM created_at)::bigint
    , .{ user_id, target_type, target_id, emoji });

    if (row) |r| {
        // Get username
        const user_row = try pool.row(
            \\SELECT username FROM users WHERE id = $1
        , .{user_id});

        if (user_row) |ur| {
            return ReactionRecord{
                .id = r.get(i64, 0),
                .user_id = r.get(i64, 1),
                .username = ur.get([]const u8, 0),
                .emoji = r.get([]const u8, 4),
                .created_at = r.get(i64, 5),
            };
        }
    }
    return null;
}

pub fn remove(pool: *Pool, user_id: i64, target_type: []const u8, target_id: i64, emoji: []const u8) !void {
    _ = try pool.exec(
        \\DELETE FROM reactions
        \\WHERE user_id = $1 AND target_type = $2 AND target_id = $3 AND emoji = $4
    , .{ user_id, target_type, target_id, emoji });
}

pub fn getForTarget(pool: *Pool, allocator: std.mem.Allocator, target_type: []const u8, target_id: i64) ![]ReactionRecord {
    var conn = try pool.acquire();
    defer conn.release();

    var result = try conn.query(
        \\SELECT r.id, r.user_id, u.username, r.emoji, EXTRACT(EPOCH FROM r.created_at)::bigint
        \\FROM reactions r
        \\JOIN users u ON r.user_id = u.id
        \\WHERE r.target_type = $1 AND r.target_id = $2
        \\ORDER BY r.created_at ASC
    , .{ target_type, target_id });
    defer result.deinit();

    var reactions: std.ArrayList(ReactionRecord) = .{};
    while (try result.next()) |row| {
        try reactions.append(allocator, ReactionRecord{
            .id = row.get(i64, 0),
            .user_id = row.get(i64, 1),
            .username = row.get([]const u8, 2),
            .emoji = row.get([]const u8, 3),
            .created_at = row.get(i64, 4),
        });
    }

    return try reactions.toOwnedSlice(allocator);
}
