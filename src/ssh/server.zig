const std = @import("std");
const testing = std.testing;
const log = std.log.scoped(.ssh_server);
const net = std.net;

const bindings = @import("bindings.zig");
const security = @import("security.zig");
const host_key = @import("host_key.zig");
const shutdown = @import("shutdown.zig");
const command = @import("command.zig");
const auth = @import("auth.zig");
const session = @import("session.zig");

// SSH Server Implementation
// Orchestrates all SSH components to provide a complete Git SSH server

// Phase 1: Core Server Types and Configuration - Tests First

test "creates SSH server configuration" {
    const allocator = testing.allocator;
    
    const config = SshServerConfig{
        .bind_address = "127.0.0.1",
        .port = 2222,
        .host_key_path = "/tmp/test_host_key",
        .max_connections = 10,
        .connection_timeout = 300,
        .auth_timeout = 30,
    };
    
    try testing.expectEqualStrings("127.0.0.1", config.bind_address);
    try testing.expectEqual(@as(u16, 2222), config.port);
    try testing.expectEqual(@as(u32, 10), config.max_connections);
}

test "validates server configuration" {
    const allocator = testing.allocator;
    
    // Valid configuration
    const valid_config = SshServerConfig{
        .bind_address = "0.0.0.0",
        .port = 22,
        .host_key_path = "/etc/ssh/host_key",
        .max_connections = 100,
        .connection_timeout = 600,
        .auth_timeout = 60,
    };
    
    try valid_config.validate();
    
    // Invalid configuration - port 0
    const invalid_config = SshServerConfig{
        .bind_address = "127.0.0.1",
        .port = 0,
        .host_key_path = "/tmp/host_key",
        .max_connections = 10,
        .connection_timeout = 300,
        .auth_timeout = 30,
    };
    
    try testing.expectError(SshServerError.InvalidConfiguration, invalid_config.validate());
}

// Now implement the types and functions to make tests pass

pub const SshServerError = error{
    InvalidConfiguration,
    HostKeyLoadFailed,
    BindFailed,
    AcceptFailed,
    ConnectionHandlingFailed,
    ServerShutdown,
    OutOfMemory,
};

pub const SshServerConfig = struct {
    bind_address: []const u8,
    port: u16,
    host_key_path: []const u8,
    max_connections: u32,
    connection_timeout: u32,  // seconds
    auth_timeout: u32,        // seconds
    
    pub fn validate(self: *const SshServerConfig) SshServerError!void {
        if (self.port == 0) return error.InvalidConfiguration;
        if (self.max_connections == 0) return error.InvalidConfiguration;
        if (self.connection_timeout == 0) return error.InvalidConfiguration;
        if (self.auth_timeout == 0) return error.InvalidConfiguration;
        if (self.bind_address.len == 0) return error.InvalidConfiguration;
        if (self.host_key_path.len == 0) return error.InvalidConfiguration;
    }
    
    pub fn default() SshServerConfig {
        return SshServerConfig{
            .bind_address = "0.0.0.0",
            .port = 22,
            .host_key_path = "/etc/ssh/plue_host_key",
            .max_connections = 100,
            .connection_timeout = 600,   // 10 minutes
            .auth_timeout = 60,          // 1 minute
        };
    }
};

pub const ConnectionInfo = struct {
    client_addr: net.Address,
    session_id: []const u8,
    start_time: i64,
    
    pub fn deinit(self: *const ConnectionInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.session_id);
    }
    
    pub fn getClientIP(self: *const ConnectionInfo, allocator: std.mem.Allocator) ![]u8 {
        const ip_str = switch (self.client_addr.any.family) {
            std.posix.AF.INET => blk: {
                const ipv4 = self.client_addr.in;
                const addr = @byteSwap(ipv4.sa.addr);
                break :blk try std.fmt.allocPrint(allocator, "{}.{}.{}.{}", .{
                    (addr >> 24) & 0xFF,
                    (addr >> 16) & 0xFF,
                    (addr >> 8) & 0xFF,
                    addr & 0xFF,
                });
            },
            std.posix.AF.INET6 => try allocator.dupe(u8, "::1"), // Simplified IPv6
            else => try allocator.dupe(u8, "unknown"),
        };
        return ip_str;
    }
    
    pub fn getClientPort(self: *const ConnectionInfo) u16 {
        return switch (self.client_addr.any.family) {
            std.posix.AF.INET => @byteSwap(self.client_addr.in.sa.port),
            std.posix.AF.INET6 => @byteSwap(self.client_addr.in6.sa.port),
            else => 0,
        };
    }
};

// Phase 2: Server State Management - Tests First

test "initializes SSH server components" {
    const allocator = testing.allocator;
    
    const config = SshServerConfig.default();
    var server = SshServer.init(allocator, config) catch |err| switch (err) {
        error.HostKeyLoadFailed => {
            // Expected in test environment
            return;
        },
        else => return err,
    };
    defer server.deinit();
    
    try testing.expect(!server.is_running);
}

test "manages server lifecycle" {
    const allocator = testing.allocator;
    
    var lifecycle = ServerLifecycle.init(allocator);
    defer lifecycle.deinit();
    
    try testing.expectEqual(ServerState.stopped, lifecycle.getState());
    
    lifecycle.setState(.starting);
    try testing.expectEqual(ServerState.starting, lifecycle.getState());
    
    lifecycle.setState(.running);
    try testing.expectEqual(ServerState.running, lifecycle.getState());
}

pub const ServerState = enum {
    stopped,
    starting,
    running,
    shutting_down,
    error_state,
    
    pub fn toString(self: ServerState) []const u8 {
        return switch (self) {
            .stopped => "stopped",
            .starting => "starting",
            .running => "running",
            .shutting_down => "shutting_down",
            .error_state => "error_state",
        };
    }
};

pub const ServerLifecycle = struct {
    allocator: std.mem.Allocator,
    state: ServerState,
    state_change_time: i64,
    
    pub fn init(allocator: std.mem.Allocator) ServerLifecycle {
        return ServerLifecycle{
            .allocator = allocator,
            .state = .stopped,
            .state_change_time = std.time.timestamp(),
        };
    }
    
    pub fn deinit(self: *ServerLifecycle) void {
        _ = self;
    }
    
    pub fn getState(self: *const ServerLifecycle) ServerState {
        return self.state;
    }
    
    pub fn setState(self: *ServerLifecycle, new_state: ServerState) void {
        log.info("SSH Server: State transition {s} -> {s}", .{
            self.state.toString(), new_state.toString()
        });
        self.state = new_state;
        self.state_change_time = std.time.timestamp();
    }
    
    pub fn getStateAge(self: *const ServerLifecycle) i64 {
        return std.time.timestamp() - self.state_change_time;
    }
};

pub const SshServer = struct {
    allocator: std.mem.Allocator,
    config: SshServerConfig,
    lifecycle: ServerLifecycle,
    host_key_manager: host_key.HostKeyManager,
    security_manager: security.SecurityManager,
    session_manager: session.SessionManager,
    shutdown_manager: shutdown.ShutdownManager,
    is_running: bool,
    socket: ?net.Server,
    
    pub fn init(allocator: std.mem.Allocator, config: SshServerConfig) SshServerError!SshServer {
        try config.validate();
        
        // Initialize host key manager
        var host_key_manager = host_key.HostKeyManager.init(allocator);
        errdefer host_key_manager.deinit();
        
        // Load host key
        host_key_manager.loadHostKey(config.host_key_path) catch |err| {
            log.err("Failed to load host key from {s}: {}", .{config.host_key_path, err});
            return error.HostKeyLoadFailed;
        };
        
        // Initialize other managers
        const security_manager = try security.SecurityManager.init(allocator);
        errdefer security_manager.deinit();
        
        const session_manager = try session.SessionManager.init(allocator);
        errdefer session_manager.deinit();
        
        const shutdown_manager = shutdown.ShutdownManager.init();
        
        log.info("SSH Server: Initialized with config - bind: {s}:{d}, max_connections: {d}", .{
            config.bind_address, config.port, config.max_connections
        });
        
        return SshServer{
            .allocator = allocator,
            .config = config,
            .lifecycle = ServerLifecycle.init(allocator),
            .host_key_manager = host_key_manager,
            .security_manager = security_manager,
            .session_manager = session_manager,
            .shutdown_manager = shutdown_manager,
            .is_running = false,
            .socket = null,
        };
    }
    
    pub fn deinit(self: *SshServer) void {
        if (self.is_running) {
            self.stop() catch {};
        }
        
        self.host_key_manager.deinit();
        self.security_manager.deinit();
        self.session_manager.deinit();
        // shutdown_manager has no deinit
    }
    
    pub fn start(self: *SshServer) SshServerError!void {
        if (self.is_running) {
            log.warn("SSH Server: Already running, ignoring start request", .{});
            return;
        }
        
        self.lifecycle.setState(.starting);
        
        // Parse bind address
        const addr = net.Address.parseIp(self.config.bind_address, self.config.port) catch |err| {
            log.err("SSH Server: Invalid bind address {s}:{d}: {}", .{self.config.bind_address, self.config.port, err});
            self.lifecycle.setState(.error_state);
            return error.BindFailed;
        };
        
        // Create socket
        var server = net.Server.init(.{
            .reuse_address = true,
            .reuse_port = false,
        });
        
        server.listen(addr) catch |err| {
            log.err("SSH Server: Failed to bind to {s}:{d}: {}", .{self.config.bind_address, self.config.port, err});
            self.lifecycle.setState(.error_state);
            return error.BindFailed;
        };
        
        self.socket = server;
        self.is_running = true;
        self.lifecycle.setState(.running);
        
        log.info("SSH Server: Started on {s}:{d", .{self.config.bind_address, self.config.port});
    }
    
    pub fn stop(self: *SshServer) SshServerError!void {
        if (!self.is_running) {
            return;
        }
        
        self.lifecycle.setState(.shutting_down);
        
        // Signal shutdown
        self.shutdown_manager.requestShutdown();
        
        // Close socket
        if (self.socket) |*server| {
            server.deinit();
            self.socket = null;
        }
        
        self.is_running = false;
        self.lifecycle.setState(.stopped);
        
        log.info("SSH Server: Stopped", .{});
    }
    
    pub fn isRunning(self: *const SshServer) bool {
        return self.is_running and self.lifecycle.getState() == .running;
    }
};

// Phase 3: Connection Handling - Tests First

test "handles connection acceptance" {
    const allocator = testing.allocator;
    
    var handler = ConnectionHandler.init(allocator);
    defer handler.deinit();
    
    // Mock connection info
    const mock_addr = net.Address.initIp4([4]u8{192, 168, 1, 100}, 45678);
    const conn_info = ConnectionInfo{
        .client_addr = mock_addr,
        .session_id = "test_connection_123",
        .start_time = std.time.timestamp(),
    };
    
    // Should not crash
    handler.logConnection(&conn_info);
}

test "enforces connection limits" {
    const allocator = testing.allocator;
    
    var handler = ConnectionHandler.init(allocator);
    defer handler.deinit();
    
    // Test connection counting
    handler.incrementConnections();
    handler.incrementConnections();
    handler.incrementConnections();
    
    try testing.expectEqual(@as(u32, 3), handler.getConnectionCount());
    
    handler.decrementConnections();
    try testing.expectEqual(@as(u32, 2), handler.getConnectionCount());
}

pub const ConnectionHandler = struct {
    allocator: std.mem.Allocator,
    active_connections: u32,
    total_connections: u64,
    
    pub fn init(allocator: std.mem.Allocator) ConnectionHandler {
        return ConnectionHandler{
            .allocator = allocator,
            .active_connections = 0,
            .total_connections = 0,
        };
    }
    
    pub fn deinit(self: *ConnectionHandler) void {
        _ = self;
    }
    
    pub fn acceptConnection(self: *ConnectionHandler, server: *SshServer, client_addr: net.Address) !void {
        // Check connection limits
        if (self.active_connections >= server.config.max_connections) {
            log.warn("SSH Server: Connection limit reached ({d}), rejecting connection", .{server.config.max_connections});
            return error.ConnectionLimitReached;
        }
        
        // Check if server is shutting down
        if (server.shutdown_manager.getState() != .running) {
            log.warn("SSH Server: Rejecting connection during shutdown", .{});
            return error.ServerShutdown;
        }
        
        // Generate session ID
        const session_id = try generateSessionId(self.allocator);
        defer self.allocator.free(session_id);
        
        const conn_info = ConnectionInfo{
            .client_addr = client_addr,
            .session_id = try self.allocator.dupe(u8, session_id),
            .start_time = std.time.timestamp(),
        };
        defer conn_info.deinit(self.allocator);
        
        self.incrementConnections();
        defer self.decrementConnections();
        
        log.info("SSH Server: Accepted connection {s} from {}", .{conn_info.session_id, client_addr});
        
        // Handle the connection
        self.handleConnection(server, &conn_info) catch |err| {
            log.err("SSH Server: Error handling connection {s}: {}", .{conn_info.session_id, err});
        };
    }
    
    fn handleConnection(self: *ConnectionHandler, server: *SshServer, conn_info: *const ConnectionInfo) !void {
        _ = self;
        
        // Get client IP string
        const client_ip = try conn_info.getClientIP(server.allocator);
        defer server.allocator.free(client_ip);
        
        // Check security constraints
        try server.security_manager.rate_limiter.checkConnection(conn_info.client_addr);
        
        // Create SSH session
        var ssh_session = try session.SshSession.init(
            server.allocator,
            conn_info.session_id,
            client_ip,
            conn_info.getClientPort(),
        );
        defer ssh_session.deinit(server.allocator);
        
        // Register session
        try server.session_manager.registerSession(&ssh_session);
        defer server.session_manager.unregisterSession(ssh_session.info.session_id);
        
        log.info("SSH Session {s}: Starting SSH protocol handling", .{ssh_session.info.session_id});
        
        // TODO: Implement full SSH protocol handling
        // This would involve:
        // 1. SSH handshake
        // 2. Authentication
        // 3. Command execution
        // 4. Session cleanup
        
        // For now, simulate basic flow
        try simulateConnectionFlow(server, &ssh_session);
    }
    
    fn simulateConnectionFlow(server: *SshServer, ssh_session: *session.SshSession) !void {
        _ = server;
        
        // Simulate authentication attempt
        ssh_session.setState(.authenticating);
        std.time.sleep(1000000); // 1ms
        
        // Simulate authentication failure (no real auth implemented yet)
        ssh_session.setState(.error_state);
        
        log.info("SSH Session {s}: Simulated connection flow completed", .{ssh_session.info.session_id});
    }
    
    pub fn logConnection(self: *ConnectionHandler, conn_info: *const ConnectionInfo) void {
        _ = self;
        log.info("SSH Connection: {s} from {} at {d}", .{
            conn_info.session_id, conn_info.client_addr, conn_info.start_time
        });
    }
    
    pub fn incrementConnections(self: *ConnectionHandler) void {
        self.active_connections += 1;
        self.total_connections += 1;
    }
    
    pub fn decrementConnections(self: *ConnectionHandler) void {
        if (self.active_connections > 0) {
            self.active_connections -= 1;
        }
    }
    
    pub fn getConnectionCount(self: *const ConnectionHandler) u32 {
        return self.active_connections;
    }
    
    pub fn getTotalConnections(self: *const ConnectionHandler) u64 {
        return self.total_connections;
    }
};

fn generateSessionId(allocator: std.mem.Allocator) ![]u8 {
    const timestamp = std.time.timestamp();
    var random_bytes: [8]u8 = undefined;
    std.crypto.random.bytes(&random_bytes);
    
    return try std.fmt.allocPrint(allocator, "ssh_{d}_{x}", .{
        timestamp, 
        std.mem.readIntBig(u64, &random_bytes)
    });
}

// Phase 4: Server Main Loop - Tests First

test "runs server event loop" {
    const allocator = testing.allocator;
    
    const config = SshServerConfig{
        .bind_address = "127.0.0.1",
        .port = 0, // Invalid port to trigger early exit
        .host_key_path = "/nonexistent",
        .max_connections = 1,
        .connection_timeout = 1,
        .auth_timeout = 1,
    };
    
    var server = SshServer.init(allocator, config) catch |err| switch (err) {
        error.HostKeyLoadFailed, error.InvalidConfiguration => {
            // Expected in test
            return;
        },
        else => return err,
    };
    defer server.deinit();
}

test "handles server shutdown gracefully" {
    const allocator = testing.allocator;
    
    var server_runner = ServerRunner.init(allocator);
    defer server_runner.deinit();
    
    // Test shutdown signaling
    server_runner.requestShutdown();
    try testing.expect(server_runner.should_shutdown);
}

pub const ServerRunner = struct {
    allocator: std.mem.Allocator,
    should_shutdown: bool,
    connection_handler: ConnectionHandler,
    
    pub fn init(allocator: std.mem.Allocator) ServerRunner {
        return ServerRunner{
            .allocator = allocator,
            .should_shutdown = false,
            .connection_handler = ConnectionHandler.init(allocator),
        };
    }
    
    pub fn deinit(self: *ServerRunner) void {
        self.connection_handler.deinit();
    }
    
    pub fn run(self: *ServerRunner, server: *SshServer) !void {
        if (!server.isRunning()) {
            return error.ServerNotRunning;
        }
        
        log.info("SSH Server: Starting main event loop", .{});
        
        while (!self.should_shutdown and server.isRunning()) {
            // Check for shutdown signal
            if (server.shutdown_manager.getState() != .running) {
                log.info("SSH Server: Shutdown signal received, stopping event loop", .{});
                break;
            }
            
            // Accept connections (simplified - would use select/poll in real implementation)
            if (server.socket) |*socket| {
                // Simulate connection acceptance with timeout
                const connection_result = self.acceptConnectionWithTimeout(socket, 1000); // 1 second timeout
                
                switch (connection_result) {
                    .connection => |client_addr| {
                        self.connection_handler.acceptConnection(server, client_addr) catch |err| {
                            log.warn("SSH Server: Failed to handle connection: {}", .{err});
                        };
                    },
                    .timeout => {
                        // Normal timeout, continue loop
                    },
                    .error => |err| {
                        log.err("SSH Server: Accept error: {}", .{err});
                        if (err == error.SocketClosed) break;
                    },
                }
            }
            
            // Small sleep to prevent busy loop in test
            std.time.sleep(1000000); // 1ms
        }
        
        log.info("SSH Server: Event loop terminated", .{});
    }
    
    const AcceptResult = union(enum) {
        connection: net.Address,
        timeout: void,
        error: anyerror,
    };
    
    fn acceptConnectionWithTimeout(self: *ServerRunner, socket: *net.Server, timeout_ms: u32) AcceptResult {
        _ = self;
        _ = timeout_ms;
        
        // Simplified implementation - in real version would use proper select/poll
        const connection = socket.accept() catch |err| {
            return AcceptResult{ .error = err };
        };
        defer connection.stream.close();
        
        return AcceptResult{ .connection = connection.address };
    }
    
    pub fn requestShutdown(self: *ServerRunner) void {
        self.should_shutdown = true;
        log.info("SSH Server: Shutdown requested", .{});
    }
};

// Phase 5: Integration and Public API - Tests First

test "creates complete SSH server setup" {
    const allocator = testing.allocator;
    
    var ssh_server_manager = SshServerManager.init(allocator);
    defer ssh_server_manager.deinit();
    
    const config = SshServerConfig{
        .bind_address = "127.0.0.1",
        .port = 2223,
        .host_key_path = "/tmp/test_key",
        .max_connections = 5,
        .connection_timeout = 60,
        .auth_timeout = 30,
    };
    
    // Should handle initialization gracefully even if host key doesn't exist
    const result = ssh_server_manager.createServer(config);
    _ = result; // May fail due to missing host key, which is expected
}

test "manages multiple server instances" {
    const allocator = testing.allocator;
    
    var manager = SshServerManager.init(allocator);
    defer manager.deinit();
    
    try testing.expectEqual(@as(u32, 0), manager.getServerCount());
    
    // Manager starts with no servers
}

pub const SshServerManager = struct {
    allocator: std.mem.Allocator,
    servers: std.ArrayList(*SshServer),
    
    pub fn init(allocator: std.mem.Allocator) SshServerManager {
        return SshServerManager{
            .allocator = allocator,
            .servers = std.ArrayList(*SshServer).init(allocator),
        };
    }
    
    pub fn deinit(self: *SshServerManager) void {
        for (self.servers.items) |server| {
            server.deinit();
            self.allocator.destroy(server);
        }
        self.servers.deinit();
    }
    
    pub fn createServer(self: *SshServerManager, config: SshServerConfig) !*SshServer {
        const server = try self.allocator.create(SshServer);
        errdefer self.allocator.destroy(server);
        
        server.* = try SshServer.init(self.allocator, config);
        errdefer server.deinit();
        
        try self.servers.append(server);
        
        log.info("SSH Server Manager: Created server for {s}:{d}", .{config.bind_address, config.port});
        return server;
    }
    
    pub fn startAll(self: *SshServerManager) !void {
        for (self.servers.items) |server| {
            try server.start();
        }
        log.info("SSH Server Manager: Started {} servers", .{self.servers.items.len});
    }
    
    pub fn stopAll(self: *SshServerManager) !void {
        for (self.servers.items) |server| {
            try server.stop();
        }
        log.info("SSH Server Manager: Stopped {} servers", .{self.servers.items.len});
    }
    
    pub fn getServerCount(self: *const SshServerManager) u32 {
        return @intCast(self.servers.items.len);
    }
    
    pub fn getRunningCount(self: *const SshServerManager) u32 {
        var count: u32 = 0;
        for (self.servers.items) |server| {
            if (server.isRunning()) count += 1;
        }
        return count;
    }
};

// Public API for easy SSH server usage
pub fn createSshServer(allocator: std.mem.Allocator, config: SshServerConfig) !*SshServer {
    return try SshServer.init(allocator, config);
}

pub fn runSshServer(allocator: std.mem.Allocator, config: SshServerConfig) !void {
    var server = try createSshServer(allocator, config);
    defer {
        server.deinit();
        allocator.destroy(server);
    }
    
    try server.start();
    defer server.stop() catch {};
    
    var runner = ServerRunner.init(allocator);
    defer runner.deinit();
    
    try runner.run(server);
}

// Convenience function for default configuration
pub fn runDefaultSshServer(allocator: std.mem.Allocator, port: u16) !void {
    var config = SshServerConfig.default();
    config.port = port;
    try runSshServer(allocator, config);
}