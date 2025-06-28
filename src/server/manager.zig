const std = @import("std");
const Process = @import("../util/process.zig").Process;
const ProcessOptions = @import("../util/process.zig").ProcessOptions;
const ServerConfig = @import("config.zig").ServerConfig;

pub const ServerError = error{
    PortInUse,
    StartupTimeout,
    EventStreamConnectionFailed,
    ProcessSpawnFailed,
    InvalidConfiguration,
    ServerCrashed,
    PortParsingFailed,
    LogFileCreationFailed,
    EnvironmentSetupFailed,
    ProcessAlreadyRunning,
    ForceKillTimeout,
};

pub const ErrorContext = struct {
    message: []const u8,
    details: ?[]const u8 = null,
    stdout: ?[]const u8 = null,
    stderr: ?[]const u8 = null,
};

pub const EventStreamConnection = struct {
    allocator: std.mem.Allocator,
    url: []const u8,
    // http_client: std.http.Client, // TODO: implement proper HTTP client
    abort_signal: std.atomic.Value(bool),
    connected: bool,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, url: []const u8) !*Self {
        const conn = try allocator.create(Self);
        conn.* = .{
            .allocator = allocator,
            .url = try allocator.dupe(u8, url),
            // .http_client = std.http.Client{ .allocator = allocator }, // TODO: implement
            .abort_signal = std.atomic.Value(bool).init(false),
            .connected = false,
        };
        return conn;
    }

    pub fn connect(self: *Self) !void {
        // TODO: Implement proper HTTP/SSE client
        // For now, just mark as connected for testing
        self.connected = true;
        std.log.warn("EventStreamConnection.connect() not yet implemented", .{});
    }

    pub fn disconnect(self: *Self) void {
        self.abort_signal.store(true, .monotonic);
        self.connected = false;
    }

    pub fn isConnected(self: *const Self) bool {
        return self.connected;
    }

    pub fn deinit(self: *Self) void {
        self.disconnect();
        // self.http_client.deinit(); // TODO: when implemented
        self.allocator.free(self.url);
        self.allocator.destroy(self);
    }
};

pub const ServerManager = struct {
    allocator: std.mem.Allocator,
    config: ServerConfig,
    process: ?*Process,
    state: ServerState,
    event_stream: ?*EventStreamConnection,
    consecutive_failures: u32,
    actual_port: u16,
    server_url: []u8,
    log_file: ?std.fs.File,
    startup_start_time: ?i64,

    const Self = @This();

    pub const ServerState = enum {
        stopped,
        starting,
        waiting_ready,
        running,
        stopping,
        crashed,
    };

    pub fn init(allocator: std.mem.Allocator, config: ServerConfig) !*Self {
        try config.validate();

        var manager = try allocator.create(Self);
        manager.* = .{
            .allocator = allocator,
            .config = config,
            .process = null,
            .state = .stopped,
            .event_stream = null,
            .consecutive_failures = 0,
            .actual_port = 0,
            .server_url = try allocator.alloc(u8, 0),
            .log_file = null,
            .startup_start_time = null,
        };

        // Create log file if configured
        if (config.log_file_path) |log_path| {
            manager.log_file = std.fs.createFileAbsolute(log_path, .{ .truncate = false }) catch |err| {
                std.log.err("Failed to create log file at {s}: {}", .{ log_path, err });
                return error.LogFileCreationFailed;
            };
        }

        return manager;
    }

    pub fn start(self: *Self) !void {
        if (self.state != .stopped and self.state != .crashed) {
            return error.ProcessAlreadyRunning;
        }

        self.state = .starting;
        self.consecutive_failures = 0;
        self.startup_start_time = std.time.milliTimestamp();

        std.log.info("Starting OpenCode server...", .{});

        // Build command arguments
        const argv = &[_][]const u8{
            "bun",
            "run",
            "packages/opencode/src/server/server.ts",
        };

        // Set PORT environment variable to 0 for auto-assignment
        if (self.config.env) |*env| {
            try env.put("PORT", "0");
        }

        // Spawn the process
        const process_options = ProcessOptions{
            .cwd = self.config.opencode_path,
            .env = self.config.getEnvMapPtr(),
            .stdout = .pipe,
            .stderr = .pipe,
        };

        self.process = Process.spawn(self.allocator, argv, process_options) catch |err| {
            std.log.err("Failed to spawn OpenCode server: {}", .{err});
            self.state = .crashed;
            return error.ProcessSpawnFailed;
        };

        self.state = .waiting_ready;

        // Start monitoring stdout/stderr for port information
        try self.parsePortFromOutput();
    }

    fn parsePortFromOutput(self: *Self) !void {
        const process = self.process orelse return error.ProcessSpawnFailed;

        // Give the server a moment to start outputting
        std.time.sleep(500 * std.time.ns_per_ms);

        // Collect initial output
        try process.collectOutput();

        // Look for port in output (OpenCode typically outputs "Server running on port XXXXX")
        const stdout = process.getStdout() orelse "";
        const stderr = process.getStderr() orelse "";

        // Log output if we have a log file
        if (self.log_file) |file| {
            _ = try file.write(stdout);
            _ = try file.write(stderr);
        }

        // Try to find port in stdout
        if (std.mem.indexOf(u8, stdout, "port")) |port_idx| {
            const port_start = port_idx + 5; // Skip "port "
            if (port_start < stdout.len) {
                var i = port_start;
                while (i < stdout.len and std.ascii.isWhitespace(stdout[i])) : (i += 1) {}
                
                var port_end = i;
                while (port_end < stdout.len and std.ascii.isDigit(stdout[port_end])) : (port_end += 1) {}
                
                if (i < port_end) {
                    const port_str = stdout[i..port_end];
                    self.actual_port = try std.fmt.parseInt(u16, port_str, 10);
                    
                    // Update server URL
                    self.allocator.free(self.server_url);
                    self.server_url = try std.fmt.allocPrint(self.allocator, "http://{s}:{d}", .{ self.config.host, self.actual_port });
                    
                    // Update environment variable
                    try self.config.updateServerUrl(self.server_url);
                    
                    std.log.info("Server started on port {d}", .{self.actual_port});
                    
                    // Log startup time
                    if (self.startup_start_time) |start_time| {
                        const elapsed = std.time.milliTimestamp() - start_time;
                        std.log.info("Startup completed in {d}ms", .{elapsed});
                    }
                    
                    return;
                }
            }
        }

        // If we couldn't parse the port, assume default or configured port
        if (self.config.port > 0) {
            self.actual_port = self.config.port;
        } else {
            // Try common default port
            self.actual_port = 3000;
        }

        self.allocator.free(self.server_url);
        self.server_url = try std.fmt.allocPrint(self.allocator, "http://{s}:{d}", .{ self.config.host, self.actual_port });
        try self.config.updateServerUrl(self.server_url);

        std.log.warn("Could not parse port from output, using {d}", .{self.actual_port});
    }

    pub fn stop(self: *Self) !void {
        if (self.state != .running and self.state != .waiting_ready) {
            return;
        }

        self.state = .stopping;
        std.log.info("Shutting down OpenCode server...", .{});

        // Disconnect event stream first
        if (self.event_stream) |stream| {
            stream.disconnect();
        }

        // Try graceful shutdown
        if (self.process) |process| {
            process.killWithTimeout(self.config.force_kill_timeout_ms) catch |err| {
                std.log.err("Failed to kill process: {}", .{err});
                return error.ForceKillTimeout;
            };

            _ = try process.wait();
            process.deinit();
            self.process = null;
        }

        self.state = .stopped;
        std.log.info("OpenCode server stopped", .{});
    }

    pub fn forceStop(self: *Self) !void {
        std.log.warn("Force stopping OpenCode server...", .{});

        if (self.event_stream) |stream| {
            stream.disconnect();
        }

        if (self.process) |process| {
            try process.kill();
            _ = try process.wait();
            process.deinit();
            self.process = null;
        }

        self.state = .stopped;
    }

    pub fn restart(self: *Self) !void {
        std.log.info("Restarting OpenCode server...", .{});
        try self.stop();
        try self.start();
    }

    pub fn connectEventStream(self: *Self) !void {
        if (self.state != .running and self.state != .waiting_ready) {
            return error.InvalidState;
        }

        // Clean up existing connection
        if (self.event_stream) |stream| {
            stream.deinit();
        }

        const event_url = try std.fmt.allocPrint(self.allocator, "{s}/event", .{self.server_url});
        defer self.allocator.free(event_url);

        self.event_stream = try EventStreamConnection.init(self.allocator, event_url);
        
        self.event_stream.?.connect() catch |err| {
            std.log.err("Failed to connect to event stream: {}", .{err});
            self.consecutive_failures += 1;
            
            if (self.consecutive_failures >= self.config.max_connection_failures) {
                std.log.err("Max connection failures reached, restarting server", .{});
                try self.restart();
            }
            
            return error.EventStreamConnectionFailed;
        };

        self.consecutive_failures = 0;
        self.state = .running;
    }

    pub fn handleDisconnection(self: *Self) void {
        self.consecutive_failures += 1;
        std.log.warn("Event stream disconnected, consecutive failures: {d}", .{self.consecutive_failures});

        if (self.consecutive_failures >= self.config.max_connection_failures) {
            std.log.err("Max connection failures reached, server may have crashed", .{});
            self.state = .crashed;
        }
    }

    pub fn getState(self: *const Self) ServerState {
        return self.state;
    }

    pub fn getUrl(self: *const Self) []const u8 {
        return self.server_url;
    }

    pub fn waitReady(self: *Self, timeout_ms: u32) !void {
        const start_time = std.time.milliTimestamp();
        
        while (self.state == .waiting_ready) {
            const elapsed = @as(u32, @intCast(std.time.milliTimestamp() - start_time));
            if (elapsed > timeout_ms) {
                return error.StartupTimeout;
            }

            // Try to connect to event stream
            self.connectEventStream() catch {
                // Wait before retrying
                std.time.sleep(self.config.event_stream_reconnect_ms * std.time.ns_per_ms);
                continue;
            };

            // If connection succeeded, we're ready
            if (self.state == .running) {
                return;
            }
        }

        if (self.state != .running) {
            return error.StartupTimeout;
        }
    }

    pub fn deinit(self: *Self) void {
        // Stop the server if running
        self.stop() catch {};

        // Clean up event stream
        if (self.event_stream) |stream| {
            stream.deinit();
        }

        // Close log file
        if (self.log_file) |file| {
            file.close();
        }

        // Free server URL
        self.allocator.free(self.server_url);

        // Clean up config
        self.config.deinit();

        // Free self
        self.allocator.destroy(self);
    }
};

test "ServerManager init" {
    const allocator = std.testing.allocator;

    const tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config = try ServerConfig.initDefault(allocator, tmp_path);
    var manager = try ServerManager.init(allocator, config);
    defer manager.deinit();

    try std.testing.expect(manager.state == .stopped);
    try std.testing.expect(manager.process == null);
    try std.testing.expect(manager.actual_port == 0);
}

test "ServerManager state transitions" {
    const allocator = std.testing.allocator;

    const tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config = try ServerConfig.initDefault(allocator, tmp_path);
    var manager = try ServerManager.init(allocator, config);
    defer manager.deinit();

    // Initial state
    try std.testing.expect(manager.getState() == .stopped);

    // Can't stop when already stopped
    try manager.stop();
    try std.testing.expect(manager.getState() == .stopped);
}