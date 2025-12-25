//! Mentions Data Access Object
//!
//! SQL operations for tracking @mentions in issues and comments.

const std = @import("std");
const pg = @import("pg");

pub const Pool = pg.Pool;

// =============================================================================
// Mention Extraction
// =============================================================================

/// Extract unique @username mentions from text
/// Returns lowercase usernames (case-insensitive matching)
pub fn extractMentions(allocator: std.mem.Allocator, text: []const u8) ![][]const u8 {
    var mentions: std.ArrayList([]const u8) = .{};
    errdefer {
        for (mentions.items) |mention| {
            allocator.free(mention);
        }
        mentions.deinit(allocator);
    }

    var seen = std.StringHashMap(void).init(allocator);
    defer seen.deinit();

    var i: usize = 0;
    while (i < text.len) {
        // Look for '@' character
        if (text[i] == '@') {
            i += 1;
            const start = i;

            // Extract username: alphanumeric, underscore, hyphen (1-39 chars, GitHub-style)
            var len: usize = 0;
            while (i < text.len and len < 39) : (i += 1) {
                const c = text[i];
                if ((c >= 'a' and c <= 'z') or
                    (c >= 'A' and c <= 'Z') or
                    (c >= '0' and c <= '9') or
                    c == '_' or
                    c == '-')
                {
                    len += 1;
                } else {
                    break;
                }
            }

            // If we found a valid username (at least 1 char)
            if (len > 0) {
                const username = text[start .. start + len];

                // Convert to lowercase for deduplication
                const lower = try std.ascii.allocLowerString(allocator, username);
                errdefer allocator.free(lower);

                // Only add if not already seen
                if (!seen.contains(lower)) {
                    try seen.put(lower, {});
                    try mentions.append(allocator, lower);
                } else {
                    allocator.free(lower);
                }
            }
        } else {
            i += 1;
        }
    }

    return try mentions.toOwnedSlice(allocator);
}

// =============================================================================
// Database Operations
// =============================================================================

/// Save mentions from issue body to database
/// Extracts @usernames, looks up user IDs, and inserts into mentions table
pub fn saveMentionsForIssue(
    pool: *Pool,
    allocator: std.mem.Allocator,
    repository_id: i64,
    issue_number: i64,
    body_text: ?[]const u8,
) !void {
    const text = body_text orelse return;

    // Extract mentions
    const usernames = try extractMentions(allocator, text);
    defer {
        for (usernames) |username| {
            allocator.free(username);
        }
        allocator.free(usernames);
    }

    if (usernames.len == 0) return;

    // Get connection for transaction
    var conn = try pool.acquire();
    defer conn.release();

    // Look up user IDs for mentioned usernames
    // We need to query for each username individually since pg doesn't support ANY with array
    for (usernames) |username| {
        var user_result = try conn.query(
            \\SELECT id FROM users
            \\WHERE lower_username = $1
            \\  AND is_active = true
            \\  AND prohibit_login = false
        , .{username});
        defer user_result.deinit();

        // Insert mention for each found user
        while (try user_result.next()) |row| {
            const user_id = row.get(i64, 0);

            // Insert mention (ON CONFLICT DO NOTHING)
            _ = conn.exec(
                \\INSERT INTO mentions (repository_id, issue_number, comment_id, mentioned_user_id)
                \\VALUES ($1, $2, NULL, $3)
                \\ON CONFLICT DO NOTHING
            , .{ repository_id, issue_number, user_id }) catch |err| {
                // Ignore duplicate/constraint errors, log others
                if (err != error.PostgresError) {
                    return err;
                }
            };
        }
    }
}

/// Save mentions from comment body to database
/// Extracts @usernames, looks up user IDs, and inserts into mentions table
pub fn saveMentionsForComment(
    pool: *Pool,
    allocator: std.mem.Allocator,
    repository_id: i64,
    issue_number: i64,
    comment_id: i64,
    body_text: []const u8,
) !void {
    // Extract mentions
    const usernames = try extractMentions(allocator, body_text);
    defer {
        for (usernames) |username| {
            allocator.free(username);
        }
        allocator.free(usernames);
    }

    if (usernames.len == 0) return;

    // Get connection for transaction
    var conn = try pool.acquire();
    defer conn.release();

    // Convert comment_id to string (stored as VARCHAR(10) in DB)
    var comment_id_buf: [20]u8 = undefined;
    const comment_id_str = try std.fmt.bufPrint(&comment_id_buf, "{d}", .{comment_id});

    // Look up user IDs for mentioned usernames
    for (usernames) |username| {
        var user_result = try conn.query(
            \\SELECT id FROM users
            \\WHERE lower_username = $1
            \\  AND is_active = true
            \\  AND prohibit_login = false
        , .{username});
        defer user_result.deinit();

        // Insert mention for each found user
        while (try user_result.next()) |row| {
            const user_id = row.get(i64, 0);

            // Insert mention (ON CONFLICT DO NOTHING)
            _ = conn.exec(
                \\INSERT INTO mentions (repository_id, issue_number, comment_id, mentioned_user_id)
                \\VALUES ($1, $2, $3, $4)
                \\ON CONFLICT DO NOTHING
            , .{ repository_id, issue_number, comment_id_str, user_id }) catch |err| {
                // Ignore duplicate/constraint errors, log others
                if (err != error.PostgresError) {
                    return err;
                }
            };
        }
    }
}

// =============================================================================
// Tests
// =============================================================================

test "extractMentions - basic" {
    const allocator = std.testing.allocator;

    const text = "Hey @alice and @bob, check this out!";
    const mentions = try extractMentions(allocator, text);
    defer {
        for (mentions) |m| allocator.free(m);
        allocator.free(mentions);
    }

    try std.testing.expectEqual(@as(usize, 2), mentions.len);
    try std.testing.expectEqualStrings("alice", mentions[0]);
    try std.testing.expectEqualStrings("bob", mentions[1]);
}

test "extractMentions - duplicates" {
    const allocator = std.testing.allocator;

    const text = "@alice @bob @alice @bob";
    const mentions = try extractMentions(allocator, text);
    defer {
        for (mentions) |m| allocator.free(m);
        allocator.free(mentions);
    }

    try std.testing.expectEqual(@as(usize, 2), mentions.len);
}

test "extractMentions - case insensitive" {
    const allocator = std.testing.allocator;

    const text = "@Alice @ALICE @alice";
    const mentions = try extractMentions(allocator, text);
    defer {
        for (mentions) |m| allocator.free(m);
        allocator.free(mentions);
    }

    try std.testing.expectEqual(@as(usize, 1), mentions.len);
    try std.testing.expectEqualStrings("alice", mentions[0]);
}

test "extractMentions - valid characters" {
    const allocator = std.testing.allocator;

    const text = "@user_name @user-name @user123";
    const mentions = try extractMentions(allocator, text);
    defer {
        for (mentions) |m| allocator.free(m);
        allocator.free(mentions);
    }

    try std.testing.expectEqual(@as(usize, 3), mentions.len);
    try std.testing.expectEqualStrings("user_name", mentions[0]);
    try std.testing.expectEqualStrings("user-name", mentions[1]);
    try std.testing.expectEqualStrings("user123", mentions[2]);
}

test "extractMentions - no mentions" {
    const allocator = std.testing.allocator;

    const text = "No mentions here";
    const mentions = try extractMentions(allocator, text);
    defer allocator.free(mentions);

    try std.testing.expectEqual(@as(usize, 0), mentions.len);
}

test "extractMentions - empty string" {
    const allocator = std.testing.allocator;

    const mentions = try extractMentions(allocator, "");
    defer allocator.free(mentions);

    try std.testing.expectEqual(@as(usize, 0), mentions.len);
}
