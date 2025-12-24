/// Security event logging for SSH server
/// Provides structured logging for security-relevant events
const std = @import("std");
const log = std.log.scoped(.ssh_security);

/// Security event types for tracking and alerting
pub const SecurityEvent = enum {
    // Connection events
    connection_attempt,
    connection_accepted,
    connection_rejected_rate_limit,
    connection_rejected_banned,
    connection_rejected_limit,
    connection_closed,

    // Authentication events
    auth_success,
    auth_failure_invalid_key,
    auth_failure_unknown_user,
    auth_failure_key_not_found,
    auth_failure_disabled_user,

    // Session events
    session_started,
    session_closed,
    command_executed,
    command_rejected,

    // Security alerts
    potential_bruteforce,
    ip_banned,
    ip_unbanned,

    pub fn isAlert(self: SecurityEvent) bool {
        return switch (self) {
            .auth_failure_invalid_key,
            .auth_failure_unknown_user,
            .auth_failure_key_not_found,
            .auth_failure_disabled_user,
            .connection_rejected_banned,
            .potential_bruteforce,
            .ip_banned,
            .command_rejected,
            => true,
            else => false,
        };
    }

    pub fn severity(self: SecurityEvent) Severity {
        return switch (self) {
            .connection_attempt, .connection_accepted, .session_started, .session_closed, .connection_closed => .info,
            .auth_success, .command_executed, .ip_unbanned => .info,
            .connection_rejected_rate_limit, .connection_rejected_limit => .warn,
            .auth_failure_invalid_key, .auth_failure_unknown_user, .auth_failure_key_not_found, .auth_failure_disabled_user => .warn,
            .connection_rejected_banned, .potential_bruteforce, .ip_banned, .command_rejected => .err,
        };
    }
};

pub const Severity = enum {
    debug,
    info,
    warn,
    err,
};

/// Context for security events
pub const EventContext = struct {
    ip: []const u8,
    username: ?[]const u8 = null,
    key_fingerprint: ?[]const u8 = null,
    command: ?[]const u8 = null,
    reason: ?[]const u8 = null,
    duration_ms: ?i64 = null,
    ban_duration_s: ?i64 = null,
    failure_count: ?u32 = null,
};

/// Log a security event with structured data
pub fn logEvent(event: SecurityEvent, ctx: EventContext) void {
    const event_name = @tagName(event);
    const user = ctx.username orelse "-";
    const reason = ctx.reason orelse "-";

    // Build structured log message
    // Format: [SECURITY] event=<event> ip=<ip> user=<user> ...
    switch (event.severity()) {
        .debug => log.debug("[SECURITY] event={s} ip={s} user={s} reason={s}", .{
            event_name, ctx.ip, user, reason,
        }),
        .info => log.info("[SECURITY] event={s} ip={s} user={s} reason={s}", .{
            event_name, ctx.ip, user, reason,
        }),
        .warn => log.warn("[SECURITY] event={s} ip={s} user={s} reason={s}", .{
            event_name, ctx.ip, user, reason,
        }),
        .err => log.err("[SECURITY] event={s} ip={s} user={s} reason={s}", .{
            event_name, ctx.ip, user, reason,
        }),
    }

    // Additional alert logging for security-relevant events
    if (event.isAlert()) {
        logAlert(event, ctx);
    }
}

/// Log security alerts that may require attention
fn logAlert(event: SecurityEvent, ctx: EventContext) void {
    const event_name = @tagName(event);

    // These are potential attack indicators
    switch (event) {
        .potential_bruteforce => {
            log.err("[ALERT] Bruteforce detected from {s}: {d} failures", .{
                ctx.ip,
                ctx.failure_count orelse 0,
            });
        },
        .ip_banned => {
            log.err("[ALERT] IP {s} banned for {d}s after repeated failures", .{
                ctx.ip,
                ctx.ban_duration_s orelse 0,
            });
        },
        .command_rejected => {
            log.err("[ALERT] Rejected command from {s}: {s}", .{
                ctx.ip,
                ctx.command orelse "unknown",
            });
        },
        else => {
            log.warn("[ALERT] Suspicious activity: {s} from {s}", .{
                event_name, ctx.ip,
            });
        },
    }
}

// Convenience functions for common events

/// Log a connection attempt
pub fn logConnectionAttempt(ip: []const u8) void {
    logEvent(.connection_attempt, .{ .ip = ip });
}

/// Log a successful connection
pub fn logConnectionAccepted(ip: []const u8) void {
    logEvent(.connection_accepted, .{ .ip = ip });
}

/// Log a connection rejection due to rate limiting
pub fn logConnectionRejectedRateLimit(ip: []const u8) void {
    logEvent(.connection_rejected_rate_limit, .{
        .ip = ip,
        .reason = "rate limit exceeded",
    });
}

/// Log a connection rejection due to IP ban
pub fn logConnectionRejectedBanned(ip: []const u8, remaining_seconds: i64) void {
    var buf: [64]u8 = undefined;
    const reason = std.fmt.bufPrint(&buf, "banned for {d}s more", .{remaining_seconds}) catch "banned";
    logEvent(.connection_rejected_banned, .{
        .ip = ip,
        .reason = reason,
    });
}

/// Log a connection rejection due to connection limit
pub fn logConnectionRejectedLimit(ip: []const u8, reason: []const u8) void {
    logEvent(.connection_rejected_limit, .{
        .ip = ip,
        .reason = reason,
    });
}

/// Log successful authentication
pub fn logAuthSuccess(ip: []const u8, username: []const u8, key_fingerprint: ?[]const u8) void {
    logEvent(.auth_success, .{
        .ip = ip,
        .username = username,
        .key_fingerprint = key_fingerprint,
    });
}

/// Log authentication failure
pub fn logAuthFailure(event: SecurityEvent, ip: []const u8, username: ?[]const u8, reason: ?[]const u8) void {
    logEvent(event, .{
        .ip = ip,
        .username = username,
        .reason = reason,
    });
}

/// Log an IP being banned
pub fn logIPBanned(ip: []const u8, duration_seconds: i64, failure_count: u32) void {
    logEvent(.ip_banned, .{
        .ip = ip,
        .ban_duration_s = duration_seconds,
        .failure_count = failure_count,
    });
}

/// Log session start
pub fn logSessionStarted(ip: []const u8, username: []const u8) void {
    logEvent(.session_started, .{
        .ip = ip,
        .username = username,
    });
}

/// Log session close
pub fn logSessionClosed(ip: []const u8, username: ?[]const u8, duration_ms: i64) void {
    logEvent(.session_closed, .{
        .ip = ip,
        .username = username,
        .duration_ms = duration_ms,
    });
}

/// Log command execution
pub fn logCommandExecuted(ip: []const u8, username: []const u8, command: []const u8) void {
    logEvent(.command_executed, .{
        .ip = ip,
        .username = username,
        .command = command,
    });
}

/// Log command rejection
pub fn logCommandRejected(ip: []const u8, username: []const u8, command: []const u8, reason: []const u8) void {
    logEvent(.command_rejected, .{
        .ip = ip,
        .username = username,
        .command = command,
        .reason = reason,
    });
}

test "SecurityEvent properties" {
    // Alert events
    try std.testing.expect(SecurityEvent.auth_failure_invalid_key.isAlert());
    try std.testing.expect(SecurityEvent.ip_banned.isAlert());

    // Non-alert events
    try std.testing.expect(!SecurityEvent.connection_attempt.isAlert());
    try std.testing.expect(!SecurityEvent.auth_success.isAlert());

    // Severity levels
    try std.testing.expectEqual(Severity.info, SecurityEvent.connection_attempt.severity());
    try std.testing.expectEqual(Severity.warn, SecurityEvent.auth_failure_invalid_key.severity());
    try std.testing.expectEqual(Severity.err, SecurityEvent.ip_banned.severity());
}
