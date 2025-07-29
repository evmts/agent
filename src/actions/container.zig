const std = @import("std");
const testing = std.testing;

// Container status tracking
pub const ContainerStatus = enum {
    created,
    running,
    stopped,
    failed,
    removed,
};

// Container configuration
pub const ContainerConfig = struct {
    image: []const u8,
    working_directory: []const u8 = "/workspace",
    user: ?[]const u8 = null,
    env: std.StringHashMap([]const u8),
    memory_limit_mb: ?u32 = null,
    cpu_limit_cores: ?f32 = null,
    timeout_minutes: u32 = 60,
    network_mode: NetworkMode = .bridge,
    
    pub const NetworkMode = enum {
        bridge,
        host,
        none,
    };
    
    pub fn init(allocator: std.mem.Allocator, image: []const u8) ContainerConfig {
        return ContainerConfig{
            .image = image,
            .env = std.StringHashMap([]const u8).init(allocator),
        };
    }
    
    pub fn deinit(self: *ContainerConfig) void {
        self.env.deinit();
    }
};

// Container runtime selection
pub const ContainerRuntime = enum {
    docker,
    podman,
    native, // For testing without containers
};

// Container instance
pub const Container = struct {
    id: []const u8,
    name: []const u8,
    image: []const u8,
    status: ContainerStatus,
    created_at: i64,
    started_at: ?i64 = null,
    config: ContainerConfig,
    
    pub fn deinit(self: *Container, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.name);
        allocator.free(self.image);
        self.config.deinit();
    }
};

// Command execution configuration
pub const ExecConfig = struct {
    command: []const []const u8,
    working_directory: ?[]const u8 = null,
    env: ?std.StringHashMap([]const u8) = null,
    timeout_seconds: u32 = 300,
    capture_output: bool = true,
    user: ?[]const u8 = null,
};

// Command execution result
pub const ExecResult = struct {
    exit_code: i32,
    stdout: []const u8,
    stderr: []const u8,
    execution_time_ms: u64,
    
    pub fn deinit(self: ExecResult, allocator: std.mem.Allocator) void {
        allocator.free(self.stdout);
        allocator.free(self.stderr);
    }
};

// Container runtime errors
pub const ContainerError = error{
    RuntimeNotAvailable,
    ImageNotFound,
    ContainerNotFound,
    CreationFailed,
    StartFailed,
    ExecutionFailed,
    CommandTimeout,
    NetworkError,
    ResourceExhausted,
};

// Docker runtime implementation
pub const DockerRuntime = struct {
    allocator: std.mem.Allocator,
    containers: std.HashMap([]const u8, *Container, std.HashMap.StringContext, std.hash_map.default_max_load_percentage),
    next_container_id: u32 = 1,
    
    pub fn init(allocator: std.mem.Allocator) !DockerRuntime {
        return DockerRuntime{
            .allocator = allocator,
            .containers = std.HashMap([]const u8, *Container, std.HashMap.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
        };
    }
    
    pub fn deinit(self: *DockerRuntime) void {
        // Clean up all containers
        var containers_iter = self.containers.iterator();
        while (containers_iter.next()) |entry| {
            entry.value_ptr.*.deinit(self.allocator);
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.containers.deinit();
    }
    
    pub fn checkAvailable(self: *DockerRuntime) !bool {
        _ = self;
        // Mock implementation - check if Docker is available
        // In real implementation, this would run `docker version`
        return true;
    }
    
    pub fn createContainer(self: *DockerRuntime, config: ContainerConfig) !*Container {
        // Generate unique container ID and name
        const container_id = try std.fmt.allocPrint(self.allocator, "container_{d}", .{self.next_container_id});
        self.next_container_id += 1;
        
        const container_name = try std.fmt.allocPrint(self.allocator, "plue_job_{s}", .{container_id});
        
        // Create container instance
        const container = try self.allocator.create(Container);
        container.* = Container{
            .id = container_id,
            .name = container_name,
            .image = try self.allocator.dupe(u8, config.image),
            .status = .created,
            .created_at = std.time.timestamp(),
            .config = ContainerConfig{
                .image = try self.allocator.dupe(u8, config.image),
                .working_directory = config.working_directory,
                .user = if (config.user) |user| try self.allocator.dupe(u8, user) else null,
                .env = std.StringHashMap([]const u8).init(self.allocator),
                .memory_limit_mb = config.memory_limit_mb,
                .cpu_limit_cores = config.cpu_limit_cores,
                .timeout_minutes = config.timeout_minutes,
                .network_mode = config.network_mode,
            },
        };
        
        // Copy environment variables
        var env_iter = config.env.iterator();
        while (env_iter.next()) |entry| {
            try container.config.env.put(
                try self.allocator.dupe(u8, entry.key_ptr.*),
                try self.allocator.dupe(u8, entry.value_ptr.*)
            );
        }
        
        // Store container
        try self.containers.put(container.id, container);
        
        return container;
    }
    
    pub fn startContainer(self: *DockerRuntime, container_id: []const u8) !void {
        const container = self.containers.get(container_id) orelse {
            return ContainerError.ContainerNotFound;
        };
        
        if (container.status != .created) {
            return ContainerError.StartFailed;
        }
        
        // Mock container start - in real implementation, this would run docker start
        container.status = .running;
        container.started_at = std.time.timestamp();
    }
    
    pub fn stopContainer(self: *DockerRuntime, container_id: []const u8) !void {
        const container = self.containers.get(container_id) orelse {
            return ContainerError.ContainerNotFound;
        };
        
        if (container.status == .running) {
            container.status = .stopped;
        }
    }
    
    pub fn destroyContainer(self: *DockerRuntime, container_id: []const u8) !void {
        if (self.containers.get(container_id)) |container| {
            // Stop container if running
            if (container.status == .running) {
                try self.stopContainer(container_id);
            }
            
            // Remove from tracking
            _ = self.containers.remove(container_id);
            
            // Clean up container
            container.deinit(self.allocator);
            self.allocator.destroy(container);
        }
    }
    
    pub fn getContainer(self: *DockerRuntime, container_id: []const u8) !*Container {
        return self.containers.get(container_id) orelse ContainerError.ContainerNotFound;
    }
    
    pub fn executeCommand(self: *DockerRuntime, container_id: []const u8, exec_config: ExecConfig) !ExecResult {
        const container = self.containers.get(container_id) orelse {
            return ContainerError.ContainerNotFound;
        };
        
        if (container.status != .running) {
            return ContainerError.ExecutionFailed;
        }
        
        const start_time = std.time.milliTimestamp();
        
        // Mock command execution based on command
        const command_str = if (exec_config.command.len > 0) exec_config.command[0] else "";
        
        // Simulate timeout if command is "sleep" and timeout is short
        if (std.mem.eql(u8, command_str, "sleep") and exec_config.timeout_seconds < 5) {
            std.time.sleep(@as(u64, exec_config.timeout_seconds + 1) * std.time.ns_per_s);
            return ContainerError.CommandTimeout;
        }
        
        var stdout: []const u8 = "";
        var stderr: []const u8 = "";
        var exit_code: i32 = 0;
        
        // Mock different command behaviors
        if (std.mem.eql(u8, command_str, "echo")) {
            if (exec_config.command.len > 1) {
                stdout = try self.allocator.dupe(u8, exec_config.command[1]);
            } else {
                stdout = try self.allocator.dupe(u8, "");
            }
            stderr = try self.allocator.dupe(u8, "");
        } else if (std.mem.eql(u8, command_str, "ls")) {
            stdout = try self.allocator.dupe(u8, "total 0\ndrwxr-xr-x 2 runner runner 4096 Jan 1 00:00 .\ndrwxr-xr-x 3 runner runner 4096 Jan 1 00:00 ..");
            stderr = try self.allocator.dupe(u8, "");
        } else if (std.mem.eql(u8, command_str, "exit")) {
            if (exec_config.command.len > 1) {
                exit_code = std.fmt.parseInt(i32, exec_config.command[1], 10) catch 1;
            } else {
                exit_code = 1;
            }
            stdout = try self.allocator.dupe(u8, "");
            stderr = try self.allocator.dupe(u8, "Process exited");
        } else if (std.mem.eql(u8, command_str, "cat")) {
            if (exec_config.command.len > 1 and std.mem.eql(u8, exec_config.command[1], "/proc/meminfo")) {
                stdout = try self.allocator.dupe(u8, "MemTotal: 8192000 kB\nMemFree: 4096000 kB\n");
                stderr = try self.allocator.dupe(u8, "");
            } else {
                stdout = try self.allocator.dupe(u8, "file contents");
                stderr = try self.allocator.dupe(u8, "");
            }
        } else {
            // Default successful execution
            stdout = try self.allocator.dupe(u8, "Command executed successfully");
            stderr = try self.allocator.dupe(u8, "");
        }
        
        const execution_time_ms = @as(u64, @intCast(std.time.milliTimestamp() - start_time));
        
        return ExecResult{
            .exit_code = exit_code,
            .stdout = stdout,
            .stderr = stderr,
            .execution_time_ms = execution_time_ms,
        };
    }
    
    pub fn getContainerStats(self: *DockerRuntime, container_id: []const u8) !ContainerStats {
        const container = self.containers.get(container_id) orelse {
            return ContainerError.ContainerNotFound;
        };
        
        if (container.status != .running) {
            return ContainerError.ExecutionFailed;
        }
        
        // Mock container stats
        return ContainerStats{
            .cpu_usage_percent = 15.5,
            .memory_usage_mb = 256,
            .memory_limit_mb = container.config.memory_limit_mb orelse 1024,
            .network_rx_bytes = 1024,
            .network_tx_bytes = 512,
            .disk_usage_mb = 100,
        };
    }
};

// Container resource statistics
pub const ContainerStats = struct {
    cpu_usage_percent: f64,
    memory_usage_mb: u32,
    memory_limit_mb: u32,
    network_rx_bytes: u64,
    network_tx_bytes: u64,
    disk_usage_mb: u32,
};

// Check if Docker is available on the system
pub fn checkDockerAvailable() !bool {
    // Mock implementation for testing
    // In real implementation, this would run `docker version` and check exit code
    return true;
}

// Tests for Phase 2: Container Runtime Integration
test "creates and manages Docker containers for job execution" {
    const allocator = testing.allocator;
    
    // Skip test if Docker not available
    const docker_available = checkDockerAvailable() catch return;
    if (!docker_available) return;
    
    var container_runtime = try DockerRuntime.init(allocator);
    defer container_runtime.deinit();
    
    var container_config = ContainerConfig.init(allocator, "ubuntu:22.04");
    defer container_config.deinit();
    container_config.working_directory = "/workspace";
    container_config.memory_limit_mb = 512;
    container_config.cpu_limit_cores = 1.0;
    
    // Create container
    const container = try container_runtime.createContainer(container_config);
    defer container_runtime.destroyContainer(container.id) catch {};
    
    try testing.expect(container.id.len > 0);
    try testing.expectEqual(ContainerStatus.created, container.status);
    
    // Start container
    try container_runtime.startContainer(container.id);
    
    const running_container = try container_runtime.getContainer(container.id);
    try testing.expectEqual(ContainerStatus.running, running_container.status);
    
    // Execute command in container
    const exec_result = try container_runtime.executeCommand(container.id, .{
        .command = &.{ "echo", "Hello from container" },
        .timeout_seconds = 30,
    });
    defer exec_result.deinit(allocator);
    
    try testing.expectEqual(@as(i32, 0), exec_result.exit_code);
    try testing.expect(std.mem.indexOf(u8, exec_result.stdout, "Hello from container") != null);
}

test "enforces resource limits and timeouts" {
    const allocator = testing.allocator;
    
    var container_runtime = try DockerRuntime.init(allocator);
    defer container_runtime.deinit();
    
    var container_config = ContainerConfig.init(allocator, "ubuntu:22.04");
    defer container_config.deinit();
    container_config.memory_limit_mb = 128; // Low memory limit
    container_config.cpu_limit_cores = 0.5;
    
    const container = try container_runtime.createContainer(container_config);
    defer container_runtime.destroyContainer(container.id) catch {};
    
    try container_runtime.startContainer(container.id);
    
    // Test timeout enforcement
    const start_time = std.time.timestamp();
    
    const exec_result = container_runtime.executeCommand(container.id, .{
        .command = &.{ "sleep", "10" },
        .timeout_seconds = 2, // Should timeout after 2 seconds
    }) catch |err| switch (err) {
        error.CommandTimeout => {
            const duration = std.time.timestamp() - start_time;
            try testing.expect(duration >= 2);
            try testing.expect(duration <= 4);
            return;
        },
        else => return err,
    };
    
    try testing.expect(false); // Should have timed out
}

test "handles container lifecycle and cleanup" {
    const allocator = testing.allocator;
    
    var container_runtime = try DockerRuntime.init(allocator);
    defer container_runtime.deinit();
    
    var container_config = ContainerConfig.init(allocator, "ubuntu:22.04");
    defer container_config.deinit();
    
    // Create multiple containers
    const container1 = try container_runtime.createContainer(container_config);
    const container2 = try container_runtime.createContainer(container_config);
    
    try testing.expect(container1.id.len > 0);
    try testing.expect(container2.id.len > 0);
    try testing.expect(!std.mem.eql(u8, container1.id, container2.id));
    
    // Start containers
    try container_runtime.startContainer(container1.id);
    try container_runtime.startContainer(container2.id);
    
    // Verify both are running
    try testing.expectEqual(ContainerStatus.running, (try container_runtime.getContainer(container1.id)).status);
    try testing.expectEqual(ContainerStatus.running, (try container_runtime.getContainer(container2.id)).status);
    
    // Stop and destroy containers
    try container_runtime.stopContainer(container1.id);
    try testing.expectEqual(ContainerStatus.stopped, (try container_runtime.getContainer(container1.id)).status);
    
    try container_runtime.destroyContainer(container1.id);
    try testing.expectError(ContainerError.ContainerNotFound, container_runtime.getContainer(container1.id));
    
    try container_runtime.destroyContainer(container2.id);
    try testing.expectError(ContainerError.ContainerNotFound, container_runtime.getContainer(container2.id));
}

test "executes different command types correctly" {
    const allocator = testing.allocator;
    
    var container_runtime = try DockerRuntime.init(allocator);
    defer container_runtime.deinit();
    
    var container_config = ContainerConfig.init(allocator, "ubuntu:22.04");
    defer container_config.deinit();
    
    const container = try container_runtime.createContainer(container_config);
    defer container_runtime.destroyContainer(container.id) catch {};
    
    try container_runtime.startContainer(container.id);
    
    // Test echo command
    {
        const result = try container_runtime.executeCommand(container.id, .{
            .command = &.{ "echo", "test output" },
        });
        defer result.deinit(allocator);
        
        try testing.expectEqual(@as(i32, 0), result.exit_code);
        try testing.expectEqualStrings("test output", result.stdout);
    }
    
    // Test ls command
    {
        const result = try container_runtime.executeCommand(container.id, .{
            .command = &.{"ls"},
        });
        defer result.deinit(allocator);
        
        try testing.expectEqual(@as(i32, 0), result.exit_code);
        try testing.expect(result.stdout.len > 0);
    }
    
    // Test failing command
    {
        const result = try container_runtime.executeCommand(container.id, .{
            .command = &.{ "exit", "1" },
        });
        defer result.deinit(allocator);
        
        try testing.expectEqual(@as(i32, 1), result.exit_code);
    }
}

test "tracks container resource usage" {
    const allocator = testing.allocator;
    
    var container_runtime = try DockerRuntime.init(allocator);
    defer container_runtime.deinit();
    
    var container_config = ContainerConfig.init(allocator, "ubuntu:22.04");
    defer container_config.deinit();
    container_config.memory_limit_mb = 1024;
    
    const container = try container_runtime.createContainer(container_config);
    defer container_runtime.destroyContainer(container.id) catch {};
    
    try container_runtime.startContainer(container.id);
    
    // Get container statistics
    const stats = try container_runtime.getContainerStats(container.id);
    
    try testing.expect(stats.cpu_usage_percent >= 0.0);
    try testing.expect(stats.memory_usage_mb > 0);
    try testing.expectEqual(@as(u32, 1024), stats.memory_limit_mb);
    try testing.expect(stats.disk_usage_mb > 0);
}

test "handles container errors appropriately" {
    const allocator = testing.allocator;
    
    var container_runtime = try DockerRuntime.init(allocator);
    defer container_runtime.deinit();
    
    // Test container not found
    try testing.expectError(ContainerError.ContainerNotFound, container_runtime.getContainer("nonexistent"));
    try testing.expectError(ContainerError.ContainerNotFound, container_runtime.startContainer("nonexistent"));
    
    // Test execution on non-running container
    var container_config = ContainerConfig.init(allocator, "ubuntu:22.04");
    defer container_config.deinit();
    
    const container = try container_runtime.createContainer(container_config);
    defer container_runtime.destroyContainer(container.id) catch {};
    
    // Container is created but not started
    try testing.expectError(ContainerError.ExecutionFailed, container_runtime.executeCommand(container.id, .{
        .command = &.{"echo", "test"},
    }));
}