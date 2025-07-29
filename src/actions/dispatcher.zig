const std = @import("std");
const testing = std.testing;
const queue = @import("queue.zig");
const registry = @import("registry.zig");

// Job status tracking
pub const JobStatus = enum {
    queued,
    assigned,
    running,
    completed,
    failed,
    cancelled,
};

// Job result from completion
pub const JobResult = struct {
    status: JobStatus,
    exit_code: ?i32 = null,
    output: []const u8 = "",
    error_message: []const u8 = "",
    completed_at: i64,
};

// Assigned job for runners
pub const AssignedJob = struct {
    job_id: u32,
    runner_id: u32,
    job_definition: queue.QueuedJob,
    assigned_at: i64,
};

// Queue metrics for monitoring
pub const QueueMetrics = struct {
    total_jobs: u32,
    critical_jobs: u32,
    high_jobs: u32,
    normal_jobs: u32,
    low_jobs: u32,
    oldest_job_age_seconds: i64,
    average_wait_time_seconds: f64,
};

// Runner utilization metrics
pub const RunnerUtilization = struct {
    runner_id: u32,
    name: []const u8,
    status: registry.RunnerStatus,
    current_jobs: u32,
    max_jobs: u32,
    load_percentage: f32,
};

// Requeue reasons for job failure handling
pub const RequeueReason = enum {
    runner_failure,
    timeout,
    system_error,
};

// Dispatcher configuration
pub const DispatcherConfig = struct {
    selection_policy: registry.SelectionPolicy = .least_loaded,
    max_assignment_retries: u32 = 3,
    job_timeout_seconds: u32 = 3600,
};

// Mock database connection for testing
pub const DatabaseConnection = struct {
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, config: anytype) !DatabaseConnection {
        _ = config;
        return DatabaseConnection{ .allocator = allocator };
    }
    
    pub fn deinit(self: *DatabaseConnection, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
    }
};

// Job scheduler for assignment decisions
pub const JobScheduler = struct {
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) JobScheduler {
        return JobScheduler{ .allocator = allocator };
    }
    
    pub fn deinit(self: *JobScheduler) void {
        _ = self;
    }
};

// Metrics collector for monitoring
pub const MetricsCollector = struct {
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) MetricsCollector {
        return MetricsCollector{ .allocator = allocator };
    }
    
    pub fn deinit(self: *MetricsCollector) void {
        _ = self;
    }
};

// Main job dispatcher system
pub const JobDispatcher = struct {
    allocator: std.mem.Allocator,
    db: *DatabaseConnection,
    scheduler: JobScheduler,
    runner_registry: registry.RunnerRegistry,
    job_queue: queue.JobQueue,
    metrics: MetricsCollector,
    config: DispatcherConfig,
    assigned_jobs: std.HashMap(u32, AssignedJob, JobHashContext, std.hash_map.default_max_load_percentage),
    job_results: std.HashMap(u32, JobResult, JobHashContext, std.hash_map.default_max_load_percentage),
    next_job_id: u32,
    
    const JobHashContext = struct {
        pub fn hash(self: @This(), key: u32) u64 {
            _ = self;
            return @as(u64, key);
        }
        
        pub fn eql(self: @This(), a: u32, b: u32) bool {
            _ = self;
            return a == b;
        }
    };
    
    pub fn init(allocator: std.mem.Allocator, init_config: struct {
        db: *DatabaseConnection,
        scheduler: ?JobScheduler = null,
        metrics: ?MetricsCollector = null,
        selection_policy: registry.SelectionPolicy = .least_loaded,
    }) !JobDispatcher {
        return JobDispatcher{
            .allocator = allocator,
            .db = init_config.db,
            .scheduler = init_config.scheduler orelse JobScheduler.init(allocator),
            .runner_registry = try registry.RunnerRegistry.init(allocator),
            .job_queue = try queue.JobQueue.init(allocator),
            .metrics = init_config.metrics orelse MetricsCollector.init(allocator),
            .config = DispatcherConfig{
                .selection_policy = init_config.selection_policy,
            },
            .assigned_jobs = std.HashMap(u32, AssignedJob, JobHashContext, std.hash_map.default_max_load_percentage).init(allocator),
            .job_results = std.HashMap(u32, JobResult, JobHashContext, std.hash_map.default_max_load_percentage).init(allocator),
            .next_job_id = 1,
        };
    }
    
    pub fn deinit(self: *JobDispatcher) void {
        self.runner_registry.deinit();
        self.job_queue.deinit();
        self.scheduler.deinit();
        self.metrics.deinit();
        self.assigned_jobs.deinit();
        
        // Free job results
        var results_iter = self.job_results.iterator();
        while (results_iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.output);
            self.allocator.free(entry.value_ptr.error_message);
        }
        self.job_results.deinit();
    }
    
    pub fn start(self: *JobDispatcher) !void {
        _ = self;
        // TODO: Start background dispatch loop
    }
    
    pub fn stop(self: *JobDispatcher) !void {
        _ = self;
        // TODO: Stop background dispatch loop
    }
    
    pub fn registerRunner(self: *JobDispatcher, runner_info: struct {
        id: u32,
        name: []const u8 = "test-runner",
        capabilities: registry.RunnerCapabilities,
    }) !void {
        try self.runner_registry.registerRunner(.{
            .id = runner_info.id,
            .name = runner_info.name,
            .status = .online,
            .capabilities = runner_info.capabilities,
        });
    }
    
    pub fn enqueueJob(self: *JobDispatcher, job: queue.QueuedJob) !void {
        try self.job_queue.enqueue(job);
    }
    
    pub fn cancelJob(self: *JobDispatcher, job_id: u32) !void {
        try self.job_queue.remove(job_id);
        _ = self.assigned_jobs.remove(job_id);
    }
    
    pub fn requeueJob(self: *JobDispatcher, job_id: u32, reason: RequeueReason) !void {
        _ = reason;
        if (self.assigned_jobs.get(job_id)) |assigned_job| {
            var requeued_job = assigned_job.job_definition;
            requeued_job.retry_count += 1;
            
            if (requeued_job.retry_count <= requeued_job.max_retries) {
                try self.job_queue.enqueue(requeued_job);
            }
            
            // Free up runner capacity
            try self.runner_registry.decrementJobCount(assigned_job.runner_id);
            _ = self.assigned_jobs.remove(job_id);
        }
    }
    
    pub fn pollForJob(self: *JobDispatcher, runner_id: u32, capabilities: registry.RunnerCapabilities) !?AssignedJob {
        // Update runner capabilities
        try self.runner_registry.updateCapabilities(runner_id, capabilities);
        
        // Check if this runner is available and should get a job
        const runner = self.runner_registry.getRunner(runner_id) orelse return null;
        if (!runner.isAvailable()) return null;
        
        // Try to find a compatible job
        if (try self.job_queue.dequeue(queue.RunnerRequirements{
            .labels = capabilities.labels,
            .architecture = capabilities.architecture,
        })) |job| {
            // Find all compatible runners for this job
            const compatible_runners = try self.runner_registry.findCompatibleRunners(self.allocator, job.requirements);
            defer self.allocator.free(compatible_runners);
            
            // Select best runner using configured policy
            if (compatible_runners.len > 0) {
                const best_runner_id = try self.runner_registry.selectBestRunner(compatible_runners, self.config.selection_policy);
                
                // Only assign if this runner was selected as best
                if (best_runner_id == runner_id) {
                    // Create assignment
                    const assigned_job = AssignedJob{
                        .job_id = job.id,
                        .runner_id = runner_id,
                        .job_definition = job,
                        .assigned_at = std.time.timestamp(),
                    };
                    
                    // Track assignment
                    try self.assigned_jobs.put(job.id, assigned_job);
                    try self.runner_registry.incrementJobCount(runner_id);
                    
                    return assigned_job;
                } else {
                    // Put job back in queue for the selected runner
                    try self.job_queue.enqueue(job);
                }
            } else {
                // Put job back in queue if no compatible runners
                try self.job_queue.enqueue(job);
            }
        }
        
        return null;
    }
    
    pub fn updateJobStatus(self: *JobDispatcher, job_id: u32, status: JobStatus) !void {
        if (self.assigned_jobs.getPtr(job_id)) |assigned_job| {
            _ = assigned_job;
            // Update job status (would normally persist to database)
            if (status == .failed) {
                try self.requeueJob(job_id, .system_error);
            }
        }
    }
    
    pub fn completeJob(self: *JobDispatcher, job_id: u32, result: JobResult) !void {
        if (self.assigned_jobs.get(job_id)) |assigned_job| {
            // Store result
            const owned_result = JobResult{
                .status = result.status,
                .exit_code = result.exit_code,
                .output = try self.allocator.dupe(u8, result.output),
                .error_message = try self.allocator.dupe(u8, result.error_message),
                .completed_at = result.completed_at,
            };
            try self.job_results.put(job_id, owned_result);
            
            // Mark job as completed for dependency tracking
            try self.job_queue.markJobCompleted(job_id, assigned_job.job_definition.job_id);
            
            // Free up runner capacity
            try self.runner_registry.decrementJobCount(assigned_job.runner_id);
            _ = self.assigned_jobs.remove(job_id);
        }
    }
    
    pub fn getQueueDepth(self: *JobDispatcher) !QueueMetrics {
        return QueueMetrics{
            .total_jobs = self.job_queue.getTotalJobs(),
            .critical_jobs = @intCast(self.job_queue.priority_queues[3].items.len),
            .high_jobs = @intCast(self.job_queue.priority_queues[2].items.len),
            .normal_jobs = @intCast(self.job_queue.priority_queues[1].items.len),
            .low_jobs = @intCast(self.job_queue.priority_queues[0].items.len),
            .oldest_job_age_seconds = 0, // TODO: Calculate oldest job age
            .average_wait_time_seconds = 0.0, // TODO: Calculate average wait time
        };
    }
    
    pub fn getWaitingJobs(self: *JobDispatcher, allocator: std.mem.Allocator, limit: u32) ![]queue.QueuedJob {
        _ = self;
        _ = allocator;
        _ = limit;
        // TODO: Implement waiting jobs retrieval
        return &.{};
    }
    
    pub fn getRunnerUtilization(self: *JobDispatcher, allocator: std.mem.Allocator) ![]RunnerUtilization {
        var utilization = std.ArrayList(RunnerUtilization).init(allocator);
        errdefer utilization.deinit();
        
        var runner_iter = self.runner_registry.runners.iterator();
        while (runner_iter.next()) |entry| {
            const runner = entry.value_ptr;
            try utilization.append(RunnerUtilization{
                .runner_id = runner.id,
                .name = runner.name,
                .status = runner.status,
                .current_jobs = runner.capabilities.current_jobs,
                .max_jobs = runner.capabilities.max_parallel_jobs,
                .load_percentage = runner.capabilities.getLoadPercentage(),
            });
        }
        
        return utilization.toOwnedSlice();
    }
};

// Test data and helpers
const test_db_config = struct {};

const runner1_capabilities = registry.RunnerCapabilities{
    .labels = &.{"ubuntu-latest"},
    .max_parallel_jobs = 4,
    .current_jobs = 3,
};

const runner2_capabilities = registry.RunnerCapabilities{
    .labels = &.{"ubuntu-latest"},
    .max_parallel_jobs = 4,
    .current_jobs = 1,
};

const standard_requirements = queue.RunnerRequirements{
    .labels = &.{"ubuntu-latest"},
};

const standard_capabilities = registry.RunnerCapabilities{
    .labels = &.{"ubuntu-latest"},
    .max_parallel_jobs = 2,
    .current_jobs = 0,
};

// Tests for Phase 3: Job Assignment and Load Balancing
test "dispatcher assigns jobs to best available runners" {
    const allocator = testing.allocator;
    
    var db = try DatabaseConnection.init(allocator, test_db_config);
    defer db.deinit(allocator);
    
    var dispatcher = try JobDispatcher.init(allocator, .{
        .db = &db,
        .selection_policy = .least_loaded,
    });
    defer dispatcher.deinit();
    
    // Register runners with different load levels
    try dispatcher.registerRunner(.{
        .id = 1,
        .capabilities = runner1_capabilities,
    });
    
    try dispatcher.registerRunner(.{
        .id = 2,
        .capabilities = runner2_capabilities,
    });
    
    const job = queue.QueuedJob{
        .id = 100,
        .requirements = standard_requirements,
        .queued_at = std.time.timestamp(),
    };
    
    try dispatcher.enqueueJob(job);
    
    // Simulate runner polling
    const assignment1 = try dispatcher.pollForJob(1, runner1_capabilities);
    const assignment2 = try dispatcher.pollForJob(2, runner2_capabilities);
    
    // Job should be assigned to less loaded runner (runner 2)
    try testing.expect(assignment1 == null);
    try testing.expect(assignment2 != null);
    try testing.expectEqual(@as(u32, 100), assignment2.?.job_id);
}

test "dispatcher handles job failures and rescheduling" {
    const allocator = testing.allocator;
    
    var db = try DatabaseConnection.init(allocator, test_db_config);
    defer db.deinit(allocator);
    
    var dispatcher = try JobDispatcher.init(allocator, .{ .db = &db });
    defer dispatcher.deinit();
    
    try dispatcher.registerRunner(.{
        .id = 1,
        .capabilities = standard_capabilities,
    });
    
    const job = queue.QueuedJob{
        .id = 200,
        .retry_count = 0,
        .max_retries = 2,
        .requirements = standard_requirements,
        .queued_at = std.time.timestamp(),
    };
    
    try dispatcher.enqueueJob(job);
    
    // Assign job to runner
    const assignment = try dispatcher.pollForJob(1, standard_capabilities);
    try testing.expect(assignment != null);
    try testing.expectEqual(@as(u32, 200), assignment.?.job_id);
    
    // Simulate job failure
    try dispatcher.updateJobStatus(200, .failed);
    
    // Job should be requeued for retry
    const requeued_job = try dispatcher.pollForJob(1, standard_capabilities);
    try testing.expect(requeued_job != null);
    try testing.expectEqual(@as(u32, 200), requeued_job.?.job_id);
    try testing.expectEqual(@as(u32, 1), requeued_job.?.job_definition.retry_count);
}

// Tests for Phase 4: Database Integration and Persistence
test "dispatcher provides accurate queue metrics" {
    const allocator = testing.allocator;
    
    var db = try DatabaseConnection.init(allocator, test_db_config);
    defer db.deinit(allocator);
    
    var dispatcher = try JobDispatcher.init(allocator, .{ .db = &db });
    defer dispatcher.deinit();
    
    // Add jobs with different priorities
    try dispatcher.enqueueJob(.{ .id = 1, .priority = .critical, .requirements = standard_requirements, .queued_at = std.time.timestamp() });
    try dispatcher.enqueueJob(.{ .id = 2, .priority = .high, .requirements = standard_requirements, .queued_at = std.time.timestamp() });
    try dispatcher.enqueueJob(.{ .id = 3, .priority = .normal, .requirements = standard_requirements, .queued_at = std.time.timestamp() });
    try dispatcher.enqueueJob(.{ .id = 4, .priority = .low, .requirements = standard_requirements, .queued_at = std.time.timestamp() });
    
    const metrics = try dispatcher.getQueueDepth();
    
    try testing.expectEqual(@as(u32, 4), metrics.total_jobs);
    try testing.expectEqual(@as(u32, 1), metrics.critical_jobs);
    try testing.expectEqual(@as(u32, 1), metrics.high_jobs);
    try testing.expectEqual(@as(u32, 1), metrics.normal_jobs);
    try testing.expectEqual(@as(u32, 1), metrics.low_jobs);
}

// Tests for Phase 5: Performance Optimization and Monitoring
test "dispatcher handles high throughput job assignment" {
    const allocator = testing.allocator;
    
    var db = try DatabaseConnection.init(allocator, test_db_config);
    defer db.deinit(allocator);
    
    var dispatcher = try JobDispatcher.init(allocator, .{ .db = &db });
    defer dispatcher.deinit();
    
    // Register multiple runners
    for (0..10) |i| {
        try dispatcher.registerRunner(.{
            .id = @intCast(i),
            .capabilities = standard_capabilities,
        });
    }
    
    // Enqueue many jobs
    const job_count = 100; // Reduced for faster testing
    for (0..job_count) |i| {
        const job = queue.QueuedJob{
            .id = @intCast(i),
            .requirements = standard_requirements,
            .queued_at = std.time.timestamp(),
        };
        try dispatcher.enqueueJob(job);
    }
    
    // Measure assignment performance
    const start_time = std.time.nanoTimestamp();
    
    var assigned_count: u32 = 0;
    for (0..10) |runner_id| {
        while (true) {
            const assignment = try dispatcher.pollForJob(@intCast(runner_id), standard_capabilities);
            if (assignment == null) break;
            assigned_count += 1;
        }
    }
    
    const duration = std.time.nanoTimestamp() - start_time;
    const assignments_per_second = (@as(f64, @floatFromInt(assigned_count)) / @as(f64, @floatFromInt(duration))) * @as(f64, std.time.ns_per_s);
    
    try testing.expect(assigned_count == job_count);
    try testing.expect(assignments_per_second > 10.0); // At least 10 assignments/second
}

test "dispatcher runner utilization metrics" {
    const allocator = testing.allocator;
    
    var db = try DatabaseConnection.init(allocator, test_db_config);
    defer db.deinit(allocator);
    
    var dispatcher = try JobDispatcher.init(allocator, .{ .db = &db });
    defer dispatcher.deinit();
    
    // Register runners
    try dispatcher.registerRunner(.{
        .id = 1,
        .name = "runner-1",
        .capabilities = .{
            .labels = &.{"ubuntu-latest"},
            .max_parallel_jobs = 4,
            .current_jobs = 2,
        },
    });
    
    try dispatcher.registerRunner(.{
        .id = 2,
        .name = "runner-2",
        .capabilities = .{
            .labels = &.{"ubuntu-latest"},
            .max_parallel_jobs = 2,
            .current_jobs = 0,
        },
    });
    
    const utilization = try dispatcher.getRunnerUtilization(allocator);
    defer allocator.free(utilization);
    
    try testing.expectEqual(@as(usize, 2), utilization.len);
    
    // Find runner 1 utilization
    for (utilization) |runner_util| {
        if (runner_util.runner_id == 1) {
            try testing.expectEqual(@as(u32, 2), runner_util.current_jobs);
            try testing.expectEqual(@as(u32, 4), runner_util.max_jobs);
            try testing.expectEqual(@as(f32, 50.0), runner_util.load_percentage);
        }
    }
}

// Tests for Phase 6: Integration and Production Features
test "dispatcher job completion workflow" {
    const allocator = testing.allocator;
    
    var db = try DatabaseConnection.init(allocator, test_db_config);
    defer db.deinit(allocator);
    
    var dispatcher = try JobDispatcher.init(allocator, .{ .db = &db });
    defer dispatcher.deinit();
    
    try dispatcher.registerRunner(.{
        .id = 1,
        .capabilities = standard_capabilities,
    });
    
    const job = queue.QueuedJob{
        .id = 300,
        .job_id = "test-job",
        .requirements = standard_requirements,
        .queued_at = std.time.timestamp(),
    };
    
    try dispatcher.enqueueJob(job);
    
    // Assign job
    const assignment = try dispatcher.pollForJob(1, standard_capabilities);
    try testing.expect(assignment != null);
    
    // Complete job
    const result = JobResult{
        .status = .completed,
        .exit_code = 0,
        .output = "Job completed successfully",
        .error_message = "",
        .completed_at = std.time.timestamp(),
    };
    
    try dispatcher.completeJob(300, result);
    
    // Verify job is completed and runner capacity is freed
    const runner = dispatcher.runner_registry.getRunner(1).?;
    try testing.expectEqual(@as(u32, 0), runner.capabilities.current_jobs);
    try testing.expectEqual(registry.RunnerStatus.online, runner.status);
}