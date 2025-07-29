# Actions: Job Execution & Logging

<task_definition>
Implement a comprehensive job execution engine that runs GitHub Actions workflows on registered runners with real-time logging, artifact management, and complete GitHub Actions compatibility. This system will handle job lifecycle management, step execution, environment setup, and comprehensive logging with enterprise-grade security and reliability for the Plue CI/CD platform.
</task_definition>

<context_and_constraints>

<technical_requirements>

- **Language/Framework**: Zig with process management - https://ziglang.org/documentation/master/
- **Dependencies**: Runner registration (#28), Actions data models (#25), Docker/container runtime
- **Location**: `src/actions/executor.zig`, `src/actions/job_runner.zig`, `src/actions/logging.zig`
- **Execution**: Docker containers, VM isolation, process sandboxing
- **Logging**: Real-time streaming, structured logging, log aggregation
- **Security**: Sandbox isolation, secret injection, resource limits
- **Performance**: Efficient step execution, parallel processing, resource optimization

</technical_requirements>

<business_context>

Job execution and logging enables:

- **CI/CD Automation**: Complete workflow execution with GitHub Actions compatibility
- **Development Velocity**: Fast feedback loops with efficient job execution
- **Quality Assurance**: Automated testing, building, and deployment processes
- **Compliance**: Audit trails, security scanning, policy enforcement
- **Debugging**: Detailed logs, step-by-step execution visibility
- **Resource Management**: Efficient compute utilization, cost optimization
- **Enterprise Features**: Multi-tenancy, resource quotas, security controls

This provides the execution engine that transforms workflow definitions into running processes with complete observability.

</business_context>

</context_and_constraints>

<detailed_specifications>

<input>

Job execution requirements:

1. **Job Structure Execution**:
   ```yaml
   # Workflow job to execute
   jobs:
     build:
       runs-on: ubuntu-latest
       env:
         NODE_VERSION: '18'
         CI: true
       steps:
         - name: Checkout code
           uses: actions/checkout@v4
           with:
             fetch-depth: 0
         
         - name: Setup Node.js
           uses: actions/setup-node@v3
           with:
             node-version: ${{ env.NODE_VERSION }}
             cache: 'npm'
         
         - name: Install dependencies
           run: npm ci
           
         - name: Run tests
           run: npm test
           env:
             DATABASE_URL: ${{ secrets.DATABASE_URL }}
         
         - name: Upload test results
           uses: actions/upload-artifact@v3
           if: always()
           with:
             name: test-results
             path: test-results/
   ```

2. **Step Execution Types**:
   ```zig
   const StepType = union(enum) {
       action: struct {
           name: []const u8, // actions/checkout@v4
           with: std.StringHashMap([]const u8),
           env: std.StringHashMap([]const u8),
       },
       run: struct {
           command: []const u8,
           shell: ?[]const u8, // bash, sh, powershell, cmd
           working_directory: ?[]const u8,
           env: std.StringHashMap([]const u8),
       },
       composite: struct {
           steps: []const Step,
       },
   };
   ```

3. **Execution Environment**:
   ```zig
   const ExecutionEnvironment = struct {
       // Container/VM configuration
       image: []const u8, // ubuntu:22.04, node:18
       working_directory: []const u8,
       user: ?[]const u8,
       
       // Environment variables
       env: std.StringHashMap([]const u8),
       secrets: std.StringHashMap([]const u8),
       
       // Resource limits
       memory_limit_mb: ?u32,
       cpu_limit_cores: ?f32,
       timeout_minutes: u32,
       
       // Networking and services
       services: []const ServiceContainer,
       network_access: NetworkPolicy,
   };
   ```

4. **Real-time Logging**:
   ```zig
   // Stream logs in real-time
   var log_stream = try job_executor.getLogStream(allocator, job_id);
   defer log_stream.deinit();
   
   while (try log_stream.readLine(allocator)) |line| {
       defer allocator.free(line);
       
       const log_entry = LogEntry{
           .timestamp = std.time.nanoTimestamp(),
           .level = .info,
           .step_name = current_step.name,
           .message = line,
           .metadata = current_metadata,
       };
       
       try log_aggregator.append(allocator, log_entry);
       try websocket_broadcaster.send(allocator, log_entry);
   }
   ```

Expected execution flow:
```zig
// Initialize job executor
var executor = try JobExecutor.init(allocator, .{
    .container_runtime = .docker,
    .log_aggregator = &log_aggregator,
    .artifact_storage = &artifact_storage,
    .secret_manager = &secret_manager,
});
defer executor.deinit(allocator);

// Execute assigned job
const job_result = try executor.executeJob(allocator, assigned_job);

// Report completion
try runner_client.completeJob(allocator, assigned_job.job_id, job_result);
```

</input>

<expected_output>

Complete job execution system providing:

1. **Job Executor**: Orchestrates complete job lifecycle from start to finish
2. **Step Runner**: Executes individual workflow steps with proper isolation
3. **Action Runner**: Downloads and executes GitHub Actions with caching
4. **Container Manager**: Docker/VM management for execution environments
5. **Log Aggregator**: Real-time log collection and streaming
6. **Secret Manager**: Secure secret injection and masking
7. **Artifact Manager**: Upload/download of build artifacts
8. **Resource Monitor**: CPU, memory, and resource usage tracking

Core execution architecture:
```zig
const JobExecutor = struct {
    allocator: std.mem.Allocator,
    container_runtime: ContainerRuntime,
    log_aggregator: *LogAggregator,
    artifact_storage: *ArtifactStorage,
    secret_manager: *SecretManager,
    config: ExecutorConfig,
    
    pub fn init(allocator: std.mem.Allocator, config: ExecutorConfig) !JobExecutor;
    pub fn deinit(self: *JobExecutor, allocator: std.mem.Allocator) void;
    
    // Job execution
    pub fn executeJob(self: *JobExecutor, allocator: std.mem.Allocator, job: AssignedJob) !JobResult;
    pub fn cancelJob(self: *JobExecutor, allocator: std.mem.Allocator, job_id: u32) !void;
    
    // Step execution
    pub fn executeStep(self: *JobExecutor, allocator: std.mem.Allocator, step: Step, context: ExecutionContext) !StepResult;
    pub fn runCommand(self: *JobExecutor, allocator: std.mem.Allocator, command: []const u8, env: ExecutionEnvironment) !CommandResult;
    pub fn runAction(self: *JobExecutor, allocator: std.mem.Allocator, action: ActionStep, context: ExecutionContext) !ActionResult;
    
    // Logging and monitoring
    pub fn getLogStream(self: *JobExecutor, allocator: std.mem.Allocator, job_id: u32) !*LogStream;
    pub fn getResourceUsage(self: *JobExecutor, allocator: std.mem.Allocator, job_id: u32) !ResourceUsage;
};

const StepRunner = struct {
    executor: *JobExecutor,
    container: *Container,
    log_stream: *LogStream,
    
    pub fn runStep(self: *StepRunner, allocator: std.mem.Allocator, step: Step) !StepResult;
    pub fn setupEnvironment(self: *StepRunner, allocator: std.mem.Allocator, env: ExecutionEnvironment) !void;
    pub fn injectSecrets(self: *StepRunner, allocator: std.mem.Allocator, secrets: std.StringHashMap([]const u8)) !void;
    pub fn collectArtifacts(self: *StepRunner, allocator: std.mem.Allocator, patterns: []const []const u8) ![]Artifact;
};

const LogAggregator = struct {
    streams: std.HashMap(u32, *LogStream),
    storage: *LogStorage,
    broadcasters: []LogBroadcaster,
    
    pub fn createLogStream(self: *LogAggregator, allocator: std.mem.Allocator, job_id: u32) !*LogStream;
    pub fn appendLog(self: *LogAggregator, allocator: std.mem.Allocator, job_id: u32, entry: LogEntry) !void;
    pub fn getJobLogs(self: *LogAggregator, allocator: std.mem.Allocator, job_id: u32, options: LogQueryOptions) ![]LogEntry;
    pub fn streamLogs(self: *LogAggregator, allocator: std.mem.Allocator, job_id: u32, callback: LogCallback) !void;
};

const JobResult = struct {
    job_id: u32,
    status: JobStatus,
    conclusion: ?JobConclusion,
    started_at: i64,
    completed_at: i64,
    steps: []StepResult,
    outputs: std.StringHashMap([]const u8),
    artifacts: []Artifact,
    resource_usage: ResourceUsage,
    
    const JobStatus = enum {
        queued,
        in_progress,
        completed,
        cancelled,
        failed,
    };
    
    const JobConclusion = enum {
        success,
        failure,
        cancelled,
        timed_out,
        action_required,
        neutral,
        skipped,
    };
};
```

</expected_output>

<implementation_steps>

**CRITICAL**: Follow TDD approach. Use real container runtime for testing. Run `zig build && zig build test` after EVERY change.

**CRITICAL**: Zero tolerance for test failures. Any failing tests indicate YOU caused a regression.

<phase_1>
<title>Phase 1: Job Execution Foundation (TDD)</title>

1. **Create job execution module structure**
   ```bash
   mkdir -p src/actions
   touch src/actions/executor.zig
   touch src/actions/job_runner.zig
   touch src/actions/step_runner.zig
   touch src/actions/logging.zig
   ```

2. **Write tests for basic job execution**
   ```zig
   test "executes simple job with run steps" {
       const allocator = testing.allocator;
       
       var executor = try JobExecutor.init(allocator, .{
           .container_runtime = .docker,
           .log_level = .debug,
       });
       defer executor.deinit(allocator);
       
       const job = AssignedJob{
           .job_id = 1,
           .job_definition = .{
               .name = "test-job",
               .runs_on = "ubuntu-latest",
               .steps = &.{
                   .{
                       .name = "Hello World",
                       .run = .{
                           .command = "echo 'Hello, World!'",
                           .shell = "bash",
                       },
                   },
                   .{
                       .name = "List Files",
                       .run = .{
                           .command = "ls -la",
                           .shell = "bash",
                       },
                   },
               },
           },
           .environment = .{
               .env = std.StringHashMap([]const u8).init(allocator),
               .secrets = std.StringHashMap([]const u8).init(allocator),
           },
       };
       
       const result = try executor.executeJob(allocator, job);
       defer result.deinit(allocator);
       
       try testing.expectEqual(JobResult.JobStatus.completed, result.status);
       try testing.expectEqual(JobResult.JobConclusion.success, result.conclusion.?);
       try testing.expectEqual(@as(usize, 2), result.steps.len);
       
       // Verify all steps completed successfully
       for (result.steps) |step_result| {
           try testing.expectEqual(StepResult.StepStatus.completed, step_result.status);
           try testing.expectEqual(@as(i32, 0), step_result.exit_code.?);
       }
   }
   
   test "handles job execution failure correctly" {
       const allocator = testing.allocator;
       
       var executor = try JobExecutor.init(allocator, test_config);
       defer executor.deinit(allocator);
       
       const failing_job = AssignedJob{
           .job_id = 2,
           .job_definition = .{
               .name = "failing-job",
               .runs_on = "ubuntu-latest",
               .steps = &.{
                   .{
                       .name = "Success Step",
                       .run = .{ .command = "echo 'This works'" },
                   },
                   .{
                       .name = "Failing Step",
                       .run = .{ .command = "exit 1" }, // Intentional failure
                   },
                   .{
                       .name = "Should Not Run",
                       .run = .{ .command = "echo 'This should not run'" },
                   },
               },
           },
       };
       
       const result = try executor.executeJob(allocator, failing_job);
       defer result.deinit(allocator);
       
       try testing.expectEqual(JobResult.JobStatus.completed, result.status);
       try testing.expectEqual(JobResult.JobConclusion.failure, result.conclusion.?);
       
       // First step should succeed
       try testing.expectEqual(StepResult.StepStatus.completed, result.steps[0].status);
       try testing.expectEqual(@as(i32, 0), result.steps[0].exit_code.?);
       
       // Second step should fail
       try testing.expectEqual(StepResult.StepStatus.completed, result.steps[1].status);
       try testing.expectEqual(@as(i32, 1), result.steps[1].exit_code.?);
       
       // Third step should be skipped
       try testing.expectEqual(StepResult.StepStatus.skipped, result.steps[2].status);
   }
   ```

3. **Implement basic job executor with step sequencing**
4. **Add error handling and job failure scenarios**
5. **Test job lifecycle and state transitions**

</phase_1>

<phase_2>
<title>Phase 2: Container Runtime Integration (TDD)</title>

1. **Write tests for container execution**
   ```zig
   test "creates and manages Docker containers for job execution" {
       const allocator = testing.allocator;
       
       // Skip test if Docker not available
       const docker_available = checkDockerAvailable() catch return;
       if (!docker_available) return;
       
       var container_runtime = try DockerRuntime.init(allocator);
       defer container_runtime.deinit(allocator);
       
       const container_config = ContainerConfig{
           .image = "ubuntu:22.04",
           .working_directory = "/workspace",
           .env = std.StringHashMap([]const u8).init(allocator),
           .memory_limit_mb = 512,
           .cpu_limit_cores = 1.0,
       };
       
       // Create container
       const container = try container_runtime.createContainer(allocator, container_config);
       defer container_runtime.destroyContainer(allocator, container.id) catch {};
       
       try testing.expect(container.id.len > 0);
       try testing.expectEqual(ContainerStatus.created, container.status);
       
       // Start container
       try container_runtime.startContainer(allocator, container.id);
       
       const running_container = try container_runtime.getContainer(allocator, container.id);
       try testing.expectEqual(ContainerStatus.running, running_container.status);
       
       // Execute command in container
       const exec_result = try container_runtime.executeCommand(allocator, container.id, .{
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
       defer container_runtime.deinit(allocator);
       
       const container_config = ContainerConfig{
           .image = "ubuntu:22.04",
           .memory_limit_mb = 128, // Low memory limit
           .cpu_limit_cores = 0.5,
       };
       
       const container = try container_runtime.createContainer(allocator, container_config);
       defer container_runtime.destroyContainer(allocator, container.id) catch {};
       
       try container_runtime.startContainer(allocator, container.id);
       
       // Test timeout enforcement
       const start_time = std.time.timestamp();
       
       const exec_result = container_runtime.executeCommand(allocator, container.id, .{
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
   ```

2. **Implement Docker container runtime**
3. **Add resource limits and monitoring**
4. **Test container lifecycle and cleanup**

</phase_2>

<phase_3>
<title>Phase 3: Step Execution and Action Support (TDD)</title>

1. **Write tests for step execution**
   ```zig
   test "executes action steps with input parameters" {
       const allocator = testing.allocator;
       
       var step_runner = try StepRunner.init(allocator, .{
           .container_runtime = &docker_runtime,
           .action_cache = &action_cache,
       });
       defer step_runner.deinit(allocator);
       
       const checkout_step = Step{
           .name = "Checkout code",
           .uses = "actions/checkout@v4",
           .with = blk: {
               var with_params = std.StringHashMap([]const u8).init(allocator);
               try with_params.put("fetch-depth", "0");
               try with_params.put("ref", "main");
               break :blk with_params;
           },
       };
       defer checkout_step.with.deinit();
       
       const execution_context = ExecutionContext{
           .working_directory = "/workspace",
           .github = .{
               .repository = "owner/repo",
               .ref = "refs/heads/main",
               .sha = "abc123def456",
           },
           .env = std.StringHashMap([]const u8).init(allocator),
       };
       defer execution_context.env.deinit();
       
       const result = try step_runner.executeStep(allocator, checkout_step, execution_context);
       defer result.deinit(allocator);
       
       try testing.expectEqual(StepResult.StepStatus.completed, result.status);
       try testing.expectEqual(@as(i32, 0), result.exit_code.?);
       
       // Verify checkout occurred (files should exist)
       const file_check = try step_runner.runCommand(allocator, "ls -la /workspace", .{});
       defer file_check.deinit(allocator);
       
       try testing.expect(std.mem.indexOf(u8, file_check.stdout, ".git") != null);
   }
   
   test "handles action download and caching" {
       const allocator = testing.allocator;
       
       var action_cache = try ActionCache.init(allocator, "/tmp/actions-cache");
       defer action_cache.deinit(allocator);
       
       const action_ref = "actions/setup-node@v3";
       
       // First download should fetch from remote
       const start_time1 = std.time.nanoTimestamp();
       const action1 = try action_cache.getAction(allocator, action_ref);
       defer action1.deinit(allocator);
       const duration1 = std.time.nanoTimestamp() - start_time1;
       
       try testing.expect(action1.path.len > 0);
       try testing.expect(std.fs.path.isAbsolute(action1.path));
       
       // Second request should use cache (much faster)
       const start_time2 = std.time.nanoTimestamp();
       const action2 = try action_cache.getAction(allocator, action_ref);
       defer action2.deinit(allocator);
       const duration2 = std.time.nanoTimestamp() - start_time2;
       
       try testing.expectEqualStrings(action1.path, action2.path);
       try testing.expect(duration2 < duration1 / 2); // Cache should be much faster
   }
   ```

2. **Implement action download and caching system**
3. **Add step execution with proper context**
4. **Test complex action scenarios and edge cases**

</phase_3>

<phase_4>
<title>Phase 4: Real-time Logging System (TDD)</title>

1. **Write tests for logging system**
   ```zig
   test "captures and streams job logs in real-time" {
       const allocator = testing.allocator;
       
       var log_aggregator = try LogAggregator.init(allocator, .{
           .storage_backend = .memory,
           .enable_streaming = true,
       });
       defer log_aggregator.deinit(allocator);
       
       const job_id: u32 = 123;
       
       // Create log stream
       var log_stream = try log_aggregator.createLogStream(allocator, job_id);
       defer log_stream.deinit();
       
       // Set up log subscriber for testing
       var received_logs = std.ArrayList(LogEntry).init(allocator);
       defer received_logs.deinit();
       
       try log_aggregator.subscribe(allocator, job_id, struct {
           logs: *std.ArrayList(LogEntry),
           
           fn onLogEntry(self: @This(), entry: LogEntry) !void {
               try self.logs.append(entry);
           }
       }{ .logs = &received_logs });
       
       // Write log entries
       const log_entries = [_]LogEntry{
           .{
               .timestamp = std.time.nanoTimestamp(),
               .level = .info,
               .step_name = "Setup",
               .message = "Starting step execution",
           },
           .{
               .timestamp = std.time.nanoTimestamp(),
               .level = .info,
               .step_name = "Setup",
               .message = "Environment configured",
           },
           .{
               .timestamp = std.time.nanoTimestamp(),
               .level = .info,
               .step_name = "Setup",
               .message = "Step completed successfully",
           },
       };
       
       for (log_entries) |entry| {
           try log_aggregator.appendLog(allocator, job_id, entry);
       }
       
       // Give streaming time to process
       std.time.sleep(100 * std.time.ns_per_ms);
       
       // Verify logs were received
       try testing.expectEqual(@as(usize, 3), received_logs.items.len);
       try testing.expectEqualStrings("Starting step execution", received_logs.items[0].message);
       try testing.expectEqualStrings("Setup", received_logs.items[0].step_name);
   }
   
   test "persists logs and allows querying" {
       const allocator = testing.allocator;
       
       var log_storage = try LogStorage.init(allocator, .{
           .backend = .filesystem,
           .base_path = "/tmp/job-logs",
       });
       defer log_storage.deinit(allocator);
       
       const job_id: u32 = 456;
       
       // Store logs
       const test_logs = [_]LogEntry{
           .{ .timestamp = 1000000000, .level = .info, .step_name = "Build", .message = "Starting build" },
           .{ .timestamp = 1000000001, .level = .info, .step_name = "Build", .message = "Compiling source" },
           .{ .timestamp = 1000000002, .level = .error, .step_name = "Build", .message = "Compilation failed" },
           .{ .timestamp = 1000000003, .level = .info, .step_name = "Build", .message = "Build completed with errors" },
       };
       
       for (test_logs) |log_entry| {
           try log_storage.storeLog(allocator, job_id, log_entry);
       }
       
       // Query all logs
       const all_logs = try log_storage.getJobLogs(allocator, job_id, .{});
       defer allocator.free(all_logs);
       
       try testing.expectEqual(@as(usize, 4), all_logs.len);
       
       // Query error logs only
       const error_logs = try log_storage.getJobLogs(allocator, job_id, .{
           .level = .error,
       });
       defer allocator.free(error_logs);
       
       try testing.expectEqual(@as(usize, 1), error_logs.len);
       try testing.expectEqualStrings("Compilation failed", error_logs[0].message);
   }
   ```

2. **Implement real-time log streaming system**
3. **Add log persistence and querying**
4. **Test log filtering and search capabilities**

</phase_4>

<phase_5>
<title>Phase 5: Secret Management and Security (TDD)</title>

1. **Write tests for secret handling**
   ```zig
   test "injects secrets into job environment securely" {
       const allocator = testing.allocator;
       
       var secret_manager = try SecretManager.init(allocator, .{
           .encryption_key = test_encryption_key,
       });
       defer secret_manager.deinit(allocator);
       
       // Create job with secrets
       const job = AssignedJob{
           .job_id = 789,
           .secrets = blk: {
               var secrets = std.StringHashMap([]const u8).init(allocator);
               try secrets.put("DATABASE_URL", "postgresql://user:secret@db:5432/app");
               try secrets.put("API_KEY", "super-secret-api-key-12345");
               break :blk secrets;
           },
           .job_definition = .{
               .steps = &.{
                   .{
                       .name = "Use secrets",
                       .run = .{
                           .command = "echo $DATABASE_URL | wc -c", // Should show length but not value
                       },
                   },
               },
           },
       };
       defer job.secrets.deinit();
       
       var executor = try JobExecutor.init(allocator, .{
           .secret_manager = &secret_manager,
           .log_secret_masking = true,
       });
       defer executor.deinit(allocator);
       
       const result = try executor.executeJob(allocator, job);
       defer result.deinit(allocator);
       
       // Verify secrets were injected (command should succeed)
       try testing.expectEqual(StepResult.StepStatus.completed, result.steps[0].status);
       
       // Verify secrets are masked in logs
       const job_logs = try executor.getJobLogs(allocator, job.job_id);
       defer allocator.free(job_logs);
       
       for (job_logs) |log_entry| {
           // No secret values should appear in logs
           try testing.expect(std.mem.indexOf(u8, log_entry.message, "secret@db") == null);
           try testing.expect(std.mem.indexOf(u8, log_entry.message, "super-secret-api-key") == null);
           
           // But masked indicators should be present
           if (std.mem.indexOf(u8, log_entry.message, "***") != null) {
               // Found masked secret, that's good
           }
       }
   }
   
   test "prevents secret leakage through environment" {
       const allocator = testing.allocator;
       
       var executor = try JobExecutor.init(allocator, .{
           .secret_manager = &secret_manager,
           .strict_secret_handling = true,
       });
       defer executor.deinit(allocator);
       
       const job_with_secrets = createJobWithSecrets(allocator);
       defer job_with_secrets.deinit(allocator);
       
       // Try to expose secrets through env command
       const malicious_step = Step{
           .name = "Try to expose secrets",
           .run = .{ .command = "env | grep -E '(SECRET|PASSWORD|KEY)'" },
       };
       
       // This should either fail or mask the output
       const result = try executor.executeStep(allocator, malicious_step, test_context);
       defer result.deinit(allocator);
       
       // Verify no secret values in output
       if (result.stdout) |stdout| {
           try testing.expect(std.mem.indexOf(u8, stdout, "actual-secret-value") == null);
       }
   }
   ```

2. **Implement secure secret injection**
3. **Add secret masking in logs**
4. **Test secret leakage prevention**

</phase_5>

<phase_6>
<title>Phase 6: Artifact Management (TDD)</title>

1. **Write tests for artifact handling**
   ```zig
   test "uploads and manages job artifacts" {
       const allocator = testing.allocator;
       
       var artifact_storage = try ArtifactStorage.init(allocator, .{
           .backend = .filesystem,
           .base_path = "/tmp/artifacts",
       });
       defer artifact_storage.deinit(allocator);
       
       var executor = try JobExecutor.init(allocator, .{
           .artifact_storage = &artifact_storage,
       });
       defer executor.deinit(allocator);
       
       // Create test files to upload
       var tmp_dir = testing.tmpDir(.{});
       defer tmp_dir.cleanup();
       
       const test_file_path = try tmp_dir.dir.realpathAlloc(allocator, "test-results.xml");
       defer allocator.free(test_file_path);
       
       try tmp_dir.dir.writeFile("test-results.xml", "<results><test>passed</test></results>");
       
       const upload_step = Step{
           .name = "Upload test results",
           .uses = "actions/upload-artifact@v3",
           .with = blk: {
               var with_params = std.StringHashMap([]const u8).init(allocator);
               try with_params.put("name", "test-results");
               try with_params.put("path", "test-results.xml");
               break :blk with_params;
           },
       };
       defer upload_step.with.deinit();
       
       const result = try executor.executeStep(allocator, upload_step, test_context);
       defer result.deinit(allocator);
       
       try testing.expectEqual(StepResult.StepStatus.completed, result.status);
       
       // Verify artifact was uploaded
       const artifacts = try artifact_storage.getJobArtifacts(allocator, job_id);
       defer allocator.free(artifacts);
       
       try testing.expectEqual(@as(usize, 1), artifacts.len);
       try testing.expectEqualStrings("test-results", artifacts[0].name);
       try testing.expect(artifacts[0].size > 0);
   }
   ```

2. **Implement artifact upload/download system**
3. **Add artifact metadata and indexing**
4. **Test artifact retention and cleanup**

</phase_6>

<phase_7>
<title>Phase 7: Performance Optimization and Monitoring (TDD)</title>

1. **Write tests for performance characteristics**
2. **Implement resource usage monitoring**
3. **Add job execution metrics and analytics**
4. **Test high-load scenarios and optimization**

</phase_7>

</implementation_steps>

</detailed_specifications>

<quality_assurance>

<testing_requirements>

- **Container Integration**: Real Docker/container runtime for isolation testing
- **Process Management**: Command execution, timeouts, resource limits
- **Security Testing**: Secret handling, isolation, privilege escalation prevention
- **Performance Testing**: Large job execution, resource usage, parallel steps
- **Logging Testing**: Real-time streaming, log persistence, search functionality
- **Integration Testing**: End-to-end workflow execution with all components

</testing_requirements>

<success_criteria>

1. **All tests pass**: Complete job execution functionality with zero failures
2. **GitHub compatibility**: Execute 95%+ of GitHub Actions workflows correctly
3. **Performance**: Fast step execution, efficient resource usage, parallel processing
4. **Security**: Secure secret handling, proper isolation, no privilege escalation
5. **Reliability**: 99.9% successful job completion, proper error handling
6. **Observability**: Real-time logging, metrics, resource monitoring
7. **Production ready**: Resource limits, cleanup, graceful shutdown, error recovery

</success_criteria>

</quality_assurance>

<reference_implementations>

- **GitHub Actions Runner**: Official runner implementation and protocols
- **act**: Local GitHub Actions runner for testing
- **GitLab Runner**: Job execution and container management patterns
- **Jenkins Pipeline**: Step execution and artifact management
- **Tekton Pipelines**: Container-based CI/CD execution patterns

</reference_implementations>