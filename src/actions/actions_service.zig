const std = @import("std");
const testing = std.testing;
const models = @import("models.zig");
const workflow_manager = @import("workflow_manager.zig");
const dispatcher = @import("dispatcher.zig");
const executor = @import("executor.zig");
const execution_pipeline = @import("execution_pipeline.zig");
const registry = @import("registry.zig");
const queue = @import("queue.zig");
const repository_model = @import("../database/models/repository.zig");
const artifacts = @import("artifacts.zig");

const ActionsDAO = models.ActionsDAO;
const WorkflowManager = workflow_manager.WorkflowManager;
const JobDispatcher = dispatcher.JobDispatcher;
const JobExecutor = executor.JobExecutor;
const ExecutionPipeline = execution_pipeline.ExecutionPipeline;

pub const ActionsServiceError = error{
    InitializationFailed,
    ServiceAlreadyRunning,
    ServiceNotRunning,
    ComponentInitFailed,
    DatabaseConnectionFailed,
    OutOfMemory,
} || std.mem.Allocator.Error;

pub const ServiceStatus = enum {
    stopped,
    starting,
    running,
    stopping,
    error_state,
};

pub const ActionsServiceConfig = struct {
    database_url: []const u8,
    executor_config: executor.ExecutorConfig = .{},
    dispatcher_config: dispatcher.DispatcherConfig = .{},
    enable_execution_pipeline: bool = true,
    max_concurrent_workflows: u32 = 100,
    
    pub fn default() ActionsServiceConfig {
        return ActionsServiceConfig{
            .database_url = "postgresql://localhost:5432/plue",
        };
    }
};

pub const ServiceStats = struct {
    status: ServiceStatus,
    uptime_seconds: u64,
    registered_runners: u32,
    active_workflows: u32,
    queued_jobs: u32,
    running_jobs: u32,
    completed_jobs: u64,
    failed_jobs: u64,
    avg_job_duration_ms: u64,
    runner_utilization_percent: f32,
    
    pub fn isHealthy(self: ServiceStats) bool {
        return self.status == .running and self.runner_utilization_percent < 95.0;
    }
};

pub const ActionsService = struct {
    allocator: std.mem.Allocator,
    config: ActionsServiceConfig,
    status: ServiceStatus,
    started_at: ?i64 = null,
    
    // Core components
    dao: *ActionsDAO,
    workflow_manager: *WorkflowManager,
    job_dispatcher: *JobDispatcher,
    job_executor: *JobExecutor,
    execution_pipeline: ?*ExecutionPipeline = null,
    
    // Statistics tracking
    completed_jobs_count: u64 = 0,
    failed_jobs_count: u64 = 0,
    total_job_duration_ms: u64 = 0,
    
    pub fn init(allocator: std.mem.Allocator, config: ActionsServiceConfig) !*ActionsService {
        const service = try allocator.create(ActionsService);
        errdefer allocator.destroy(service);
        
        // Initialize DAO with database connection
        const dao = try allocator.create(ActionsDAO);
        errdefer allocator.destroy(dao);
        
        // For now, create a mock database connection
        // In a real implementation, this would connect to PostgreSQL
        dao.* = ActionsDAO.init(allocator, undefined);
        
        // Initialize job executor
        const job_executor = try allocator.create(JobExecutor);
        errdefer allocator.destroy(job_executor);
        job_executor.* = try JobExecutor.init(allocator, config.executor_config);
        
        // Initialize job dispatcher
        const job_dispatcher = try allocator.create(JobDispatcher);
        errdefer allocator.destroy(job_dispatcher);
        
        const mock_db = try allocator.create(dispatcher.DatabaseConnection);
        errdefer allocator.destroy(mock_db);
        mock_db.* = try dispatcher.DatabaseConnection.init(allocator, .{});
        
        job_dispatcher.* = try JobDispatcher.init(allocator, .{
            .db = mock_db,
            .selection_policy = config.dispatcher_config.selection_policy,
        });
        
        // Initialize workflow manager
        const workflow_manager_instance = try allocator.create(WorkflowManager);
        errdefer allocator.destroy(workflow_manager_instance);
        workflow_manager_instance.* = try WorkflowManager.init(allocator, dao, job_dispatcher);
        
        // Initialize execution pipeline if enabled
        var pipeline: ?*ExecutionPipeline = null;
        if (config.enable_execution_pipeline) {
            const pipeline_instance = try allocator.create(ExecutionPipeline);
            errdefer allocator.destroy(pipeline_instance);
            
            pipeline_instance.* = ExecutionPipeline.init(
                allocator,
                dao,
                workflow_manager_instance,
                job_dispatcher,
                job_executor,
            );
            
            // Connect workflow manager to pipeline
            workflow_manager_instance.setExecutionPipeline(pipeline_instance);
            pipeline = pipeline_instance;
        }
        
        service.* = ActionsService{
            .allocator = allocator,
            .config = config,
            .status = .stopped,
            .dao = dao,
            .workflow_manager = workflow_manager_instance,
            .job_dispatcher = job_dispatcher,
            .job_executor = job_executor,
            .execution_pipeline = pipeline,
        };
        
        return service;
    }
    
    pub fn deinit(self: *ActionsService) void {
        // Stop service if running
        self.stop() catch {};
        
        // Clean up execution pipeline
        if (self.execution_pipeline) |pipeline| {
            pipeline.deinit();
            self.allocator.destroy(pipeline);
        }
        
        // Clean up workflow manager
        self.workflow_manager.deinit();
        self.allocator.destroy(self.workflow_manager);
        
        // Clean up job executor
        self.job_executor.deinit();
        self.allocator.destroy(self.job_executor);
        
        // Clean up job dispatcher
        self.job_dispatcher.deinit();
        self.allocator.destroy(self.job_dispatcher);
        
        // Clean up DAO
        self.dao.deinit();
        self.allocator.destroy(self.dao);
        
        self.allocator.destroy(self);
    }
    
    pub fn start(self: *ActionsService) !void {
        if (self.status != .stopped) {
            return ActionsServiceError.ServiceAlreadyRunning;
        }
        
        self.status = .starting;
        self.started_at = std.time.timestamp();
        
        std.log.info("Starting Actions service...", .{});
        
        // Start job dispatcher
        try self.job_dispatcher.start();
        
        // Start execution pipeline if enabled
        if (self.execution_pipeline) |pipeline| {
            try pipeline.start();
            std.log.info("Actions execution pipeline started", .{});
        }
        
        self.status = .running;
        std.log.info("Actions service started successfully", .{});
    }
    
    pub fn stop(self: *ActionsService) !void {
        if (self.status != .running) {
            return ActionsServiceError.ServiceNotRunning;
        }
        
        self.status = .stopping;
        std.log.info("Stopping Actions service...", .{});
        
        // Stop execution pipeline
        if (self.execution_pipeline) |pipeline| {
            try pipeline.stop();
        }
        
        // Stop job dispatcher
        try self.job_dispatcher.stop();
        
        self.status = .stopped;
        std.started_at = null;
        std.log.info("Actions service stopped", .{});
    }
    
    pub fn registerRunner(self: *ActionsService, runner_info: struct {
        id: u32,
        name: []const u8,
        capabilities: registry.RunnerCapabilities,
    }) !void {
        if (self.status != .running) {
            return ActionsServiceError.ServiceNotRunning;
        }
        
        try self.job_dispatcher.registerRunner(runner_info);
        std.log.info("Registered runner '{}' with ID {}", .{ runner_info.name, runner_info.id });
    }
    
    pub fn processGitPush(self: *ActionsService, push_event: workflow_manager.PushEvent) !workflow_manager.HookResult {
        if (self.status != .running) {
            return ActionsServiceError.ServiceNotRunning;
        }
        
        return self.workflow_manager.processPushEvent(push_event);
    }
    
    pub fn pollForJob(self: *ActionsService, runner_id: u32, capabilities: registry.RunnerCapabilities) !?dispatcher.AssignedJob {
        if (self.status != .running) {
            return null;
        }
        
        if (self.execution_pipeline) |pipeline| {
            return pipeline.processRunnerPoll(runner_id, capabilities);
        } else {
            return self.job_dispatcher.pollForJob(runner_id, capabilities);
        }
    }
    
    pub fn reportJobStarted(self: *ActionsService, job_id: u32, runner_id: u32) !void {
        if (self.status != .running) {
            return ActionsServiceError.ServiceNotRunning;
        }
        
        if (self.execution_pipeline) |pipeline| {
            try pipeline.reportJobStarted(job_id, runner_id);
        } else {
            try self.job_dispatcher.updateJobStatus(job_id, .running);
        }
    }
    
    pub fn reportJobCompleted(self: *ActionsService, job_id: u32, runner_id: u32, result: executor.JobResult) !void {
        if (self.status != .running) {
            return ActionsServiceError.ServiceNotRunning;
        }
        
        // Update statistics
        self.total_job_duration_ms += @intCast(result.completed_at - result.started_at);
        if (result.conclusion == .success) {
            self.completed_jobs_count += 1;
        } else {
            self.failed_jobs_count += 1;
        }
        
        if (self.execution_pipeline) |pipeline| {
            try pipeline.reportJobCompleted(job_id, runner_id, result);
        } else {
            const dispatcher_result = dispatcher.JobResult{
                .status = switch (result.status) {
                    .completed => .completed,
                    .failed => .failed,
                    .cancelled => .cancelled,
                    else => .failed,
                },
                .exit_code = if (result.conclusion == .success) 0 else 1,
                .output = "",
                .error_message = "",
                .completed_at = result.completed_at,
            };
            try self.job_dispatcher.completeJob(job_id, dispatcher_result);
        }
    }
    
    pub fn getServiceStats(self: *ActionsService) !ServiceStats {
        const current_time = std.time.timestamp();
        const uptime = if (self.started_at) |started|
            @as(u64, @intCast(current_time - started))
        else
            0;
        
        // Get runner utilization
        const runner_utilization = try self.job_dispatcher.getRunnerUtilization(self.allocator);
        defer self.allocator.free(runner_utilization);
        
        var available_runners: u32 = 0;
        var total_utilization: f32 = 0.0;
        
        for (runner_utilization) |runner| {
            if (runner.status == .online) {
                if (runner.current_jobs < runner.max_jobs) {
                    available_runners += 1;
                }
                total_utilization += runner.load_percentage;
            }
        }
        
        const avg_runner_utilization = if (runner_utilization.len > 0)
            total_utilization / @as(f32, @floatFromInt(runner_utilization.len))
        else
            0.0;
        
        // Get queue metrics
        const queue_metrics = try self.job_dispatcher.getQueueDepth();
        
        // Calculate average job duration
        const total_jobs = self.completed_jobs_count + self.failed_jobs_count;
        const avg_job_duration = if (total_jobs > 0)
            self.total_job_duration_ms / total_jobs
        else
            0;
        
        // Get execution stats if pipeline enabled
        var active_workflows: u32 = 0;
        var running_jobs: u32 = 0;
        
        if (self.execution_pipeline) |pipeline| {
            const exec_stats = try pipeline.getExecutionStats();
            active_workflows = exec_stats.active_runs;
            running_jobs = exec_stats.running_jobs;
        }
        
        return ServiceStats{
            .status = self.status,
            .uptime_seconds = uptime,
            .registered_runners = @intCast(runner_utilization.len),
            .active_workflows = active_workflows,
            .queued_jobs = queue_metrics.total_jobs,
            .running_jobs = running_jobs,
            .completed_jobs = self.completed_jobs_count,
            .failed_jobs = self.failed_jobs_count,
            .avg_job_duration_ms = avg_job_duration,
            .runner_utilization_percent = avg_runner_utilization,
        };
    }
    
    pub fn getHealthStatus(self: *ActionsService) !struct { healthy: bool, message: []const u8 } {
        const stats = try self.getServiceStats();
        
        if (!stats.isHealthy()) {
            if (stats.status != .running) {
                return .{ .healthy = false, .message = "Service not running" };
            } else if (stats.runner_utilization_percent > 95.0) {
                return .{ .healthy = false, .message = "Runner utilization too high" };
            } else {
                return .{ .healthy = false, .message = "Service unhealthy" };
            }
        }
        
        return .{ .healthy = true, .message = "Service healthy" };
    }
    
    pub fn discoveryWorkflows(self: *ActionsService, repo_id: u32, repo_path: []const u8) !workflow_manager.WorkflowDiscoveryResult {
        if (self.status != .running) {
            return ActionsServiceError.ServiceNotRunning;
        }
        
        return self.workflow_manager.loadRepositoryWorkflows(repo_id, repo_path);
    }
    
    // API Methods needed by handlers
    pub fn getJobsForWorkflowRun(self: *ActionsService, allocator: std.mem.Allocator, run_id: u32) ![]models.JobExecution {
        _ = allocator; // Use the available getQueuedJobs method for now
        return self.dao.getQueuedJobs(run_id);
    }
    
    pub fn getRepositoryByName(self: *ActionsService, allocator: std.mem.Allocator, owner: []const u8, name: []const u8) !?repository_model.Repository {
        // This should be handled by the main DAO, not ActionsDAO
        // For now, return a mock repository to avoid breaking the build
        _ = self;
        _ = allocator;
        _ = owner;
        _ = name;
        return null; // TODO: Implement proper repository lookup
    }
    
    pub fn getArtifactsForRepository(self: *ActionsService, allocator: std.mem.Allocator, repository_id: u32, name: ?[]const u8) ![]artifacts.Artifact {
        // This should query artifacts from a proper artifacts table
        // For now, return empty slice to avoid breaking the build
        _ = self;
        _ = allocator;
        _ = repository_id;
        _ = name;
        return &[_]artifacts.Artifact{};
    }
};

// Tests for Actions service
test "actions service initializes and starts correctly" {
    const allocator = testing.allocator;
    
    const config = ActionsServiceConfig.default();
    var service = try ActionsService.init(allocator, config);
    defer service.deinit();
    
    try testing.expectEqual(ServiceStatus.stopped, service.status);
    
    // Start service
    try service.start();
    try testing.expectEqual(ServiceStatus.running, service.status);
    try testing.expect(service.started_at != null);
    
    // Stop service
    try service.stop();
    try testing.expectEqual(ServiceStatus.stopped, service.status);
}

test "actions service manages runner registration" {
    const allocator = testing.allocator;
    
    const config = ActionsServiceConfig.default();
    var service = try ActionsService.init(allocator, config);
    defer service.deinit();
    
    try service.start();
    defer service.stop() catch {};
    
    // Register a runner
    try service.registerRunner(.{
        .id = 1,
        .name = "test-runner",
        .capabilities = .{
            .labels = &.{"ubuntu-latest"},
            .max_parallel_jobs = 2,
            .current_jobs = 0,
        },
    });
    
    // Get stats to verify registration
    const stats = try service.getServiceStats();
    try testing.expectEqual(@as(u32, 1), stats.registered_runners);
}

test "actions service provides health status" {
    const allocator = testing.allocator;
    
    const config = ActionsServiceConfig.default();
    var service = try ActionsService.init(allocator, config);
    defer service.deinit();
    
    // Service should be unhealthy when stopped
    var health = try service.getHealthStatus();
    try testing.expect(!health.healthy);
    
    // Start service
    try service.start();
    defer service.stop() catch {};
    
    // Service should be healthy when running
    health = try service.getHealthStatus();
    try testing.expect(health.healthy);
}

test "actions service generates comprehensive statistics" {
    const allocator = testing.allocator;
    
    const config = ActionsServiceConfig.default();
    var service = try ActionsService.init(allocator, config);
    defer service.deinit();
    
    try service.start();
    defer service.stop() catch {};
    
    const stats = try service.getServiceStats();
    
    try testing.expectEqual(ServiceStatus.running, stats.status);
    try testing.expect(stats.uptime_seconds >= 0);
    try testing.expectEqual(@as(u32, 0), stats.registered_runners);
    try testing.expectEqual(@as(u32, 0), stats.queued_jobs);
    try testing.expectEqual(@as(u64, 0), stats.completed_jobs);
    try testing.expectEqual(@as(u64, 0), stats.failed_jobs);
}

test "actions service handles job lifecycle tracking" {
    const allocator = testing.allocator;
    
    const config = ActionsServiceConfig.default();
    var service = try ActionsService.init(allocator, config);
    defer service.deinit();
    
    try service.start();
    defer service.stop() catch {};
    
    // Register a runner
    try service.registerRunner(.{
        .id = 1,
        .name = "test-runner",
        .capabilities = .{
            .labels = &.{"ubuntu-latest"},
            .max_parallel_jobs = 1,
            .current_jobs = 0,
        },
    });
    
    // Poll for job (should be null since no jobs queued)
    const assignment = try service.pollForJob(1, .{
        .labels = &.{"ubuntu-latest"},
        .max_parallel_jobs = 1,
        .current_jobs = 0,
    });
    try testing.expect(assignment == null);
    
    // Report job started (should not error even if no job)
    try service.reportJobStarted(999, 1);
    
    // Create mock job result
    const job_result = executor.JobResult{
        .job_id = 999,
        .status = .completed,
        .conclusion = .success,
        .started_at = std.time.timestamp() - 10,
        .completed_at = std.time.timestamp(),
        .steps = &.{},
        .outputs = std.StringHashMap([]const u8).init(allocator),
        .resource_usage = .{},
    };
    
    // Report job completed
    try service.reportJobCompleted(999, 1, job_result);
    
    // Check stats updated
    const stats = try service.getServiceStats();
    try testing.expectEqual(@as(u64, 1), stats.completed_jobs);
}

test "service stats calculate health correctly" {
    // Test healthy service
    const healthy_stats = ServiceStats{
        .status = .running,
        .uptime_seconds = 3600,
        .registered_runners = 5,
        .active_workflows = 3,
        .queued_jobs = 10,
        .running_jobs = 15,
        .completed_jobs = 100,
        .failed_jobs = 5,
        .avg_job_duration_ms = 30000,
        .runner_utilization_percent = 75.0,
    };
    
    try testing.expect(healthy_stats.isHealthy());
    
    // Test unhealthy service (over-utilized)
    const unhealthy_stats = ServiceStats{
        .status = .running,
        .uptime_seconds = 3600,
        .registered_runners = 5,
        .active_workflows = 10,
        .queued_jobs = 50,
        .running_jobs = 25,
        .completed_jobs = 100,
        .failed_jobs = 20,
        .avg_job_duration_ms = 60000,
        .runner_utilization_percent = 98.0,
    };
    
    try testing.expect(!unhealthy_stats.isHealthy());
    
    // Test stopped service
    const stopped_stats = ServiceStats{
        .status = .stopped,
        .uptime_seconds = 0,
        .registered_runners = 0,
        .active_workflows = 0,
        .queued_jobs = 0,
        .running_jobs = 0,
        .completed_jobs = 0,
        .failed_jobs = 0,
        .avg_job_duration_ms = 0,
        .runner_utilization_percent = 0.0,
    };
    
    try testing.expect(!stopped_stats.isHealthy());
}