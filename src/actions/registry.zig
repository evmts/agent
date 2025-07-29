const std = @import("std");
const testing = std.testing;
const queue = @import("queue.zig");

// Runner status enum
pub const RunnerStatus = enum {
    offline,
    online,
    busy,
    maintenance,
};

// Runner capabilities for job matching
pub const RunnerCapabilities = struct {
    labels: []const []const u8 = &.{},
    architecture: []const u8 = "x64",
    memory_gb: u32 = 4,
    cpu_cores: u32 = 2,
    docker_enabled: bool = false,
    max_parallel_jobs: u32 = 1,
    current_jobs: u32 = 0,
    
    pub fn canRunJob(self: *const RunnerCapabilities, requirements: queue.RunnerRequirements) bool {
        // Check architecture compatibility
        if (!std.mem.eql(u8, self.architecture, requirements.architecture)) {
            return false;
        }
        
        // Check memory requirements
        if (self.memory_gb < requirements.min_memory_gb) {
            return false;
        }
        
        // Check Docker requirement
        if (requirements.requires_docker and !self.docker_enabled) {
            return false;
        }
        
        // Check capacity availability
        if (self.current_jobs >= self.max_parallel_jobs) {
            return false;
        }
        
        // Check label compatibility
        for (requirements.labels) |required_label| {
            var has_label = false;
            for (self.labels) |runner_label| {
                if (std.mem.eql(u8, runner_label, required_label)) {
                    has_label = true;
                    break;
                }
            }
            if (!has_label) {
                return false;
            }
        }
        
        return true;
    }
    
    pub fn getLoadPercentage(self: *const RunnerCapabilities) f32 {
        if (self.max_parallel_jobs == 0) return 100.0;
        return (@as(f32, @floatFromInt(self.current_jobs)) / @as(f32, @floatFromInt(self.max_parallel_jobs))) * 100.0;
    }
};

// Registered runner in the system
pub const RegisteredRunner = struct {
    id: u32,
    name: []const u8,
    status: RunnerStatus,
    capabilities: RunnerCapabilities,
    last_heartbeat: i64,
    registered_at: i64,
    
    pub fn isAvailable(self: *const RegisteredRunner) bool {
        return self.status == .online and self.capabilities.current_jobs < self.capabilities.max_parallel_jobs;
    }
};

// Runner selection policies
pub const SelectionPolicy = enum {
    least_loaded,
    round_robin,
    first_available,
};

// Context for hash operations
const RunnerHashContext = struct {
    pub fn hash(self: @This(), key: u32) u64 {
        _ = self;
        return @as(u64, key);
    }
    
    pub fn eql(self: @This(), a: u32, b: u32) bool {
        _ = self;
        return a == b;
    }
};

// Runner registry for tracking and managing runners
pub const RunnerRegistry = struct {
    allocator: std.mem.Allocator,
    runners: std.HashMap(u32, RegisteredRunner, RunnerHashContext, std.hash_map.default_max_load_percentage),
    
    pub fn init(allocator: std.mem.Allocator) !RunnerRegistry {
        return RunnerRegistry{
            .allocator = allocator,
            .runners = std.HashMap(u32, RegisteredRunner, RunnerHashContext, std.hash_map.default_max_load_percentage).init(allocator),
        };
    }
    
    pub fn deinit(self: *RunnerRegistry) void {
        // Free allocated runner names
        var iterator = self.runners.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.value_ptr.name);
        }
        self.runners.deinit();
    }
    
    pub fn registerRunner(self: *RunnerRegistry, runner_info: struct {
        id: u32,
        name: []const u8,
        status: RunnerStatus,
        capabilities: RunnerCapabilities,
    }) !void {
        const runner = RegisteredRunner{
            .id = runner_info.id,
            .name = try self.allocator.dupe(u8, runner_info.name),
            .status = runner_info.status,
            .capabilities = runner_info.capabilities,
            .last_heartbeat = std.time.timestamp(),
            .registered_at = std.time.timestamp(),
        };
        
        try self.runners.put(runner_info.id, runner);
    }
    
    pub fn unregisterRunner(self: *RunnerRegistry, runner_id: u32) !void {
        if (self.runners.fetchRemove(runner_id)) |entry| {
            self.allocator.free(entry.value.name);
        }
    }
    
    pub fn updateCapabilities(self: *RunnerRegistry, runner_id: u32, capabilities: RunnerCapabilities) !void {
        if (self.runners.getPtr(runner_id)) |runner| {
            runner.capabilities = capabilities;
            runner.last_heartbeat = std.time.timestamp();
        }
    }
    
    pub fn updateStatus(self: *RunnerRegistry, runner_id: u32, status: RunnerStatus) !void {
        if (self.runners.getPtr(runner_id)) |runner| {
            runner.status = status;
            runner.last_heartbeat = std.time.timestamp();
        }
    }
    
    pub fn findCompatibleRunners(self: *RunnerRegistry, allocator: std.mem.Allocator, requirements: queue.RunnerRequirements) ![]u32 {
        var compatible = std.ArrayList(u32).init(allocator);
        errdefer compatible.deinit();
        
        var iterator = self.runners.iterator();
        while (iterator.next()) |entry| {
            const runner = entry.value_ptr;
            if (runner.isAvailable() and runner.capabilities.canRunJob(requirements)) {
                try compatible.append(runner.id);
            }
        }
        
        return compatible.toOwnedSlice();
    }
    
    pub fn selectBestRunner(self: *RunnerRegistry, candidates: []const u32, selection_policy: SelectionPolicy) !u32 {
        if (candidates.len == 0) {
            return error.NoRunnersAvailable;
        }
        
        switch (selection_policy) {
            .first_available => return candidates[0],
            .least_loaded => {
                var best_runner_id = candidates[0];
                var lowest_load: f32 = 100.0;
                
                for (candidates) |runner_id| {
                    if (self.runners.get(runner_id)) |runner| {
                        const load = runner.capabilities.getLoadPercentage();
                        if (load < lowest_load) {
                            lowest_load = load;
                            best_runner_id = runner_id;
                        }
                    }
                }
                
                return best_runner_id;
            },
            .round_robin => {
                // Simple round robin - just return first for now
                // TODO: Implement proper round robin state
                return candidates[0];
            },
        }
    }
    
    pub fn getRunner(self: *RunnerRegistry, runner_id: u32) ?*RegisteredRunner {
        return self.runners.getPtr(runner_id);
    }
    
    pub fn incrementJobCount(self: *RunnerRegistry, runner_id: u32) !void {
        if (self.runners.getPtr(runner_id)) |runner| {
            runner.capabilities.current_jobs += 1;
            if (runner.capabilities.current_jobs >= runner.capabilities.max_parallel_jobs) {
                runner.status = .busy;
            }
        }
    }
    
    pub fn decrementJobCount(self: *RunnerRegistry, runner_id: u32) !void {
        if (self.runners.getPtr(runner_id)) |runner| {
            if (runner.capabilities.current_jobs > 0) {
                runner.capabilities.current_jobs -= 1;
                if (runner.status == .busy and runner.capabilities.current_jobs < runner.capabilities.max_parallel_jobs) {
                    runner.status = .online;
                }
            }
        }
    }
    
    pub fn getTotalRunners(self: *const RunnerRegistry) u32 {
        return @intCast(self.runners.count());
    }
    
    pub fn getAvailableRunners(self: *const RunnerRegistry) u32 {
        var count: u32 = 0;
        var iterator = self.runners.iterator();
        while (iterator.next()) |entry| {
            if (entry.value_ptr.isAvailable()) {
                count += 1;
            }
        }
        return count;
    }
};

// Test data
const test_requirements = queue.RunnerRequirements{
    .labels = &.{"ubuntu-latest"},
    .architecture = "x64",
    .min_memory_gb = 4,
    .requires_docker = true,
};

const standard_capabilities = RunnerCapabilities{
    .labels = &.{"ubuntu-latest", "self-hosted"},
    .architecture = "x64",
    .memory_gb = 8,
    .cpu_cores = 4,
    .docker_enabled = true,
    .max_parallel_jobs = 2,
    .current_jobs = 0,
};

// Tests for Phase 2: Runner Registry and Capability Matching
test "runner registry tracks capabilities and availability" {
    const allocator = testing.allocator;
    
    var registry = try RunnerRegistry.init(allocator);
    defer registry.deinit();
    
    const runner_capabilities = RunnerCapabilities{
        .labels = &.{"ubuntu-latest", "self-hosted"},
        .architecture = "x64",
        .memory_gb = 8,
        .cpu_cores = 4,
        .docker_enabled = true,
        .max_parallel_jobs = 2,
        .current_jobs = 0,
    };
    
    // Register runner
    try registry.registerRunner(.{
        .id = 123,
        .name = "test-runner-1",
        .status = .online,
        .capabilities = runner_capabilities,
    });
    
    // Test capability matching
    const job_requirements = queue.RunnerRequirements{
        .labels = &.{"ubuntu-latest"},
        .architecture = "x64",
        .min_memory_gb = 4,
        .requires_docker = true,
    };
    
    const compatible_runners = try registry.findCompatibleRunners(allocator, job_requirements);
    defer allocator.free(compatible_runners);
    
    try testing.expectEqual(@as(usize, 1), compatible_runners.len);
    try testing.expectEqual(@as(u32, 123), compatible_runners[0]);
}

test "runner registry filters by availability and capacity" {
    const allocator = testing.allocator;
    
    var registry = try RunnerRegistry.init(allocator);
    defer registry.deinit();
    
    // Register busy runner (at capacity)
    const busy_capabilities = RunnerCapabilities{
        .labels = &.{"ubuntu-latest"},
        .max_parallel_jobs = 1,
        .current_jobs = 1, // At capacity
    };
    
    try registry.registerRunner(.{
        .id = 1,
        .name = "busy-runner",
        .status = .busy,
        .capabilities = busy_capabilities,
    });
    
    // Register available runner
    const available_capabilities = RunnerCapabilities{
        .labels = &.{"ubuntu-latest"},
        .max_parallel_jobs = 2,
        .current_jobs = 0, // Available
    };
    
    try registry.registerRunner(.{
        .id = 2,
        .name = "available-runner",
        .status = .online,
        .capabilities = available_capabilities,
    });
    
    const job_requirements = queue.RunnerRequirements{
        .labels = &.{"ubuntu-latest"},
    };
    
    const available_runners = try registry.findCompatibleRunners(allocator, job_requirements);
    defer allocator.free(available_runners);
    
    // Should only return the available runner
    try testing.expectEqual(@as(usize, 1), available_runners.len);
    try testing.expectEqual(@as(u32, 2), available_runners[0]);
}

test "runner capabilities can validate job requirements" {
    const capabilities = RunnerCapabilities{
        .labels = &.{"ubuntu-latest", "gpu"},
        .architecture = "x64",
        .memory_gb = 16,
        .cpu_cores = 8,
        .docker_enabled = true,
        .max_parallel_jobs = 4,
        .current_jobs = 1,
    };
    
    // Compatible requirements
    const compatible_req = queue.RunnerRequirements{
        .labels = &.{"ubuntu-latest"},
        .architecture = "x64",
        .min_memory_gb = 8,
        .requires_docker = true,
    };
    
    try testing.expect(capabilities.canRunJob(compatible_req));
    
    // Incompatible requirements (insufficient memory)
    const incompatible_req = queue.RunnerRequirements{
        .labels = &.{"ubuntu-latest"},
        .architecture = "x64",
        .min_memory_gb = 32, // More than available
        .requires_docker = true,
    };
    
    try testing.expect(!capabilities.canRunJob(incompatible_req));
    
    // Missing required label
    const missing_label_req = queue.RunnerRequirements{
        .labels = &.{"windows-latest"}, // Not available
        .architecture = "x64",
        .min_memory_gb = 4,
        .requires_docker = false,
    };
    
    try testing.expect(!capabilities.canRunJob(missing_label_req));
}

test "runner selection policies work correctly" {
    const allocator = testing.allocator;
    
    var registry = try RunnerRegistry.init(allocator);
    defer registry.deinit();
    
    // Register runners with different load levels
    try registry.registerRunner(.{
        .id = 1,
        .name = "runner-1",
        .status = .online,
        .capabilities = RunnerCapabilities{
            .labels = &.{"ubuntu-latest"},
            .max_parallel_jobs = 4,
            .current_jobs = 3, // High load (75%)
        },
    });
    
    try registry.registerRunner(.{
        .id = 2,
        .name = "runner-2", 
        .status = .online,
        .capabilities = RunnerCapabilities{
            .labels = &.{"ubuntu-latest"},
            .max_parallel_jobs = 4,
            .current_jobs = 1, // Low load (25%)
        },
    });
    
    const candidates = [_]u32{ 1, 2 };
    
    // Test least loaded policy
    const best_runner = try registry.selectBestRunner(&candidates, .least_loaded);
    try testing.expectEqual(@as(u32, 2), best_runner); // Should select runner with lower load
    
    // Test first available policy
    const first_runner = try registry.selectBestRunner(&candidates, .first_available);
    try testing.expectEqual(@as(u32, 1), first_runner); // Should select first in list
}

test "runner registry job count management" {
    const allocator = testing.allocator;
    
    var registry = try RunnerRegistry.init(allocator);
    defer registry.deinit();
    
    try registry.registerRunner(.{
        .id = 100,
        .name = "test-runner",
        .status = .online,
        .capabilities = RunnerCapabilities{
            .labels = &.{"ubuntu-latest"},
            .max_parallel_jobs = 2,
            .current_jobs = 0,
        },
    });
    
    // Initially available
    try testing.expect(registry.getRunner(100).?.isAvailable());
    try testing.expectEqual(@as(u32, 1), registry.getAvailableRunners());
    
    // Increment job count
    try registry.incrementJobCount(100);
    try testing.expectEqual(@as(u32, 1), registry.getRunner(100).?.capabilities.current_jobs);
    try testing.expect(registry.getRunner(100).?.isAvailable());
    
    // Increment to capacity
    try registry.incrementJobCount(100);
    try testing.expectEqual(@as(u32, 2), registry.getRunner(100).?.capabilities.current_jobs);
    try testing.expect(!registry.getRunner(100).?.isAvailable());
    try testing.expectEqual(RunnerStatus.busy, registry.getRunner(100).?.status);
    try testing.expectEqual(@as(u32, 0), registry.getAvailableRunners());
    
    // Decrement job count
    try registry.decrementJobCount(100);
    try testing.expectEqual(@as(u32, 1), registry.getRunner(100).?.capabilities.current_jobs);
    try testing.expect(registry.getRunner(100).?.isAvailable());
    try testing.expectEqual(RunnerStatus.online, registry.getRunner(100).?.status);
}