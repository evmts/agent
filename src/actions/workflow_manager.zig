const std = @import("std");
const testing = std.testing;
const models = @import("models.zig");
const workflow_parser = @import("workflow_parser.zig");
const trigger = @import("trigger.zig");
const queue = @import("queue.zig");
const dispatcher = @import("dispatcher.zig");

const Workflow = models.Workflow;
const WorkflowRun = models.WorkflowRun;
const JobExecution = models.JobExecution;
const ActionsDAO = models.ActionsDAO;
const WorkflowParser = workflow_parser.WorkflowParser;
const ParsedWorkflow = workflow_parser.ParsedWorkflow;

pub const WorkflowManagerError = error{
    InvalidWorkflowFile,
    WorkflowNotFound,
    RepositoryNotFound,
    TriggerEvaluationFailed,
    JobCreationFailed,
    DatabaseError,
    OutOfMemory,
} || std.mem.Allocator.Error;

pub const CachedWorkflow = struct {
    workflows: []Workflow,
    timestamp: i64,
    
    pub fn deinit(self: *CachedWorkflow, allocator: std.mem.Allocator) void {
        for (self.workflows) |*workflow| {
            workflow.deinit(allocator);
        }
        allocator.free(self.workflows);
    }
};

pub const WorkflowDiscoveryResult = struct {
    found_count: u32,
    parsed_count: u32,
    error_count: u32,
    workflows: []Workflow,
    
    pub fn deinit(self: *WorkflowDiscoveryResult, allocator: std.mem.Allocator) void {
        for (self.workflows) |*workflow| {
            workflow.deinit(allocator);
        }
        allocator.free(self.workflows);
    }
};

pub const PushEvent = struct {
    repository_id: u32,
    repository_path: []const u8,
    ref: []const u8,
    before: []const u8,
    after: []const u8,
    commits: []const []const u8,
    pusher_id: u32,
    
    pub fn deinit(self: *PushEvent, allocator: std.mem.Allocator) void {
        allocator.free(self.repository_path);
        allocator.free(self.ref);
        allocator.free(self.before);
        allocator.free(self.after);
        for (self.commits) |commit| {
            allocator.free(commit);
        }
        allocator.free(self.commits);
    }
};

pub const HookResult = struct {
    triggered_workflows: []WorkflowRun,
    execution_time_ms: i64,
    errors: []WorkflowManagerError,
    
    pub fn deinit(self: *HookResult, allocator: std.mem.Allocator) void {
        for (self.triggered_workflows) |*run| {
            run.deinit(allocator);
        }
        allocator.free(self.triggered_workflows);
        allocator.free(self.errors);
    }
};

pub const WorkflowManager = struct {
    allocator: std.mem.Allocator,
    dao: *ActionsDAO,
    parser: WorkflowParser,
    cache: std.StringHashMap(CachedWorkflow),
    job_dispatcher: *dispatcher.JobDispatcher,
    execution_pipeline: ?*@import("execution_pipeline.zig").ExecutionPipeline = null,
    
    pub fn init(allocator: std.mem.Allocator, dao: *ActionsDAO, job_dispatcher: *dispatcher.JobDispatcher) !WorkflowManager {
        return WorkflowManager{
            .allocator = allocator,
            .dao = dao,
            .parser = WorkflowParser.init(allocator, .{}),
            .cache = std.StringHashMap(CachedWorkflow).init(allocator),
            .job_dispatcher = job_dispatcher,
        };
    }
    
    pub fn deinit(self: *WorkflowManager) void {
        var cache_iterator = self.cache.iterator();
        while (cache_iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(self.allocator);
        }
        self.cache.deinit();
    }
    
    pub fn loadRepositoryWorkflows(
        self: *WorkflowManager,
        repo_id: u32,
        repo_path: []const u8,
    ) !WorkflowDiscoveryResult {
        // Check cache first
        const cache_key = try std.fmt.allocPrint(self.allocator, "repo:{}", .{repo_id});
        defer self.allocator.free(cache_key);
        
        if (self.cache.get(cache_key)) |cached| {
            if (std.time.timestamp() - cached.timestamp < 300) { // 5 min cache
                var workflows = try self.allocator.alloc(Workflow, cached.workflows.len);
                for (cached.workflows, 0..) |workflow, i| {
                    workflows[i] = try self.cloneWorkflow(workflow);
                }
                
                return WorkflowDiscoveryResult{
                    .found_count = @intCast(cached.workflows.len),
                    .parsed_count = @intCast(cached.workflows.len),
                    .error_count = 0,
                    .workflows = workflows,
                };
            }
        }
        
        // Clear stale cache entry
        if (self.cache.getPtr(cache_key)) |cached_ptr| {
            cached_ptr.deinit(self.allocator);
            _ = self.cache.remove(cache_key);
        }
        
        // Scan .github/workflows directory
        const workflows_dir = try std.fs.path.join(self.allocator, &.{
            repo_path, ".github", "workflows"
        });
        defer self.allocator.free(workflows_dir);
        
        var workflows = std.ArrayList(Workflow).init(self.allocator);
        errdefer {
            for (workflows.items) |*workflow| {
                workflow.deinit(self.allocator);
            }
            workflows.deinit();
        }
        
        var found_count: u32 = 0;
        var error_count: u32 = 0;
        
        var dir = std.fs.openDirAbsolute(workflows_dir, .{ .iterate = true }) catch |err| {
            switch (err) {
                error.FileNotFound => {
                    // No workflows directory - return empty result
                    return WorkflowDiscoveryResult{
                        .found_count = 0,
                        .parsed_count = 0,
                        .error_count = 0,
                        .workflows = try workflows.toOwnedSlice(),
                    };
                },
                else => return err,
            }
        };
        defer dir.close();
        
        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind != .file) continue;
            
            // Only process .yml and .yaml files
            if (!std.mem.endsWith(u8, entry.name, ".yml") and
                !std.mem.endsWith(u8, entry.name, ".yaml")) continue;
            
            found_count += 1;
            
            const file_path = try std.fs.path.join(self.allocator, &.{
                workflows_dir, entry.name
            });
            defer self.allocator.free(file_path);
            
            // Read and parse workflow
            const content = std.fs.cwd().readFileAlloc(self.allocator, file_path, 1024 * 1024) catch |err| {
                std.log.warn("Failed to read workflow file {s}: {}", .{ file_path, err });
                error_count += 1;
                continue;
            };
            defer self.allocator.free(content);
            
            // Parse workflow YAML
            var parsed_workflow = WorkflowParser.parse(self.allocator, content, .{}) catch |err| {
                std.log.warn("Failed to parse workflow file {s}: {}", .{ entry.name, err });
                error_count += 1;
                continue;
            };
            defer parsed_workflow.deinit(self.allocator);
            
            // Convert parsed workflow to database model
            var workflow = try self.createWorkflowFromParsed(repo_id, entry.name, content, &parsed_workflow);
            
            // Store in database
            const workflow_id = self.dao.createWorkflow(.{
                .repository_id = repo_id,
                .name = workflow.name,
                .filename = workflow.filename,
                .yaml_content = workflow.yaml_content,
            }) catch |err| {
                std.log.warn("Failed to store workflow {s} in database: {}", .{ entry.name, err });
                workflow.deinit(self.allocator);
                error_count += 1;
                continue;
            };
            workflow.id = workflow_id;
            
            try workflows.append(workflow);
        }
        
        const result_workflows = try workflows.toOwnedSlice();
        
        // Update cache
        const cache_workflows = try self.allocator.alloc(Workflow, result_workflows.len);
        for (result_workflows, 0..) |workflow, i| {
            cache_workflows[i] = try self.cloneWorkflow(workflow);
        }
        
        try self.cache.put(try self.allocator.dupe(u8, cache_key), CachedWorkflow{
            .workflows = cache_workflows,
            .timestamp = std.time.timestamp(),
        });
        
        return WorkflowDiscoveryResult{
            .found_count = found_count,
            .parsed_count = @intCast(result_workflows.len),
            .error_count = error_count,
            .workflows = result_workflows,
        };
    }
    
    pub fn setExecutionPipeline(self: *WorkflowManager, pipeline: *@import("execution_pipeline.zig").ExecutionPipeline) void {
        self.execution_pipeline = pipeline;
    }
    
    pub fn processPushEvent(self: *WorkflowManager, event: PushEvent) !HookResult {
        const start_time = std.time.milliTimestamp();
        var triggered_runs = std.ArrayList(WorkflowRun).init(self.allocator);
        defer triggered_runs.deinit();
        
        var errors = std.ArrayList(WorkflowManagerError).init(self.allocator);
        defer errors.deinit();
        
        // Load repository workflows
        const discovery_result = self.loadRepositoryWorkflows(
            event.repository_id,
            event.repository_path,
        ) catch |err| {
            try errors.append(err);
            return HookResult{
                .triggered_workflows = try triggered_runs.toOwnedSlice(),
                .execution_time_ms = std.time.milliTimestamp() - start_time,
                .errors = try errors.toOwnedSlice(),
            };
        };
        defer {
            var mut_result = discovery_result;
            mut_result.deinit(self.allocator);
        }
        
        // Find matching workflows for this push event
        for (discovery_result.workflows) |workflow| {
            const should_trigger = self.evaluateTrigger(workflow.triggers, event) catch |err| {
                std.log.warn("Failed to evaluate trigger for workflow {s}: {}", .{ workflow.name, err });
                try errors.append(err);
                continue;
            };
            
            if (!should_trigger) continue;
            
            // Create workflow run
            const run = self.createWorkflowRun(workflow, event) catch |err| {
                std.log.warn("Failed to create workflow run for {s}: {}", .{ workflow.name, err });
                try errors.append(err);
                continue;
            };
            try triggered_runs.append(run);
            
            // Process through execution pipeline if available
            if (self.execution_pipeline) |pipeline| {
                pipeline.processWorkflowRun(run.id) catch |err| {
                    std.log.warn("Failed to process workflow run {} through pipeline: {}", .{ run.id, err });
                    try errors.append(err);
                    continue;
                };
            } else {
                // Fallback to direct job creation and queuing (legacy mode)
                const jobs = self.createJobsFromWorkflow(workflow, run) catch |err| {
                    std.log.warn("Failed to create jobs for workflow {s}: {}", .{ workflow.name, err });
                    try errors.append(err);
                    continue;
                };
                defer {
                    for (jobs) |*job| {
                        job.deinit(self.allocator);
                    }
                    self.allocator.free(jobs);
                }
                
                // Queue jobs with dispatcher
                for (jobs) |job| {
                    self.job_dispatcher.enqueueJob(job) catch |err| {
                        std.log.warn("Failed to enqueue job {s}: {}", .{ job.job_id, err });
                        try errors.append(err);
                        continue;
                    };
                }
            }
            
            if (self.execution_pipeline != null) {
                std.log.info("Triggered workflow '{}' run #{} via execution pipeline", .{
                    workflow.name,
                    run.run_number,
                });
            } else {
                std.log.info("Triggered workflow '{}' run #{} with direct job queuing", .{
                    workflow.name,
                    run.run_number,
                });
            }
        }
        
        return HookResult{
            .triggered_workflows = try triggered_runs.toOwnedSlice(),
            .execution_time_ms = std.time.milliTimestamp() - start_time,
            .errors = try errors.toOwnedSlice(),
        };
    }
    
    pub fn rerunWorkflow(
        self: *WorkflowManager,
        original_run: WorkflowRun,
        actor_id: u32,
    ) !WorkflowRun {
        // Get original workflow
        const workflow = try self.dao.getWorkflow(original_run.workflow_id);
        defer {
            var mut_workflow = workflow;
            mut_workflow.deinit(self.allocator);
        }
        
        // Create new run with same parameters
        const new_run_id = try self.dao.createWorkflowRun(.{
            .repository_id = original_run.repository_id,
            .workflow_id = original_run.workflow_id,
            .trigger_event = original_run.trigger_event,
            .commit_sha = original_run.commit_sha,
            .branch = original_run.branch,
            .actor_id = actor_id,
        });
        
        return try self.dao.getWorkflowRun(new_run_id);
    }
    
    pub fn updateWorkflowRunStatus(
        self: *WorkflowManager,
        run_id: u32,
    ) !void {
        // Get all jobs for this run
        const jobs = try self.dao.getQueuedJobs(run_id);
        defer {
            for (jobs) |*job| {
                job.deinit(self.allocator);
            }
            self.allocator.free(jobs);
        }
        
        // Check if all jobs are completed
        var all_completed = true;
        var has_failures = false;
        
        for (jobs) |job| {
            switch (job.status) {
                .completed => {
                    if (job.conclusion) |conclusion| {
                        if (conclusion == .failure) {
                            has_failures = true;
                        }
                    }
                },
                .failed => has_failures = true,
                else => all_completed = false,
            }
        }
        
        // Update workflow run status based on job states
        if (all_completed) {
            const conclusion: WorkflowRun.RunConclusion = if (has_failures) .failure else .success;
            // TODO: Update workflow run in database with completed status and conclusion
            _ = conclusion;
        }
    }
    
    fn createWorkflowFromParsed(
        self: *WorkflowManager,
        repo_id: u32,
        filename: []const u8,
        yaml_content: []const u8,
        parsed: *const ParsedWorkflow,
    ) !Workflow {
        // Convert parsed triggers to model triggers
        var triggers = try self.allocator.alloc(models.TriggerEvent, parsed.triggers.len);
        for (parsed.triggers, 0..) |parsed_trigger, i| {
            triggers[i] = parsed_trigger.event;
        }
        
        // Convert parsed jobs to model jobs
        var jobs = std.StringHashMap(models.Job).init(self.allocator);
        var job_iterator = parsed.jobs.iterator();
        while (job_iterator.next()) |entry| {
            const job_id = entry.key_ptr.*;
            const parsed_job = entry.value_ptr.*;
            
            try jobs.put(
                try self.allocator.dupe(u8, job_id),
                try self.cloneJob(parsed_job)
            );
        }
        
        return Workflow{
            .id = 0, // Will be set by caller
            .repository_id = repo_id,
            .name = try self.allocator.dupe(u8, parsed.name),
            .filename = try self.allocator.dupe(u8, filename),
            .yaml_content = try self.allocator.dupe(u8, yaml_content),
            .triggers = triggers,
            .jobs = jobs,
            .active = true,
            .created_at = std.time.timestamp(),
            .updated_at = std.time.timestamp(),
        };
    }
    
    fn evaluateTrigger(
        self: *WorkflowManager,
        triggers: []const models.TriggerEvent,
        event: PushEvent,
    ) !bool {
        _ = self;
        
        for (triggers) |trigger_event| {
            switch (trigger_event) {
                .push => |push_trigger| {
                    // Extract branch name from ref (refs/heads/branch_name)
                    const branch_name = if (std.mem.startsWith(u8, event.ref, "refs/heads/"))
                        event.ref[11..]
                    else
                        continue;
                    
                    // Check if this branch matches any trigger patterns
                    for (push_trigger.branches) |pattern| {
                        if (std.mem.eql(u8, pattern, branch_name) or std.mem.eql(u8, pattern, "*")) {
                            return true;
                        }
                    }
                },
                else => continue, // Other trigger types not supported yet
            }
        }
        
        return false;
    }
    
    fn createWorkflowRun(
        self: *WorkflowManager,
        workflow: Workflow,
        event: PushEvent,
    ) !WorkflowRun {
        const run_id = try self.dao.createWorkflowRun(.{
            .repository_id = workflow.repository_id,
            .workflow_id = workflow.id,
            .trigger_event = models.TriggerEvent{
                .push = .{
                    .branches = try self.allocator.alloc([]const u8, 1),
                    .tags = try self.allocator.alloc([]const u8, 0),
                    .paths = try self.allocator.alloc([]const u8, 0),
                },
            },
            .commit_sha = event.after,
            .branch = event.ref,
            .actor_id = event.pusher_id,
        });
        
        return try self.dao.getWorkflowRun(run_id);
    }
    
    fn createJobsFromWorkflow(
        self: *WorkflowManager,
        workflow: Workflow,
        run: WorkflowRun,
    ) ![]queue.QueuedJob {
        var jobs = std.ArrayList(queue.QueuedJob).init(self.allocator);
        errdefer {
            for (jobs.items) |*job| {
                job.deinit(self.allocator);
            }
            jobs.deinit();
        }
        
        // Process each job in workflow
        var job_iterator = workflow.jobs.iterator();
        while (job_iterator.next()) |entry| {
            const job_id = entry.key_ptr.*;
            const job_def = entry.value_ptr.*;
            
            // Create queued job
            const queued_job = queue.QueuedJob{
                .id = 0, // Will be set by database
                .workflow_run_id = run.id,
                .job_id = try self.allocator.dupe(u8, job_id),
                .job_name = if (job_def.name) |name| try self.allocator.dupe(u8, name) else null,
                .runner_requirements = try self.allocator.alloc([]const u8, 1),
                .priority = .normal,
                .created_at = std.time.timestamp(),
                .timeout_minutes = job_def.timeout_minutes,
                .environment = try self.cloneStringHashMap(&job_def.environment),
                .steps = try self.cloneSteps(job_def.steps),
            };
            
            // Set runner requirements from runs-on
            queued_job.runner_requirements[0] = try self.allocator.dupe(u8, job_def.runs_on);
            
            try jobs.append(queued_job);
        }
        
        return jobs.toOwnedSlice();
    }
    
    fn cloneWorkflow(self: *WorkflowManager, original: Workflow) !Workflow {
        var triggers = try self.allocator.alloc(models.TriggerEvent, original.triggers.len);
        for (original.triggers, 0..) |trigger, i| {
            triggers[i] = try self.cloneTriggerEvent(trigger);
        }
        
        var jobs = std.StringHashMap(models.Job).init(self.allocator);
        var job_iterator = original.jobs.iterator();
        while (job_iterator.next()) |entry| {
            const job_id = entry.key_ptr.*;
            const job = entry.value_ptr.*;
            
            try jobs.put(
                try self.allocator.dupe(u8, job_id),
                try self.cloneJob(job)
            );
        }
        
        return Workflow{
            .id = original.id,
            .repository_id = original.repository_id,
            .name = try self.allocator.dupe(u8, original.name),
            .filename = try self.allocator.dupe(u8, original.filename),
            .yaml_content = try self.allocator.dupe(u8, original.yaml_content),
            .triggers = triggers,
            .jobs = jobs,
            .active = original.active,
            .created_at = original.created_at,
            .updated_at = original.updated_at,
        };
    }
    
    fn cloneTriggerEvent(self: *WorkflowManager, original: models.TriggerEvent) !models.TriggerEvent {
        return switch (original) {
            .push => |push| models.TriggerEvent{
                .push = .{
                    .branches = try self.allocator.dupe([]const u8, push.branches),
                    .tags = try self.allocator.dupe([]const u8, push.tags),
                    .paths = try self.allocator.dupe([]const u8, push.paths),
                },
            },
            .pull_request => |pr| models.TriggerEvent{
                .pull_request = .{
                    .types = try self.allocator.dupe([]const u8, pr.types),
                    .branches = try self.allocator.dupe([]const u8, pr.branches),
                },
            },
            .schedule => |sched| models.TriggerEvent{
                .schedule = .{
                    .cron = try self.allocator.dupe(u8, sched.cron),
                },
            },
            .workflow_dispatch => |wd| models.TriggerEvent{
                .workflow_dispatch = .{
                    .inputs = try self.cloneWorkflowInputs(&wd.inputs),
                },
            },
        };
    }
    
    fn cloneJob(self: *WorkflowManager, original: models.Job) !models.Job {
        var needs = try self.allocator.alloc([]const u8, original.needs.len);
        for (original.needs, 0..) |need, i| {
            needs[i] = try self.allocator.dupe(u8, need);
        }
        
        var steps = try self.allocator.alloc(models.JobStep, original.steps.len);
        for (original.steps, 0..) |step, i| {
            steps[i] = try self.cloneJobStep(step);
        }
        
        return models.Job{
            .id = try self.allocator.dupe(u8, original.id),
            .name = if (original.name) |name| try self.allocator.dupe(u8, name) else null,
            .runs_on = try self.allocator.dupe(u8, original.runs_on),
            .needs = needs,
            .if_condition = if (original.if_condition) |cond| try self.allocator.dupe(u8, cond) else null,
            .strategy = if (original.strategy) |strat| try self.cloneJobStrategy(strat) else null,
            .steps = steps,
            .timeout_minutes = original.timeout_minutes,
            .environment = try self.cloneStringHashMap(&original.environment),
            .continue_on_error = original.continue_on_error,
        };
    }
    
    fn cloneJobStep(self: *WorkflowManager, original: models.JobStep) !models.JobStep {
        return models.JobStep{
            .name = if (original.name) |name| try self.allocator.dupe(u8, name) else null,
            .uses = if (original.uses) |uses| try self.allocator.dupe(u8, uses) else null,
            .run = if (original.run) |run| try self.allocator.dupe(u8, run) else null,
            .with = try self.cloneStringHashMap(&original.with),
            .env = try self.cloneStringHashMap(&original.env),
            .if_condition = if (original.if_condition) |cond| try self.allocator.dupe(u8, cond) else null,
            .continue_on_error = original.continue_on_error,
            .timeout_minutes = original.timeout_minutes,
        };
    }
    
    fn cloneJobStrategy(self: *WorkflowManager, original: models.JobStrategy) !models.JobStrategy {
        var matrix = std.StringHashMap([]const []const u8).init(self.allocator);
        var matrix_iterator = original.matrix.iterator();
        while (matrix_iterator.next()) |entry| {
            const key = entry.key_ptr.*;
            const values = entry.value_ptr.*;
            
            var cloned_values = try self.allocator.alloc([]const u8, values.len);
            for (values, 0..) |value, i| {
                cloned_values[i] = try self.allocator.dupe(u8, value);
            }
            
            try matrix.put(try self.allocator.dupe(u8, key), cloned_values);
        }
        
        return models.JobStrategy{
            .matrix = matrix,
            .fail_fast = original.fail_fast,
            .max_parallel = original.max_parallel,
        };
    }
    
    fn cloneWorkflowInputs(self: *WorkflowManager, original: *const std.StringHashMap(models.WorkflowInput)) !std.StringHashMap(models.WorkflowInput) {
        var inputs = std.StringHashMap(models.WorkflowInput).init(self.allocator);
        var iterator = original.iterator();
        while (iterator.next()) |entry| {
            const key = entry.key_ptr.*;
            const input = entry.value_ptr.*;
            
            try inputs.put(
                try self.allocator.dupe(u8, key),
                models.WorkflowInput{
                    .description = try self.allocator.dupe(u8, input.description),
                    .required = input.required,
                    .default = if (input.default) |default| try self.allocator.dupe(u8, default) else null,
                    .type = input.type,
                }
            );
        }
        
        return inputs;
    }
    
    fn cloneStringHashMap(self: *WorkflowManager, original: *const std.StringHashMap([]const u8)) !std.StringHashMap([]const u8) {
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
    
    fn cloneSteps(self: *WorkflowManager, original: []const models.JobStep) ![]queue.JobStep {
        var steps = try self.allocator.alloc(queue.JobStep, original.len);
        for (original, 0..) |step, i| {
            steps[i] = queue.JobStep{
                .name = if (step.name) |name| try self.allocator.dupe(u8, name) else null,
                .uses = if (step.uses) |uses| try self.allocator.dupe(u8, uses) else null,
                .run = if (step.run) |run| try self.allocator.dupe(u8, run) else null,
                .with = try self.cloneStringHashMap(&step.with),
                .env = try self.cloneStringHashMap(&step.env),
                .if_condition = if (step.if_condition) |cond| try self.allocator.dupe(u8, cond) else null,
                .continue_on_error = step.continue_on_error,
                .timeout_minutes = step.timeout_minutes,
            };
        }
        return steps;
    }
};

// Tests for workflow manager
test "WorkflowManager initialization" {
    const allocator = testing.allocator;
    
    // Mock DAO and dispatcher
    var mock_dao = models.ActionsDAO.init(allocator, undefined);
    defer mock_dao.deinit();
    
    var mock_dispatcher = dispatcher.JobDispatcher.init(allocator, undefined);
    defer mock_dispatcher.deinit();
    
    var manager = try WorkflowManager.init(allocator, &mock_dao, &mock_dispatcher);
    defer manager.deinit();
    
    try testing.expect(manager.allocator.ptr == allocator.ptr);
    try testing.expect(manager.cache.count() == 0);
}

test "workflow discovery handles missing directory gracefully" {
    const allocator = testing.allocator;
    
    var mock_dao = models.ActionsDAO.init(allocator, undefined);
    defer mock_dao.deinit();
    
    var mock_dispatcher = dispatcher.JobDispatcher.init(allocator, undefined);
    defer mock_dispatcher.deinit();
    
    var manager = try WorkflowManager.init(allocator, &mock_dao, &mock_dispatcher);
    defer manager.deinit();
    
    // Try to load workflows from non-existent directory
    var result = try manager.loadRepositoryWorkflows(1, "/tmp/nonexistent-repo");
    defer result.deinit(allocator);
    
    try testing.expectEqual(@as(u32, 0), result.found_count);
    try testing.expectEqual(@as(u32, 0), result.parsed_count);
    try testing.expectEqual(@as(u32, 0), result.error_count);
    try testing.expectEqual(@as(usize, 0), result.workflows.len);
}

test "push event evaluation works correctly" {
    const allocator = testing.allocator;
    
    var mock_dao = models.ActionsDAO.init(allocator, undefined);
    defer mock_dao.deinit();
    
    var mock_dispatcher = dispatcher.JobDispatcher.init(allocator, undefined);
    defer mock_dispatcher.deinit();
    
    var manager = try WorkflowManager.init(allocator, &mock_dao, &mock_dispatcher);
    defer manager.deinit();
    
    // Create a simple push trigger
    var push_trigger = models.TriggerEvent{
        .push = .{
            .branches = try allocator.alloc([]const u8, 1),
            .tags = try allocator.alloc([]const u8, 0),
            .paths = try allocator.alloc([]const u8, 0),
        },
    };
    push_trigger.push.branches[0] = try allocator.dupe(u8, "main");
    defer push_trigger.deinit(allocator);
    
    const triggers = [_]models.TriggerEvent{push_trigger};
    
    // Create push event for main branch
    var push_event = PushEvent{
        .repository_id = 1,
        .repository_path = try allocator.dupe(u8, "/tmp/test-repo"),
        .ref = try allocator.dupe(u8, "refs/heads/main"),
        .before = try allocator.dupe(u8, "abc123"),
        .after = try allocator.dupe(u8, "def456"),
        .commits = try allocator.alloc([]const u8, 0),
        .pusher_id = 123,
    };
    defer push_event.deinit(allocator);
    
    // Test trigger evaluation
    const should_trigger = try manager.evaluateTrigger(&triggers, push_event);
    try testing.expect(should_trigger);
    
    // Test with different branch
    allocator.free(push_event.ref);
    push_event.ref = try allocator.dupe(u8, "refs/heads/feature");
    
    const should_not_trigger = try manager.evaluateTrigger(&triggers, push_event);
    try testing.expect(!should_not_trigger);
}

test "workflow caching works correctly" {
    const allocator = testing.allocator;
    
    var mock_dao = models.ActionsDAO.init(allocator, undefined);
    defer mock_dao.deinit();
    
    var mock_dispatcher = dispatcher.JobDispatcher.init(allocator, undefined);
    defer mock_dispatcher.deinit();
    
    var manager = try WorkflowManager.init(allocator, &mock_dao, &mock_dispatcher);
    defer manager.deinit();
    
    // Add a cache entry manually for testing
    const cache_key = try allocator.dupe(u8, "repo:123");
    
    var cached_workflow = models.Workflow{
        .id = 1,
        .repository_id = 123,
        .name = try allocator.dupe(u8, "Test Workflow"),
        .filename = try allocator.dupe(u8, "test.yml"),
        .yaml_content = try allocator.dupe(u8, "name: Test"),
        .triggers = try allocator.alloc(models.TriggerEvent, 0),
        .jobs = std.StringHashMap(models.Job).init(allocator),
        .active = true,
        .created_at = std.time.timestamp(),
        .updated_at = std.time.timestamp(),
    };
    
    const cached_workflows = try allocator.alloc(models.Workflow, 1);
    cached_workflows[0] = cached_workflow;
    
    try manager.cache.put(cache_key, CachedWorkflow{
        .workflows = cached_workflows,
        .timestamp = std.time.timestamp(),
    });
    
    // Verify cache contains the entry
    try testing.expect(manager.cache.contains("repo:123"));
    
    const cached_entry = manager.cache.get("repo:123").?;
    try testing.expectEqual(@as(usize, 1), cached_entry.workflows.len);
    try testing.expectEqualStrings("Test Workflow", cached_entry.workflows[0].name);
}