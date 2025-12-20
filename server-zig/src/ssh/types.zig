/// SSH Protocol Types and Constants
/// Based on RFC 4253, RFC 4252, RFC 4254
const std = @import("std");

/// SSH Protocol Version
pub const SSH_VERSION = "SSH-2.0-PlueSSH_1.0";

/// SSH Message Types (RFC 4253, RFC 4252, RFC 4254)
pub const MessageType = enum(u8) {
    // Transport Layer (RFC 4253)
    SSH_MSG_DISCONNECT = 1,
    SSH_MSG_IGNORE = 2,
    SSH_MSG_UNIMPLEMENTED = 3,
    SSH_MSG_DEBUG = 4,
    SSH_MSG_SERVICE_REQUEST = 5,
    SSH_MSG_SERVICE_ACCEPT = 6,
    SSH_MSG_KEXINIT = 20,
    SSH_MSG_NEWKEYS = 21,

    // User Authentication (RFC 4252)
    SSH_MSG_USERAUTH_REQUEST = 50,
    SSH_MSG_USERAUTH_FAILURE = 51,
    SSH_MSG_USERAUTH_SUCCESS = 52,
    SSH_MSG_USERAUTH_BANNER = 53,
    SSH_MSG_USERAUTH_PK_OK = 60,

    // Connection Protocol (RFC 4254)
    SSH_MSG_GLOBAL_REQUEST = 80,
    SSH_MSG_REQUEST_SUCCESS = 81,
    SSH_MSG_REQUEST_FAILURE = 82,
    SSH_MSG_CHANNEL_OPEN = 90,
    SSH_MSG_CHANNEL_OPEN_CONFIRMATION = 91,
    SSH_MSG_CHANNEL_OPEN_FAILURE = 92,
    SSH_MSG_CHANNEL_WINDOW_ADJUST = 93,
    SSH_MSG_CHANNEL_DATA = 94,
    SSH_MSG_CHANNEL_EXTENDED_DATA = 95,
    SSH_MSG_CHANNEL_EOF = 96,
    SSH_MSG_CHANNEL_CLOSE = 97,
    SSH_MSG_CHANNEL_REQUEST = 98,
    SSH_MSG_CHANNEL_SUCCESS = 99,
    SSH_MSG_CHANNEL_FAILURE = 100,

    pub fn fromByte(byte: u8) ?MessageType {
        return std.meta.intToEnum(MessageType, byte) catch null;
    }
};

/// SSH Disconnect Reason Codes (RFC 4253)
pub const DisconnectReason = enum(u32) {
    SSH_DISCONNECT_HOST_NOT_ALLOWED_TO_CONNECT = 1,
    SSH_DISCONNECT_PROTOCOL_ERROR = 2,
    SSH_DISCONNECT_KEY_EXCHANGE_FAILED = 3,
    SSH_DISCONNECT_RESERVED = 4,
    SSH_DISCONNECT_MAC_ERROR = 5,
    SSH_DISCONNECT_COMPRESSION_ERROR = 6,
    SSH_DISCONNECT_SERVICE_NOT_AVAILABLE = 7,
    SSH_DISCONNECT_PROTOCOL_VERSION_NOT_SUPPORTED = 8,
    SSH_DISCONNECT_HOST_KEY_NOT_VERIFIABLE = 9,
    SSH_DISCONNECT_CONNECTION_LOST = 10,
    SSH_DISCONNECT_BY_APPLICATION = 11,
    SSH_DISCONNECT_TOO_MANY_CONNECTIONS = 12,
    SSH_DISCONNECT_AUTH_CANCELLED_BY_USER = 13,
    SSH_DISCONNECT_NO_MORE_AUTH_METHODS_AVAILABLE = 14,
    SSH_DISCONNECT_ILLEGAL_USER_NAME = 15,
};

/// SSH Channel Open Failure Reason Codes (RFC 4254)
pub const ChannelOpenFailure = enum(u32) {
    SSH_OPEN_ADMINISTRATIVELY_PROHIBITED = 1,
    SSH_OPEN_CONNECT_FAILED = 2,
    SSH_OPEN_UNKNOWN_CHANNEL_TYPE = 3,
    SSH_OPEN_RESOURCE_SHORTAGE = 4,
};

/// Authenticated User Information
pub const AuthUser = struct {
    user_id: i64,
    username: []const u8,
    key_id: i64,
};

/// SSH Key Information
pub const SshKey = struct {
    id: i64,
    user_id: i64,
    fingerprint: []const u8,
    public_key: []const u8,
    key_type: []const u8,

    pub fn deinit(self: *SshKey, allocator: std.mem.Allocator) void {
        allocator.free(self.fingerprint);
        allocator.free(self.public_key);
        allocator.free(self.key_type);
    }
};

/// SSH Channel for session management
pub const Channel = struct {
    id: u32,
    remote_id: u32,
    window_size: u32,
    max_packet_size: u32,
    state: ChannelState,

    pub const ChannelState = enum {
        open,
        eof_received,
        eof_sent,
        closed,
    };
};

/// SSH Command Parser Result
pub const GitCommand = struct {
    command: CommandType,
    user: []const u8,
    repo: []const u8,

    pub const CommandType = enum {
        git_upload_pack, // clone/fetch
        git_receive_pack, // push
    };

    /// Parse SSH command like "git-upload-pack '/user/repo.git'"
    pub fn parse(allocator: std.mem.Allocator, cmd_str: []const u8) !GitCommand {
        var parts = std.mem.tokenizeScalar(u8, cmd_str, ' ');

        // Get command
        const cmd_part = parts.next() orelse return error.InvalidCommand;
        const command = if (std.mem.eql(u8, cmd_part, "git-upload-pack"))
            CommandType.git_upload_pack
        else if (std.mem.eql(u8, cmd_part, "git-receive-pack"))
            CommandType.git_receive_pack
        else
            return error.UnsupportedCommand;

        // Get repo path (remove quotes and leading slash)
        var repo_path = parts.next() orelse return error.MissingRepoPath;
        if (repo_path[0] == '\'') repo_path = repo_path[1..];
        if (repo_path[repo_path.len - 1] == '\'') repo_path = repo_path[0 .. repo_path.len - 1];
        if (repo_path[0] == '/') repo_path = repo_path[1..];

        // Remove .git suffix if present
        if (std.mem.endsWith(u8, repo_path, ".git")) {
            repo_path = repo_path[0 .. repo_path.len - 4];
        }

        // Parse user/repo format
        var path_parts = std.mem.tokenizeScalar(u8, repo_path, '/');
        const user = path_parts.next() orelse return error.InvalidRepoPath;
        const repo = path_parts.next() orelse return error.InvalidRepoPath;

        return GitCommand{
            .command = command,
            .user = try allocator.dupe(u8, user),
            .repo = try allocator.dupe(u8, repo),
        };
    }

    pub fn deinit(self: *GitCommand, allocator: std.mem.Allocator) void {
        allocator.free(self.user);
        allocator.free(self.repo);
    }
};

/// SSH Packet Buffer Writer
pub const PacketWriter = struct {
    buffer: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) PacketWriter {
        return .{ .buffer = std.ArrayList(u8).init(allocator) };
    }

    pub fn deinit(self: *PacketWriter) void {
        self.buffer.deinit();
    }

    pub fn writeByte(self: *PacketWriter, value: u8) !void {
        try self.buffer.append(value);
    }

    pub fn writeU32(self: *PacketWriter, value: u32) !void {
        try self.buffer.writer().writeInt(u32, value, .big);
    }

    pub fn writeString(self: *PacketWriter, str: []const u8) !void {
        try self.writeU32(@intCast(str.len));
        try self.buffer.appendSlice(str);
    }

    pub fn writeBoolean(self: *PacketWriter, value: bool) !void {
        try self.buffer.append(if (value) 1 else 0);
    }

    pub fn toOwnedSlice(self: *PacketWriter) ![]u8 {
        return self.buffer.toOwnedSlice();
    }
};

test "GitCommand parse" {
    const allocator = std.testing.allocator;

    // Test git-upload-pack
    var cmd1 = try GitCommand.parse(allocator, "git-upload-pack '/alice/myrepo.git'");
    defer cmd1.deinit(allocator);
    try std.testing.expectEqual(GitCommand.CommandType.git_upload_pack, cmd1.command);
    try std.testing.expectEqualStrings("alice", cmd1.user);
    try std.testing.expectEqualStrings("myrepo", cmd1.repo);

    // Test git-receive-pack
    var cmd2 = try GitCommand.parse(allocator, "git-receive-pack '/bob/project'");
    defer cmd2.deinit(allocator);
    try std.testing.expectEqual(GitCommand.CommandType.git_receive_pack, cmd2.command);
    try std.testing.expectEqualStrings("bob", cmd2.user);
    try std.testing.expectEqualStrings("project", cmd2.repo);
}
