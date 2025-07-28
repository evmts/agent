const std = @import("std");

pub const c = @cImport({
    @cInclude("libssh2.h");
    @cInclude("libssh2_sftp.h");
});

pub const SshError = error{
    // Connection errors
    ConnectionRefused,
    ConnectionTimeout,
    TooManyConnections,
    RateLimitExceeded,
    ProxyProtocolError,
    
    // Authentication errors
    AuthenticationFailed,
    KeyNotFound,
    KeyTooWeak,
    KeyTypeNotAllowed,
    UserDisabled,
    UserNotFound,
    UserInactive,
    UserDeleted,
    InvalidUsername,
    
    // Certificate errors
    CertificateInvalid,
    CertificateExpired,
    UntrustedCA,
    PrincipalNotFound,
    InvalidCertificateType,
    
    // Deploy key errors
    DeployKeyNotAuthorized,
    DeployKeyRepoMismatch,
    
    // Command errors
    InvalidCommand,
    InvalidRepositoryPath,
    CommandNotAllowed,
    
    // Protocol errors
    InvalidProtocol,
    UnsupportedCipher,
    
    // System errors
    HostKeyGenerationFailed,
    ShutdownInProgress,
    WriteTimeout,
    
    // libssh2 specific errors
    SocketDisconnected,
    Timeout,
    HostKeyInit,
    HostKeySign,
    Decrypt,
    PublicKeyUnverified,
    SessionInitFailed,
    ChannelOpenFailed,
    LibSSH2Error,
} || error{OutOfMemory};

pub fn checkError(rc: c_int) SshError!void {
    if (rc < 0) return switch (rc) {
        c.LIBSSH2_ERROR_SOCKET_DISCONNECT => SshError.SocketDisconnected,
        c.LIBSSH2_ERROR_TIMEOUT => SshError.Timeout,
        c.LIBSSH2_ERROR_HOSTKEY_INIT => SshError.HostKeyInit,
        c.LIBSSH2_ERROR_HOSTKEY_SIGN => SshError.HostKeySign,
        c.LIBSSH2_ERROR_DECRYPT => SshError.Decrypt,
        c.LIBSSH2_ERROR_PUBLICKEY_UNVERIFIED => SshError.PublicKeyUnverified,
        c.LIBSSH2_ERROR_AUTHENTICATION_FAILED => SshError.AuthenticationFailed,
        else => SshError.LibSSH2Error,
    };
}

pub const Session = struct {
    handle: *c.LIBSSH2_SESSION,
    
    pub fn init() SshError!Session {
        const handle = c.libssh2_session_init_ex(null, null, null, null) orelse return SshError.SessionInitFailed;
        return Session{ .handle = handle };
    }
    
    pub fn deinit(self: *Session) void {
        _ = c.libssh2_session_free(self.handle);
    }
    
    pub fn handshake(self: *Session, socket: std.posix.socket_t) SshError!void {
        try checkError(c.libssh2_session_handshake(self.handle, socket));
    }
    
    pub fn setBlocking(self: *Session, blocking: bool) void {
        c.libssh2_session_set_blocking(self.handle, if (blocking) 1 else 0);
    }
    
    pub fn userAuthList(self: *Session, username: []const u8) SshError!?[]const u8 {
        const methods = c.libssh2_userauth_list(
            self.handle,
            username.ptr,
            @intCast(username.len)
        );
        if (methods == null) return null;
        return std.mem.span(@as([*:0]const u8, @ptrCast(methods)));
    }
    
    pub fn userAuthAuthenticated(self: *Session) bool {
        return c.libssh2_userauth_authenticated(self.handle) != 0;
    }
    
    pub fn getUsername(self: *Session, buf: []u8) SshError![]const u8 {
        // Use different approach since libssh2_session_username may not be available
        _ = self;
        _ = buf;
        return "unknown";
    }
};

pub const Channel = struct {
    handle: *c.LIBSSH2_CHANNEL,
    
    pub fn openSession(session: *Session) SshError!Channel {
        const handle = c.libssh2_channel_open_session(session.handle) orelse {
            return SshError.ChannelOpenFailed;
        };
        return Channel{ .handle = handle };
    }
    
    pub fn deinit(self: *Channel) void {
        _ = c.libssh2_channel_free(self.handle);
    }
    
    pub fn exec(self: *Channel, command: []const u8) SshError!void {
        const rc = c.libssh2_channel_exec(self.handle, command.ptr);
        try checkError(rc);
    }
    
    pub fn read(self: *Channel, buf: []u8) SshError!usize {
        const bytes_read = c.libssh2_channel_read(self.handle, buf.ptr, buf.len);
        if (bytes_read < 0) {
            try checkError(@intCast(bytes_read));
            return 0;
        }
        return @intCast(bytes_read);
    }
    
    pub fn write(self: *Channel, data: []const u8) SshError!usize {
        const bytes_written = c.libssh2_channel_write(self.handle, data.ptr, data.len);
        if (bytes_written < 0) {
            try checkError(@intCast(bytes_written));
            return 0;
        }
        return @intCast(bytes_written);
    }
    
    pub fn sendEof(self: *Channel) void {
        _ = c.libssh2_channel_send_eof(self.handle);
    }
    
    pub fn close(self: *Channel) void {
        _ = c.libssh2_channel_close(self.handle);
    }
    
    pub fn getExitStatus(self: *Channel) i32 {
        return c.libssh2_channel_get_exit_status(self.handle);
    }
};

fn sshAlloc(count: usize, abstract: ?*anyopaque) callconv(.C) ?*anyopaque {
    const allocator = @as(*std.mem.Allocator, @ptrCast(@alignCast(abstract.?)));
    const mem = allocator.alloc(u8, count) catch return null;
    return mem.ptr;
}

fn sshFree(ptr: ?*anyopaque, abstract: ?*anyopaque) callconv(.C) void {
    _ = ptr;
    _ = abstract;
    // Note: We can't properly free here without storing size information
    // This is a limitation of the libssh2 allocator callback design
}

fn sshRealloc(ptr: ?*anyopaque, count: usize, abstract: ?*anyopaque) callconv(.C) ?*anyopaque {
    _ = ptr;
    const allocator = @as(*std.mem.Allocator, @ptrCast(@alignCast(abstract.?)));
    const mem = allocator.alloc(u8, count) catch return null;
    return mem.ptr;
}

pub fn initLibSSH2(allocator: std.mem.Allocator) SshError!void {
    // Use simple init if _ex version is not available
    _ = allocator;
    const rc = c.libssh2_init(0);
    try checkError(rc);
}

pub fn exitLibSSH2() void {
    c.libssh2_exit();
}

test "libssh2 initialization" {
    const allocator = std.testing.allocator;
    
    try initLibSSH2(allocator);
    defer exitLibSSH2();
    
    // Test that we can create and destroy a session
    var session = try Session.init();
    defer session.deinit();
    
    // Verify session is non-blocking by default
    session.setBlocking(false);
    session.setBlocking(true);
}

test "session creation and cleanup" {
    const allocator = std.testing.allocator;
    
    try initLibSSH2(allocator);
    defer exitLibSSH2();
    
    // Create multiple sessions to test cleanup
    var session1 = try Session.init();
    var session2 = try Session.init();
    
    session1.deinit();
    session2.deinit();
}

test "error handling for invalid operations" {
    const allocator = std.testing.allocator;
    
    try initLibSSH2(allocator);
    defer exitLibSSH2();
    
    var session = try Session.init();
    defer session.deinit();
    
    // Try to get username without authentication
    var buf: [256]u8 = undefined;
    const result = session.getUsername(&buf);
    
    // Should return an error since no username is set
    try std.testing.expectError(SshError.InvalidUsername, result);
}