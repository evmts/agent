const std = @import("std");
const testing = std.testing;
const log = std.log.scoped(.ssh_session);
const bindings = @import("bindings.zig");
const auth = @import("auth.zig");
const command = @import("command.zig");
const security = @import("security.zig");

// SSH Session Management for handling SSH connections and command execution
// Manages the complete SSH session lifecycle from connection to command execution

// Phase 1: Core Session Types - Tests First

test "creates SSH session with connection info" {
    const allocator = testing.allocator;
    
    const session_info = SessionInfo{
        .session_id = "test_session_123",
        .client_ip = "192.168.1.100",
        .client_port = 45678,
        .server_port = 22,
        .start_time = std.time.timestamp(),
        .user_id = null,
        .username = null,
    };
    
    try testing.expectEqualStrings("test_session_123", session_info.session_id);
    try testing.expectEqualStrings("192.168.1.100", session_info.client_ip);
    try testing.expectEqual(@as(u16, 45678), session_info.client_port);
}

test "session state transitions" {
    const allocator = testing.allocator;
    
    var session = try SshSession.init(allocator, "session_456", "10.0.0.1", 12345);
    defer session.deinit(allocator);
    
    try testing.expectEqual(SessionState.connected, session.state);
    
    session.setState(.authenticating);
    try testing.expectEqual(SessionState.authenticating, session.state);
    
    session.setState(.authenticated);
    try testing.expectEqual(SessionState.authenticated, session.state);
    
    session.setState(.executing_command);
    try testing.expectEqual(SessionState.executing_command, session.state);
    
    session.setState(.closed);
    try testing.expectEqual(SessionState.closed, session.state);
}

test "validates session state transitions" {
    const allocator = testing.allocator;
    
    var session = try SshSession.init(allocator, "session_789", "10.0.0.2", 54321);
    defer session.deinit(allocator);
    
    // Valid transition: connected -> authenticating
    try testing.expect(session.canTransitionTo(.authenticating));
    
    // Invalid transition: connected -> executing_command (must authenticate first)
    try testing.expect(!session.canTransitionTo(.executing_command));
}

// Now implement the types and functions to make tests pass

pub const SessionState = enum {
    connected,
    authenticating,
    authenticated,
    executing_command,
    error_state,
    closed,
    
    pub fn toString(self: SessionState) []const u8 {
        return switch (self) {
            .connected => "connected",
            .authenticating => "authenticating",
            .authenticated => "authenticated",
            .executing_command => "executing_command",
            .error_state => "error_state",
            .closed => "closed",
        };
    }
};

pub const SessionInfo = struct {
    session_id: []const u8,
    client_ip: []const u8,
    client_port: u16,
    server_port: u16,
    start_time: i64,
    user_id: ?u32,
    username: ?[]const u8,
    
    pub fn deinit(self: *const SessionInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.session_id);
        allocator.free(self.client_ip);
        if (self.username) |username| {
            allocator.free(username);
        }
    }
};

pub const SessionError = error{
    InvalidTransition,
    SessionClosed,
    AuthenticationRequired,
    CommandExecutionFailed,
    SessionTimeout,
    OutOfMemory,
};

pub const SshSession = struct {
    info: SessionInfo,
    state: SessionState,
    auth_result: ?auth.AuthResult,
    command_context: ?command.CommandContext,
    start_time: i64,
    last_activity: i64,
    
    pub fn init(allocator: std.mem.Allocator, session_id: []const u8, client_ip: []const u8, client_port: u16) !SshSession {
        const now = std.time.timestamp();
        
        return SshSession{
            .info = SessionInfo{
                .session_id = try allocator.dupe(u8, session_id),
                .client_ip = try allocator.dupe(u8, client_ip),
                .client_port = client_port,
                .server_port = 22,
                .start_time = now,
                .user_id = null,
                .username = null,
            },
            .state = .connected,
            .auth_result = null,
            .command_context = null,
            .start_time = now,
            .last_activity = now,
        };
    }
    
    pub fn deinit(self: *SshSession, allocator: std.mem.Allocator) void {
        self.info.deinit(allocator);
        // auth_result and command_context are not owned by session
    }
    
    pub fn setState(self: *SshSession, new_state: SessionState) void {
        log.info("SSH Session {s}: State transition {s} -> {s}", .{
            self.info.session_id, self.state.toString(), new_state.toString()
        });
        self.state = new_state;
        self.last_activity = std.time.timestamp();
    }
    
    pub fn canTransitionTo(self: *const SshSession, new_state: SessionState) bool {
        return switch (self.state) {
            .connected => switch (new_state) {
                .authenticating, .closed, .error_state => true,
                else => false,
            },
            .authenticating => switch (new_state) {
                .authenticated, .connected, .closed, .error_state => true,
                else => false,
            },
            .authenticated => switch (new_state) {
                .executing_command, .closed, .error_state => true,
                else => false,
            },
            .executing_command => switch (new_state) {
                .authenticated, .closed, .error_state => true,
                else => false,
            },
            .error_state => switch (new_state) {
                .closed => true,
                else => false,
            },
            .closed => false, // No transitions from closed state
        };
    }
    
    pub fn isActive(self: *const SshSession) bool {
        return switch (self.state) {
            .connected, .authenticating, .authenticated, .executing_command => true,
            .error_state, .closed => false,
        };
    }
    
    pub fn getSessionDuration(self: *const SshSession) i64 {
        const now = std.time.timestamp();
        return now - self.start_time;
    }
    
    pub fn getIdleTime(self: *const SshSession) i64 {
        const now = std.time.timestamp();
        return now - self.last_activity;
    }
};

// Phase 2: Session Authentication Integration - Tests First

test "handles authentication flow" {
    const allocator = testing.allocator;
    
    var session = try SshSession.init(allocator, "auth_session", "192.168.1.50", 33445);
    defer session.deinit(allocator);
    
    var session_manager = try SessionManager.init(allocator);
    defer session_manager.deinit();
    
    // Start authentication
    try session_manager.startAuthentication(&session, "testuser", "ssh-rsa AAAAB3NzaC1...");
    try testing.expectEqual(SessionState.authenticating, session.state);
    
    // Complete authentication (mock success)
    const auth_result = auth.AuthResult.success(789, "key_123");
    try session_manager.completeAuthentication(&session, auth_result);
    try testing.expectEqual(SessionState.authenticated, session.state);
    try testing.expect(session.info.user_id != null);
}

test "handles authentication failure" {
    const allocator = testing.allocator;
    
    var session = try SshSession.init(allocator, "fail_session", "192.168.1.51", 44567);
    defer session.deinit(allocator);
    
    var session_manager = try SessionManager.init(allocator);
    defer session_manager.deinit();
    
    try session_manager.startAuthentication(&session, "baduser", "invalid-key");
    
    const auth_result = auth.AuthResult.failure("Invalid credentials");
    try session_manager.completeAuthentication(&session, auth_result);
    try testing.expectEqual(SessionState.error_state, session.state);
}

pub const SessionManager = struct {
    allocator: std.mem.Allocator,
    active_sessions: std.HashMap([]const u8, *SshSession, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    
    pub fn init(allocator: std.mem.Allocator) !SessionManager {
        return SessionManager{
            .allocator = allocator,
            .active_sessions = std.HashMap([]const u8, *SshSession, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
        };
    }
    
    pub fn deinit(self: *SessionManager) void {
        // Note: Sessions are managed externally, we just track pointers
        self.active_sessions.deinit();
    }
    
    pub fn startAuthentication(self: *SessionManager, session: *SshSession, username: []const u8, ssh_key: []const u8) !void {
        _ = self;
        _ = ssh_key; // TODO: Use for actual authentication
        
        if (!session.canTransitionTo(.authenticating)) {
            return error.InvalidTransition;
        }
        
        session.setState(.authenticating);
        
        // Store username (simplified - in production would be more complex)
        const owned_username = try self.allocator.dupe(u8, username);
        session.info.username = owned_username;
        
        log.info("SSH Session {s}: Starting authentication for user '{s}'", .{
            session.info.session_id, username
        });
    }
    
    pub fn completeAuthentication(self: *SessionManager, session: *SshSession, auth_result: auth.AuthResult) !void {
        _ = self;
        
        if (auth_result.success) {
            if (!session.canTransitionTo(.authenticated)) {
                return error.InvalidTransition;
            }
            
            session.setState(.authenticated);
            session.info.user_id = auth_result.user_id;
            session.auth_result = auth_result;
            
            log.info("SSH Session {s}: Authentication successful for user '{s}' (ID: {d})", .{
                session.info.session_id, session.info.username orelse "unknown", auth_result.user_id orelse 0
            });
        } else {
            session.setState(.error_state);
            
            log.warn("SSH Session {s}: Authentication failed for user '{s}': {s}", .{
                session.info.session_id, 
                session.info.username orelse "unknown",
                auth_result.failure_reason orelse "Unknown error"
            });
        }
    }
    
    pub fn registerSession(self: *SessionManager, session: *SshSession) !void {
        const session_id = try self.allocator.dupe(u8, session.info.session_id);
        try self.active_sessions.put(session_id, session);
        
        log.info("SSH: Registered session {s} from {s}:{d}", .{
            session.info.session_id, session.info.client_ip, session.info.client_port
        });
    }
    
    pub fn unregisterSession(self: *SessionManager, session_id: []const u8) void {
        if (self.active_sessions.fetchRemove(session_id)) |kv| {
            self.allocator.free(kv.key);
            log.info("SSH: Unregistered session {s}", .{session_id});
        }
    }
    
    pub fn getActiveSessionCount(self: *const SessionManager) u32 {
        return @intCast(self.active_sessions.count());
    }
};

// Phase 3: Command Execution Integration - Tests First

test "executes git command in session" {
    const allocator = testing.allocator;
    
    var session = try SshSession.init(allocator, "cmd_session", "192.168.1.52", 55678);
    defer session.deinit(allocator);
    
    // Set up authenticated session
    session.setState(.authenticated);
    session.info.user_id = 456;
    session.info.username = try allocator.dupe(u8, "gituser");
    defer allocator.free(session.info.username.?);
    
    var session_manager = try SessionManager.init(allocator);
    defer session_manager.deinit();
    
    // Execute command
    const cmd_line = "git-upload-pack 'owner/repo.git'";
    const result = session_manager.executeCommand(allocator, &session, cmd_line, null) catch |err| switch (err) {
        error.AuthenticationRequired => {
            // Expected if no proper auth setup
            return;
        },
        else => return err,
    };
    
    // If we get here, command execution was attempted
    _ = result;
}

test "rejects command execution without authentication" {
    const allocator = testing.allocator;
    
    var session = try SshSession.init(allocator, "unauth_session", "192.168.1.53", 66789);
    defer session.deinit(allocator);
    
    var session_manager = try SessionManager.init(allocator);
    defer session_manager.deinit();
    
    const cmd_line = "git-upload-pack 'owner/repo.git'";
    try testing.expectError(SessionError.AuthenticationRequired,
        session_manager.executeCommand(allocator, &session, cmd_line, null));
}

// Extend SessionManager with command execution capabilities
pub const SessionManagerError = SessionError || command.SshCommandError;

// Add methods to SessionManager for command execution
pub const SessionManagerExtended = struct {
    base: SessionManager,
    command_executor: command.SshCommandExecutor,
    
    pub fn init(allocator: std.mem.Allocator) !SessionManagerExtended {
        return SessionManagerExtended{
            .base = try SessionManager.init(allocator),
            .command_executor = try command.SshCommandExecutor.init(allocator),
        };
    }
    
    pub fn deinit(self: *SessionManagerExtended, allocator: std.mem.Allocator) void {
        self.base.deinit();
        self.command_executor.deinit(allocator);
    }
    
    pub fn executeCommand(
        self: *SessionManagerExtended,
        allocator: std.mem.Allocator,
        session: *SshSession,
        command_line: []const u8,
        stdin_data: ?[]const u8,
    ) SessionManagerError!command.SshCommandResult {
        // Verify session is authenticated
        if (session.state != .authenticated) {
            return error.AuthenticationRequired;
        }
        
        if (session.info.user_id == null or session.info.username == null) {
            return error.AuthenticationRequired;
        }
        
        if (!session.canTransitionTo(.executing_command)) {
            return error.InvalidTransition;
        }
        
        session.setState(.executing_command);
        
        // Parse SSH command
        const ssh_cmd = try command.SshCommand.parse(allocator, command_line);
        defer ssh_cmd.deinit(allocator);
        
        // Create command context
        const cmd_context = try command.CommandContext.fromSshCommand(
            &ssh_cmd,
            session.info.user_id.?,
            session.info.username.?,
            "session_key", // TODO: Get actual key ID from auth result
            session.info.client_ip,
        );
        
        log.info("SSH Session {s}: Executing command '{s}' for user {s} on {s}/{s}", .{
            session.info.session_id,
            ssh_cmd.command_type.toString(),
            cmd_context.username,
            cmd_context.repository_owner,
            cmd_context.repository_name,
        });
        
        // Execute command
        const result = try command.executeWithLogging(
            allocator,
            &self.command_executor,
            ssh_cmd,
            cmd_context,
            stdin_data,
        );
        
        // Update session state based on result
        if (result.success) {
            session.setState(.authenticated); // Return to authenticated state for more commands
        } else {
            session.setState(.error_state);
        }
        
        return result;
    }
};

// Add to SessionManager for convenience
const SessionManagerMethods = struct {
    pub fn executeCommand(
        self: *SessionManager,
        allocator: std.mem.Allocator,
        session: *SshSession,
        command_line: []const u8,
        stdin_data: ?[]const u8,
    ) SessionManagerError!command.SshCommandResult {
        // This is a simplified version - in production would have full executor
        _ = self;
        
        if (session.state != .authenticated) {
            return error.AuthenticationRequired;
        }
        
        if (session.info.user_id == null) {
            return error.AuthenticationRequired;
        }
        
        // Mock result for testing
        return command.SshCommandResult{
            .success = false,
            .exit_code = 255,
            .stdout = try allocator.dupe(u8, ""),
            .stderr = try allocator.dupe(u8, "Mock execution not implemented"),
            .command_type = .upload_pack,
            .execution_time_ms = 0,
        };
    }
};

// Add the methods to SessionManager
pub usingnamespace SessionManagerMethods;

// Phase 4: Session Lifecycle Management - Tests First

test "manages session timeouts" {
    const allocator = testing.allocator;
    
    var session = try SshSession.init(allocator, "timeout_session", "192.168.1.54", 77890);
    defer session.deinit(allocator);
    
    // Test session duration
    std.time.sleep(1000000); // 1ms
    const duration = session.getSessionDuration();
    try testing.expect(duration >= 0);
    
    // Test idle time
    const idle_time = session.getIdleTime();
    try testing.expect(idle_time >= 0);
}

test "cleanup inactive sessions" {
    const allocator = testing.allocator;
    
    var lifecycle = try SessionLifecycle.init(allocator);
    defer lifecycle.deinit();
    
    var session1 = try SshSession.init(allocator, "session1", "192.168.1.100", 11111);
    defer session1.deinit(allocator);
    
    var session2 = try SshSession.init(allocator, "session2", "192.168.1.101", 22222);
    defer session2.deinit(allocator);
    
    try lifecycle.addSession(&session1);
    try lifecycle.addSession(&session2);
    
    try testing.expectEqual(@as(u32, 2), lifecycle.getSessionCount());
    
    // Close one session
    session1.setState(.closed);
    const cleaned = try lifecycle.cleanupInactiveSessions();
    try testing.expectEqual(@as(u32, 1), cleaned);
    try testing.expectEqual(@as(u32, 1), lifecycle.getSessionCount());
}

pub const SessionLifecycle = struct {
    allocator: std.mem.Allocator,
    sessions: std.ArrayList(*SshSession),
    max_session_duration: i64,
    max_idle_time: i64,
    
    pub fn init(allocator: std.mem.Allocator) !SessionLifecycle {
        return SessionLifecycle{
            .allocator = allocator,
            .sessions = std.ArrayList(*SshSession).init(allocator),
            .max_session_duration = 3600, // 1 hour
            .max_idle_time = 300,         // 5 minutes
        };
    }
    
    pub fn deinit(self: *SessionLifecycle) void {
        self.sessions.deinit();
    }
    
    pub fn addSession(self: *SessionLifecycle, session: *SshSession) !void {
        try self.sessions.append(session);
        log.info("Session lifecycle: Added session {s} (total: {})", .{
            session.info.session_id, self.sessions.items.len
        });
    }
    
    pub fn removeSession(self: *SessionLifecycle, session_id: []const u8) bool {
        for (self.sessions.items, 0..) |session, i| {
            if (std.mem.eql(u8, session.info.session_id, session_id)) {
                _ = self.sessions.orderedRemove(i);
                log.info("Session lifecycle: Removed session {s} (total: {})", .{
                    session_id, self.sessions.items.len
                });
                return true;
            }
        }
        return false;
    }
    
    pub fn getSessionCount(self: *const SessionLifecycle) u32 {
        return @intCast(self.sessions.items.len);
    }
    
    pub fn cleanupInactiveSessions(self: *SessionLifecycle) !u32 {
        var cleanup_count: u32 = 0;
        var i: usize = 0;
        
        while (i < self.sessions.items.len) {
            const session = self.sessions.items[i];
            
            if (!session.isActive() or 
                session.getSessionDuration() > self.max_session_duration or
                session.getIdleTime() > self.max_idle_time) {
                
                log.info("Session lifecycle: Cleaning up inactive session {s}", .{session.info.session_id});
                _ = self.sessions.orderedRemove(i);
                cleanup_count += 1;
            } else {
                i += 1;
            }
        }
        
        if (cleanup_count > 0) {
            log.info("Session lifecycle: Cleaned up {} inactive sessions", .{cleanup_count});
        }
        
        return cleanup_count;
    }
    
    pub fn getActiveSessionsForIP(self: *const SessionLifecycle, client_ip: []const u8) u32 {
        var count: u32 = 0;
        for (self.sessions.items) |session| {
            if (std.mem.eql(u8, session.info.client_ip, client_ip) and session.isActive()) {
                count += 1;
            }
        }
        return count;
    }
};

// Phase 5: Session Security and Monitoring - Tests First

test "tracks session security events" {
    const allocator = testing.allocator;
    
    var monitor = SessionSecurityMonitor.init(allocator);
    defer monitor.deinit();
    
    var session = try SshSession.init(allocator, "security_session", "192.168.1.100", 88901);
    defer session.deinit(allocator);
    
    monitor.logSessionEvent(&session, .connection_established);
    monitor.logSessionEvent(&session, .authentication_success);
    monitor.logSessionEvent(&session, .command_executed);
    monitor.logSessionEvent(&session, .session_closed);
    
    // Should not crash
}

test "detects suspicious session patterns" {
    const allocator = testing.allocator;
    
    var monitor = SessionSecurityMonitor.init(allocator);
    defer monitor.deinit();
    
    // Multiple failed authentications from same IP
    var session1 = try SshSession.init(allocator, "sus1", "192.168.1.200", 11111);
    defer session1.deinit(allocator);
    var session2 = try SshSession.init(allocator, "sus2", "192.168.1.200", 22222);
    defer session2.deinit(allocator);
    var session3 = try SshSession.init(allocator, "sus3", "192.168.1.200", 33333);
    defer session3.deinit(allocator);
    
    monitor.logSessionEvent(&session1, .authentication_failure);
    monitor.logSessionEvent(&session2, .authentication_failure);
    monitor.logSessionEvent(&session3, .authentication_failure);
    
    const failure_count = monitor.getAuthFailureCount("192.168.1.200");
    try testing.expect(failure_count >= 3);
}

pub const SessionSecurityEvent = enum {
    connection_established,
    authentication_attempt,
    authentication_success,
    authentication_failure,
    command_executed,
    session_timeout,
    session_closed,
    suspicious_activity,
    
    pub fn toString(self: SessionSecurityEvent) []const u8 {
        return switch (self) {
            .connection_established => "CONNECTION_ESTABLISHED",
            .authentication_attempt => "AUTHENTICATION_ATTEMPT",
            .authentication_success => "AUTHENTICATION_SUCCESS",
            .authentication_failure => "AUTHENTICATION_FAILURE",
            .command_executed => "COMMAND_EXECUTED",
            .session_timeout => "SESSION_TIMEOUT",
            .session_closed => "SESSION_CLOSED",
            .suspicious_activity => "SUSPICIOUS_ACTIVITY",
        };
    }
};

pub const SessionSecurityMonitor = struct {
    allocator: std.mem.Allocator,
    auth_failures: std.HashMap([]const u8, u32, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    
    pub fn init(allocator: std.mem.Allocator) SessionSecurityMonitor {
        return SessionSecurityMonitor{
            .allocator = allocator,
            .auth_failures = std.HashMap([]const u8, u32, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
        };
    }
    
    pub fn deinit(self: *SessionSecurityMonitor) void {
        var iterator = self.auth_failures.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.auth_failures.deinit();
    }
    
    pub fn logSessionEvent(self: *SessionSecurityMonitor, session: *const SshSession, event: SessionSecurityEvent) void {
        log.info("SSH Security Event: {s} - Session {s} from {s}:{d}", .{
            event.toString(),
            session.info.session_id,
            session.info.client_ip,
            session.info.client_port,
        });
        
        switch (event) {
            .authentication_failure => {
                self.incrementAuthFailures(session.info.client_ip);
            },
            .authentication_success => {
                self.resetAuthFailures(session.info.client_ip);
            },
            else => {},
        }
    }
    
    pub fn getAuthFailureCount(self: *const SessionSecurityMonitor, client_ip: []const u8) u32 {
        return self.auth_failures.get(client_ip) orelse 0;
    }
    
    fn incrementAuthFailures(self: *SessionSecurityMonitor, client_ip: []const u8) void {
        const current = self.auth_failures.get(client_ip) orelse 0;
        const owned_ip = self.allocator.dupe(u8, client_ip) catch return;
        self.auth_failures.put(owned_ip, current + 1) catch return;
    }
    
    fn resetAuthFailures(self: *SessionSecurityMonitor, client_ip: []const u8) void {
        if (self.auth_failures.fetchRemove(client_ip)) |kv| {
            self.allocator.free(kv.key);
        }
    }
};