const std = @import("std");
const json = std.json;
const http = std.http;
const crypto = std.crypto;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

// Farcaster SDK for Zig
// Based on Farcaster Hub HTTP API and protocol specifications
// Hub: Pinata (hub.pinata.cloud) - free, reliable, no auth required

// ===== Core Types =====

pub const FarcasterError = error{
    HttpError,
    JsonParseError,
    SigningError,
    InvalidMessage,
    NetworkError,
    OutOfMemory,
};

pub const MessageType = enum(u8) {
    cast_add = 1,
    cast_remove = 2,
    reaction_add = 3,
    reaction_remove = 4,
    link_add = 5,
    link_remove = 6,
    user_data_add = 11,
    user_data_remove = 12,
};

pub const ReactionType = enum(u8) {
    like = 1,
    recast = 2,
};

pub const UserDataType = enum(u8) {
    pfp = 1,
    display = 2,
    bio = 3,
    url = 5,
    username = 6,
};

pub const LinkType = enum(u8) {
    follow = 1,
    unfollow = 2,
};

// Core Farcaster structures
pub const FarcasterUser = struct {
    fid: u64,
    username: []const u8,
    display_name: []const u8,
    bio: []const u8,
    pfp_url: []const u8,
    follower_count: u32,
    following_count: u32,
};

pub const FarcasterCast = struct {
    hash: []const u8,
    parent_hash: ?[]const u8,
    parent_url: ?[]const u8, // For channels
    author: FarcasterUser,
    text: []const u8,
    timestamp: u64,
    mentions: []u64,
    replies_count: u32,
    reactions_count: u32,
    recasts_count: u32,
};

pub const FarcasterReaction = struct {
    type: ReactionType,
    reactor: FarcasterUser,
    target_cast_hash: []const u8,
    timestamp: u64,
};

pub const FarcasterChannel = struct {
    id: []const u8,
    url: []const u8,
    name: []const u8,
    description: []const u8,
    image_url: []const u8,
    creator_fid: u64,
    follower_count: u32,
};

// Message structures for API communication
pub const MessageData = struct {
    type: MessageType,
    fid: u64,
    timestamp: u64,
    network: u8, // 1 = mainnet
    body: union(MessageType) {
        cast_add: CastAddBody,
        cast_remove: CastRemoveBody,
        reaction_add: ReactionAddBody,
        reaction_remove: ReactionRemoveBody,
        link_add: LinkAddBody,
        link_remove: LinkRemoveBody,
        user_data_add: UserDataAddBody,
        user_data_remove: UserDataRemoveBody,
    },
};

pub const CastAddBody = struct {
    text: []const u8,
    mentions: []u64,
    mentions_positions: []u64,
    embeds: [][]const u8,
    parent_cast_id: ?CastId,
    parent_url: ?[]const u8,
};

pub const CastRemoveBody = struct {
    target_hash: []const u8,
};

pub const ReactionAddBody = struct {
    type: ReactionType,
    target_cast_id: ?CastId,
    target_url: ?[]const u8,
};

pub const ReactionRemoveBody = struct {
    type: ReactionType,
    target_cast_id: ?CastId,
    target_url: ?[]const u8,
};

pub const LinkAddBody = struct {
    type: []const u8, // "follow"
    target_fid: u64,
};

pub const LinkRemoveBody = struct {
    type: []const u8, // "follow"
    target_fid: u64,
};

pub const UserDataAddBody = struct {
    type: UserDataType,
    value: []const u8,
};

pub const UserDataRemoveBody = struct {
    type: UserDataType,
};

pub const CastId = struct {
    fid: u64,
    hash: []const u8,
};

// ===== Client Implementation =====

pub const FarcasterClient = struct {
    allocator: Allocator,
    http_client: http.Client,
    base_url: []const u8,
    user_fid: u64,
    private_key: [64]u8, // Ed25519 private key (64 bytes for seed + extended)
    public_key: [32]u8,  // Ed25519 public key
    
    const Self = @This();
    
    pub fn init(allocator: Allocator, user_fid: u64, private_key_hex: []const u8) !Self {
        var private_key: [64]u8 = undefined;
        var public_key: [32]u8 = undefined;
        
        // Parse hex private key (64 bytes)
        if (private_key_hex.len != 128) return FarcasterError.InvalidMessage; // 128 hex chars = 64 bytes
        _ = try std.fmt.hexToBytes(&private_key, private_key_hex);
        
        // Create Ed25519 keypair from secret key bytes
        const secret_key = try crypto.sign.Ed25519.SecretKey.fromBytes(private_key);
        const kp = try crypto.sign.Ed25519.KeyPair.fromSecretKey(secret_key);
        public_key = kp.public_key.bytes;
        
        const http_client = http.Client{ .allocator = allocator };
        
        return Self{
            .allocator = allocator,
            .http_client = http_client,
            .base_url = "https://hub.pinata.cloud",
            .user_fid = user_fid,
            .private_key = private_key,
            .public_key = public_key,
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.http_client.deinit();
    }
    
    // ===== Cast Operations =====
    
    pub fn getCastsByFid(self: *Self, fid: u64, limit: u32) ![]FarcasterCast {
        const uri_str = try std.fmt.allocPrint(self.allocator, "{s}/v1/castsByFid?fid={d}&limit={d}", .{ self.base_url, fid, limit });
        defer self.allocator.free(uri_str);
        
        const response_body = try self.httpGet(uri_str);
        defer self.allocator.free(response_body);
        
        return self.parseCastsResponse(response_body);
    }
    
    pub fn getCastsByChannel(self: *Self, channel_url: []const u8, limit: u32) ![]FarcasterCast {
        // Encode the channel URL for the query parameter
        // For now, we'll use a simple approach - in production you'd want proper URL encoding
        const uri_str = try std.fmt.allocPrint(self.allocator, "{s}/v1/castsByParent?url={s}&limit={d}", .{ self.base_url, channel_url, limit });
        defer self.allocator.free(uri_str);
        
        const response_body = try self.httpGet(uri_str);
        defer self.allocator.free(response_body);
        
        return self.parseCastsResponse(response_body);
    }
    
    pub fn postCast(self: *Self, text: []const u8, channel_url: ?[]const u8) ![]const u8 {
        const timestamp = @as(u64, @intCast(std.time.timestamp()));
        
        const cast_body = CastAddBody{
            .text = text,
            .mentions = &[_]u64{},
            .mentions_positions = &[_]u64{},
            .embeds = &[_][]const u8{},
            .parent_cast_id = null,
            .parent_url = channel_url,
        };
        
        const message_data = MessageData{
            .type = .cast_add,
            .fid = self.user_fid,
            .timestamp = timestamp,
            .network = 1, // mainnet
            .body = .{ .cast_add = cast_body },
        };
        
        return self.submitMessage(message_data);
    }
    
    // ===== Reaction Operations =====
    
    pub fn likeCast(self: *Self, cast_hash: []const u8, cast_fid: u64) ![]const u8 {
        return self.addReaction(.like, cast_hash, cast_fid);
    }
    
    pub fn recastCast(self: *Self, cast_hash: []const u8, cast_fid: u64) ![]const u8 {
        return self.addReaction(.recast, cast_hash, cast_fid);
    }
    
    pub fn unlikeCast(self: *Self, cast_hash: []const u8, cast_fid: u64) ![]const u8 {
        return self.removeReaction(.like, cast_hash, cast_fid);
    }
    
    pub fn unrecastCast(self: *Self, cast_hash: []const u8, cast_fid: u64) ![]const u8 {
        return self.removeReaction(.recast, cast_hash, cast_fid);
    }
    
    fn addReaction(self: *Self, reaction_type: ReactionType, cast_hash: []const u8, cast_fid: u64) ![]const u8 {
        const timestamp = @as(u64, @intCast(std.time.timestamp()));
        
        const reaction_body = ReactionAddBody{
            .type = reaction_type,
            .target_cast_id = CastId{ .fid = cast_fid, .hash = cast_hash },
            .target_url = null,
        };
        
        const message_data = MessageData{
            .type = .reaction_add,
            .fid = self.user_fid,
            .timestamp = timestamp,
            .network = 1,
            .body = .{ .reaction_add = reaction_body },
        };
        
        return self.submitMessage(message_data);
    }
    
    fn removeReaction(self: *Self, reaction_type: ReactionType, cast_hash: []const u8, cast_fid: u64) ![]const u8 {
        const timestamp = @as(u64, @intCast(std.time.timestamp()));
        
        const reaction_body = ReactionRemoveBody{
            .type = reaction_type,
            .target_cast_id = CastId{ .fid = cast_fid, .hash = cast_hash },
            .target_url = null,
        };
        
        const message_data = MessageData{
            .type = .reaction_remove,
            .fid = self.user_fid,
            .timestamp = timestamp,
            .network = 1,
            .body = .{ .reaction_remove = reaction_body },
        };
        
        return self.submitMessage(message_data);
    }
    
    // ===== Follow Operations =====
    
    pub fn followUser(self: *Self, target_fid: u64) ![]const u8 {
        const timestamp = @as(u64, @intCast(std.time.timestamp()));
        
        const link_body = LinkAddBody{
            .type = "follow",
            .target_fid = target_fid,
        };
        
        const message_data = MessageData{
            .type = .link_add,
            .fid = self.user_fid,
            .timestamp = timestamp,
            .network = 1,
            .body = .{ .link_add = link_body },
        };
        
        return self.submitMessage(message_data);
    }
    
    pub fn unfollowUser(self: *Self, target_fid: u64) ![]const u8 {
        const timestamp = @as(u64, @intCast(std.time.timestamp()));
        
        const link_body = LinkRemoveBody{
            .type = "follow",
            .target_fid = target_fid,
        };
        
        const message_data = MessageData{
            .type = .link_remove,
            .fid = self.user_fid,
            .timestamp = timestamp,
            .network = 1,
            .body = .{ .link_remove = link_body },
        };
        
        return self.submitMessage(message_data);
    }
    
    pub fn getFollowers(self: *Self, fid: u64) ![]FarcasterUser {
        const uri_str = try std.fmt.allocPrint(self.allocator, "{s}/v1/linksByTargetFid?target_fid={d}&link_type=follow", .{ self.base_url, fid });
        defer self.allocator.free(uri_str);
        
        const response_body = try self.httpGet(uri_str);
        defer self.allocator.free(response_body);
        
        return self.parseFollowersResponse(response_body);
    }
    
    pub fn getFollowing(self: *Self, fid: u64) ![]FarcasterUser {
        const uri_str = try std.fmt.allocPrint(self.allocator, "{s}/v1/linksByFid?fid={d}&link_type=follow", .{ self.base_url, fid });
        defer self.allocator.free(uri_str);
        
        const response_body = try self.httpGet(uri_str);
        defer self.allocator.free(response_body);
        
        return self.parseFollowingResponse(response_body);
    }
    
    // ===== User Profile Operations =====
    
    pub fn getUserProfile(self: *Self, fid: u64) !FarcasterUser {
        const uri_str = try std.fmt.allocPrint(self.allocator, "{s}/v1/userDataByFid?fid={d}", .{ self.base_url, fid });
        defer self.allocator.free(uri_str);
        
        const response_body = try self.httpGet(uri_str);
        defer self.allocator.free(response_body);
        
        return self.parseUserProfileResponse(response_body, fid);
    }
    
    // ===== Internal HTTP and Message Handling =====
    
    fn httpGet(self: *Self, uri_str: []const u8) ![]u8 {
        const uri = try std.Uri.parse(uri_str);
        
        var header_buf: [8192]u8 = undefined;
        var req = try self.http_client.open(.GET, uri, .{ 
            .server_header_buffer = &header_buf 
        });
        defer req.deinit();
        
        // Note: Setting headers in Zig 0.14 requires manual addition
        // For now, we'll use default headers and the service should work
        
        try req.send();
        try req.finish();
        try req.wait();
        
        if (req.response.status != .ok) {
            return FarcasterError.HttpError;
        }
        
        const body = try req.reader().readAllAlloc(self.allocator, 16 * 1024 * 1024); // 16MB max
        return body;
    }
    
    fn submitMessage(self: *Self, message_data: MessageData) ![]const u8 {
        // 1. Serialize message data to bytes
        const message_bytes = try self.serializeMessageData(message_data);
        defer self.allocator.free(message_bytes);
        
        // 2. Hash the message with BLAKE3
        var hasher = crypto.hash.Blake3.init(.{});
        hasher.update(message_bytes);
        var hash: [32]u8 = undefined;
        hasher.final(&hash);
        
        // 3. Sign the hash with Ed25519
        const secret_key = crypto.sign.Ed25519.SecretKey{ .bytes = self.private_key };
        const public_key = crypto.sign.Ed25519.PublicKey{ .bytes = self.public_key };
        const kp = crypto.sign.Ed25519.KeyPair{ .secret_key = secret_key, .public_key = public_key };
        const signature = try kp.sign(&hash, null);
        
        // 4. Create complete message with signature
        const complete_message = try self.createSignedMessage(message_data, hash, signature);
        defer self.allocator.free(complete_message);
        
        // 5. Submit to hub
        return self.httpPostMessage(complete_message);
    }
    
    fn serializeMessageData(self: *Self, message_data: MessageData) ![]u8 {
        // This would normally be protobuf serialization
        // For now, we'll use JSON as a placeholder (the actual implementation would need protobuf)
        var string = ArrayList(u8).init(self.allocator);
        defer string.deinit();
        
        try json.stringify(message_data, .{}, string.writer());
        return string.toOwnedSlice();
    }
    
    fn createSignedMessage(self: *Self, _: MessageData, hash: [32]u8, _: crypto.sign.Ed25519.Signature) ![]u8 {
        // Create a simple JSON string manually to avoid complex HashMap serialization issues
        // This is simplified - real implementation would use protobuf
        
        // Convert hash to hex string
        var hash_hex: [64]u8 = undefined;
        _ = try std.fmt.bufPrint(&hash_hex, "{x}", .{std.fmt.fmtSliceHexLower(&hash)});
        
        // Create JSON string manually
        const json_template = 
            \\{{"hash":"{s}","signature":"placeholder_signature","signatureScheme":"ED25519","hashScheme":"BLAKE3"}}
        ;
        
        return try std.fmt.allocPrint(self.allocator, json_template, .{hash_hex});
    }
    
    fn httpPostMessage(self: *Self, message_bytes: []const u8) ![]const u8 {
        const uri_str = try std.fmt.allocPrint(self.allocator, "{s}/v1/submitMessage", .{self.base_url});
        defer self.allocator.free(uri_str);
        
        const uri = try std.Uri.parse(uri_str);
        
        var header_buf: [8192]u8 = undefined;
        var req = try self.http_client.open(.POST, uri, .{ 
            .server_header_buffer = &header_buf 
        });
        defer req.deinit();
        
        // Note: Setting headers in Zig 0.14 requires manual addition
        // For now, we'll use default headers and the service should work
        
        try req.send();
        try req.writeAll(message_bytes);
        try req.finish();
        try req.wait();
        
        if (req.response.status != .ok) {
            return FarcasterError.HttpError;
        }
        
        const body = try req.reader().readAllAlloc(self.allocator, 16 * 1024 * 1024);
        return body;
    }
    
    // ===== Response Parsing =====
    
    fn parseCastsResponse(self: *Self, response_body: []const u8) ![]FarcasterCast {
        // Parse JSON response and convert to FarcasterCast structs
        // This is a simplified implementation - real one would handle all message fields
        var casts = ArrayList(FarcasterCast).init(self.allocator);
        defer casts.deinit();
        
        const parsed = try json.parseFromSlice(json.Value, self.allocator, response_body, .{});
        defer parsed.deinit();
        
        if (parsed.value.object.get("messages")) |messages_value| {
            for (messages_value.array.items) |message| {
                const cast = try self.parsecastFromMessage(message);
                try casts.append(cast);
            }
        }
        
        return casts.toOwnedSlice();
    }
    
    fn parsecastFromMessage(_: *Self, message: json.Value) !FarcasterCast {
        // Extract cast data from Farcaster message
        // This is simplified - real implementation would handle all fields properly
        const data = message.object.get("data").?.object;
        const cast_body = data.get("castAddBody").?.object;
        
        const author = FarcasterUser{
            .fid = @as(u64, @intCast(data.get("fid").?.integer)),
            .username = "unknown", // Would fetch from user data
            .display_name = "Unknown User",
            .bio = "",
            .pfp_url = "",
            .follower_count = 0,
            .following_count = 0,
        };
        
        return FarcasterCast{
            .hash = message.object.get("hash").?.string,
            .parent_hash = null,
            .parent_url = if (cast_body.get("parentUrl")) |url| url.string else null,
            .author = author,
            .text = cast_body.get("text").?.string,
            .timestamp = @as(u64, @intCast(data.get("timestamp").?.integer)),
            .mentions = &[_]u64{},
            .replies_count = 0,
            .reactions_count = 0,
            .recasts_count = 0,
        };
    }
    
    fn parseFollowersResponse(self: *Self, _: []const u8) ![]FarcasterUser {
        // Parse followers from links response
        var users = ArrayList(FarcasterUser).init(self.allocator);
        defer users.deinit();
        
        // Implementation would parse link messages and extract follower FIDs
        // Then fetch user profiles for each
        
        return users.toOwnedSlice();
    }
    
    fn parseFollowingResponse(self: *Self, _: []const u8) ![]FarcasterUser {
        // Parse following from links response
        var users = ArrayList(FarcasterUser).init(self.allocator);
        defer users.deinit();
        
        // Implementation would parse link messages and extract following FIDs
        // Then fetch user profiles for each
        
        return users.toOwnedSlice();
    }
    
    fn parseUserProfileResponse(self: *Self, response_body: []const u8, fid: u64) !FarcasterUser {
        // Parse user profile from userData response
        const parsed = try json.parseFromSlice(json.Value, self.allocator, response_body, .{});
        defer parsed.deinit();
        
        var username: []const u8 = "unknown";
        var display_name: []const u8 = "Unknown User";
        var bio: []const u8 = "";
        var pfp_url: []const u8 = "";
        
        if (parsed.value.object.get("messages")) |messages| {
            for (messages.array.items) |message| {
                const data = message.object.get("data").?.object;
                const user_data_body = data.get("userDataBody").?.object;
                const data_type = user_data_body.get("type").?.string;
                const value = user_data_body.get("value").?.string;
                
                if (std.mem.eql(u8, data_type, "USER_DATA_TYPE_USERNAME")) {
                    username = value;
                } else if (std.mem.eql(u8, data_type, "USER_DATA_TYPE_DISPLAY")) {
                    display_name = value;
                } else if (std.mem.eql(u8, data_type, "USER_DATA_TYPE_BIO")) {
                    bio = value;
                } else if (std.mem.eql(u8, data_type, "USER_DATA_TYPE_PFP")) {
                    pfp_url = value;
                }
            }
        }
        
        return FarcasterUser{
            .fid = fid,
            .username = username,
            .display_name = display_name,
            .bio = bio,
            .pfp_url = pfp_url,
            .follower_count = 0, // Would need separate API call
            .following_count = 0, // Would need separate API call
        };
    }
};

// ===== C-compatible exports for Swift integration =====

// Export C-compatible functions that Swift can call
export fn fc_client_create(fid: u64, private_key_hex: [*:0]const u8) ?*FarcasterClient {
    const allocator = std.heap.c_allocator;
    
    const key_slice = std.mem.span(private_key_hex);
    const client = allocator.create(FarcasterClient) catch return null;
    
    client.* = FarcasterClient.init(allocator, fid, key_slice) catch {
        allocator.destroy(client);
        return null;
    };
    
    return client;
}

export fn fc_client_destroy(client: ?*FarcasterClient) void {
    if (client) |c| {
        c.deinit();
        std.heap.c_allocator.destroy(c);
    }
}

export fn fc_post_cast(client: ?*FarcasterClient, text: [*:0]const u8, channel_url: [*:0]const u8) [*:0]const u8 {
    const c = client orelse return "ERROR: null client";
    
    const text_slice = std.mem.span(text);
    const channel_slice = if (std.mem.len(channel_url) > 0) std.mem.span(channel_url) else null;
    
    const result = c.postCast(text_slice, channel_slice) catch return "ERROR: post failed";
    
    // Convert to null-terminated string for C
    const c_str = std.heap.c_allocator.dupeZ(u8, result) catch return "ERROR: memory allocation";
    std.heap.c_allocator.free(result);
    
    return c_str.ptr;
}

export fn fc_like_cast(client: ?*FarcasterClient, cast_hash: [*:0]const u8, cast_fid: u64) [*:0]const u8 {
    const c = client orelse return "ERROR: null client";
    
    const hash_slice = std.mem.span(cast_hash);
    const result = c.likeCast(hash_slice, cast_fid) catch return "ERROR: like failed";
    
    const c_str = std.heap.c_allocator.dupeZ(u8, result) catch return "ERROR: memory allocation";
    std.heap.c_allocator.free(result);
    
    return c_str.ptr;
}

export fn fc_get_casts_by_channel(client: ?*FarcasterClient, channel_url: [*:0]const u8, limit: u32) [*:0]const u8 {
    const c = client orelse return "ERROR: null client";
    
    const channel_slice = std.mem.span(channel_url);
    const casts = c.getCastsByChannel(channel_slice, limit) catch return "ERROR: fetch failed";
    defer std.heap.c_allocator.free(casts);
    
    // Convert casts array to JSON string
    var json_str = std.ArrayList(u8).init(std.heap.c_allocator);
    defer json_str.deinit();
    
    json.stringify(casts, .{}, json_str.writer()) catch return "ERROR: json serialization";
    
    const c_str = std.heap.c_allocator.dupeZ(u8, json_str.items) catch return "ERROR: memory allocation";
    
    return c_str.ptr;
}

// Helper for Swift to free C strings
export fn fc_free_string(str: [*:0]const u8) void {
    const slice = std.mem.span(str);
    std.heap.c_allocator.free(slice);
}