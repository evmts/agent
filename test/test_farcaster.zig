const std = @import("std");
const testing = std.testing;
const farcaster = @import("farcaster");

// Mock HTTP responses for testing
const mock_casts_response = 
    \\{
    \\  "messages": [
    \\    {
    \\      "hash": "0x1234567890abcdef",
    \\      "data": {
    \\        "fid": 12345,
    \\        "timestamp": 1234567890,
    \\        "castAddBody": {
    \\          "text": "Hello, Farcaster!",
    \\          "parentUrl": "https://farcaster.group/test"
    \\        }
    \\      }
    \\    }
    \\  ]
    \\}
;

const mock_user_data_response = 
    \\{
    \\  "messages": [
    \\    {
    \\      "data": {
    \\        "fid": 12345,
    \\        "userDataBody": {
    \\          "type": "USER_DATA_TYPE_USERNAME",
    \\          "value": "testuser"
    \\        }
    \\      }
    \\    },
    \\    {
    \\      "data": {
    \\        "fid": 12345,
    \\        "userDataBody": {
    \\          "type": "USER_DATA_TYPE_DISPLAY",
    \\          "value": "Test User"
    \\        }
    \\      }
    \\    }
    \\  ]
    \\}
;

test "FarcasterClient initialization with test private key" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 64 bytes = 128 hex characters (this is not a valid Ed25519 key, so should fail)
    const test_private_key = "1234567890abcdef" ** 8; // 128 chars
    
    // This test key should fail - we're testing error handling
    const result = farcaster.FarcasterClient.init(allocator, 12345, test_private_key);
    try testing.expectError(error.NonCanonical, result);
}

test "FarcasterClient initialization with invalid private key" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const invalid_key = "invalid_key";
    
    const result = farcaster.FarcasterClient.init(allocator, 12345, invalid_key);
    try testing.expectError(farcaster.FarcasterError.InvalidMessage, result);
}

test "MessageType enum values" {
    try testing.expectEqual(@as(u8, 1), @intFromEnum(farcaster.MessageType.cast_add));
    try testing.expectEqual(@as(u8, 2), @intFromEnum(farcaster.MessageType.cast_remove));
    try testing.expectEqual(@as(u8, 3), @intFromEnum(farcaster.MessageType.reaction_add));
    try testing.expectEqual(@as(u8, 4), @intFromEnum(farcaster.MessageType.reaction_remove));
}

test "ReactionType enum values" {
    try testing.expectEqual(@as(u8, 1), @intFromEnum(farcaster.ReactionType.like));
    try testing.expectEqual(@as(u8, 2), @intFromEnum(farcaster.ReactionType.recast));
}

test "UserDataType enum values" {
    try testing.expectEqual(@as(u8, 1), @intFromEnum(farcaster.UserDataType.pfp));
    try testing.expectEqual(@as(u8, 2), @intFromEnum(farcaster.UserDataType.display));
    try testing.expectEqual(@as(u8, 3), @intFromEnum(farcaster.UserDataType.bio));
    try testing.expectEqual(@as(u8, 6), @intFromEnum(farcaster.UserDataType.username));
}

test "FarcasterUser struct creation" {
    const user = farcaster.FarcasterUser{
        .fid = 12345,
        .username = "testuser",
        .display_name = "Test User",
        .bio = "Test bio",
        .pfp_url = "https://example.com/pfp.jpg",
        .follower_count = 100,
        .following_count = 50,
    };

    try testing.expectEqual(@as(u64, 12345), user.fid);
    try testing.expectEqualStrings("testuser", user.username);
    try testing.expectEqualStrings("Test User", user.display_name);
    try testing.expectEqual(@as(u32, 100), user.follower_count);
}

test "FarcasterCast struct creation" {
    const author = farcaster.FarcasterUser{
        .fid = 12345,
        .username = "testuser",
        .display_name = "Test User",
        .bio = "",
        .pfp_url = "",
        .follower_count = 0,
        .following_count = 0,
    };

    const cast = farcaster.FarcasterCast{
        .hash = "0x1234567890abcdef",
        .parent_hash = null,
        .parent_url = "https://farcaster.group/test",
        .author = author,
        .text = "Hello, Farcaster!",
        .timestamp = 1234567890,
        .mentions = &[_]u64{},
        .replies_count = 0,
        .reactions_count = 5,
        .recasts_count = 2,
    };

    try testing.expectEqualStrings("0x1234567890abcdef", cast.hash);
    try testing.expectEqualStrings("Hello, Farcaster!", cast.text);
    try testing.expectEqual(@as(u32, 5), cast.reactions_count);
}

test "MessageData struct creation for cast" {
    const cast_body = farcaster.CastAddBody{
        .text = "Test cast",
        .mentions = &[_]u64{},
        .mentions_positions = &[_]u64{},
        .embeds = &[_][]const u8{},
        .parent_cast_id = null,
        .parent_url = "https://farcaster.group/test",
    };

    const message_data = farcaster.MessageData{
        .type = .cast_add,
        .fid = 12345,
        .timestamp = 1234567890,
        .network = 1,
        .body = .{ .cast_add = cast_body },
    };

    try testing.expectEqual(farcaster.MessageType.cast_add, message_data.type);
    try testing.expectEqual(@as(u64, 12345), message_data.fid);
    try testing.expectEqual(@as(u8, 1), message_data.network);
    try testing.expectEqualStrings("Test cast", message_data.body.cast_add.text);
}

// C API tests commented out - exported functions are not accessible from Zig tests
// test "C API client creation and destruction" {
//     const test_fid: u64 = 12345;
//     const test_key = "1234567890abcdef" ** 8; // 128 chars
//     
//     // This will likely fail due to invalid key format, but test the API
//     const client = farcaster.fc_client_create(test_fid, test_key.ptr);
//     if (client) |c| {
//         farcaster.fc_client_destroy(c);
//     }
//     // If client is null due to invalid key, that's expected behavior
// }

// test "C API post cast with null client" {
//     const result = farcaster.fc_post_cast(null, "Test message", "");
//     try testing.expectEqualStrings("ERROR: null client", std.mem.span(result));
// }

// test "C API like cast with null client" {
//     const result = farcaster.fc_like_cast(null, "0x1234", 12345);
//     try testing.expectEqualStrings("ERROR: null client", std.mem.span(result));
// }

// test "C API get casts by channel with null client" {
//     const result = farcaster.fc_get_casts_by_channel(null, "https://farcaster.group/test", 10);
//     try testing.expectEqualStrings("ERROR: null client", std.mem.span(result));
// }

test "FarcasterChannel struct creation" {
    const channel = farcaster.FarcasterChannel{
        .id = "test",
        .url = "https://farcaster.group/test",
        .name = "Test Channel",
        .description = "A test channel",
        .image_url = "https://example.com/image.jpg",
        .creator_fid = 12345,
        .follower_count = 1000,
    };

    try testing.expectEqualStrings("test", channel.id);
    try testing.expectEqualStrings("Test Channel", channel.name);
    try testing.expectEqual(@as(u64, 12345), channel.creator_fid);
    try testing.expectEqual(@as(u32, 1000), channel.follower_count);
}

test "CastId struct creation" {
    const cast_id = farcaster.CastId{
        .fid = 12345,
        .hash = "0x1234567890abcdef",
    };

    try testing.expectEqual(@as(u64, 12345), cast_id.fid);
    try testing.expectEqualStrings("0x1234567890abcdef", cast_id.hash);
}

test "ReactionAddBody struct creation" {
    const cast_id = farcaster.CastId{
        .fid = 12345,
        .hash = "0x1234567890abcdef",
    };

    const reaction_body = farcaster.ReactionAddBody{
        .type = .like,
        .target_cast_id = cast_id,
        .target_url = null,
    };

    try testing.expectEqual(farcaster.ReactionType.like, reaction_body.type);
    try testing.expect(reaction_body.target_cast_id != null);
    try testing.expectEqual(@as(u64, 12345), reaction_body.target_cast_id.?.fid);
}

test "Memory management with multiple structs" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create multiple users and casts to test memory handling
    var users = std.ArrayList(farcaster.FarcasterUser).init(allocator);
    defer users.deinit();

    for (0..10) |i| {
        const username = try std.fmt.allocPrint(allocator, "user{d}", .{i});
        defer allocator.free(username);

        const user = farcaster.FarcasterUser{
            .fid = i,
            .username = try allocator.dupe(u8, username),
            .display_name = try allocator.dupe(u8, username),
            .bio = "",
            .pfp_url = "",
            .follower_count = @intCast(i * 10),
            .following_count = @intCast(i * 5),
        };

        try users.append(user);
    }

    // Clean up allocated strings
    for (users.items) |user| {
        allocator.free(user.username);
        allocator.free(user.display_name);
    }
}