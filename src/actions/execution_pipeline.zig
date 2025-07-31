const std = @import("std");
const testing = std.testing;
const models = @import("models.zig");
const workflow_manager = @import("workflow_manager.zig");
const dispatcher = @import("dispatcher.zig");
const executor = @import("executor.zig");
const queue = @import("queue.zig");
const registry = @import("registry.zig");

const WorkflowRun = models.WorkflowRun;
const JobExecution = models.JobExecution;
const ActionsDAO = models.ActionsDAO;
const WorkflowManager = workflow_manager.WorkflowManager;
const JobDispatcher = dispatcher.JobDispatcher;
const JobExecutor = executor.JobExecutor;

pub const PipelineError = error{
    WorkflowNotFound,
    JobCreationFailed,
    RunnerNotAvailable,
    ExecutionFailed,
    DatabaseError,
    OutOfMemory,
} || std.mem.Allocator.Error;

pub const PipelineStatus = enum {
    idle,
    processing,
    waiting_for_runners,
    error_state,
};

pub const ExecutionStats = struct {
    active_runs: u32,
    completed_runs: u32,
    failed_runs: u32,
    queued_jobs: u32,
    running_jobs: u32,
    available_runners: u32,
    total_runners: u32,
    
    pub fn getRunnerUtilization(self: ExecutionStats) f32 {
        if (self.total_runners == 0) return 0.0;
        const used_runners = self.total_runners - self.available_runners;
        return @as(f32, @floatFromInt(used_runners)) / @as(f32, @floatFromInt(self.total_runners)) * 100.0;
    }
};

pub const RunnerAssignment = struct {
    runner_id: u32,
    job_id: u32,
    assigned_at: i64,
    estimated_completion: ?i64 = null,
};

pub const PipelineEvent = union(enum) {
    workflow_run_created: struct {
        run_id: u32,
        workflow_id: u32,
        repository_id: u32,
    },
    job_queued: struct {
        job_id: u32,
        run_id: u32,
        priority: queue.JobPriority,
    },
    job_assigned: struct {
        job_id: u32,
        runner_id: u32,
        assigned_at: i64,
    },
    job_started: struct {
        job_id: u32,
        runner_id: u32,
        started_at: i64,
    },
    job_completed: struct {
        job_id: u32,
        runner_id: u32,
        status: executor.JobStatus,
        conclusion: ?executor.JobConclusion,
        completed_at: i64,
    },
    workflow_run_completed: struct {
        run_id: u32,
        status: WorkflowRun.RunStatus,
        conclusion: ?WorkflowRun.RunConclusion,
        completed_at: i64,
    },
};

pub const ExecutionPipeline = struct {
    allocator: std.mem.Allocator,
    dao: *ActionsDAO,
    workflow_manager: *WorkflowManager,
    job_dispatcher: *JobDispatcher,
    job_executor: *JobExecutor,
    status: PipelineStatus,
    active_runs: std.HashMap(u32, *ActiveWorkflowRun, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage),
    runner_assignments: std.HashMap(u32, RunnerAssignment, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage),
    event_listeners: std.ArrayList(*const fn (PipelineEvent) void),
    
    const ActiveWorkflowRun = struct {
        run_id: u32,
        workflow_run: WorkflowRun,
        queued_jobs: std.ArrayList(queue.QueuedJob),
        running_jobs: std.ArrayList(u32),
        completed_jobs: std.ArrayList(JobResult),
        created_at: i64,
        
        pub fn deinit(self: *ActiveWorkflowRun, allocator: std.mem.Allocator) void {
            self.workflow_run.deinit(allocator);
            
            // QueuedJob doesn't need deinit (simple struct)
            self.queued_jobs.deinit();
            
            self.running_jobs.deinit();
            
            for (self.completed_jobs.items) |*result| {
                result.deinit(allocator);
            }
            self.completed_jobs.deinit();
            
            allocator.destroy(self);
        }
        
        pub fn isComplete(self: *const ActiveWorkflowRun) bool {
            return self.running_jobs.items.len == 0 and self.queued_jobs.items.len == 0;
        }
        
        pub fn hasFailures(self: *const ActiveWorkflowRun) bool {
            for (self.completed_jobs.items) |result| {
                if (result.conclusion == .failure) return true;
            }
            return false;
        }
    };
    
    const JobResult = struct {
        job_id: u32,
        status: executor.JobStatus,
        conclusion: ?executor.JobConclusion,
        completed_at: i64,
        resource_usage: executor.ResourceUsage,
        
        pub fn deinit(self: *JobResult, allocator: std.mem.Allocator) void {
            _ = self;
            _ = allocator;
        }
    };
    
    pub fn init(
        allocator: std.mem.Allocator,
        dao: *ActionsDAO,
        workflow_mgr: *WorkflowManager,
        job_dispatcher: *JobDispatcher,
        job_executor: *JobExecutor,
    ) ExecutionPipeline {
        return ExecutionPipeline{
            .allocator = allocator,
            .dao = dao,
            .workflow_manager = workflow_mgr,
            .job_dispatcher = job_dispatcher,
            .job_executor = job_executor,
            .status = .idle,
            .active_runs = std.HashMap(u32, *ActiveWorkflowRun, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage).init(allocator),
            .runner_assignments = std.HashMap(u32, RunnerAssignment, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage).init(allocator),
            .event_listeners = std.ArrayList(*const fn (PipelineEvent) void).init(allocator),
        };
    }
    
    pub fn deinit(self: *ExecutionPipeline) void {
        // Clean up active workflow runs
        var runs_iter = self.active_runs.iterator();
        while (runs_iter.next()) |entry| {
            entry.value_ptr.*.deinit(self.allocator);
        }
        self.active_runs.deinit();
        
        self.runner_assignments.deinit();
        self.event_listeners.deinit();
    }
    
    pub fn start(self: *ExecutionPipeline) !void {
        self.status = .processing;
        std.log.info("Execution pipeline started", .{});
    }
    
    pub fn stop(self: *ExecutionPipeline) !void {
        self.status = .idle;
        
        // Wait for any running jobs to complete gracefully
        var runs_iter = self.active_runs.iterator();
        while (runs_iter.next()) |entry| {
            const active_run = entry.value_ptr.*;
            for (active_run.running_jobs.items) |job_id| {
                try self.job_executor.cancelJob(job_id);
            }
        }
        
        std.log.info("Execution pipeline stopped", .{});
    }
    
    pub fn processWorkflowRun(self: *ExecutionPipeline, run_id: u32) !void {
        // Get workflow run from database
        const workflow_run = try self.dao.getWorkflowRun(run_id);
        
        // Get workflow definition
        const workflow = try self.dao.getWorkflow(workflow_run.workflow_id);
        defer {
            var mut_workflow = workflow;
            mut_workflow.deinit(self.allocator);
        }
        
        // Create active run tracking
        const active_run = try self.allocator.create(ActiveWorkflowRun);
        active_run.* = ActiveWorkflowRun{
            .run_id = run_id,
            .workflow_run = workflow_run,
            .queued_jobs = std.ArrayList(queue.QueuedJob).init(self.allocator),
            .running_jobs = std.ArrayList(u32).init(self.allocator),
            .completed_jobs = std.ArrayList(JobResult).init(self.allocator),
            .created_at = std.time.timestamp(),
        };
        
        try self.active_runs.put(run_id, active_run);
        
        // Emit event
        self.emitEvent(PipelineEvent{
            .workflow_run_created = .{
                .run_id = run_id,
                .workflow_id = workflow_run.workflow_id,
                .repository_id = workflow_run.repository_id,
            },
        });
        
        // Convert workflow jobs to queued jobs
        try self.createJobsForWorkflowRun(workflow, active_run);
        
        // Start processing jobs
        try self.processQueuedJobs(active_run);
    }
    
    pub fn processRunnerPoll(self: *ExecutionPipeline, runner_id: u32, capabilities: registry.RunnerCapabilities) !?dispatcher.AssignedJob {
        // Get job assignment from dispatcher
        const assignment = try self.job_dispatcher.pollForJob(runner_id, capabilities);
        
        if (assignment) |assigned_job| {
            // Track the assignment
            try self.runner_assignments.put(assigned_job.job_id, RunnerAssignment{
                .runner_id = runner_id,
                .job_id = assigned_job.job_id,
                .assigned_at = std.time.timestamp(),
            });
            
            // Update active run tracking
            if (self.findActiveRunForJob(assigned_job.job_id)) |active_run| {
                // Remove from queued jobs and add to running jobs
                for (active_run.queued_jobs.items, 0..) |job, i| {
                    if (job.id == assigned_job.job_id) {
                        _ = active_run.queued_jobs.orderedRemove(i);
                        break;
                    }
                }
                try active_run.running_jobs.append(assigned_job.job_id);
            }
            
            // Emit event
            self.emitEvent(PipelineEvent{
                .job_assigned = .{
                    .job_id = assigned_job.job_id,
                    .runner_id = runner_id,
                    .assigned_at = std.time.timestamp(),
                },
            });
            
            return assigned_job;
        }
        
        return null;
    }
    
    pub fn reportJobStarted(self: *ExecutionPipeline, job_id: u32, runner_id: u32) !void {
        // Update job status in dispatcher
        try self.job_dispatcher.updateJobStatus(job_id, .running);
        
        // Emit event
        self.emitEvent(PipelineEvent{
            .job_started = .{
                .job_id = job_id,
                .runner_id = runner_id,
                .started_at = std.time.timestamp(),
            },
        });
    }
    
    pub fn reportJobCompleted(
        self: *ExecutionPipeline,
        job_id: u32,
        runner_id: u32,
        result: executor.JobResult,
    ) !void {
        // Complete job in dispatcher
        const dispatcher_result = dispatcher.JobResult{
            .status = switch (result.status) {
                .completed => .completed,
                .failed => .failed,
                .cancelled => .cancelled,
                else => .failed,
            },
            .exit_code = if (result.conclusion == .success) 0 else 1,
            .output = "", // Would contain actual job logs in real implementation
            .error_message = "", // Would contain error details
            .completed_at = result.completed_at,
        };
        
        try self.job_dispatcher.completeJob(job_id, dispatcher_result);
        
        // Remove runner assignment
        _ = self.runner_assignments.remove(job_id);
        
        // Update active run tracking
        if (self.findActiveRunForJob(job_id)) |active_run| {
            // Remove from running jobs
            for (active_run.running_jobs.items, 0..) |running_job_id, i| {
                if (running_job_id == job_id) {
                    _ = active_run.running_jobs.orderedRemove(i);
                    break;
                }
            }
            
            // Add to completed jobs
            try active_run.completed_jobs.append(JobResult{
                .job_id = job_id,
                .status = result.status,
                .conclusion = result.conclusion,
                .completed_at = result.completed_at,
                .resource_usage = result.resource_usage,
            });
            
            // Emit job completed event
            self.emitEvent(PipelineEvent{
                .job_completed = .{
                    .job_id = job_id,
                    .runner_id = runner_id,
                    .status = result.status,
                    .conclusion = result.conclusion,
                    .completed_at = result.completed_at,
                },
            });
            
            // Check if workflow run is complete
            if (active_run.isComplete()) {
                try self.completeWorkflowRun(active_run);
            } else {
                // Try to process any remaining queued jobs
                try self.processQueuedJobs(active_run);
            }
        }
    }
    
    pub fn getExecutionStats(self: *ExecutionPipeline) !ExecutionStats {
        var active_runs: u32 = 0;
        const completed_runs: u32 = 0;
        const failed_runs: u32 = 0;
        var queued_jobs: u32 = 0;
        var running_jobs: u32 = 0;
        
        // Count active runs and jobs
        var runs_iter = self.active_runs.iterator();
        while (runs_iter.next()) |entry| {
            const active_run = entry.value_ptr.*;
            active_runs += 1;
            queued_jobs += @intCast(active_run.queued_jobs.items.len);
            running_jobs += @intCast(active_run.running_jobs.items.len);
        }
        
        // Get runner statistics
        const runner_utilization = try self.job_dispatcher.getRunnerUtilization(self.allocator);
        defer self.allocator.free(runner_utilization);
        
        var available_runners: u32 = 0;
        const total_runners = @as(u32, @intCast(runner_utilization.len));
        
        for (runner_utilization) |runner| {
            if (runner.status == .online and runner.current_jobs < runner.max_jobs) {
                available_runners += 1;
            }
        }
        
        return ExecutionStats{
            .active_runs = active_runs,
            .completed_runs = completed_runs,
            .failed_runs = failed_runs,
            .queued_jobs = queued_jobs,
            .running_jobs = running_jobs,
            .available_runners = available_runners,
            .total_runners = total_runners,
        };
    }
    
    pub fn addEventListener(self: *ExecutionPipeline, listener: *const fn (PipelineEvent) void) !void {
        try self.event_listeners.append(listener);
    }
    
    fn createJobsForWorkflowRun(self: *ExecutionPipeline, workflow: models.Workflow, active_run: *ActiveWorkflowRun) !void {
        var job_iterator = workflow.jobs.iterator();
        while (job_iterator.next()) |entry| {
            const job_id = entry.key_ptr.*;
            const job_def = entry.value_ptr.*;
            
            // Create queued job from workflow job definition
            const queued_job = queue.QueuedJob{
                .id = active_run.queued_jobs.items.len + 1, // Simple ID generation
                .workflow_run_id = active_run.run_id,
                .job_id = try self.allocator.dupe(u8, job_id),
                .job_name = if (job_def.name) |name| try self.allocator.dupe(u8, name) else null,
                .runner_requirements = try self.allocator.alloc([]const u8, 1),
                .priority = .normal,
                .created_at = std.time.timestamp(),
                .timeout_minutes = job_def.timeout_minutes,
                .environment = try self.cloneStringHashMap(&job_def.environment),
                .steps = try self.convertJobSteps(job_def.steps),
            };
            
            // Set runner requirements
            queued_job.runner_requirements[0] = try self.allocator.dupe(u8, job_def.runs_on);
            
            try active_run.queued_jobs.append(queued_job);
            
            // Emit event
            self.emitEvent(PipelineEvent{
                .job_queued = .{
                    .job_id = queued_job.id,
                    .run_id = active_run.run_id,
                    .priority = queued_job.priority,
                },
            });
        }
    }
    
    fn processQueuedJobs(self: *ExecutionPipeline, active_run: *ActiveWorkflowRun) !void {
        // Queue all jobs with the dispatcher
        for (active_run.queued_jobs.items) |job| {
            try self.job_dispatcher.enqueueJob(job);
        }
    }
    
    fn completeWorkflowRun(self: *ExecutionPipeline, active_run: *ActiveWorkflowRun) !void {
        const completion_time = std.time.timestamp();
        
        // Determine final status and conclusion
        const conclusion: WorkflowRun.RunConclusion = if (active_run.hasFailures()) .failure else .success;
        
        // Update workflow run status in database (would be implemented in DAO)
        // TODO: Add updateWorkflowRun method to DAO
        
        // Emit completion event
        self.emitEvent(PipelineEvent{
            .workflow_run_completed = .{
                .run_id = active_run.run_id,
                .status = .completed,
                .conclusion = conclusion,
                .completed_at = completion_time,
            },
        });
        
        // Clean up active run
        _ = self.active_runs.remove(active_run.run_id);
        active_run.deinit(self.allocator);
        
        std.log.info("Workflow run {} completed with conclusion: {}", .{ active_run.run_id, conclusion });
    }
    
    fn findActiveRunForJob(self: *ExecutionPipeline, job_id: u32) ?*ActiveWorkflowRun {
        var runs_iter = self.active_runs.iterator();
        while (runs_iter.next()) |entry| {
            const active_run = entry.value_ptr.*;
            
            // Check queued jobs
            for (active_run.queued_jobs.items) |job| {
                if (job.id == job_id) return active_run;
            }
            
            // Check running jobs
            for (active_run.running_jobs.items) |running_job_id| {
                if (running_job_id == job_id) return active_run;
            }
            
            // Check completed jobs
            for (active_run.completed_jobs.items) |result| {
                if (result.job_id == job_id) return active_run;
            }
        }
        
        return null;
    }
    
    fn convertJobSteps(self: *ExecutionPipeline, model_steps: []const models.JobStep) ![]queue.JobStep {
        var steps = try self.allocator.alloc(queue.JobStep, model_steps.len);
        for (model_steps, 0..) |model_step, i| {
            steps[i] = queue.JobStep{
                .name = if (model_step.name) |name| try self.allocator.dupe(u8, name) else null,
                .uses = if (model_step.uses) |uses| try self.allocator.dupe(u8, uses) else null,
                .run = if (model_step.run) |run| try self.allocator.dupe(u8, run) else null,
                .with = try self.cloneStringHashMap(&model_step.with),
                .env = try self.cloneStringHashMap(&model_step.env),
                .if_condition = if (model_step.if_condition) |cond| try self.allocator.dupe(u8, cond) else null,
                .continue_on_error = model_step.continue_on_error,
                .timeout_minutes = model_step.timeout_minutes,
            };
        }
        return steps;
    }
    
    fn cloneStringHashMap(self: *ExecutionPipeline, original: *const std.StringHashMap([]const u8)) !std.StringHashMap([]const u8) {
        var cloned = std.StringHashMap([]const u8).init(self.allocator);
        var iterator = original.iterator();
        while (iterator.next()) |entry| {
            try cloned.put(
                try self.allocator.dupe(u8, entry.key_ptr.*),
                try self.allocator.dupe(u8, entry.value_ptr.*)
            );
        }
        return cloned;
    }
    
    fn emitEvent(self: *ExecutionPipeline, event: PipelineEvent) void {
        for (self.event_listeners.items) |listener| {
            listener(event);
        }
    }
};

// Test event listener
var test_events: std.ArrayList(PipelineEvent) = undefined;
var test_events_initialized = false;

fn testEventListener(event: PipelineEvent) void {
    if (!test_events_initialized) return;
    test_events.append(event) catch return;
}

// Tests for execution pipeline
test "execution pipeline initializes correctly" {
    const allocator = testing.allocator;
    
    // Create mock dependencies
    var mock_dao = models.ActionsDAO.init(allocator, undefined);
    defer mock_dao.deinit();
    
    var mock_db = dispatcher.DatabaseConnection.init(allocator, .{}) catch unreachable;
    defer mock_db.deinit(allocator);
    
    var job_dispatcher = try dispatcher.JobDispatcher.init(allocator, .{ .db = &mock_db });
    defer job_dispatcher.deinit();
    
    var workflow_mgr = try workflow_manager.WorkflowManager.init(allocator, &mock_dao, &job_dispatcher);
    defer workflow_mgr.deinit();
    
    var job_executor = try executor.JobExecutor.init(allocator, .{});
    defer job_executor.deinit();
    
    // Create execution pipeline
    var pipeline = ExecutionPipeline.init(
        allocator,
        &mock_dao,
        &workflow_mgr,
        &job_dispatcher,
        &job_executor,
    );
    defer pipeline.deinit();
    
    try testing.expectEqual(PipelineStatus.idle, pipeline.status);
    try testing.expectEqual(@as(usize, 0), pipeline.active_runs.count());
}

test "execution pipeline tracks workflow run lifecycle" {
    const allocator = testing.allocator;
    
    // Initialize test events tracking
    test_events = std.ArrayList(PipelineEvent).init(allocator);
    defer test_events.deinit();
    test_events_initialized = true;
    defer test_events_initialized = false;
    
    // Create mock dependencies
    var mock_dao = models.ActionsDAO.init(allocator, undefined);
    defer mock_dao.deinit();
    
    var mock_db = dispatcher.DatabaseConnection.init(allocator, .{}) catch unreachable;
    defer mock_db.deinit(allocator);
    
    var job_dispatcher = try dispatcher.JobDispatcher.init(allocator, .{ .db = &mock_db });
    defer job_dispatcher.deinit();
    
    var workflow_mgr = try workflow_manager.WorkflowManager.init(allocator, &mock_dao, &job_dispatcher);
    defer workflow_mgr.deinit();
    
    var job_executor = try executor.JobExecutor.init(allocator, .{});
    defer job_executor.deinit();
    
    var pipeline = ExecutionPipeline.init(
        allocator,
        &mock_dao,
        &workflow_mgr,
        &job_dispatcher,
        &job_executor,
    );
    defer pipeline.deinit();
    
    // Add event listener
    try pipeline.addEventListener(testEventListener);
    
    // Start pipeline
    try pipeline.start();
    try testing.expectEqual(PipelineStatus.processing, pipeline.status);
    
    // Stop pipeline
    try pipeline.stop();
    try testing.expectEqual(PipelineStatus.idle, pipeline.status);
}

test "execution pipeline generates execution statistics" {
    const allocator = testing.allocator;
    
    // Create mock dependencies
    var mock_dao = models.ActionsDAO.init(allocator, undefined);
    defer mock_dao.deinit();
    
    var mock_db = dispatcher.DatabaseConnection.init(allocator, .{}) catch unreachable;
    defer mock_db.deinit(allocator);
    
    var job_dispatcher = try dispatcher.JobDispatcher.init(allocator, .{ .db = &mock_db });
    defer job_dispatcher.deinit();
    
    var workflow_mgr = try workflow_manager.WorkflowManager.init(allocator, &mock_dao, &job_dispatcher);
    defer workflow_mgr.deinit();
    
    var job_executor = try executor.JobExecutor.init(allocator, .{});
    defer job_executor.deinit();
    
    var pipeline = ExecutionPipeline.init(
        allocator,
        &mock_dao,
        &workflow_mgr,
        &job_dispatcher,
        &job_executor,
    );
    defer pipeline.deinit();
    
    // Get initial stats
    const stats = try pipeline.getExecutionStats();
    
    try testing.expectEqual(@as(u32, 0), stats.active_runs);
    try testing.expectEqual(@as(u32, 0), stats.queued_jobs);
    try testing.expectEqual(@as(u32, 0), stats.running_jobs);
    try testing.expect(stats.getRunnerUtilization() >= 0.0);
}

test "execution pipeline handles runner polling" {
    const allocator = testing.allocator;
    
    // Create mock dependencies
    var mock_dao = models.ActionsDAO.init(allocator, undefined);
    defer mock_dao.deinit();
    
    var mock_db = dispatcher.DatabaseConnection.init(allocator, .{}) catch unreachable;
    defer mock_db.deinit(allocator);
    
    var job_dispatcher = try dispatcher.JobDispatcher.init(allocator, .{ .db = &mock_db });
    defer job_dispatcher.deinit();
    
    var workflow_mgr = try workflow_manager.WorkflowManager.init(allocator, &mock_dao, &job_dispatcher);
    defer workflow_mgr.deinit();
    
    var job_executor = try executor.JobExecutor.init(allocator, .{});
    defer job_executor.deinit();
    
    var pipeline = ExecutionPipeline.init(
        allocator,
        &mock_dao,
        &workflow_mgr,
        &job_dispatcher,
        &job_executor,
    );
    defer pipeline.deinit();
    
    // Register a runner
    try job_dispatcher.registerRunner(.{
        .id = 1,
        .capabilities = .{
            .labels = &.{"ubuntu-latest"},
            .max_parallel_jobs = 2,
            .current_jobs = 0,
        },
    });
    
    // Poll for job (should return null since no jobs queued)
    const capabilities = registry.RunnerCapabilities{
        .labels = &.{"ubuntu-latest"},
        .max_parallel_jobs = 2,
        .current_jobs = 0,
    };
    
    const assignment = try pipeline.processRunnerPoll(1, capabilities);
    try testing.expect(assignment == null);
}

test "execution statistics calculate runner utilization correctly" {
    const stats = ExecutionStats{
        .active_runs = 5,
        .completed_runs = 10,
        .failed_runs = 2,
        .queued_jobs = 3,
        .running_jobs = 7,
        .available_runners = 2,
        .total_runners = 10,
    };
    
    const utilization = stats.getRunnerUtilization();
    try testing.expectEqual(@as(f32, 80.0), utilization); // 8 used out of 10 total = 80%
    
    // Test edge case with no runners
    const empty_stats = ExecutionStats{
        .active_runs = 0,
        .completed_runs = 0,
        .failed_runs = 0,
        .queued_jobs = 0,
        .running_jobs = 0,
        .available_runners = 0,
        .total_runners = 0,
    };
    
    try testing.expectEqual(@as(f32, 0.0), empty_stats.getRunnerUtilization());
}