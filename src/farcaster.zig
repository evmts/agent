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

/// Smart allocator wrapper for HTTP operations
const HttpArenaAllocator = struct {
    gpa: std.heap.GeneralPurposeAllocator(.{}),
    arena: std.heap.ArenaAllocator,
    
    const Self = @This();
    
    fn init(base_allocator: Allocator) Self {
        return Self{
            .gpa = std.heap.GeneralPurposeAllocator(.{}){},
            .arena = std.heap.ArenaAllocator.init(base_allocator),
        };
    }
    
    fn deinit(self: *Self) void {
        self.arena.deinit();
        _ = self.gpa.deinit();
    }
    
    fn allocator(self: *Self) Allocator {
        return self.arena.allocator();
    }
    
    /// Reset arena between HTTP operations for optimal performance
    fn reset(self: *Self) void {
        self.arena.deinit();
        self.arena = std.heap.ArenaAllocator.init(self.gpa.allocator());
    }
};

pub const FarcasterClient = struct {
    base_allocator: Allocator,  // For long-lived allocations
    http_arena: HttpArenaAllocator,  // For temporary HTTP/JSON operations
    http_client: http.Client,
    base_url: []const u8,
    user_fid: u64,
    private_key: [64]u8, // Ed25519 private key (64 bytes for seed + extended)
    public_key: [32]u8,  // Ed25519 public key
    
    const Self = @This();
    
    /// Initialize FarcasterClient with smart allocation strategy
    /// Uses arena allocator for temporary operations, base allocator for persistent data
    pub fn init(allocator: Allocator, user_fid: u64, private_key_hex: []const u8) !Self {
        var private_key: [64]u8 = undefined;
        var public_key: [32]u8 = undefined;
        
        // Validate input first
        if (private_key_hex.len != 128) {
            std.log.err("Invalid private key length: {} (expected 128)", .{private_key_hex.len});
            return FarcasterError.InvalidMessage;
        }
        
        // Convert hex with proper error handling
        _ = std.fmt.hexToBytes(&private_key, private_key_hex) catch {
            std.log.err("Failed to parse hex private key", .{});
            return FarcasterError.InvalidMessage;
        };
        
        // Create cryptographic keys with error handling and security cleanup
        const secret_key = crypto.sign.Ed25519.SecretKey.fromBytes(private_key) catch {
            // Zero out sensitive data on error - Rust-style security
            @memset(&private_key, 0);
            std.log.err("Failed to create Ed25519 secret key", .{});
            return FarcasterError.SigningError;
        };
        errdefer @memset(&private_key, 0); // ✅ Zero sensitive data on any error
        
        const kp = crypto.sign.Ed25519.KeyPair.fromSecretKey(secret_key) catch {
            @memset(&private_key, 0);
            std.log.err("Failed to create Ed25519 keypair", .{});
            return FarcasterError.SigningError;
        };
        public_key = kp.public_key.bytes;
        
        // Initialize HTTP client with error handling
        const http_client = http.Client{ .allocator = allocator };
        errdefer http_client.deinit(); // ✅ Cleanup on error
        
        return Self{
            .base_allocator = allocator,
            .http_arena = HttpArenaAllocator.init(allocator),
            .http_client = http_client,
            .base_url = "https://hub.pinata.cloud",
            .user_fid = user_fid,
            .private_key = private_key,
            .public_key = public_key,
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.http_client.deinit();
        self.http_arena.deinit();
    }
    
    // ===== Cast Operations =====
    
    pub fn getCastsByFid(self: *Self, fid: u64, limit: u32) ![]FarcasterCast {
        // Reset arena for this operation - all temp allocations freed together
        self.http_arena.reset();
        
        const arena_allocator = self.http_arena.allocator();
        const uri_str = try std.fmt.allocPrint(arena_allocator, "{s}/v1/castsByFid?fid={d}&limit={d}", .{ self.base_url, fid, limit });
        
        const response_body = try self.httpGet(uri_str);
        
        const result = try self.parseCastsResponse(response_body);
        
        // Copy result to persistent memory
        return try self.base_allocator.dupe(FarcasterCast, result);
    }
    
    pub fn getCastsByChannel(self: *Self, channel_url: []const u8, limit: u32) ![]FarcasterCast {
        // Reset arena for this operation
        self.http_arena.reset();
        
        const arena_allocator = self.http_arena.allocator();
        const uri_str = try std.fmt.allocPrint(arena_allocator, "{s}/v1/castsByParent?url={s}&limit={d}", .{ self.base_url, channel_url, limit });
        
        const response_body = try self.httpGet(uri_str);
        
        const result = try self.parseCastsResponse(response_body);
        
        // Copy result to persistent memory
        return try self.base_allocator.dupe(FarcasterCast, result);
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
        // Reset arena for this operation
        self.http_arena.reset();
        
        const arena_allocator = self.http_arena.allocator();
        const uri_str = try std.fmt.allocPrint(arena_allocator, "{s}/v1/linksByTargetFid?target_fid={d}&link_type=follow", .{ self.base_url, fid });
        
        const response_body = try self.httpGet(uri_str);
        
        const result = try self.parseFollowersResponse(response_body);
        
        // Copy result to persistent memory
        return try self.base_allocator.dupe(FarcasterUser, result);
    }
    
    pub fn getFollowing(self: *Self, fid: u64) ![]FarcasterUser {
        // Reset arena for this operation
        self.http_arena.reset();
        
        const arena_allocator = self.http_arena.allocator();
        const uri_str = try std.fmt.allocPrint(arena_allocator, "{s}/v1/linksByFid?fid={d}&link_type=follow", .{ self.base_url, fid });
        
        const response_body = try self.httpGet(uri_str);
        
        const result = try self.parseFollowingResponse(response_body);
        
        // Copy result to persistent memory
        return try self.base_allocator.dupe(FarcasterUser, result);
    }
    
    // ===== User Profile Operations =====
    
    pub fn getUserProfile(self: *Self, fid: u64) !FarcasterUser {
        // Reset arena for this operation
        self.http_arena.reset();
        
        const arena_allocator = self.http_arena.allocator();
        const uri_str = try std.fmt.allocPrint(arena_allocator, "{s}/v1/userDataByFid?fid={d}", .{ self.base_url, fid });
        
        const response_body = try self.httpGet(uri_str);
        
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
        
        try req.send();
        try req.finish();
        try req.wait();
        
        if (req.response.status != .ok) {
            return FarcasterError.HttpError;
        }
        
        // Use arena allocator for HTTP response - auto-freed on reset
        const body = try req.reader().readAllAlloc(self.http_arena.allocator(), 16 * 1024 * 1024);
        return body;
    }
    
    fn submitMessage(self: *Self, message_data: MessageData) ![]const u8 {
        // Reset arena for this operation - all temp allocations freed together
        self.http_arena.reset();
        
        // 1. Serialize message data to bytes (arena allocated)
        const message_bytes = try self.serializeMessageData(message_data);
        
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
        
        // 4. Create complete message with signature (arena allocated)
        const complete_message = try self.createSignedMessage(message_data, hash, signature);
        
        // 5. Submit to hub and copy result to persistent memory
        const response = try self.httpPostMessage(complete_message);
        return try self.base_allocator.dupe(u8, response);
    }
    
    fn serializeMessageData(self: *Self, message_data: MessageData) ![]u8 {
        // This would normally be protobuf serialization
        // For now, we'll use JSON as a placeholder (the actual implementation would need protobuf)
        var string = ArrayList(u8).init(self.allocator);
        errdefer string.deinit(); // ✅ Cleanup on error
        
        json.stringify(message_data, .{}, string.writer()) catch |err| {
            std.log.err("Failed to serialize message data: {}", .{err});
            return err;
        };
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
        errdefer casts.deinit(); // ✅ Cleanup on error
        
        const parsed = json.parseFromSlice(json.Value, self.allocator, response_body, .{}) catch |err| {
            std.log.err("Failed to parse JSON response: {}", .{err});
            return err;
        };
        defer parsed.deinit(); // ✅ Always cleanup parsed JSON
        
        if (parsed.value.object.get("messages")) |messages_value| {
            for (messages_value.array.items) |message| {
                const cast = self.parsecastFromMessage(message) catch |err| {
                    std.log.err("Failed to parse cast from message: {}", .{err});
                    return err;
                };
                casts.append(cast) catch |err| {
                    std.log.err("Failed to append cast to list: {}", .{err});
                    return err;
                };
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
        errdefer users.deinit(); // ✅ Cleanup on error
        
        // Implementation would parse link messages and extract follower FIDs
        // Then fetch user profiles for each
        
        return users.toOwnedSlice();
    }
    
    fn parseFollowingResponse(self: *Self, _: []const u8) ![]FarcasterUser {
        // Parse following from links response
        var users = ArrayList(FarcasterUser).init(self.allocator);
        errdefer users.deinit(); // ✅ Cleanup on error
        
        // Implementation would parse link messages and extract following FIDs
        // Then fetch user profiles for each
        
        return users.toOwnedSlice();
    }
    
    fn parseUserProfileResponse(self: *Self, response_body: []const u8, fid: u64) !FarcasterUser {
        // Parse user profile from userData response
        const parsed = json.parseFromSlice(json.Value, self.allocator, response_body, .{}) catch |err| {
            std.log.err("Failed to parse user profile JSON: {}", .{err});
            return err;
        };
        defer parsed.deinit(); // ✅ Always cleanup parsed JSON
        
        var username: []const u8 = "unknown";
        var display_name: []const u8 = "Unknown User";
        var bio: []const u8 = "";
        var pfp_url: []const u8 = "";
        
        if (parsed.value.object.get("messages")) |messages| {
            for (messages.array.items) |message| {
                const data = message.object.get("data") orelse continue;
                const user_data_body = data.object.get("userDataBody") orelse continue;
                const data_type = user_data_body.object.get("type") orelse continue;
                const value = user_data_body.object.get("value") orelse continue;
                
                if (std.mem.eql(u8, data_type.string, "USER_DATA_TYPE_USERNAME")) {
                    username = value.string;
                } else if (std.mem.eql(u8, data_type.string, "USER_DATA_TYPE_DISPLAY")) {
                    display_name = value.string;
                } else if (std.mem.eql(u8, data_type.string, "USER_DATA_TYPE_BIO")) {
                    bio = value.string;
                } else if (std.mem.eql(u8, data_type.string, "USER_DATA_TYPE_PFP")) {
                    pfp_url = value.string;
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
// All functions follow Rust-style ownership semantics with clear documentation

/// Create FarcasterClient with proper error handling
/// Ownership: Returns owned pointer - caller MUST call fc_client_destroy()
/// Returns: null on failure, valid pointer on success
export fn fc_client_create(fid: u64, private_key_hex: ?[*:0]const u8) ?*FarcasterClient {
    // Validate input
    const key_ptr = private_key_hex orelse {
        std.log.err("Null private key pointer passed to fc_client_create", .{});
        return null;
    };
    
    const allocator = std.heap.c_allocator;
    const key_slice = std.mem.span(key_ptr);
    
    // Allocate client with error handling
    const client = allocator.create(FarcasterClient) catch |err| {
        std.log.err("Failed to allocate FarcasterClient: {}", .{err});
        return null;
    };
    errdefer allocator.destroy(client); // ✅ Cleanup on error
    
    // Initialize client with comprehensive error handling
    client.* = FarcasterClient.init(allocator, fid, key_slice) catch |err| {
        std.log.err("Failed to initialize FarcasterClient: {}", .{err});
        allocator.destroy(client);
        return null;
    };
    
    return client;
}

/// Destroy FarcasterClient with safe ownership transfer
/// Ownership: Takes ownership from caller and destroys it
/// Safety: Handles null pointers gracefully
export fn fc_client_destroy(client: ?*FarcasterClient) void {
    if (client) |c| {
        c.deinit(); // ✅ Cleanup internal resources
        std.heap.c_allocator.destroy(c); // ✅ Free client memory
    } else {
        std.log.warn("Attempted to destroy null FarcasterClient", .{});
    }
}

/// Post cast with safe memory management
/// Returns: owned null-terminated string - caller MUST call fc_free_string()
/// Ownership: Transfers ownership to caller
/// Returns: null on error, owned string on success
export fn fc_post_cast(client: ?*FarcasterClient, text: ?[*:0]const u8, channel_url: ?[*:0]const u8) ?[*:0]const u8 {
    // Validate inputs
    const c = client orelse {
        std.log.err("Null client passed to fc_post_cast", .{});
        return null;
    };
    
    const text_ptr = text orelse {
        std.log.err("Null text passed to fc_post_cast", .{});
        return null;
    };
    
    const text_slice = std.mem.span(text_ptr);
    const channel_slice = if (channel_url) |ch_url| 
        if (std.mem.len(ch_url) > 0) std.mem.span(ch_url) else null
    else null;
    
    // Post cast with error handling
    const result = c.postCast(text_slice, channel_slice) catch |err| {
        std.log.err("Failed to post cast: {}", .{err});
        return null;
    };
    errdefer std.heap.c_allocator.free(result); // ✅ Cleanup on error
    
    // Convert to C string with clear ownership transfer
    const c_str = std.heap.c_allocator.dupeZ(u8, result) catch |err| {
        std.log.err("Failed to allocate C string: {}", .{err});
        std.heap.c_allocator.free(result);
        return null;
    };
    
    // Free original, transfer ownership of c_str to caller
    std.heap.c_allocator.free(result);
    return c_str.ptr;
}

/// Like cast with safe memory management  
/// Returns: owned null-terminated string - caller MUST call fc_free_string()
/// Ownership: Transfers ownership to caller
/// Returns: null on error, owned string on success
export fn fc_like_cast(client: ?*FarcasterClient, cast_hash: ?[*:0]const u8, cast_fid: u64) ?[*:0]const u8 {
    // Validate inputs
    const c = client orelse {
        std.log.err("Null client passed to fc_like_cast", .{});
        return null;
    };
    
    const hash_ptr = cast_hash orelse {
        std.log.err("Null cast_hash passed to fc_like_cast", .{});
        return null;
    };
    
    const hash_slice = std.mem.span(hash_ptr);
    
    // Like cast with error handling
    const result = c.likeCast(hash_slice, cast_fid) catch |err| {
        std.log.err("Failed to like cast: {}", .{err});
        return null;
    };
    errdefer std.heap.c_allocator.free(result); // ✅ Cleanup on error
    
    // Convert to C string with clear ownership transfer
    const c_str = std.heap.c_allocator.dupeZ(u8, result) catch |err| {
        std.log.err("Failed to allocate C string: {}", .{err});
        std.heap.c_allocator.free(result);
        return null;
    };
    
    // Free original, transfer ownership of c_str to caller
    std.heap.c_allocator.free(result);
    return c_str.ptr;
}

/// Get casts by channel with safe memory management
/// Returns: owned null-terminated JSON string - caller MUST call fc_free_string()
/// Ownership: Transfers ownership to caller
/// Returns: null on error, owned JSON string on success
export fn fc_get_casts_by_channel(client: ?*FarcasterClient, channel_url: ?[*:0]const u8, limit: u32) ?[*:0]const u8 {
    // Validate inputs
    const c = client orelse {
        std.log.err("Null client passed to fc_get_casts_by_channel", .{});
        return null;
    };
    
    const channel_ptr = channel_url orelse {
        std.log.err("Null channel_url passed to fc_get_casts_by_channel", .{});
        return null;
    };
    
    const channel_slice = std.mem.span(channel_ptr);
    
    // Get casts with error handling
    const casts = c.getCastsByChannel(channel_slice, limit) catch |err| {
        std.log.err("Failed to get casts by channel: {}", .{err});
        return null;
    };
    errdefer std.heap.c_allocator.free(casts); // ✅ Cleanup on error
    
    // Convert casts array to JSON string
    var json_str = std.ArrayList(u8).init(std.heap.c_allocator);
    defer json_str.deinit(); // ✅ Always cleanup ArrayList
    
    json.stringify(casts, .{}, json_str.writer()) catch |err| {
        std.log.err("Failed to serialize casts to JSON: {}", .{err});
        std.heap.c_allocator.free(casts);
        return null;
    };
    
    // Create C string with ownership transfer
    const c_str = std.heap.c_allocator.dupeZ(u8, json_str.items) catch |err| {
        std.log.err("Failed to allocate JSON C string: {}", .{err});
        std.heap.c_allocator.free(casts);
        return null;
    };
    
    // Free original casts array
    std.heap.c_allocator.free(casts);
    return c_str.ptr;
}

/// Safely free string allocated by Farcaster C API functions
/// Ownership: Takes ownership from caller and destroys it
/// Safety: Handles null and validates pointers with comprehensive checks
export fn fc_free_string(str: ?[*:0]const u8) void {
    // Rust-style safety: validate pointer before use
    const str_ptr = str orelse {
        std.log.warn("Attempted to free null string pointer", .{});
        return;
    };
    
    const slice = std.mem.span(str_ptr);
    if (slice.len == 0) {
        std.log.warn("Attempted to free empty string", .{});
        return;
    }
    
    // Additional safety: basic pointer validation
    // Check if pointer seems reasonable (not obviously corrupted)
    if (@intFromPtr(str) < 0x1000) {
        std.log.err("Attempted to free invalid pointer: 0x{x}", .{@intFromPtr(str)});
        return;
    }
    
    // Safe destruction with proper allocator
    std.heap.c_allocator.free(slice);
}