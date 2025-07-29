# Actions: Core Data Models & Database Schema

<task_definition>
Implement the foundational data models and database schema for a GitHub Actions-compatible CI/CD system. This includes workflow definitions, job configurations, runner management, execution tracking, and comprehensive audit logging with enterprise-grade performance and reliability for the Plue git hosting platform.
</task_definition>

<context_and_constraints>

<technical_requirements>

- **Language/Framework**: Zig with PostgreSQL - https://ziglang.org/documentation/master/
- **Dependencies**: Database connection pool, JSON parsing, UUID generation
- **Location**: `src/actions/models.zig`, `migrations/actions/`
- **Database**: PostgreSQL with proper indexing, constraints, and performance optimization
- **Schema**: GitHub Actions-compatible workflow and job structure
- **Performance**: Efficient queries for high-throughput CI/CD operations
- **Reliability**: ACID transactions, data integrity, audit trails

</technical_requirements>

<business_context>

GitHub Actions data models enable:

- **Workflow Management**: YAML workflow definitions with triggers and jobs
- **Job Execution**: Parallel job execution with dependency management
- **Runner Infrastructure**: Self-hosted and cloud runner management
- **Execution Tracking**: Real-time status updates and detailed logging
- **Security**: Secret management, permission controls, audit compliance
- **Scalability**: Support for thousands of concurrent workflows and jobs
- **Monitoring**: Performance metrics, failure analysis, resource utilization

This provides the data foundation for a complete CI/CD platform comparable to GitHub Actions.

</business_context>

</context_and_constraints>

<detailed_specifications>

<input>

GitHub Actions data structure requirements:

1. **Workflow Structure**:
   ```yaml
   name: CI
   on:
     push:
       branches: [ main ]
     pull_request:
       branches: [ main ]
   
   jobs:
     test:
       runs-on: ubuntu-latest
       steps:
         - uses: actions/checkout@v3
         - name: Run tests
           run: npm test
   ```

2. **Core Entity Relationships**:
   ```
   Repository -> Workflows -> Workflow Runs -> Jobs -> Job Steps
   Runners -> Job Assignments -> Job Executions
   Users -> Workflow Triggers -> Audit Logs
   Secrets -> Workflow Context -> Job Environment
   ```

3. **Execution States**:
   - Workflow Run: `queued`, `in_progress`, `completed`, `cancelled`
   - Job: `pending`, `queued`, `in_progress`, `completed`, `cancelled`, `failed`
   - Step: `pending`, `in_progress`, `completed`, `skipped`, `failed`

4. **Trigger Events**:
   ```zig
   const TriggerEvent = union(enum) {
       push: struct {
           branches: []const []const u8,
           tags: []const []const u8,
           paths: []const []const u8,
       },
       pull_request: struct {
           types: []const []const u8, // opened, closed, etc.
           branches: []const []const u8,
       },
       schedule: struct {
           cron: []const u8,
       },
       workflow_dispatch: struct {
           inputs: std.StringHashMap(WorkflowInput),
       },
   };
   ```

Expected database operations:
```zig
// Create workflow run
const run_id = try db.createWorkflowRun(allocator, .{
    .repository_id = repo_id,
    .workflow_id = workflow_id,
    .trigger_event = .push,
    .commit_sha = "abc123",
    .branch = "main",
});

// Queue jobs for execution
const jobs = try db.getWorkflowJobs(allocator, workflow_id);
for (jobs) |job| {
    try db.queueJob(allocator, run_id, job.id, runner_requirements);
}

// Update job status
try db.updateJobStatus(allocator, job_id, .in_progress, runner_id);
```

</input>

<expected_output>

Complete Actions data layer providing:

1. **Database Schema**: Comprehensive PostgreSQL schema with proper indexing
2. **Zig Data Models**: Type-safe structs for all Actions entities
3. **Database Access Layer**: High-performance queries with connection pooling
4. **Workflow Management**: YAML parsing and workflow definition storage
5. **Job Queuing**: Efficient job queue with priority and dependency handling
6. **Runner Management**: Runner registration, capability matching, load balancing
7. **Execution Tracking**: Real-time status updates and progress monitoring
8. **Audit Logging**: Comprehensive audit trail for compliance and debugging
9. **Secret Management**: Encrypted secret storage with access controls

Core data model structure:
```zig
// Workflow definition from YAML
const Workflow = struct {
    id: u32,
    repository_id: u32,
    name: []const u8,
    filename: []const u8, // .github/workflows/ci.yml
    yaml_content: []const u8,
    triggers: []const TriggerEvent,
    jobs: std.StringHashMap(Job),
    created_at: i64,
    updated_at: i64,
    
    pub fn deinit(self: *Workflow, allocator: std.mem.Allocator) void;
    pub fn parseFromYaml(allocator: std.mem.Allocator, yaml_content: []const u8) !Workflow;
};

// Individual job within a workflow
const Job = struct {
    id: []const u8, // Job name from YAML
    name: ?[]const u8,
    runs_on: []const u8, // Runner requirements
    needs: []const []const u8, // Job dependencies
    if_condition: ?[]const u8,
    strategy: ?JobStrategy,
    steps: []const JobStep,
    timeout_minutes: u32,
    environment: std.StringHashMap([]const u8),
};

// Runtime execution of a workflow
const WorkflowRun = struct {
    id: u32,
    repository_id: u32,
    workflow_id: u32,
    run_number: u32,
    status: RunStatus,
    trigger_event: TriggerEvent,
    commit_sha: []const u8,
    branch: []const u8,
    actor_id: u32,
    started_at: ?i64,
    completed_at: ?i64,
    conclusion: ?RunConclusion,
    
    pub const RunStatus = enum {
        queued,
        in_progress,
        completed,
        cancelled,
    };
    
    pub const RunConclusion = enum {
        success,
        failure,
        cancelled,
        timed_out,
    };
};

// Individual job execution
const JobExecution = struct {
    id: u32,
    workflow_run_id: u32,
    job_id: []const u8,
    runner_id: ?u32,
    status: JobStatus,
    started_at: ?i64,
    completed_at: ?i64,
    conclusion: ?JobConclusion,
    logs: []const u8,
    
    pub const JobStatus = enum {
        pending,
        queued,
        in_progress,
        completed,
        cancelled,
        failed,
    };
};

// CI/CD runner registration
const Runner = struct {
    id: u32,
    name: []const u8,
    labels: []const []const u8,
    repository_id: ?u32, // null for organization-wide
    organization_id: ?u32,
    status: RunnerStatus,
    last_seen: i64,
    capabilities: RunnerCapabilities,
    
    pub const RunnerStatus = enum {
        online,
        offline,
        busy,
    };
};
```

</expected_output>

<implementation_steps>

**CRITICAL**: Follow TDD approach. Use real PostgreSQL database. Run `zig build && zig build test` after EVERY change.

**CRITICAL**: Zero tolerance for test failures. Any failing tests indicate YOU caused a regression.

<phase_1>
<title>Phase 1: Database Schema and Migration Framework (TDD)</title>

1. **Create Actions module structure**
   ```bash
   mkdir -p src/actions
   mkdir -p migrations/actions
   touch src/actions/models.zig
   touch migrations/actions/001_initial_schema.sql
   ```

2. **Write tests for database schema**
   ```zig
   test "creates Actions database schema" {
       const allocator = testing.allocator;
       
       var db = try DatabaseConnection.init(allocator, test_db_config);
       defer db.deinit(allocator);
       
       // Apply migrations
       try db.applyMigration(allocator, "migrations/actions/001_initial_schema.sql");
       
       // Verify tables exist
       const tables = try db.getTables(allocator, "actions_%");
       defer allocator.free(tables);
       
       const expected_tables = [_][]const u8{
           "actions_workflows",
           "actions_workflow_runs", 
           "actions_jobs",
           "actions_job_executions",
           "actions_runners",
           "actions_secrets",
       };
       
       for (expected_tables) |table_name| {
           var found = false;
           for (tables) |table| {
               if (std.mem.eql(u8, table.name, table_name)) {
                   found = true;
                   break;
               }
           }
           try testing.expect(found);
       }
   }
   
   test "database schema has proper indexes for performance" {
       // Test that critical indexes exist for query performance
   }
   ```

3. **Create comprehensive PostgreSQL schema**
4. **Add proper indexes and constraints**
5. **Test schema creation and validation**

</phase_1>

<phase_2>
<title>Phase 2: Core Data Model Types (TDD)</title>

1. **Write tests for workflow data models**
   ```zig
   test "Workflow parses from YAML correctly" {
       const allocator = testing.allocator;
       
       const yaml_content = 
           \\name: CI
           \\on:
           \\  push:
           \\    branches: [main]
           \\jobs:
           \\  test:
           \\    runs-on: ubuntu-latest
           \\    steps:
           \\      - uses: actions/checkout@v3
           \\      - run: npm test
       ;
       
       const workflow = try Workflow.parseFromYaml(allocator, yaml_content);
       defer workflow.deinit(allocator);
       
       try testing.expectEqualStrings("CI", workflow.name);
       try testing.expect(workflow.triggers.len == 1);
       try testing.expect(workflow.jobs.contains("test"));
       
       const test_job = workflow.jobs.get("test").?;
       try testing.expectEqualStrings("ubuntu-latest", test_job.runs_on);
       try testing.expectEqual(@as(usize, 2), test_job.steps.len);
   }
   
   test "WorkflowRun tracks execution state correctly" {
       const allocator = testing.allocator;
       
       var run = WorkflowRun{
           .id = 1,
           .repository_id = 123,
           .workflow_id = 456,
           .run_number = 1,
           .status = .queued,
           .trigger_event = .{ .push = .{ .branches = &.{"main"}, .tags = &.{}, .paths = &.{} } },
           .commit_sha = "abc123def456",
           .branch = "main",
           .actor_id = 789,
           .started_at = null,
           .completed_at = null,
           .conclusion = null,
       };
       
       // Test state transitions
       try testing.expectEqual(WorkflowRun.RunStatus.queued, run.status);
       
       run.status = .in_progress;
       run.started_at = std.time.timestamp();
       
       try testing.expectEqual(WorkflowRun.RunStatus.in_progress, run.status);
       try testing.expect(run.started_at != null);
   }
   ```

2. **Implement core data model structs**
3. **Add YAML parsing for workflow definitions**
4. **Test data model validation and constraints**

</phase_2>

<phase_3>
<title>Phase 3: Database Access Layer (TDD)</title>

1. **Write tests for database operations**
   ```zig
   test "stores and retrieves workflows from database" {
       const allocator = testing.allocator;
       
       var db = try DatabaseConnection.init(allocator, test_db_config);
       defer db.deinit(allocator);
       
       // Create test repository
       const repo_id = try createTestRepository(&db, allocator, .{});
       defer _ = db.deleteRepository(allocator, repo_id) catch {};
       
       const workflow_yaml = 
           \\name: Test Workflow
           \\on: [push]
           \\jobs:
           \\  test:
           \\    runs-on: ubuntu-latest
           \\    steps:
           \\      - run: echo "Hello"
       ;
       
       // Store workflow
       const workflow_id = try db.createWorkflow(allocator, .{
           .repository_id = repo_id,
           .name = "Test Workflow",
           .filename = ".github/workflows/test.yml",
           .yaml_content = workflow_yaml,
       });
       defer _ = db.deleteWorkflow(allocator, workflow_id) catch {};
       
       // Retrieve workflow
       const retrieved = try db.getWorkflow(allocator, workflow_id);
       defer retrieved.deinit(allocator);
       
       try testing.expectEqualStrings("Test Workflow", retrieved.name);
       try testing.expectEqualStrings(".github/workflows/test.yml", retrieved.filename);
       try testing.expectEqual(repo_id, retrieved.repository_id);
   }
   
   test "creates workflow runs with proper sequencing" {
       const allocator = testing.allocator;
       
       var db = try DatabaseConnection.init(allocator, test_db_config);
       defer db.deinit(allocator);
       
       const repo_id = try createTestRepository(&db, allocator, .{});
       defer _ = db.deleteRepository(allocator, repo_id) catch {};
       
       const workflow_id = try createTestWorkflow(&db, allocator, repo_id);
       defer _ = db.deleteWorkflow(allocator, workflow_id) catch {};
       
       // Create multiple workflow runs
       const run1_id = try db.createWorkflowRun(allocator, .{
           .repository_id = repo_id,
           .workflow_id = workflow_id,
           .trigger_event = .{ .push = .{ .branches = &.{"main"}, .tags = &.{}, .paths = &.{} } },
           .commit_sha = "abc123",
           .branch = "main",
           .actor_id = 1,
       });
       
       const run2_id = try db.createWorkflowRun(allocator, .{
           .repository_id = repo_id,
           .workflow_id = workflow_id,
           .trigger_event = .{ .push = .{ .branches = &.{"main"}, .tags = &.{}, .paths = &.{} } },
           .commit_sha = "def456",
           .branch = "main",
           .actor_id = 1,
       });
       
       const run1 = try db.getWorkflowRun(allocator, run1_id);
       const run2 = try db.getWorkflowRun(allocator, run2_id);
       
       // Run numbers should be sequential
       try testing.expectEqual(@as(u32, 1), run1.run_number);
       try testing.expectEqual(@as(u32, 2), run2.run_number);
   }
   ```

2. **Implement database access layer functions**
3. **Add workflow run sequencing and numbering**
4. **Test concurrent access and data consistency**

</phase_3>

<phase_4>
<title>Phase 4: Job Management and Queuing (TDD)</title>

1. **Write tests for job operations**
   ```zig
   test "queues jobs from workflow definition" {
       const allocator = testing.allocator;
       
       var db = try DatabaseConnection.init(allocator, test_db_config);
       defer db.deinit(allocator);
       
       // Create workflow with multiple jobs
       const workflow_yaml = 
           \\jobs:
           \\  build:
           \\    runs-on: ubuntu-latest
           \\    steps:
           \\      - run: make build
           \\  test:
           \\    runs-on: ubuntu-latest
           \\    needs: [build]
           \\    steps:
           \\      - run: make test
       ;
       
       const workflow = try Workflow.parseFromYaml(allocator, workflow_yaml);
       defer workflow.deinit(allocator);
       
       const run_id = try createTestWorkflowRun(&db, allocator);
       
       // Queue jobs for execution
       try db.queueWorkflowJobs(allocator, run_id, &workflow);
       
       const queued_jobs = try db.getQueuedJobs(allocator, run_id);
       defer allocator.free(queued_jobs);
       
       try testing.expectEqual(@as(usize, 2), queued_jobs.len);
       
       // Build job should be queued immediately (no dependencies)
       // Test job should be pending (waiting for build)
       var build_queued = false;
       var test_pending = false;
       
       for (queued_jobs) |job| {
           if (std.mem.eql(u8, job.job_id, "build")) {
               try testing.expectEqual(JobExecution.JobStatus.queued, job.status);
               build_queued = true;
           } else if (std.mem.eql(u8, job.job_id, "test")) {
               try testing.expectEqual(JobExecution.JobStatus.pending, job.status);
               test_pending = true;
           }
       }
       
       try testing.expect(build_queued and test_pending);
   }
   
   test "handles job dependency resolution" {
       // Test complex job dependency chains
   }
   ```

2. **Implement job queuing with dependency resolution**
3. **Add job priority and scheduling logic**
4. **Test job state transitions and error handling**

</phase_4>

<phase_5>
<title>Phase 5: Runner Management (TDD)</title>

1. **Write tests for runner operations**
   ```zig
   test "registers and manages runners" {
       const allocator = testing.allocator;
       
       var db = try DatabaseConnection.init(allocator, test_db_config);
       defer db.deinit(allocator);
       
       const repo_id = try createTestRepository(&db, allocator, .{});
       defer _ = db.deleteRepository(allocator, repo_id) catch {};
       
       // Register a runner
       const runner_id = try db.registerRunner(allocator, .{
           .name = "test-runner-1",
           .labels = &.{ "ubuntu-latest", "x64" },
           .repository_id = repo_id,
           .capabilities = .{
               .max_parallel_jobs = 2,
               .supported_architectures = &.{"x64"},
               .docker_enabled = true,
           },
       });
       defer _ = db.unregisterRunner(allocator, runner_id) catch {};
       
       // Verify runner registration
       const runner = try db.getRunner(allocator, runner_id);
       try testing.expectEqualStrings("test-runner-1", runner.name);
       try testing.expectEqual(Runner.RunnerStatus.offline, runner.status);
       
       // Update runner status
       try db.updateRunnerStatus(allocator, runner_id, .online);
       
       const updated_runner = try db.getRunner(allocator, runner_id);
       try testing.expectEqual(Runner.RunnerStatus.online, updated_runner.status);
   }
   
   test "matches jobs to appropriate runners" {
       // Test runner capability matching for job assignment
   }
   ```

2. **Implement runner registration and management**
3. **Add runner capability matching for job assignment**
4. **Test runner load balancing and availability**

</phase_5>

<phase_6>
<title>Phase 6: Secrets Management (TDD)</title>

1. **Write tests for secrets operations**
2. **Implement encrypted secret storage**
3. **Add secret access controls and audit logging**
4. **Test secret injection into job environments**

</phase_6>

<phase_7>
<title>Phase 7: Audit Logging and Performance Optimization (TDD)</title>

1. **Write tests for audit logging**
2. **Implement comprehensive audit trails**
3. **Add query optimization and indexing**
4. **Test performance with large datasets**

</phase_7>

</implementation_steps>

</detailed_specifications>

<quality_assurance>

<testing_requirements>

- **Database Integration**: All tests use real PostgreSQL with proper cleanup
- **YAML Parsing**: Test complex workflow definitions and edge cases
- **Concurrency**: Test concurrent workflow runs and job executions
- **Performance**: Large-scale testing with thousands of workflows and jobs
- **Data Integrity**: ACID transactions and constraint validation
- **Security**: Secret encryption and access control testing

</testing_requirements>

<success_criteria>

1. **All tests pass**: Complete database and model functionality
2. **Performance**: Handle thousands of concurrent workflows and jobs
3. **Data integrity**: ACID compliance with proper constraints
4. **GitHub compatibility**: Support GitHub Actions YAML syntax
5. **Security**: Encrypted secrets with proper access controls
6. **Scalability**: Efficient queries and indexing for production workloads
7. **Audit compliance**: Comprehensive audit trails for all operations

</success_criteria>

</quality_assurance>

<reference_implementations>

- **GitHub Actions**: Official workflow syntax and execution model
- **GitLab CI**: Pipeline and job execution patterns
- **Jenkins**: Build system and job queue management
- **Tekton**: Cloud-native CI/CD pipeline specifications

</reference_implementations>