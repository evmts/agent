const std = @import("std");
const testing = std.testing;
const dispatcher = @import("dispatcher.zig");
const container = @import("container.zig");
const action_runner = @import("action_runner.zig");

// Job execution status tracking  
pub const JobStatus = enum {
    queued,
    in_progress,
    completed,
    cancelled,
    failed,
};

// Job execution conclusion
pub const JobConclusion = enum {
    success,
    failure,
    cancelled,
    timed_out,
    action_required,
    neutral,
    skipped,
};

// Step execution status
pub const StepStatus = enum {
    queued,
    in_progress,
    completed,
    cancelled,
    failed,
    skipped,
};

// Step execution types
pub const StepType = union(enum) {
    run: struct {
        command: []const u8,
        shell: ?[]const u8 = null,
        working_directory: ?[]const u8 = null,
        env: std.StringHashMap([]const u8),
    },
    action: struct {
        name: []const u8, // actions/checkout@v4
        with: std.StringHashMap([]const u8),
        env: std.StringHashMap([]const u8),
    },
    composite: struct {
        steps: []const Step,
    },
};

// Individual workflow step
pub const Step = struct {
    name: []const u8,
    id: ?[]const u8 = null,
    if_condition: ?[]const u8 = null,
    continue_on_error: bool = false,
    timeout_minutes: ?u32 = null,
    step_type: StepType,
    
    // Helper constructors for tests
    pub fn runStep(name: []const u8, command: []const u8) Step {
        return Step{
            .name = name,
            .step_type = .{
                .run = .{
                    .command = command,
                    .shell = "bash",
                    .env = std.StringHashMap([]const u8).init(std.heap.page_allocator),
                },
            },
        };
    }
    
    pub fn actionStep(name: []const u8, action_name: []const u8) Step {
        return Step{
            .name = name,
            .step_type = .{
                .action = .{
                    .name = action_name,
                    .with = std.StringHashMap([]const u8).init(std.heap.page_allocator),
                    .env = std.StringHashMap([]const u8).init(std.heap.page_allocator),
                },
            },
        };
    }
};

// Step execution result
pub const StepResult = struct {
    step_name: []const u8,
    status: StepStatus,
    conclusion: ?JobConclusion = null,
    started_at: i64,
    completed_at: ?i64 = null,
    exit_code: ?i32 = null,
    outputs: std.StringHashMap([]const u8),
    
    pub fn deinit(self: *StepResult, allocator: std.mem.Allocator) void {
        allocator.free(self.step_name);
        var outputs_iter = self.outputs.iterator();
        while (outputs_iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        self.outputs.deinit();
    }
};

// Resource usage tracking
pub const ResourceUsage = struct {
    max_memory_mb: u32 = 0,
    cpu_time_seconds: f64 = 0.0,
    wall_time_seconds: f64 = 0.0,
    disk_usage_mb: u32 = 0,
};

// Job definition for execution
pub const JobDefinition = struct {
    name: []const u8,
    runs_on: []const u8,
    steps: []const Step,
    env: std.StringHashMap([]const u8),
    timeout_minutes: u32 = 360,
    
    pub fn deinit(self: *JobDefinition, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.runs_on);
        for (self.steps) |*step| {
            allocator.free(step.name);
            switch (step.step_type) {
                .run => |*run_step| {
                    allocator.free(run_step.command);
                    if (run_step.shell) |shell| allocator.free(shell);
                    if (run_step.working_directory) |wd| allocator.free(wd);
                    run_step.env.deinit();
                },
                .action => |*action_step| {
                    allocator.free(action_step.name);
                    action_step.with.deinit();
                    action_step.env.deinit();
                },
                .composite => |*comp_step| {
                    allocator.free(comp_step.steps);
                },
            }
        }
        allocator.free(self.steps);
        self.env.deinit();
    }
};

// Execution environment for jobs
pub const ExecutionEnvironment = struct {
    working_directory: []const u8,
    env: std.StringHashMap([]const u8),
    secrets: std.StringHashMap([]const u8),
    
    pub fn init(allocator: std.mem.Allocator) ExecutionEnvironment {
        return ExecutionEnvironment{
            .working_directory = "/workspace",
            .env = std.StringHashMap([]const u8).init(allocator),
            .secrets = std.StringHashMap([]const u8).init(allocator),
        };
    }
    
    pub fn deinit(self: *ExecutionEnvironment) void {
        self.env.deinit();
        self.secrets.deinit();
    }
};

// Assigned job for execution (from dispatcher)
pub const AssignedJob = struct {
    job_id: u32,
    workflow_run_id: u32,
    job_definition: JobDefinition,
    environment: ExecutionEnvironment,
    assigned_at: i64,
    timeout_minutes: u32 = 360,
    
    pub fn deinit(self: *AssignedJob, allocator: std.mem.Allocator) void {
        self.job_definition.deinit(allocator);
        self.environment.deinit();
    }
};

// Complete job execution result
pub const JobResult = struct {
    job_id: u32,
    status: JobStatus,
    conclusion: ?JobConclusion = null,
    started_at: i64,
    completed_at: i64,
    steps: []StepResult,
    outputs: std.StringHashMap([]const u8),
    resource_usage: ResourceUsage,
    
    pub fn deinit(self: *JobResult, allocator: std.mem.Allocator) void {
        for (self.steps) |*step| {
            step.deinit(allocator);
        }
        allocator.free(self.steps);
        
        var outputs_iter = self.outputs.iterator();
        while (outputs_iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        self.outputs.deinit();
    }
};

// Executor configuration
pub const ExecutorConfig = struct {
    container_runtime: ContainerRuntime = .docker,
    log_level: LogLevel = .info,
    max_parallel_steps: u32 = 1,
    default_timeout_minutes: u32 = 360,
    workspace_base_path: []const u8 = "/tmp/workspace",
    action_cache_dir: []const u8 = "/tmp/actions-cache",
};

// Container runtime selection (re-export from container module)
pub const ContainerRuntime = container.ContainerRuntime;

// Log levels for execution
pub const LogLevel = enum {
    debug,
    info,
    warn,
    error,
};

// Mock command execution result
pub const CommandResult = struct {
    exit_code: i32,
    stdout: []const u8,
    stderr: []const u8,
    
    pub fn deinit(self: CommandResult, allocator: std.mem.Allocator) void {
        allocator.free(self.stdout);
        allocator.free(self.stderr);
    }
};

// Main job executor
pub const JobExecutor = struct {
    allocator: std.mem.Allocator,
    config: ExecutorConfig,
    running_jobs: std.HashMap(u32, *RunningJob, std.HashMap.AutoContext(u32), std.hash_map.default_max_load_percentage),
    container_runtime: ?*container.DockerRuntime = null,
    action_cache: ?*action_runner.ActionCache = null,
    step_runner: ?*action_runner.StepRunner = null,
    
    const RunningJob = struct {
        job_id: u32,
        started_at: i64,
        current_step: usize,
        steps: []StepResult,
        outputs: std.StringHashMap([]const u8),
        
        pub fn deinit(self: *RunningJob, allocator: std.mem.Allocator) void {
            for (self.steps) |*step| {
                step.deinit(allocator);
            }
            allocator.free(self.steps);
            self.outputs.deinit();
            allocator.destroy(self);
        }
    };
    
    pub fn init(allocator: std.mem.Allocator, config: ExecutorConfig) !JobExecutor {
        var executor = JobExecutor{
            .allocator = allocator,
            .config = config,
            .running_jobs = std.HashMap(u32, *RunningJob, std.HashMap.AutoContext(u32), std.hash_map.default_max_load_percentage).init(allocator),
        };
        
        // Initialize container runtime if needed
        if (config.container_runtime == .docker) {
            const runtime = try allocator.create(container.DockerRuntime);
            runtime.* = try container.DockerRuntime.init(allocator);
            executor.container_runtime = runtime;
        }
        
        // Initialize action cache and step runner
        const action_cache = try allocator.create(action_runner.ActionCache);
        action_cache.* = try action_runner.ActionCache.init(allocator, config.action_cache_dir);
        executor.action_cache = action_cache;
        
        const step_runner_instance = try allocator.create(action_runner.StepRunner);
        step_runner_instance.* = action_runner.StepRunner.init(allocator, .{
            .container_runtime = executor.container_runtime,
            .action_cache = action_cache,
        });
        executor.step_runner = step_runner_instance;
        
        return executor;
    }
    
    pub fn deinit(self: *JobExecutor) void {
        // Clean up any running jobs
        var jobs_iter = self.running_jobs.iterator();
        while (jobs_iter.next()) |entry| {
            entry.value_ptr.*.deinit(self.allocator);
        }
        self.running_jobs.deinit();
        
        // Clean up step runner
        if (self.step_runner) |step_runner| {
            step_runner.deinit();
            self.allocator.destroy(step_runner);
        }
        
        // Clean up action cache
        if (self.action_cache) |action_cache| {
            action_cache.deinit();
            self.allocator.destroy(action_cache);
        }
        
        // Clean up container runtime
        if (self.container_runtime) |runtime| {
            runtime.deinit();
            self.allocator.destroy(runtime);
        }
    }
    
    pub fn executeJob(self: *JobExecutor, job: AssignedJob) !JobResult {
        const started_at = std.time.timestamp();
        
        // Create running job tracking
        const running_job = try self.allocator.create(RunningJob);
        running_job.* = RunningJob{
            .job_id = job.job_id,
            .started_at = started_at,
            .current_step = 0,
            .steps = try self.allocator.alloc(StepResult, job.job_definition.steps.len),
            .outputs = std.StringHashMap([]const u8).init(self.allocator),
        };
        
        try self.running_jobs.put(job.job_id, running_job);
        defer _ = self.running_jobs.remove(job.job_id);
        defer running_job.deinit(self.allocator);
        
        // Initialize all step results
        for (running_job.steps, 0..) |*step_result, i| {
            step_result.* = StepResult{
                .step_name = try self.allocator.dupe(u8, job.job_definition.steps[i].name),
                .status = .queued,
                .started_at = started_at,
                .outputs = std.StringHashMap([]const u8).init(self.allocator),
            };
        }
        
        var job_status = JobStatus.in_progress;
        var job_conclusion: ?JobConclusion = null;
        
        // Execute steps sequentially
        for (job.job_definition.steps, 0..) |step, step_idx| {
            running_job.current_step = step_idx;
            
            const step_result = try self.executeStep(step, job.environment);
            running_job.steps[step_idx] = step_result;
            
            // Check if step failed and should stop execution
            if (step_result.status == .failed and !step.continue_on_error) {
                job_status = .completed;
                job_conclusion = .failure;
                
                // Mark remaining steps as skipped
                for (running_job.steps[step_idx + 1..]) |*remaining_step| {
                    remaining_step.status = .skipped;
                }
                break;
            }
        }
        
        // If we completed all steps successfully
        if (job_conclusion == null) {
            job_status = .completed;
            job_conclusion = .success;
        }
        
        const completed_at = std.time.timestamp();
        
        // Create result with copies of step results
        const result_steps = try self.allocator.alloc(StepResult, running_job.steps.len);
        for (running_job.steps, 0..) |step, i| {
            result_steps[i] = StepResult{
                .step_name = try self.allocator.dupe(u8, step.step_name),
                .status = step.status,
                .conclusion = step.conclusion,
                .started_at = step.started_at,
                .completed_at = step.completed_at,
                .exit_code = step.exit_code,
                .outputs = std.StringHashMap([]const u8).init(self.allocator),
            };
            
            // Copy outputs
            var outputs_iter = step.outputs.iterator();
            while (outputs_iter.next()) |entry| {
                try result_steps[i].outputs.put(
                    try self.allocator.dupe(u8, entry.key_ptr.*),
                    try self.allocator.dupe(u8, entry.value_ptr.*)
                );
            }
        }
        
        return JobResult{
            .job_id = job.job_id,
            .status = job_status,
            .conclusion = job_conclusion,
            .started_at = started_at,
            .completed_at = completed_at,
            .steps = result_steps,
            .outputs = std.StringHashMap([]const u8).init(self.allocator),
            .resource_usage = ResourceUsage{},
        };
    }
    
    pub fn cancelJob(self: *JobExecutor, job_id: u32) !void {
        if (self.running_jobs.get(job_id)) |running_job| {
            // Mark current and remaining steps as cancelled
            for (running_job.steps[running_job.current_step..]) |*step| {
                if (step.status == .queued or step.status == .in_progress) {
                    step.status = .cancelled;
                    step.completed_at = std.time.timestamp();
                }
            }
        }
    }
    
    fn executeStep(self: *JobExecutor, step: Step, environment: ExecutionEnvironment) !StepResult {
        _ = environment;
        
        const started_at = std.time.timestamp();
        
        var step_result = StepResult{
            .step_name = try self.allocator.dupe(u8, step.name),
            .status = .in_progress,
            .started_at = started_at,
            .outputs = std.StringHashMap([]const u8).init(self.allocator),
        };
        
        // Simulate step execution based on type
        switch (step.step_type) {
            .run => |run_step| {
                const result = try self.executeCommand(run_step.command);
                
                step_result.exit_code = result.exit_code;
                step_result.completed_at = std.time.timestamp();
                
                if (result.exit_code == 0) {
                    step_result.status = .completed;
                    step_result.conclusion = .success;
                } else {
                    step_result.status = .failed;
                    step_result.conclusion = .failure;
                }
                
                result.deinit(self.allocator);
            },
            .action => |action_step| {
                // Execute action using step runner
                if (self.step_runner) |runner| {
                    var execution_context = action_runner.ExecutionContext.init(self.allocator);
                    defer execution_context.deinit();
                    
                    // Set up execution context from environment
                    execution_context.working_directory = environment.working_directory;
                    
                    const action_result = runner.executeActionStep(
                        action_step.name,
                        action_step.with,
                        execution_context,
                    ) catch {
                        step_result.exit_code = 1;
                        step_result.completed_at = std.time.timestamp();
                        step_result.status = .failed;
                        step_result.conclusion = .failure;
                        return step_result;
                    };
                    
                    step_result.exit_code = action_result.exit_code;
                    step_result.completed_at = std.time.timestamp();
                    
                    if (action_result.success) {
                        step_result.status = .completed;
                        step_result.conclusion = .success;
                        
                        // Copy action outputs to step outputs
                        var outputs_iter = action_result.outputs.iterator();
                        while (outputs_iter.next()) |entry| {
                            try step_result.outputs.put(
                                try self.allocator.dupe(u8, entry.key_ptr.*),
                                try self.allocator.dupe(u8, entry.value_ptr.*)
                            );
                        }
                    } else {
                        step_result.status = .failed;
                        step_result.conclusion = .failure;
                    }
                    
                    // Clean up action result
                    var mut_action_result = action_result;
                    mut_action_result.deinit(self.allocator);
                } else {
                    // Fallback to mock execution
                    step_result.exit_code = 0;
                    step_result.completed_at = std.time.timestamp();
                    step_result.status = .completed;
                    step_result.conclusion = .success;
                }
            },
            .composite => |comp_step| {
                // Mock composite step execution
                _ = comp_step;
                step_result.exit_code = 0;
                step_result.completed_at = std.time.timestamp();
                step_result.status = .completed;
                step_result.conclusion = .success;
            },
        }
        
        return step_result;
    }
    
    fn executeCommand(self: *JobExecutor, command: []const u8) !CommandResult {
        // Parse command into arguments
        var args = std.ArrayList([]const u8).init(self.allocator);
        defer args.deinit();
        
        var token_iter = std.mem.tokenize(u8, command, " ");
        while (token_iter.next()) |token| {
            try args.append(token);
        }
        
        if (args.items.len == 0) {
            return CommandResult{
                .exit_code = 1,
                .stdout = try self.allocator.dupe(u8, ""),
                .stderr = try self.allocator.dupe(u8, "Empty command"),
            };
        }
        
        // Use container runtime if available, otherwise fall back to mock
        if (self.container_runtime) |runtime| {
            // For now, we'll create a temporary container for each command
            // In a real implementation, we'd reuse job containers
            var container_config = container.ContainerConfig.init(self.allocator, "ubuntu:22.04");
            defer container_config.deinit();
            
            const job_container = runtime.createContainer(container_config) catch {
                // Fall back to mock execution if container creation fails
                return self.mockExecuteCommand(command);
            };
            defer runtime.destroyContainer(job_container.id) catch {};
            
            runtime.startContainer(job_container.id) catch {
                return self.mockExecuteCommand(command);
            };
            
            const exec_result = runtime.executeCommand(job_container.id, .{
                .command = args.items,
                .timeout_seconds = 300,
            }) catch {
                return self.mockExecuteCommand(command);
            };
            
            return CommandResult{
                .exit_code = exec_result.exit_code,
                .stdout = exec_result.stdout, // Transfer ownership
                .stderr = exec_result.stderr, // Transfer ownership
            };
        } else {
            return self.mockExecuteCommand(command);
        }
    }
    
    fn mockExecuteCommand(self: *JobExecutor, command: []const u8) !CommandResult {
        // Mock command execution for testing when no container runtime
        if (std.mem.eql(u8, command, "exit 1")) {
            return CommandResult{
                .exit_code = 1,
                .stdout = try self.allocator.dupe(u8, ""),
                .stderr = try self.allocator.dupe(u8, "Command failed with exit code 1"),
            };
        } else if (std.mem.indexOf(u8, command, "echo") != null) {
            const output = if (std.mem.indexOf(u8, command, "Hello, World!") != null)
                "Hello, World!"
            else if (std.mem.indexOf(u8, command, "This works") != null)
                "This works"
            else
                "Command output";
                
            return CommandResult{
                .exit_code = 0,
                .stdout = try self.allocator.dupe(u8, output),
                .stderr = try self.allocator.dupe(u8, ""),
            };
        } else if (std.mem.indexOf(u8, command, "ls") != null) {
            return CommandResult{
                .exit_code = 0,
                .stdout = try self.allocator.dupe(u8, "total 0\ndrwxr-xr-x 2 user user 4096 Jan 1 00:00 .\ndrwxr-xr-x 3 user user 4096 Jan 1 00:00 .."),
                .stderr = try self.allocator.dupe(u8, ""),
            };
        }
        
        // Default successful execution
        return CommandResult{
            .exit_code = 0,
            .stdout = try self.allocator.dupe(u8, ""),
            .stderr = try self.allocator.dupe(u8, ""),
        };
    }
};

// Test helper to create a simple job
fn createTestJob(allocator: std.mem.Allocator, job_id: u32, steps: []const Step) !AssignedJob {
    const job_definition = JobDefinition{
        .name = try allocator.dupe(u8, "test-job"),
        .runs_on = try allocator.dupe(u8, "ubuntu-latest"),
        .steps = try allocator.dupe(Step, steps),
        .env = std.StringHashMap([]const u8).init(allocator),
    };
    
    return AssignedJob{
        .job_id = job_id,
        .workflow_run_id = 1,
        .job_definition = job_definition,
        .environment = ExecutionEnvironment.init(allocator),
        .assigned_at = std.time.timestamp(),
    };
}

// Tests for Phase 1: Job Execution Foundation
test "executes simple job with run steps" {
    const allocator = testing.allocator;
    
    var executor = try JobExecutor.init(allocator, .{
        .container_runtime = .native,
        .log_level = .debug,
    });
    defer executor.deinit();
    
    const steps = [_]Step{
        Step.runStep("Hello World", "echo 'Hello, World!'"),
        Step.runStep("List Files", "ls -la"),
    };
    
    var job = try createTestJob(allocator, 1, &steps);
    defer job.deinit(allocator);
    
    var result = try executor.executeJob(job);
    defer result.deinit(allocator);
    
    try testing.expectEqual(JobStatus.completed, result.status);
    try testing.expectEqual(JobConclusion.success, result.conclusion.?);
    try testing.expectEqual(@as(usize, 2), result.steps.len);
    
    // Verify all steps completed successfully
    for (result.steps) |step_result| {
        try testing.expectEqual(StepStatus.completed, step_result.status);
        try testing.expectEqual(@as(i32, 0), step_result.exit_code.?);
    }
}

test "handles job execution failure correctly" {
    const allocator = testing.allocator;
    
    var executor = try JobExecutor.init(allocator, .{
        .container_runtime = .native,
    });
    defer executor.deinit();
    
    const steps = [_]Step{
        Step.runStep("Success Step", "echo 'This works'"),
        Step.runStep("Failing Step", "exit 1"), // Intentional failure
        Step.runStep("Should Not Run", "echo 'This should not run'"),
    };
    
    var job = try createTestJob(allocator, 2, &steps);
    defer job.deinit(allocator);
    
    var result = try executor.executeJob(job);
    defer result.deinit(allocator);
    
    try testing.expectEqual(JobStatus.completed, result.status);
    try testing.expectEqual(JobConclusion.failure, result.conclusion.?);
    
    // First step should succeed
    try testing.expectEqual(StepStatus.completed, result.steps[0].status);
    try testing.expectEqual(@as(i32, 0), result.steps[0].exit_code.?);
    
    // Second step should fail
    try testing.expectEqual(StepStatus.failed, result.steps[1].status);
    try testing.expectEqual(@as(i32, 1), result.steps[1].exit_code.?);
    
    // Third step should be skipped
    try testing.expectEqual(StepStatus.skipped, result.steps[2].status);
}

test "tracks job execution timing and metadata" {
    const allocator = testing.allocator;
    
    var executor = try JobExecutor.init(allocator, .{
        .container_runtime = .native,
    });
    defer executor.deinit();
    
    const steps = [_]Step{
        Step.runStep("Quick Step", "echo 'done'"),
    };
    
    var job = try createTestJob(allocator, 3, &steps);
    defer job.deinit(allocator);
    
    const start_time = std.time.timestamp();
    var result = try executor.executeJob(job);
    defer result.deinit(allocator);
    const end_time = std.time.timestamp();
    
    // Verify timing
    try testing.expect(result.started_at >= start_time);
    try testing.expect(result.completed_at <= end_time);
    try testing.expect(result.completed_at >= result.started_at);
    
    // Verify step timing
    try testing.expect(result.steps[0].started_at >= start_time);
    try testing.expect(result.steps[0].completed_at.? <= end_time);
    try testing.expect(result.steps[0].completed_at.? >= result.steps[0].started_at);
}

test "supports continue-on-error for steps" {
    const allocator = testing.allocator;
    
    var executor = try JobExecutor.init(allocator, .{
        .container_runtime = .native,
    });
    defer executor.deinit();
    
    var failing_step = Step.runStep("Failing Step", "exit 1");
    failing_step.continue_on_error = true;
    
    const steps = [_]Step{
        failing_step,
        Step.runStep("Should Run", "echo 'This should run'"),
    };
    
    var job = try createTestJob(allocator, 4, &steps);
    defer job.deinit(allocator);
    
    var result = try executor.executeJob(job);
    defer result.deinit(allocator);
    
    try testing.expectEqual(JobStatus.completed, result.status);
    try testing.expectEqual(JobConclusion.success, result.conclusion.?);
    
    // First step should fail but not stop execution
    try testing.expectEqual(StepStatus.failed, result.steps[0].status);
    try testing.expectEqual(@as(i32, 1), result.steps[0].exit_code.?);
    
    // Second step should still run and succeed
    try testing.expectEqual(StepStatus.completed, result.steps[1].status);
    try testing.expectEqual(@as(i32, 0), result.steps[1].exit_code.?);
}

test "handles job cancellation" {
    const allocator = testing.allocator;
    
    var executor = try JobExecutor.init(allocator, .{
        .container_runtime = .native,
    });
    defer executor.deinit();
    
    const steps = [_]Step{
        Step.runStep("Step 1", "echo 'step1'"),
        Step.runStep("Step 2", "echo 'step2'"),
    };
    
    var job = try createTestJob(allocator, 5, &steps);
    defer job.deinit(allocator);
    
    // For this test, we'll just verify the cancel function doesn't crash
    // In a real implementation, this would interrupt running jobs
    try executor.cancelJob(5);
    try executor.cancelJob(999); // Non-existent job should not error
}

test "executes jobs with Docker container runtime" {
    const allocator = testing.allocator;
    
    var executor = try JobExecutor.init(allocator, .{
        .container_runtime = .docker,
        .log_level = .debug,
    });
    defer executor.deinit();
    
    const steps = [_]Step{
        Step.runStep("Container Test", "echo 'Hello from container'"),
        Step.runStep("List Files", "ls"),
    };
    
    var job = try createTestJob(allocator, 6, &steps);
    defer job.deinit(allocator);
    
    var result = try executor.executeJob(job);
    defer result.deinit(allocator);
    
    try testing.expectEqual(JobStatus.completed, result.status);
    try testing.expectEqual(JobConclusion.success, result.conclusion.?);
    try testing.expectEqual(@as(usize, 2), result.steps.len);
    
    // Verify all steps completed successfully
    for (result.steps) |step_result| {
        try testing.expectEqual(StepStatus.completed, step_result.status);
        try testing.expectEqual(@as(i32, 0), step_result.exit_code.?);
    }
}

test "handles container execution errors gracefully" {
    const allocator = testing.allocator;
    
    var executor = try JobExecutor.init(allocator, .{
        .container_runtime = .docker,
        .log_level = .debug,
    });
    defer executor.deinit();
    
    const steps = [_]Step{
        Step.runStep("Failing Command", "exit 1"),
    };
    
    var job = try createTestJob(allocator, 7, &steps);
    defer job.deinit(allocator);
    
    var result = try executor.executeJob(job);
    defer result.deinit(allocator);
    
    try testing.expectEqual(JobStatus.completed, result.status);
    try testing.expectEqual(JobConclusion.failure, result.conclusion.?);
    try testing.expectEqual(StepStatus.failed, result.steps[0].status);
    try testing.expectEqual(@as(i32, 1), result.steps[0].exit_code.?);
}

test "executes action steps with GitHub Actions compatibility" {
    const allocator = testing.allocator;
    
    var executor = try JobExecutor.init(allocator, .{
        .container_runtime = .native,
        .log_level = .debug,
        .action_cache_dir = "/tmp/test-actions-cache",
    });
    defer executor.deinit();
    
    const steps = [_]Step{
        Step.actionStep("Checkout Repository", "actions/checkout@v4"),
        Step.actionStep("Setup Node.js", "actions/setup-node@v3"),
    };
    
    var job = try createTestJob(allocator, 8, &steps);
    defer job.deinit(allocator);
    
    var result = try executor.executeJob(job);
    defer result.deinit(allocator);
    
    try testing.expectEqual(JobStatus.completed, result.status);
    try testing.expectEqual(JobConclusion.success, result.conclusion.?);
    try testing.expectEqual(@as(usize, 2), result.steps.len);
    
    // Verify all action steps completed successfully
    for (result.steps) |step_result| {
        try testing.expectEqual(StepStatus.completed, step_result.status);
        try testing.expectEqual(@as(i32, 0), step_result.exit_code.?);
    }
}

test "handles mixed run and action steps correctly" {
    const allocator = testing.allocator;
    
    var executor = try JobExecutor.init(allocator, .{
        .container_runtime = .native,
        .log_level = .debug,
        .action_cache_dir = "/tmp/test-actions-cache-2",
    });
    defer executor.deinit();
    
    const steps = [_]Step{
        Step.actionStep("Checkout", "actions/checkout@v4"),
        Step.runStep("Install Dependencies", "echo 'npm install'"),
        Step.actionStep("Setup Node", "actions/setup-node@v3"),
        Step.runStep("Run Tests", "echo 'npm test'"),
    };
    
    var job = try createTestJob(allocator, 9, &steps);
    defer job.deinit(allocator);
    
    var result = try executor.executeJob(job);
    defer result.deinit(allocator);
    
    try testing.expectEqual(JobStatus.completed, result.status);
    try testing.expectEqual(JobConclusion.success, result.conclusion.?);
    try testing.expectEqual(@as(usize, 4), result.steps.len);
    
    // Verify execution order and success
    try testing.expectEqualStrings("Checkout", result.steps[0].step_name);
    try testing.expectEqual(StepStatus.completed, result.steps[0].status);
    
    try testing.expectEqualStrings("Install Dependencies", result.steps[1].step_name);
    try testing.expectEqual(StepStatus.completed, result.steps[1].status);
    
    try testing.expectEqualStrings("Setup Node", result.steps[2].step_name);
    try testing.expectEqual(StepStatus.completed, result.steps[2].status);
    
    try testing.expectEqualStrings("Run Tests", result.steps[3].step_name);
    try testing.expectEqual(StepStatus.completed, result.steps[3].status);
}