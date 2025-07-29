# Actions: Runner Task Dispatching

<task_definition>
Implement a high-performance task dispatching system that assigns GitHub Actions jobs to appropriate runners based on capabilities, load balancing, and availability. This system will handle job queuing, runner selection, task assignment, and execution monitoring with enterprise-grade reliability and performance for the Plue CI/CD platform.
</task_definition>

<context_and_constraints>

<technical_requirements>

- **Language/Framework**: Zig with PostgreSQL - https://ziglang.org/documentation/master/
- **Dependencies**: Actions data models (#25), Workflow parsing (#26), Database connection pool
- **Location**: `src/actions/dispatcher.zig`, `src/actions/scheduler.zig`
- **Performance**: Sub-second job assignment with high throughput
- **Reliability**: Fault tolerance, job recovery, graceful degradation
- **Scalability**: Support thousands of concurrent jobs and hundreds of runners
- **Monitoring**: Real-time metrics, queue depth, runner utilization

</technical_requirements>

<business_context>

Runner task dispatching enables:

- **Efficient Resource Utilization**: Optimal assignment of jobs to available runners
- **Load Balancing**: Even distribution of workload across runner fleet
- **Capability Matching**: Precise matching of job requirements to runner capabilities
- **Queue Management**: Fair scheduling with priority and dependency handling
- **Fault Tolerance**: Automatic job rescheduling on runner failures
- **Performance Optimization**: Minimize job wait times and maximize throughput
- **Cost Management**: Efficient use of compute resources and auto-scaling
- **Enterprise Features**: Multi-tenancy, resource quotas, SLA compliance

This provides the intelligent orchestration layer that ensures CI/CD jobs run efficiently and reliably.

</business_context>

</context_and_constraints>

<detailed_specifications>

<input>

Task dispatching requirements:

1. **Job Queue Management**:
   ```zig
   // Job enters queue after workflow parsing
   const queued_job = QueuedJob{
       .id = job_execution_id,
       .workflow_run_id = run_id,
       .job_definition = parsed_job,
       .priority = .normal,
       .requirements = RunnerRequirements{
           .labels = &.{"ubuntu-latest"},
           .architecture = "x64",
           .min_memory_gb = 2,
           .requires_docker = true,
       },
       .queued_at = std.time.timestamp(),
       .timeout_minutes = 360,
   };
   
   try dispatcher.enqueueJob(allocator, queued_job);
   ```

2. **Runner Capability Matching**:
   ```zig
   const runner_capabilities = RunnerCapabilities{
       .labels = &.{"ubuntu-latest", "self-hosted", "x64", "large"},
       .architecture = "x64",
       .memory_gb = 8,
       .cpu_cores = 4,
       .docker_enabled = true,
       .max_parallel_jobs = 2,
       .current_jobs = 1,
   };
   
   const job_requirements = RunnerRequirements{
       .labels = &.{"ubuntu-latest"},
       .architecture = "x64",
       .min_memory_gb = 2,
       .requires_docker = true,
   };
   
   const is_compatible = runner_capabilities.canRunJob(job_requirements);
   ```

3. **Dispatching Logic**:
   - Priority-based scheduling (critical, high, normal, low)
   - Capability-based runner selection
   - Load balancing across available runners
   - Job dependency handling
   - Runner affinity and anti-affinity
   - Timeout and retry handling

4. **Expected Integration**:
   ```zig
   // Initialize dispatcher
   var dispatcher = try JobDispatcher.init(allocator, .{
       .db = &database,
       .scheduler = &job_scheduler,
       .metrics = &metrics_collector,
   });
   defer dispatcher.deinit(allocator);
   
   // Start background dispatch loop
   try dispatcher.start(allocator);
   
   // Enqueue job from workflow execution
   try dispatcher.enqueueJob(allocator, queued_job);
   
   // Runner polls for work
   const assigned_job = try dispatcher.pollForJob(allocator, runner_id, capabilities);
   ```

</input>

<expected_output>

Complete task dispatching system providing:

1. **Job Queue Manager**: Multi-priority job queuing with dependency handling
2. **Runner Registry**: Dynamic runner registration and capability tracking
3. **Matching Engine**: Intelligent job-to-runner assignment algorithm
4. **Load Balancer**: Even distribution of jobs across runner fleet
5. **Fault Recovery**: Automatic job rescheduling on runner failures
6. **Performance Optimization**: Minimize job wait times and maximize throughput
7. **Monitoring System**: Real-time metrics and queue analytics
8. **Resource Management**: Runner resource tracking and utilization optimization

Core dispatcher architecture:
```zig
const JobDispatcher = struct {
    db: *DatabaseConnection,
    scheduler: *JobScheduler,
    runner_registry: *RunnerRegistry,
    job_queue: *JobQueue,
    metrics: *MetricsCollector,
    config: DispatcherConfig,
    
    pub fn init(allocator: std.mem.Allocator, config: DispatcherConfig) !JobDispatcher;
    pub fn deinit(self: *JobDispatcher, allocator: std.mem.Allocator) void;
    
    // Lifecycle management
    pub fn start(self: *JobDispatcher, allocator: std.mem.Allocator) !void;
    pub fn stop(self: *JobDispatcher, allocator: std.mem.Allocator) !void;
    
    // Job management
    pub fn enqueueJob(self: *JobDispatcher, allocator: std.mem.Allocator, job: QueuedJob) !void;
    pub fn cancelJob(self: *JobDispatcher, allocator: std.mem.Allocator, job_id: u32) !void;
    pub fn requeueJob(self: *JobDispatcher, allocator: std.mem.Allocator, job_id: u32, reason: RequeueReason) !void;
    
    // Runner interaction
    pub fn pollForJob(self: *JobDispatcher, allocator: std.mem.Allocator, runner_id: u32, capabilities: RunnerCapabilities) !?AssignedJob;
    pub fn updateJobStatus(self: *JobDispatcher, allocator: std.mem.Allocator, job_id: u32, status: JobStatus) !void;
    pub fn completeJob(self: *JobDispatcher, allocator: std.mem.Allocator, job_id: u32, result: JobResult) !void;
    
    // Queue management
    pub fn getQueueDepth(self: *JobDispatcher, allocator: std.mem.Allocator) !QueueMetrics;
    pub fn getWaitingJobs(self: *JobDispatcher, allocator: std.mem.Allocator, limit: u32) ![]QueuedJob;
    pub fn getRunnerUtilization(self: *JobDispatcher, allocator: std.mem.Allocator) ![]RunnerUtilization;
};

const JobQueue = struct {
    priority_queues: [4]Queue(QueuedJob), // critical, high, normal, low
    dependency_tracker: DependencyTracker,
    
    pub fn enqueue(self: *JobQueue, allocator: std.mem.Allocator, job: QueuedJob) !void;
    pub fn dequeue(self: *JobQueue, allocator: std.mem.Allocator, requirements: RunnerRequirements) !?QueuedJob;
    pub fn peek(self: *JobQueue, allocator: std.mem.Allocator, count: u32) ![]QueuedJob;
    pub fn remove(self: *JobQueue, allocator: std.mem.Allocator, job_id: u32) !void;
};

const RunnerRegistry = struct {
    runners: std.HashMap(u32, RegisteredRunner),
    capability_index: CapabilityIndex,
    
    pub fn registerRunner(self: *RunnerRegistry, allocator: std.mem.Allocator, runner: Runner) !void;
    pub fn unregisterRunner(self: *RunnerRegistry, allocator: std.mem.Allocator, runner_id: u32) !void;
    pub fn updateCapabilities(self: *RunnerRegistry, allocator: std.mem.Allocator, runner_id: u32, capabilities: RunnerCapabilities) !void;
    pub fn findCompatibleRunners(self: *RunnerRegistry, allocator: std.mem.Allocator, requirements: RunnerRequirements) ![]u32;
    pub fn selectBestRunner(self: *RunnerRegistry, allocator: std.mem.Allocator, candidates: []u32, selection_policy: SelectionPolicy) !u32;
};

const JobScheduler = struct {
    pub fn scheduleJob(self: *JobScheduler, allocator: std.mem.Allocator, job: QueuedJob, available_runners: []u32) !SchedulingDecision;
    pub fn rescheduleJob(self: *JobScheduler, allocator: std.mem.Allocator, job_id: u32, reason: RescheduleReason) !void;
    pub fn optimizeSchedule(self: *JobScheduler, allocator: std.mem.Allocator) !ScheduleOptimization;
};
```

</expected_output>

<implementation_steps>

**CRITICAL**: Follow TDD approach. Use real database and queue operations. Run `zig build && zig build test` after EVERY change.

**CRITICAL**: Zero tolerance for test failures. Any failing tests indicate YOU caused a regression.

<phase_1>
<title>Phase 1: Job Queue Foundation (TDD)</title>

1. **Create dispatcher module structure**
   ```bash
   mkdir -p src/actions
   touch src/actions/dispatcher.zig
   touch src/actions/scheduler.zig
   touch src/actions/queue.zig
   ```

2. **Write tests for job queue operations**
   ```zig
   test "job queue handles priority-based ordering" {
       const allocator = testing.allocator;
       
       var job_queue = try JobQueue.init(allocator);
       defer job_queue.deinit(allocator);
       
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
       try job_queue.enqueue(allocator, normal_job);
       try job_queue.enqueue(allocator, high_job);
       try job_queue.enqueue(allocator, critical_job);
       
       // Dequeue should return critical first
       const first_job = try job_queue.dequeue(allocator, test_requirements);
       try testing.expect(first_job != null);
       try testing.expectEqual(@as(u32, 3), first_job.?.id);
       try testing.expectEqual(JobPriority.critical, first_job.?.priority);
       
       // Then high priority
       const second_job = try job_queue.dequeue(allocator, test_requirements);
       try testing.expect(second_job != null);
       try testing.expectEqual(@as(u32, 2), second_job.?.id);
       
       // Finally normal priority
       const third_job = try job_queue.dequeue(allocator, test_requirements);
       try testing.expect(third_job != null);
       try testing.expectEqual(@as(u32, 1), third_job.?.id);
   }
   
   test "job queue respects dependency constraints" {
       const allocator = testing.allocator;
       
       var job_queue = try JobQueue.init(allocator);
       defer job_queue.deinit(allocator);
       
       // Job B depends on Job A
       const job_a = QueuedJob{
           .id = 1,
           .job_id = "build",
           .dependencies = &.{},
           .requirements = test_requirements,
       };
       
       const job_b = QueuedJob{
           .id = 2,
           .job_id = "test",
           .dependencies = &.{"build"},
           .requirements = test_requirements,
       };
       
       try job_queue.enqueue(allocator, job_b);
       try job_queue.enqueue(allocator, job_a);
       
       // Should dequeue job A first (no dependencies)
       const first_job = try job_queue.dequeue(allocator, test_requirements);
       try testing.expectEqual(@as(u32, 1), first_job.?.id);
       
       // Job B should still be waiting (dependency not satisfied)
       const second_job = try job_queue.dequeue(allocator, test_requirements);
       try testing.expect(second_job == null);
       
       // Mark job A as completed
       try job_queue.markJobCompleted(allocator, 1, "build");
       
       // Now job B should be available
       const third_job = try job_queue.dequeue(allocator, test_requirements);
       try testing.expectEqual(@as(u32, 2), third_job.?.id);
   }
   ```

3. **Implement priority-based job queue**
4. **Add dependency tracking and resolution**
5. **Test queue operations and edge cases**

</phase_1>

<phase_2>
<title>Phase 2: Runner Registry and Capability Matching (TDD)</title>

1. **Write tests for runner registry**
   ```zig
   test "runner registry tracks capabilities and availability" {
       const allocator = testing.allocator;
       
       var registry = try RunnerRegistry.init(allocator);
       defer registry.deinit(allocator);
       
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
       try registry.registerRunner(allocator, .{
           .id = 123,
           .name = "test-runner-1",
           .status = .online,
           .capabilities = runner_capabilities,
       });
       
       // Test capability matching
       const job_requirements = RunnerRequirements{
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
       defer registry.deinit(allocator);
       
       // Register busy runner (at capacity)
       const busy_capabilities = RunnerCapabilities{
           .labels = &.{"ubuntu-latest"},
           .max_parallel_jobs = 1,
           .current_jobs = 1, // At capacity
       };
       
       try registry.registerRunner(allocator, .{
           .id = 1,
           .status = .busy,
           .capabilities = busy_capabilities,
       });
       
       // Register available runner
       const available_capabilities = RunnerCapabilities{
           .labels = &.{"ubuntu-latest"},
           .max_parallel_jobs = 2,
           .current_jobs = 0, // Available
       };
       
       try registry.registerRunner(allocator, .{
           .id = 2,
           .status = .online,
           .capabilities = available_capabilities,
       });
       
       const job_requirements = RunnerRequirements{
           .labels = &.{"ubuntu-latest"},
       };
       
       const available_runners = try registry.findCompatibleRunners(allocator, job_requirements);
       defer allocator.free(available_runners);
       
       // Should only return the available runner
       try testing.expectEqual(@as(usize, 1), available_runners.len);
       try testing.expectEqual(@as(u32, 2), available_runners[0]);
   }
   ```

2. **Implement runner registry with capability indexing**
3. **Add efficient capability matching algorithms**
4. **Test complex runner selection scenarios**

</phase_2>

<phase_3>
<title>Phase 3: Job Assignment and Load Balancing (TDD)</title>

1. **Write tests for job assignment**
   ```zig
   test "dispatcher assigns jobs to best available runners" {
       const allocator = testing.allocator;
       
       var db = try DatabaseConnection.init(allocator, test_db_config);
       defer db.deinit(allocator);
       
       var dispatcher = try JobDispatcher.init(allocator, .{
           .db = &db,
           .selection_policy = .least_loaded,
       });
       defer dispatcher.deinit(allocator);
       
       // Register runners with different load levels
       try dispatcher.registerRunner(allocator, .{
           .id = 1,
           .capabilities = .{
               .labels = &.{"ubuntu-latest"},
               .max_parallel_jobs = 4,
               .current_jobs = 3, // High load
           },
       });
       
       try dispatcher.registerRunner(allocator, .{
           .id = 2,
           .capabilities = .{
               .labels = &.{"ubuntu-latest"},
               .max_parallel_jobs = 4,
               .current_jobs = 1, // Low load
           },
       });
       
       const job = QueuedJob{
           .id = 100,
           .requirements = .{
               .labels = &.{"ubuntu-latest"},
           },
       };
       
       try dispatcher.enqueueJob(allocator, job);
       
       // Simulate runner polling
       const assignment1 = try dispatcher.pollForJob(allocator, 1, runner1_capabilities);
       const assignment2 = try dispatcher.pollForJob(allocator, 2, runner2_capabilities);
       
       // Job should be assigned to less loaded runner (runner 2)
       try testing.expect(assignment1 == null);
       try testing.expect(assignment2 != null);
       try testing.expectEqual(@as(u32, 100), assignment2.?.job_id);
   }
   
   test "dispatcher handles job failures and rescheduling" {
       const allocator = testing.allocator;
       
       var dispatcher = try JobDispatcher.init(allocator, test_config);
       defer dispatcher.deinit(allocator);
       
       const job = QueuedJob{
           .id = 200,
           .retry_count = 0,
           .max_retries = 2,
       };
       
       try dispatcher.enqueueJob(allocator, job);
       
       // Assign job to runner
       const assignment = try dispatcher.pollForJob(allocator, runner_id, capabilities);
       try testing.expect(assignment != null);
       
       // Simulate job failure
       try dispatcher.updateJobStatus(allocator, 200, .failed);
       
       // Job should be requeued for retry
       const requeued_job = try dispatcher.pollForJob(allocator, runner_id, capabilities);
       try testing.expect(requeued_job != null);
       try testing.expectEqual(@as(u32, 200), requeued_job.?.job_id);
       try testing.expectEqual(@as(u32, 1), requeued_job.?.retry_count);
   }
   ```

2. **Implement job assignment algorithms**
3. **Add load balancing and runner selection policies**
4. **Test job rescheduling and failure handling**

</phase_3>

<phase_4>
<title>Phase 4: Database Integration and Persistence (TDD)</title>

1. **Write tests for database operations**
   ```zig
   test "persists job queue state to database" {
       const allocator = testing.allocator;
       
       var db = try DatabaseConnection.init(allocator, test_db_config);
       defer db.deinit(allocator);
       
       var dispatcher = try JobDispatcher.init(allocator, .{ .db = &db });
       defer dispatcher.deinit(allocator);
       
       const job = QueuedJob{
           .id = 300,
           .workflow_run_id = 1,
           .job_definition = test_job_def,
           .requirements = test_requirements,
           .priority = .high,
       };
       
       try dispatcher.enqueueJob(allocator, job);
       
       // Verify job is persisted
       const queued_jobs = try db.getQueuedJobs(allocator, .{ .limit = 10 });
       defer allocator.free(queued_jobs);
       
       try testing.expectEqual(@as(usize, 1), queued_jobs.len);
       try testing.expectEqual(@as(u32, 300), queued_jobs[0].id);
       try testing.expectEqual(JobPriority.high, queued_jobs[0].priority);
   }
   
   test "recovers from database state on restart" {
       const allocator = testing.allocator;
       
       var db = try DatabaseConnection.init(allocator, test_db_config);
       defer db.deinit(allocator);
       
       // Create jobs in database
       const job1_id = try db.createQueuedJob(allocator, test_job1);
       const job2_id = try db.createQueuedJob(allocator, test_job2);
       
       // Initialize dispatcher (should recover from database)
       var dispatcher = try JobDispatcher.init(allocator, .{ .db = &db });
       defer dispatcher.deinit(allocator);
       
       const queue_metrics = try dispatcher.getQueueDepth(allocator);
       try testing.expectEqual(@as(u32, 2), queue_metrics.total_jobs);
       
       // Jobs should be available for assignment
       const assignment = try dispatcher.pollForJob(allocator, runner_id, capabilities);
       try testing.expect(assignment != null);
   }
   ```

2. **Implement database persistence layer**
3. **Add job state recovery on startup**
4. **Test transactional consistency and error handling**

</phase_4>

<phase_5>
<title>Phase 5: Performance Optimization and Monitoring (TDD)</title>

1. **Write tests for performance characteristics**
   ```zig
   test "dispatcher handles high throughput job assignment" {
       const allocator = testing.allocator;
       
       var dispatcher = try JobDispatcher.init(allocator, test_config);
       defer dispatcher.deinit(allocator);
       
       // Register multiple runners
       for (0..10) |i| {
           try dispatcher.registerRunner(allocator, .{
               .id = @intCast(u32, i),
               .capabilities = standard_capabilities,
           });
       }
       
       // Enqueue many jobs
       const job_count = 1000;
       for (0..job_count) |i| {
           const job = QueuedJob{
               .id = @intCast(u32, i),
               .requirements = standard_requirements,
           };
           try dispatcher.enqueueJob(allocator, job);
       }
       
       // Measure assignment performance
       const start_time = std.time.nanoTimestamp();
       
       var assigned_count: u32 = 0;
       for (0..10) |runner_id| {
           while (true) {
               const assignment = try dispatcher.pollForJob(allocator, @intCast(u32, runner_id), standard_capabilities);
               if (assignment == null) break;
               assigned_count += 1;
           }
       }
       
       const duration = std.time.nanoTimestamp() - start_time;
       const assignments_per_second = (@intToFloat(f64, assigned_count) / @intToFloat(f64, duration)) * std.time.ns_per_s;
       
       try testing.expect(assigned_count == job_count);
       try testing.expect(assignments_per_second > 100.0); // At least 100 assignments/second
   }
   
   test "dispatcher provides accurate queue metrics" {
       const allocator = testing.allocator;
       
       var dispatcher = try JobDispatcher.init(allocator, test_config);
       defer dispatcher.deinit(allocator);
       
       // Add jobs with different priorities
       try dispatcher.enqueueJob(allocator, .{ .priority = .critical });
       try dispatcher.enqueueJob(allocator, .{ .priority = .high });
       try dispatcher.enqueueJob(allocator, .{ .priority = .normal });
       try dispatcher.enqueueJob(allocator, .{ .priority = .low });
       
       const metrics = try dispatcher.getQueueDepth(allocator);
       
       try testing.expectEqual(@as(u32, 4), metrics.total_jobs);
       try testing.expectEqual(@as(u32, 1), metrics.critical_jobs);
       try testing.expectEqual(@as(u32, 1), metrics.high_jobs);
       try testing.expectEqual(@as(u32, 1), metrics.normal_jobs);
       try testing.expectEqual(@as(u32, 1), metrics.low_jobs);
       
       try testing.expect(metrics.oldest_job_age_seconds > 0);
       try testing.expect(metrics.average_wait_time_seconds >= 0);
   }
   ```

2. **Implement performance monitoring and metrics**
3. **Add queue optimization algorithms**
4. **Test scalability with large job volumes**

</phase_5>

<phase_6>
<title>Phase 6: Integration and Production Features (TDD)</title>

1. **Write tests for complete integration**
2. **Implement graceful shutdown and cleanup**
3. **Add comprehensive logging and observability**
4. **Test fault tolerance and recovery scenarios**

</phase_6>

</implementation_steps>

</detailed_specifications>

<quality_assurance>

<testing_requirements>

- **High Throughput**: Test with thousands of jobs and hundreds of runners
- **Concurrency**: Concurrent job assignment, runner registration, status updates
- **Database Integration**: ACID transactions, connection pooling, recovery
- **Performance**: Sub-second job assignment, queue processing efficiency
- **Fault Tolerance**: Runner failures, database outages, network partitions
- **Memory Management**: No memory leaks under sustained load

</testing_requirements>

<success_criteria>

1. **All tests pass**: Complete dispatcher functionality with zero failures
2. **Performance**: Assign jobs in under 100ms, handle 1000+ jobs/minute
3. **Reliability**: 99.9% successful job assignments, automatic failure recovery
4. **Scalability**: Support hundreds of runners and thousands of concurrent jobs
5. **Database consistency**: ACID compliance, proper transaction handling
6. **Monitoring**: Real-time metrics and queue analytics
7. **Production ready**: Graceful shutdown, comprehensive logging, fault tolerance

</success_criteria>

</quality_assurance>

<reference_implementations>

- **Kubernetes Job Queue**: Job scheduling and pod assignment patterns
- **GitHub Actions**: Runner assignment and job distribution
- **Jenkins Build Queue**: Job queuing and executor management
- **Tekton Pipeline**: Task dispatching and resource allocation

</reference_implementations>