const std = @import("std");
const testing = std.testing;

// Job priority levels for queue ordering
pub const JobPriority = enum(u8) {
    low = 0,
    normal = 1,
    high = 2,
    critical = 3,
    
    pub fn toIndex(self: JobPriority) usize {
        return @intFromEnum(self);
    }
};

// Runner requirements for job assignment
pub const RunnerRequirements = struct {
    labels: []const []const u8 = &.{},
    architecture: []const u8 = "x64",
    min_memory_gb: u32 = 1,
    requires_docker: bool = false,
};

// A queued job waiting for assignment
pub const QueuedJob = struct {
    id: u32,
    job_id: []const u8 = "",
    workflow_run_id: u32 = 0,
    priority: JobPriority = .normal,
    requirements: RunnerRequirements,
    dependencies: []const []const u8 = &.{},
    queued_at: i64,
    timeout_minutes: u32 = 360,
    retry_count: u32 = 0,
    max_retries: u32 = 3,
};

// Dependency tracker for job dependencies
pub const DependencyTracker = struct {
    allocator: std.mem.Allocator,
    completed_jobs: std.StringHashMap(void),
    
    pub fn init(allocator: std.mem.Allocator) DependencyTracker {
        return DependencyTracker{
            .allocator = allocator,
            .completed_jobs = std.StringHashMap(void).init(allocator),
        };
    }
    
    pub fn deinit(self: *DependencyTracker) void {
        // Free all allocated keys
        var iterator = self.completed_jobs.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.completed_jobs.deinit();
    }
    
    pub fn markCompleted(self: *DependencyTracker, job_id: []const u8) !void {
        const owned_id = try self.allocator.dupe(u8, job_id);
        try self.completed_jobs.put(owned_id, {});
    }
    
    pub fn isDependencySatisfied(self: *const DependencyTracker, dependencies: []const []const u8) bool {
        for (dependencies) |dep| {
            if (!self.completed_jobs.contains(dep)) {
                return false;
            }
        }
        return true;
    }
};

// Priority-based job queue with dependency tracking
pub const JobQueue = struct {
    allocator: std.mem.Allocator,
    priority_queues: [4]std.ArrayList(QueuedJob), // low, normal, high, critical
    dependency_tracker: DependencyTracker,
    
    pub fn init(allocator: std.mem.Allocator) !JobQueue {
        return JobQueue{
            .allocator = allocator,
            .priority_queues = [4]std.ArrayList(QueuedJob){
                std.ArrayList(QueuedJob).init(allocator), // low
                std.ArrayList(QueuedJob).init(allocator), // normal
                std.ArrayList(QueuedJob).init(allocator), // high
                std.ArrayList(QueuedJob).init(allocator), // critical
            },
            .dependency_tracker = DependencyTracker.init(allocator),
        };
    }
    
    pub fn deinit(self: *JobQueue) void {
        for (&self.priority_queues) |*queue| {
            queue.deinit();
        }
        self.dependency_tracker.deinit();
    }
    
    pub fn enqueue(self: *JobQueue, job: QueuedJob) !void {
        const queue_index = job.priority.toIndex();
        try self.priority_queues[queue_index].append(job);
    }
    
    pub fn dequeue(self: *JobQueue, requirements: RunnerRequirements) !?QueuedJob {
        _ = requirements; // TODO: Use for filtering compatible jobs
        
        // Check from highest priority to lowest
        var priority_idx: usize = 4;
        while (priority_idx > 0) {
            priority_idx -= 1;
            var queue = &self.priority_queues[priority_idx];
            
            // Find first job with satisfied dependencies
            var i: usize = 0;
            while (i < queue.items.len) {
                const job = queue.items[i];
                if (self.dependency_tracker.isDependencySatisfied(job.dependencies)) {
                    return queue.orderedRemove(i);
                }
                i += 1;
            }
        }
        
        return null;
    }
    
    pub fn peek(self: *const JobQueue, count: u32) ![]QueuedJob {
        _ = self;
        _ = count;
        // TODO: Implement peek functionality
        return &.{};
    }
    
    pub fn remove(self: *JobQueue, job_id: u32) !void {
        for (&self.priority_queues) |*queue| {
            var i: usize = 0;
            while (i < queue.items.len) {
                if (queue.items[i].id == job_id) {
                    _ = queue.orderedRemove(i);
                    return;
                }
                i += 1;
            }
        }
    }
    
    pub fn markJobCompleted(self: *JobQueue, job_id: u32, job_name: []const u8) !void {
        _ = job_id;
        try self.dependency_tracker.markCompleted(job_name);
    }
    
    pub fn getTotalJobs(self: *const JobQueue) u32 {
        var total: u32 = 0;
        for (self.priority_queues) |queue| {
            total += @intCast(queue.items.len);
        }
        return total;
    }
};

// Test data for reuse
const test_requirements = RunnerRequirements{
    .labels = &.{"ubuntu-latest"},
    .architecture = "x64",
    .min_memory_gb = 2,
    .requires_docker = false,
};

// Tests for Phase 1: Job Queue Foundation
test "job queue handles priority-based ordering" {
    const allocator = testing.allocator;
    
    var job_queue = try JobQueue.init(allocator);
    defer job_queue.deinit();
    
    // Add jobs with different priorities
    const normal_job = QueuedJob{
        .id = 1,
        .priority = .normal,
        .requirements = test_requirements,
        .queued_at = std.time.timestamp(),
    };
    
    const high_job = QueuedJob{
        .id = 2,
        .priority = .high,
        .requirements = test_requirements,
        .queued_at = std.time.timestamp(),
    };
    
    const critical_job = QueuedJob{
        .id = 3,
        .priority = .critical,
        .requirements = test_requirements,
        .queued_at = std.time.timestamp(),
    };
    
    // Enqueue in random order
    try job_queue.enqueue(normal_job);
    try job_queue.enqueue(high_job);
    try job_queue.enqueue(critical_job);
    
    // Dequeue should return critical first
    const first_job = try job_queue.dequeue(test_requirements);
    try testing.expect(first_job != null);
    try testing.expectEqual(@as(u32, 3), first_job.?.id);
    try testing.expectEqual(JobPriority.critical, first_job.?.priority);
    
    // Then high priority
    const second_job = try job_queue.dequeue(test_requirements);
    try testing.expect(second_job != null);
    try testing.expectEqual(@as(u32, 2), second_job.?.id);
    
    // Finally normal priority
    const third_job = try job_queue.dequeue(test_requirements);
    try testing.expect(third_job != null);
    try testing.expectEqual(@as(u32, 1), third_job.?.id);
}

test "job queue respects dependency constraints" {
    const allocator = testing.allocator;
    
    var job_queue = try JobQueue.init(allocator);
    defer job_queue.deinit();
    
    // Job B depends on Job A
    const job_a = QueuedJob{
        .id = 1,
        .job_id = "build",
        .dependencies = &.{},
        .requirements = test_requirements,
        .queued_at = std.time.timestamp(),
    };
    
    const job_b = QueuedJob{
        .id = 2,
        .job_id = "test",
        .dependencies = &.{"build"},
        .requirements = test_requirements,
        .queued_at = std.time.timestamp(),
    };
    
    try job_queue.enqueue(job_b);
    try job_queue.enqueue(job_a);
    
    // Should dequeue job A first (no dependencies)
    const first_job = try job_queue.dequeue(test_requirements);
    try testing.expectEqual(@as(u32, 1), first_job.?.id);
    
    // Job B should still be waiting (dependency not satisfied)
    const second_job = try job_queue.dequeue(test_requirements);
    try testing.expect(second_job == null);
    
    // Mark job A as completed
    try job_queue.markJobCompleted(1, "build");
    
    // Now job B should be available
    const third_job = try job_queue.dequeue(test_requirements);
    try testing.expectEqual(@as(u32, 2), third_job.?.id);
}

test "job queue tracks total job count" {
    const allocator = testing.allocator;
    
    var job_queue = try JobQueue.init(allocator);
    defer job_queue.deinit();
    
    try testing.expectEqual(@as(u32, 0), job_queue.getTotalJobs());
    
    const job1 = QueuedJob{
        .id = 1,
        .priority = .normal,
        .requirements = test_requirements,
        .queued_at = std.time.timestamp(),
    };
    
    const job2 = QueuedJob{
        .id = 2,
        .priority = .high,
        .requirements = test_requirements,
        .queued_at = std.time.timestamp(),
    };
    
    try job_queue.enqueue(job1);
    try testing.expectEqual(@as(u32, 1), job_queue.getTotalJobs());
    
    try job_queue.enqueue(job2);
    try testing.expectEqual(@as(u32, 2), job_queue.getTotalJobs());
    
    _ = try job_queue.dequeue(test_requirements);
    try testing.expectEqual(@as(u32, 1), job_queue.getTotalJobs());
}

test "job queue remove functionality" {
    const allocator = testing.allocator;
    
    var job_queue = try JobQueue.init(allocator);
    defer job_queue.deinit();
    
    const job1 = QueuedJob{
        .id = 100,
        .priority = .normal,
        .requirements = test_requirements,
        .queued_at = std.time.timestamp(),
    };
    
    const job2 = QueuedJob{
        .id = 200,
        .priority = .high,
        .requirements = test_requirements,
        .queued_at = std.time.timestamp(),
    };
    
    try job_queue.enqueue(job1);
    try job_queue.enqueue(job2);
    try testing.expectEqual(@as(u32, 2), job_queue.getTotalJobs());
    
    // Remove job1
    try job_queue.remove(100);
    try testing.expectEqual(@as(u32, 1), job_queue.getTotalJobs());
    
    // Only job2 should remain
    const remaining_job = try job_queue.dequeue(test_requirements);
    try testing.expect(remaining_job != null);
    try testing.expectEqual(@as(u32, 200), remaining_job.?.id);
}