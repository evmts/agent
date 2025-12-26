//! Landing Queue Data Access Object
//!
//! SQL operations for landing_queue and landing_line_comments tables.

const std = @import("std");
const pg = @import("pg");
const root = @import("../root.zig");

pub const Pool = pg.Pool;

// =============================================================================
// Types
// =============================================================================

pub const LandingRequest = struct {
    id: i64,
    repository_id: i64,
    change_id: []const u8,
    target_bookmark: []const u8,
    title: ?[]const u8,
    description: ?[]const u8,
    author_id: i64,
    status: []const u8,
    has_conflicts: bool,
    conflicted_files: ?[]const u8,
    created_at: i64,
    updated_at: i64,
    landed_at: ?i64,
    landed_by: ?i64,
    landed_change_id: ?[]const u8,
};

pub const LineComment = struct {
    id: i64,
    landing_id: i64,
    author_id: i64,
    file_path: []const u8,
    line_number: i32,
    side: []const u8,
    body: []const u8,
    resolved: bool,
    created_at: i64,
    updated_at: i64,
};

// =============================================================================
// Landing Request Operations
// =============================================================================

pub fn list(
    pool: *Pool,
    allocator: std.mem.Allocator,
    repository_id: i64,
    status_filter: ?[]const u8,
    limit: i32,
    offset: i32,
) ![]LandingRequest {
    var conn = try pool.acquire();
    defer conn.release();

    var result = if (status_filter) |status|
        try conn.query(
            \\SELECT id, repository_id, change_id, target_bookmark, title, description,
            \\       author_id, status, has_conflicts, conflicted_files::text,
            \\       EXTRACT(EPOCH FROM created_at)::bigint * 1000 as created_at,
            \\       EXTRACT(EPOCH FROM updated_at)::bigint * 1000 as updated_at,
            \\       EXTRACT(EPOCH FROM landed_at)::bigint * 1000 as landed_at,
            \\       landed_by, landed_change_id
            \\FROM landing_queue
            \\WHERE repository_id = $1 AND status = $2
            \\ORDER BY created_at DESC
            \\LIMIT $3 OFFSET $4
        , .{ repository_id, status, limit, offset })
    else
        try conn.query(
            \\SELECT id, repository_id, change_id, target_bookmark, title, description,
            \\       author_id, status, has_conflicts, conflicted_files::text,
            \\       EXTRACT(EPOCH FROM created_at)::bigint * 1000 as created_at,
            \\       EXTRACT(EPOCH FROM updated_at)::bigint * 1000 as updated_at,
            \\       EXTRACT(EPOCH FROM landed_at)::bigint * 1000 as landed_at,
            \\       landed_by, landed_change_id
            \\FROM landing_queue
            \\WHERE repository_id = $1
            \\ORDER BY created_at DESC
            \\LIMIT $2 OFFSET $3
        , .{ repository_id, limit, offset });
    defer result.deinit();

    var requests = std.ArrayList(LandingRequest){};
    errdefer requests.deinit(allocator);

    while (try result.next()) |row| {
        try requests.append(allocator, LandingRequest{
            .id = row.get(i64, 0),
            .repository_id = row.get(i64, 1),
            .change_id = row.get([]const u8, 2),
            .target_bookmark = row.get([]const u8, 3),
            .title = row.get(?[]const u8, 4),
            .description = row.get(?[]const u8, 5),
            .author_id = row.get(i64, 6),
            .status = row.get([]const u8, 7),
            .has_conflicts = row.get(bool, 8),
            .conflicted_files = row.get(?[]const u8, 9),
            .created_at = row.get(i64, 10),
            .updated_at = row.get(i64, 11),
            .landed_at = row.get(?i64, 12),
            .landed_by = row.get(?i64, 13),
            .landed_change_id = row.get(?[]const u8, 14),
        });
    }

    return try requests.toOwnedSlice(allocator);
}

pub fn getById(pool: *Pool, repository_id: i64, landing_id: i64) !?LandingRequest {
    const row = try pool.row(
        \\SELECT id, repository_id, change_id, target_bookmark, title, description,
        \\       author_id, status, has_conflicts, conflicted_files::text,
        \\       EXTRACT(EPOCH FROM created_at)::bigint * 1000 as created_at,
        \\       EXTRACT(EPOCH FROM updated_at)::bigint * 1000 as updated_at,
        \\       EXTRACT(EPOCH FROM landed_at)::bigint * 1000 as landed_at,
        \\       landed_by, landed_change_id
        \\FROM landing_queue
        \\WHERE repository_id = $1 AND id = $2
    , .{ repository_id, landing_id });

    if (row) |r| {
        return LandingRequest{
            .id = r.get(i64, 0),
            .repository_id = r.get(i64, 1),
            .change_id = r.get([]const u8, 2),
            .target_bookmark = r.get([]const u8, 3),
            .title = r.get(?[]const u8, 4),
            .description = r.get(?[]const u8, 5),
            .author_id = r.get(i64, 6),
            .status = r.get([]const u8, 7),
            .has_conflicts = r.get(bool, 8),
            .conflicted_files = r.get(?[]const u8, 9),
            .created_at = r.get(i64, 10),
            .updated_at = r.get(i64, 11),
            .landed_at = r.get(?i64, 12),
            .landed_by = r.get(?i64, 13),
            .landed_change_id = r.get(?[]const u8, 14),
        };
    }
    return null;
}

pub fn findByChangeId(pool: *Pool, repository_id: i64, change_id: []const u8) !?LandingRequest {
    const row = try pool.row(
        \\SELECT id, repository_id, change_id, target_bookmark, title, description,
        \\       author_id, status, has_conflicts, conflicted_files::text,
        \\       EXTRACT(EPOCH FROM created_at)::bigint * 1000 as created_at,
        \\       EXTRACT(EPOCH FROM updated_at)::bigint * 1000 as updated_at,
        \\       EXTRACT(EPOCH FROM landed_at)::bigint * 1000 as landed_at,
        \\       landed_by, landed_change_id
        \\FROM landing_queue
        \\WHERE repository_id = $1 AND change_id = $2 AND status NOT IN ('landed', 'cancelled')
    , .{ repository_id, change_id });

    if (row) |r| {
        return LandingRequest{
            .id = r.get(i64, 0),
            .repository_id = r.get(i64, 1),
            .change_id = r.get([]const u8, 2),
            .target_bookmark = r.get([]const u8, 3),
            .title = r.get(?[]const u8, 4),
            .description = r.get(?[]const u8, 5),
            .author_id = r.get(i64, 6),
            .status = r.get([]const u8, 7),
            .has_conflicts = r.get(bool, 8),
            .conflicted_files = r.get(?[]const u8, 9),
            .created_at = r.get(i64, 10),
            .updated_at = r.get(i64, 11),
            .landed_at = r.get(?i64, 12),
            .landed_by = r.get(?i64, 13),
            .landed_change_id = r.get(?[]const u8, 14),
        };
    }
    return null;
}

// =============================================================================
// Line Comment Operations
// =============================================================================

pub fn getLineCommentById(pool: *Pool, comment_id: i64) !?LineComment {
    const row = try pool.row(
        \\SELECT id, landing_id, author_id, file_path, line_number, side, body, resolved,
        \\       EXTRACT(EPOCH FROM created_at)::bigint * 1000 as created_at,
        \\       EXTRACT(EPOCH FROM updated_at)::bigint * 1000 as updated_at
        \\FROM landing_line_comments
        \\WHERE id = $1
    , .{comment_id});

    if (row) |r| {
        return LineComment{
            .id = r.get(i64, 0),
            .landing_id = r.get(i64, 1),
            .author_id = r.get(i64, 2),
            .file_path = r.get([]const u8, 3),
            .line_number = r.get(i32, 4),
            .side = r.get([]const u8, 5),
            .body = r.get([]const u8, 6),
            .resolved = r.get(bool, 7),
            .created_at = r.get(i64, 8),
            .updated_at = r.get(i64, 9),
        };
    }
    return null;
}

pub fn getLineComments(pool: *Pool, allocator: std.mem.Allocator, landing_id: i64) ![]LineComment {
    var conn = try pool.acquire();
    defer conn.release();

    var result = try conn.query(
        \\SELECT id, landing_id, author_id, file_path, line_number, side, body, resolved,
        \\       EXTRACT(EPOCH FROM created_at)::bigint * 1000 as created_at,
        \\       EXTRACT(EPOCH FROM updated_at)::bigint * 1000 as updated_at
        \\FROM landing_line_comments
        \\WHERE landing_id = $1
        \\ORDER BY created_at ASC
    , .{landing_id});
    defer result.deinit();

    var comments = std.ArrayList(LineComment){};
    errdefer comments.deinit(allocator);

    while (try result.next()) |row| {
        try comments.append(allocator, LineComment{
            .id = row.get(i64, 0),
            .landing_id = row.get(i64, 1),
            .author_id = row.get(i64, 2),
            .file_path = row.get([]const u8, 3),
            .line_number = row.get(i32, 4),
            .side = row.get([]const u8, 5),
            .body = row.get([]const u8, 6),
            .resolved = row.get(bool, 7),
            .created_at = row.get(i64, 8),
            .updated_at = row.get(i64, 9),
        });
    }

    return try comments.toOwnedSlice(allocator);
}

pub fn createLineComment(
    pool: *Pool,
    landing_id: i64,
    author_id: i64,
    file_path: []const u8,
    line_number: i32,
    side: []const u8,
    body: []const u8,
) !LineComment {
    const row = try pool.row(
        \\INSERT INTO landing_line_comments (landing_id, author_id, file_path, line_number, side, body)
        \\VALUES ($1, $2, $3, $4, $5, $6)
        \\RETURNING id, landing_id, author_id, file_path, line_number, side, body, resolved,
        \\          EXTRACT(EPOCH FROM created_at)::bigint * 1000 as created_at,
        \\          EXTRACT(EPOCH FROM updated_at)::bigint * 1000 as updated_at
    , .{ landing_id, author_id, file_path, line_number, side, body });

    if (row) |r| {
        return LineComment{
            .id = r.get(i64, 0),
            .landing_id = r.get(i64, 1),
            .author_id = r.get(i64, 2),
            .file_path = r.get([]const u8, 3),
            .line_number = r.get(i32, 4),
            .side = r.get([]const u8, 5),
            .body = r.get([]const u8, 6),
            .resolved = r.get(bool, 7),
            .created_at = r.get(i64, 8),
            .updated_at = r.get(i64, 9),
        };
    }
    return error.InsertFailed;
}

pub fn updateLineComment(pool: *Pool, comment_id: i64, body: ?[]const u8, resolved: ?bool) !LineComment {
    // Build a single UPDATE statement to avoid race conditions
    // This ensures atomicity without needing an explicit transaction
    if (body != null and resolved != null) {
        // Update both fields in a single query
        _ = try pool.exec(
            \\UPDATE landing_line_comments
            \\SET body = $2, resolved = $3, updated_at = NOW()
            \\WHERE id = $1
        , .{ comment_id, body.?, resolved.? });
    } else if (body) |b| {
        _ = try pool.exec(
            \\UPDATE landing_line_comments SET body = $2, updated_at = NOW() WHERE id = $1
        , .{ comment_id, b });
    } else if (resolved) |r| {
        _ = try pool.exec(
            \\UPDATE landing_line_comments SET resolved = $2, updated_at = NOW() WHERE id = $1
        , .{ comment_id, r });
    }

    const row = try pool.row(
        \\SELECT id, landing_id, author_id, file_path, line_number, side, body, resolved,
        \\       EXTRACT(EPOCH FROM created_at)::bigint * 1000 as created_at,
        \\       EXTRACT(EPOCH FROM updated_at)::bigint * 1000 as updated_at
        \\FROM landing_line_comments
        \\WHERE id = $1
    , .{comment_id});

    if (row) |r| {
        return LineComment{
            .id = r.get(i64, 0),
            .landing_id = r.get(i64, 1),
            .author_id = r.get(i64, 2),
            .file_path = r.get([]const u8, 3),
            .line_number = r.get(i32, 4),
            .side = r.get([]const u8, 5),
            .body = r.get([]const u8, 6),
            .resolved = r.get(bool, 7),
            .created_at = r.get(i64, 8),
            .updated_at = r.get(i64, 9),
        };
    }
    return error.NotFound;
}

pub fn deleteLineComment(pool: *Pool, comment_id: i64) !void {
    _ = try pool.exec(
        \\DELETE FROM landing_line_comments WHERE id = $1
    , .{comment_id});
}

// =============================================================================
// Landing Request CRUD
// =============================================================================

pub fn count(pool: *Pool, repository_id: i64, status_filter: ?[]const u8) !i64 {
    const row = if (status_filter) |status|
        try pool.row(
            \\SELECT COUNT(*) FROM landing_queue
            \\WHERE repository_id = $1 AND status = $2
        , .{ repository_id, status })
    else
        try pool.row(
            \\SELECT COUNT(*) FROM landing_queue
            \\WHERE repository_id = $1
        , .{repository_id});

    if (row) |r| {
        return r.get(i64, 0);
    }
    return 0;
}

pub fn create(
    pool: *Pool,
    repository_id: i64,
    change_id: []const u8,
    target_bookmark: []const u8,
    title: ?[]const u8,
    description: ?[]const u8,
    author_id: i64,
) !LandingRequest {
    const row = try pool.row(
        \\INSERT INTO landing_queue (repository_id, change_id, target_bookmark, title, description, author_id, status)
        \\VALUES ($1, $2, $3, $4, $5, $6, 'pending')
        \\RETURNING id, repository_id, change_id, target_bookmark, title, description,
        \\          author_id, status, has_conflicts, conflicted_files::text,
        \\          EXTRACT(EPOCH FROM created_at)::bigint * 1000 as created_at,
        \\          EXTRACT(EPOCH FROM updated_at)::bigint * 1000 as updated_at,
        \\          EXTRACT(EPOCH FROM landed_at)::bigint * 1000 as landed_at,
        \\          landed_by, landed_change_id
    , .{ repository_id, change_id, target_bookmark, title, description, author_id });

    if (row) |r| {
        return LandingRequest{
            .id = r.get(i64, 0),
            .repository_id = r.get(i64, 1),
            .change_id = r.get([]const u8, 2),
            .target_bookmark = r.get([]const u8, 3),
            .title = r.get(?[]const u8, 4),
            .description = r.get(?[]const u8, 5),
            .author_id = r.get(i64, 6),
            .status = r.get([]const u8, 7),
            .has_conflicts = r.get(bool, 8),
            .conflicted_files = r.get(?[]const u8, 9),
            .created_at = r.get(i64, 10),
            .updated_at = r.get(i64, 11),
            .landed_at = r.get(?i64, 12),
            .landed_by = r.get(?i64, 13),
            .landed_change_id = r.get(?[]const u8, 14),
        };
    }
    return error.InsertFailed;
}

pub fn updateStatus(pool: *Pool, landing_id: i64, status: []const u8) !void {
    _ = try pool.exec(
        \\UPDATE landing_queue SET status = $2, updated_at = NOW() WHERE id = $1
    , .{ landing_id, status });
}

pub fn updateConflicts(pool: *Pool, landing_id: i64, has_conflicts: bool, conflicted_files: []const []const u8) !void {
    // Convert files to JSON array
    var json_buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&json_buf);
    var writer = stream.writer();

    try writer.writeByte('[');
    for (conflicted_files, 0..) |file, i| {
        if (i > 0) try writer.writeByte(',');
        try root.writeJsonString(writer, file);
    }
    try writer.writeByte(']');

    const json_str = stream.getWritten();

    _ = try pool.exec(
        \\UPDATE landing_queue
        \\SET has_conflicts = $2, conflicted_files = $3::jsonb, updated_at = NOW()
        \\WHERE id = $1
    , .{ landing_id, has_conflicts, json_str });
}

pub fn markLanded(pool: *Pool, landing_id: i64, landed_by: i64, landed_change_id: []const u8) !void {
    _ = try pool.exec(
        \\UPDATE landing_queue
        \\SET status = 'landed', landed_at = NOW(), landed_by = $2, landed_change_id = $3, updated_at = NOW()
        \\WHERE id = $1
    , .{ landing_id, landed_by, landed_change_id });
}

// =============================================================================
// Landing Reviews
// =============================================================================

pub const LandingReview = struct {
    id: i64,
    landing_id: i64,
    reviewer_id: i64,
    review_type: []const u8,
    content: ?[]const u8,
    change_id: []const u8,
    created_at: i64,
};

pub fn getReviews(pool: *Pool, allocator: std.mem.Allocator, landing_id: i64) ![]LandingReview {
    var conn = try pool.acquire();
    defer conn.release();

    var result = try conn.query(
        \\SELECT id, landing_id, reviewer_id, review_type, content, change_id,
        \\       EXTRACT(EPOCH FROM created_at)::bigint * 1000 as created_at
        \\FROM landing_reviews
        \\WHERE landing_id = $1
        \\ORDER BY created_at ASC
    , .{landing_id});
    defer result.deinit();

    var reviews = std.ArrayList(LandingReview){};
    errdefer reviews.deinit(allocator);

    while (try result.next()) |row| {
        try reviews.append(allocator, LandingReview{
            .id = row.get(i64, 0),
            .landing_id = row.get(i64, 1),
            .reviewer_id = row.get(i64, 2),
            .review_type = row.get([]const u8, 3),
            .content = row.get(?[]const u8, 4),
            .change_id = row.get([]const u8, 5),
            .created_at = row.get(i64, 6),
        });
    }

    return try reviews.toOwnedSlice(allocator);
}

pub fn createReview(
    pool: *Pool,
    landing_id: i64,
    reviewer_id: i64,
    review_type: []const u8,
    content: ?[]const u8,
    change_id: []const u8,
) !LandingReview {
    const row = try pool.row(
        \\INSERT INTO landing_reviews (landing_id, reviewer_id, review_type, content, change_id)
        \\VALUES ($1, $2, $3, $4, $5)
        \\RETURNING id, landing_id, reviewer_id, review_type, content, change_id,
        \\          EXTRACT(EPOCH FROM created_at)::bigint * 1000 as created_at
    , .{ landing_id, reviewer_id, review_type, content, change_id });

    if (row) |r| {
        return LandingReview{
            .id = r.get(i64, 0),
            .landing_id = r.get(i64, 1),
            .reviewer_id = r.get(i64, 2),
            .review_type = r.get([]const u8, 3),
            .content = r.get(?[]const u8, 4),
            .change_id = r.get([]const u8, 5),
            .created_at = r.get(i64, 6),
        };
    }
    return error.InsertFailed;
}
