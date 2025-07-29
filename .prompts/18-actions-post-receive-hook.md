# Actions: Post-Receive Hook Integration

<task_definition>
Implement a comprehensive Git post-receive hook system that automatically triggers GitHub Actions workflows based on push events, with intelligent workflow selection, event filtering, and seamless integration with the Plue CI/CD platform. This system will provide real-time workflow triggering with proper context injection and enterprise-grade reliability.
</task_definition>

<context_and_constraints>

<technical_requirements>

- **Language/Framework**: Zig with Git integration - https://ziglang.org/documentation/master/
- **Dependencies**: Git command wrapper, Actions workflow parser (#26), Actions dispatcher (#27)
- **Location**: `src/git/hooks.zig`, `src/actions/trigger.zig`
- **Integration**: Git repository hooks, SSH server, HTTP Git server
- **Performance**: Sub-second hook execution, minimal repository access impact
- **Reliability**: Atomic hook execution, failure recovery, audit logging
- **Scalability**: Handle high-frequency push events, batch processing

</technical_requirements>

<business_context>

Post-receive hook integration enables:

- **Automated CI/CD**: Instant workflow triggering on code changes
- **Developer Experience**: Zero-configuration CI/CD activation
- **Event-driven Architecture**: Reactive workflows based on Git events
- **Branch Protection**: Pre-merge validation and quality gates
- **Deployment Automation**: Automatic deployments on main branch pushes
- **Compliance**: Audit trails, policy enforcement, security scanning
- **Team Productivity**: Automated testing, building, and notification systems

This provides the critical bridge between Git operations and CI/CD workflow execution.

</business_context>

</context_and_constraints>

<detailed_specifications>

<input>

Post-receive hook requirements:

1. **Git Hook Integration**:
   ```bash
   #!/bin/bash
   # Git post-receive hook script
   while read oldrev newrev refname; do
       # Call Plue hook handler
       /usr/local/bin/plue-hook-handler \
           --repository-path "$PWD" \
           --old-rev "$oldrev" \
           --new-rev "$newrev" \
           --ref-name "$refname" \
           --user-id "$PLUE_USER_ID"
   done
   ```

2. **Push Event Processing**:
   ```zig
   const PushEvent = struct {
       repository_id: u32,
       repository_path: []const u8,
       user_id: u32,
       before: []const u8, // Old commit SHA
       after: []const u8,  // New commit SHA
       ref: []const u8,    // refs/heads/main
       commits: []const Commit,
       created: bool,      // Branch/tag created
       deleted: bool,      // Branch/tag deleted
       forced: bool,       // Force push
       timestamp: i64,
       
       const Commit = struct {
           id: []const u8,
           message: []const u8,
           author: GitAuthor,
           committer: GitAuthor,
           timestamp: i64,
           added: []const []const u8,    // Added files
           removed: []const []const u8,  // Removed files
           modified: []const []const u8, // Modified files
       };
   };
   ```

3. **Workflow Trigger Matching**:
   ```zig
   // Match push events against workflow triggers
   const trigger_matchers = [_]TriggerMatcher{
       .{
           .event_type = .push,
           .conditions = .{
               .branches = &.{"main", "develop"},
               .paths = &.{"src/**", "!docs/**"},
           },
       },
       .{
           .event_type = .pull_request,
           .conditions = .{
               .types = &.{"opened", "synchronize"},
               .branches = &.{"main"},
           },
       },
   };
   
   const matching_workflows = try WorkflowTrigger.findMatchingWorkflows(
       allocator, 
       push_event, 
       repository_workflows
   );
   ```

4. **Context Injection**:
   ```zig
   const workflow_context = WorkflowContext{
       .github = .{
           .event_name = "push",
           .ref = push_event.ref,
           .sha = push_event.after,
           .repository = repository.full_name,
           .repository_owner = repository.owner.login,
           .actor = push_event.pusher.login,
           .workflow = workflow.name,
           .run_id = workflow_run.id,
           .run_number = workflow_run.run_number,
       },
       .event = push_event,
       .repository = repository,
       .secrets = repository_secrets,
   };
   ```

Expected hook execution flow:
```zig
// Initialize hook handler
var hook_handler = try PostReceiveHook.init(allocator, .{
    .db = &database,
    .workflow_trigger = &workflow_trigger,
    .job_dispatcher = &job_dispatcher,
});
defer hook_handler.deinit(allocator);

// Process push event
const hook_result = try hook_handler.processPushEvent(allocator, push_event);

for (hook_result.triggered_workflows) |workflow_run| {
    log.info("Triggered workflow '{}' for repository '{}', run #{}", .{
        workflow_run.workflow_name,
        workflow_run.repository_name,
        workflow_run.run_number,
    });
}
```

</input>

<expected_output>

Complete post-receive hook system providing:

1. **Hook Handler**: Process Git post-receive events with context extraction
2. **Event Parser**: Parse Git references and commit information
3. **Workflow Matcher**: Match push events against workflow triggers
4. **Context Builder**: Build GitHub Actions-compatible execution context
5. **Batch Processor**: Handle multiple ref updates in single push
6. **Error Recovery**: Robust error handling with retry mechanisms
7. **Audit Logger**: Comprehensive logging of hook execution and workflow triggers
8. **Performance Monitor**: Hook execution timing and repository impact metrics

Core hook architecture:
```zig
const PostReceiveHook = struct {
    db: *DatabaseConnection,
    workflow_trigger: *WorkflowTrigger,
    job_dispatcher: *JobDispatcher,
    git_client: *GitClient,
    config: HookConfig,
    
    pub fn init(allocator: std.mem.Allocator, config: HookConfig) !PostReceiveHook;
    pub fn deinit(self: *PostReceiveHook, allocator: std.mem.Allocator) void;
    
    // Hook processing
    pub fn processPushEvent(self: *PostReceiveHook, allocator: std.mem.Allocator, event: PushEvent) !HookResult;
    pub fn processRefUpdate(self: *PostReceiveHook, allocator: std.mem.Allocator, ref_update: RefUpdate) ![]WorkflowRun;
    
    // Event parsing
    pub fn parseRefUpdates(self: *PostReceiveHook, allocator: std.mem.Allocator, stdin_input: []const u8) ![]RefUpdate;
    pub fn extractCommits(self: *PostReceiveHook, allocator: std.mem.Allocator, old_sha: []const u8, new_sha: []const u8) ![]Commit;
    pub fn detectFileChanges(self: *PostReceiveHook, allocator: std.mem.Allocator, commit_range: []const u8) !FileChanges;
    
    // Workflow triggering
    pub fn findMatchingWorkflows(self: *PostReceiveHook, allocator: std.mem.Allocator, event: PushEvent) ![]Workflow;
    pub fn createWorkflowRuns(self: *PostReceiveHook, allocator: std.mem.Allocator, workflows: []Workflow, context: EventContext) ![]WorkflowRun;
};

const WorkflowTrigger = struct {
    workflow_parser: *WorkflowParser,
    
    pub fn evaluateTrigger(self: *WorkflowTrigger, allocator: std.mem.Allocator, trigger: TriggerConfig, event: PushEvent) !bool;
    pub fn matchBranches(self: *WorkflowTrigger, branches: []const []const u8, ref: []const u8) bool;
    pub fn matchPaths(self: *WorkflowTrigger, paths: []const []const u8, changed_files: []const []const u8) bool;
    pub fn buildExecutionContext(self: *WorkflowTrigger, allocator: std.mem.Allocator, event: PushEvent, workflow: Workflow) !ExecutionContext;
};

const HookResult = struct {
    triggered_workflows: []WorkflowRun,
    skipped_workflows: []SkippedWorkflow,
    execution_time_ms: u64,
    processed_refs: u32,
    processed_commits: u32,
    errors: []HookError,
    
    const WorkflowRun = struct {
        id: u32,
        workflow_name: []const u8,
        repository_name: []const u8,
        run_number: u32,
        trigger_event: []const u8,
        commit_sha: []const u8,
        branch: []const u8,
    };
    
    const SkippedWorkflow = struct {
        workflow_name: []const u8,
        skip_reason: []const u8,
    };
};

const RefUpdate = struct {
    old_sha: []const u8,
    new_sha: []const u8,
    ref_name: []const u8,
    ref_type: RefType,
    
    const RefType = enum {
        branch,
        tag,
        unknown,
        
        pub fn fromRefName(ref_name: []const u8) RefType {
            if (std.mem.startsWith(u8, ref_name, "refs/heads/")) return .branch;
            if (std.mem.startsWith(u8, ref_name, "refs/tags/")) return .tag;
            return .unknown;
        }
    };
};
```

</expected_output>

<implementation_steps>

**CRITICAL**: Follow TDD approach. Use real Git repositories for testing. Run `zig build && zig build test` after EVERY change.

**CRITICAL**: Zero tolerance for test failures. Any failing tests indicate YOU caused a regression.

<phase_1>
<title>Phase 1: Git Hook Handler Foundation (TDD)</title>

1. **Create post-receive hook module structure**
   ```bash
   mkdir -p src/git src/actions
   touch src/git/hooks.zig
   touch src/actions/trigger.zig
   touch src/git/post_receive.zig
   ```

2. **Write tests for hook input parsing**
   ```zig
   test "parses post-receive hook input correctly" {
       const allocator = testing.allocator;
       
       var hook_handler = try PostReceiveHook.init(allocator, test_config);
       defer hook_handler.deinit(allocator);
       
       // Simulate post-receive hook input
       const hook_input = 
           "0000000000000000000000000000000000000000 abc123def456789012345678901234567890abcd refs/heads/main\n" ++
           "def456789012345678901234567890abcdef123456 789abc012def345678901234567890abcdef456789 refs/heads/feature/new-feature\n" ++
           "123456789012345678901234567890abcdef123456 0000000000000000000000000000000000000000 refs/heads/old-branch\n";
       
       const ref_updates = try hook_handler.parseRefUpdates(allocator, hook_input);
       defer allocator.free(ref_updates);
       
       try testing.expectEqual(@as(usize, 3), ref_updates.len);
       
       // First update: new branch creation
       try testing.expectEqualStrings("0000000000000000000000000000000000000000", ref_updates[0].old_sha);
       try testing.expectEqualStrings("abc123def456789012345678901234567890abcd", ref_updates[0].new_sha);
       try testing.expectEqualStrings("refs/heads/main", ref_updates[0].ref_name);
       try testing.expectEqual(RefUpdate.RefType.branch, ref_updates[0].ref_type);
       
       // Second update: branch push
       try testing.expectEqualStrings("def456789012345678901234567890abcdef123456", ref_updates[1].old_sha);
       try testing.expectEqualStrings("789abc012def345678901234567890abcdef456789", ref_updates[1].new_sha);
       try testing.expectEqualStrings("refs/heads/feature/new-feature", ref_updates[1].ref_name);
       
       // Third update: branch deletion
       try testing.expectEqualStrings("123456789012345678901234567890abcdef123456", ref_updates[2].old_sha);
       try testing.expectEqualStrings("0000000000000000000000000000000000000000", ref_updates[2].new_sha);
       try testing.expectEqualStrings("refs/heads/old-branch", ref_updates[2].ref_name);
   }
   
   test "extracts commit information from Git repository" {
       const allocator = testing.allocator;
       
       // Create test Git repository
       var test_repo = try TestRepository.init(allocator);
       defer test_repo.deinit();
       
       // Add test commits
       const commit1_sha = try test_repo.createCommit("Initial commit", &.{"README.md"});
       const commit2_sha = try test_repo.createCommit("Add feature", &.{"src/main.zig", "src/lib.zig"});
       const commit3_sha = try test_repo.createCommit("Fix bug", &.{"src/main.zig"});
       
       var hook_handler = try PostReceiveHook.init(allocator, .{
           .git_client = &test_repo.git_client,
       });
       defer hook_handler.deinit(allocator);
       
       // Extract commits between commit1 and commit3
       const commits = try hook_handler.extractCommits(allocator, commit1_sha, commit3_sha);
       defer allocator.free(commits);
       
       try testing.expectEqual(@as(usize, 2), commits.len);
       
       // Verify commit information
       try testing.expectEqualStrings(commit2_sha, commits[0].id);
       try testing.expectEqualStrings("Add feature", commits[0].message);
       try testing.expectEqual(@as(usize, 2), commits[0].added.len);
       
       try testing.expectEqualStrings(commit3_sha, commits[1].id);
       try testing.expectEqualStrings("Fix bug", commits[1].message);
       try testing.expectEqual(@as(usize, 1), commits[1].modified.len);
   }
   ```

3. **Implement Git hook input parsing**
4. **Add commit extraction and file change detection**
5. **Test edge cases and malformed input handling**

</phase_1>

<phase_2>
<title>Phase 2: Workflow Trigger Matching (TDD)</title>

1. **Write tests for trigger matching**
   ```zig
   test "matches push events against workflow triggers" {
       const allocator = testing.allocator;
       
       var workflow_trigger = try WorkflowTrigger.init(allocator, test_config);
       defer workflow_trigger.deinit(allocator);
       
       // Define workflow with push trigger
       const workflow_yaml = 
           \\name: CI
           \\on:
           \\  push:
           \\    branches: [main, develop]
           \\    paths: ['src/**', '!docs/**']
           \\jobs:
           \\  test:
           \\    runs-on: ubuntu-latest
           \\    steps:
           \\      - run: npm test
       ;
       
       const workflow = try Workflow.parseFromYaml(allocator, workflow_yaml);
       defer workflow.deinit(allocator);
       
       // Test push event that should match
       const matching_event = PushEvent{
           .ref = "refs/heads/main",
           .commits = &.{
               .{
                   .modified = &.{"src/main.js", "src/utils.js"},
                   .added = &.{},
                   .removed = &.{},
               },
           },
       };
       
       const should_trigger = try workflow_trigger.evaluateTrigger(allocator, workflow.triggers[0], matching_event);
       try testing.expect(should_trigger);
       
       // Test push event that should not match (wrong branch)
       const non_matching_event = PushEvent{
           .ref = "refs/heads/feature-branch",
           .commits = &.{
               .{
                   .modified = &.{"src/main.js"},
                   .added = &.{},
                   .removed = &.{},
               },
           },
       };
       
       const should_not_trigger = try workflow_trigger.evaluateTrigger(allocator, workflow.triggers[0], non_matching_event);
       try testing.expect(!should_not_trigger);
       
       // Test push event that should not match (excluded paths)
       const excluded_paths_event = PushEvent{
           .ref = "refs/heads/main",
           .commits = &.{
               .{
                   .modified = &.{"docs/README.md"},
                   .added = &.{},
                   .removed = &.{},
               },
           },
       };
       
       const should_not_trigger_paths = try workflow_trigger.evaluateTrigger(allocator, workflow.triggers[0], excluded_paths_event);
       try testing.expect(!should_not_trigger_paths);
   }
   
   test "handles complex trigger conditions" {
       const allocator = testing.allocator;
       
       var workflow_trigger = try WorkflowTrigger.init(allocator, test_config);
       defer workflow_trigger.deinit(allocator);
       
       // Complex workflow with multiple trigger types
       const complex_workflow_yaml = 
           \\name: Complex CI
           \\on:
           \\  push:
           \\    branches: [main]
           \\    tags: ['v*']
           \\  pull_request:
           \\    types: [opened, synchronize]
           \\    branches: [main]
           \\  schedule:
           \\    - cron: '0 2 * * *'
       ;
       
       const workflow = try Workflow.parseFromYaml(allocator, complex_workflow_yaml);
       defer workflow.deinit(allocator);
       
       // Test tag push (should match push trigger)
       const tag_event = PushEvent{
           .ref = "refs/tags/v1.0.0",
           .commits = &.{},
       };
       
       var matched_triggers: u32 = 0;
       for (workflow.triggers) |trigger| {
           if (try workflow_trigger.evaluateTrigger(allocator, trigger, tag_event)) {
               matched_triggers += 1;
           }
       }
       
       try testing.expectEqual(@as(u32, 1), matched_triggers); // Should match push trigger only
   }
   ```

2. **Implement workflow trigger evaluation logic**
3. **Add branch and path pattern matching**
4. **Test complex trigger scenarios and edge cases**

</phase_2>

<phase_3>
<title>Phase 3: Event Context Building (TDD)</title>

1. **Write tests for context building**
   ```zig
   test "builds GitHub Actions execution context" {
       const allocator = testing.allocator;
       
       var db = try DatabaseConnection.init(allocator, test_db_config);
       defer db.deinit(allocator);
       
       // Create test repository
       const repo_id = try createTestRepository(&db, allocator, .{
           .name = "test-repo",
           .owner = "test-owner",
           .full_name = "test-owner/test-repo",
       });
       defer _ = db.deleteRepository(allocator, repo_id) catch {};
       
       var workflow_trigger = try WorkflowTrigger.init(allocator, .{
           .db = &db,
       });
       defer workflow_trigger.deinit(allocator);
       
       const push_event = PushEvent{
           .repository_id = repo_id,
           .user_id = 123,
           .before = "abc123def456",
           .after = "def456abc123",
           .ref = "refs/heads/main",
           .commits = &.{
               .{
                   .id = "def456abc123",
                   .message = "Add new feature",
                   .author = .{
                       .name = "John Doe",
                       .email = "john@example.com",
                   },
                   .timestamp = 1234567890,
                   .added = &.{"src/feature.js"},
                   .modified = &.{"package.json"},
                   .removed = &.{},
               },
           },
           .timestamp = std.time.timestamp(),
       };
       
       const workflow = try createTestWorkflow(allocator, "CI Workflow");
       defer workflow.deinit(allocator);
       
       const context = try workflow_trigger.buildExecutionContext(allocator, push_event, workflow);
       defer context.deinit(allocator);
       
       // Verify GitHub context
       try testing.expectEqualStrings("push", context.github.event_name);
       try testing.expectEqualStrings("refs/heads/main", context.github.ref);
       try testing.expectEqualStrings("def456abc123", context.github.sha);
       try testing.expectEqualStrings("test-owner/test-repo", context.github.repository);
       try testing.expectEqualStrings("test-owner", context.github.repository_owner);
       try testing.expectEqualStrings("CI Workflow", context.github.workflow);
       
       // Verify event context
       try testing.expect(context.event.push != null);
       try testing.expectEqualStrings("abc123def456", context.event.push.?.before);
       try testing.expectEqualStrings("def456abc123", context.event.push.?.after);
       try testing.expectEqual(@as(usize, 1), context.event.push.?.commits.len);
   }
   
   test "injects repository secrets into context" {
       const allocator = testing.allocator;
       
       var db = try DatabaseConnection.init(allocator, test_db_config);
       defer db.deinit(allocator);
       
       const repo_id = try createTestRepository(&db, allocator, .{});
       defer _ = db.deleteRepository(allocator, repo_id) catch {};
       
       // Create repository secrets
       const secret1_id = try db.createSecret(allocator, .{
           .repository_id = repo_id,
           .name = "DATABASE_URL",
           .value = "postgresql://user:pass@db:5432/app",
       });
       defer _ = db.deleteSecret(allocator, secret1_id) catch {};
       
       const secret2_id = try db.createSecret(allocator, .{
           .repository_id = repo_id,
           .name = "API_KEY",
           .value = "secret-api-key-12345",
       });
       defer _ = db.deleteSecret(allocator, secret2_id) catch {};
       
       var workflow_trigger = try WorkflowTrigger.init(allocator, .{ .db = &db });
       defer workflow_trigger.deinit(allocator);
       
       const push_event = PushEvent{ .repository_id = repo_id };
       const workflow = try createTestWorkflow(allocator, "Deploy");
       defer workflow.deinit(allocator);
       
       const context = try workflow_trigger.buildExecutionContext(allocator, push_event, workflow);
       defer context.deinit(allocator);
       
       // Verify secrets are included
       try testing.expect(context.secrets.contains("DATABASE_URL"));
       try testing.expect(context.secrets.contains("API_KEY"));
       try testing.expectEqualStrings("postgresql://user:pass@db:5432/app", context.secrets.get("DATABASE_URL").?);
       try testing.expectEqualStrings("secret-api-key-12345", context.secrets.get("API_KEY").?);
   }
   ```

2. **Implement GitHub Actions context building**
3. **Add secret injection and environment setup**
4. **Test context accuracy and completeness**

</phase_2>

<phase_4>
<title>Phase 4: Workflow Run Creation and Dispatch (TDD)</title>

1. **Write tests for workflow run creation**
   ```zig
   test "creates workflow runs and dispatches jobs" {
       const allocator = testing.allocator;
       
       var db = try DatabaseConnection.init(allocator, test_db_config);
       defer db.deinit(allocator);
       
       var job_dispatcher = try JobDispatcher.init(allocator, .{ .db = &db });
       defer job_dispatcher.deinit(allocator);
       
       var hook_handler = try PostReceiveHook.init(allocator, .{
           .db = &db,
           .job_dispatcher = &job_dispatcher,
       });
       defer hook_handler.deinit(allocator);
       
       // Create repository with workflow
       const repo_id = try createTestRepository(&db, allocator, .{});
       defer _ = db.deleteRepository(allocator, repo_id) catch {};
       
       const workflow_id = try createTestWorkflow(&db, allocator, repo_id);
       defer _ = db.deleteWorkflow(allocator, workflow_id) catch {};
       
       const push_event = PushEvent{
           .repository_id = repo_id,
           .user_id = 456,
           .before = "000000000000",
           .after = "abc123def456",
           .ref = "refs/heads/main",
           .commits = &.{
               .{
                   .id = "abc123def456",
                   .message = "Trigger CI",
                   .added = &.{"src/main.js"},
               },
           },
           .timestamp = std.time.timestamp(),
       };
       
       const hook_result = try hook_handler.processPushEvent(allocator, push_event);
       defer hook_result.deinit(allocator);
       
       // Verify workflow run was created
       try testing.expectEqual(@as(usize, 1), hook_result.triggered_workflows.len);
       
       const workflow_run = hook_result.triggered_workflows[0];
       try testing.expect(workflow_run.id > 0);
       try testing.expectEqual(@as(u32, 1), workflow_run.run_number);
       try testing.expectEqualStrings("abc123def456", workflow_run.commit_sha);
       try testing.expectEqualStrings("main", workflow_run.branch);
       
       // Verify jobs were queued
       const queued_jobs = try db.getQueuedJobs(allocator, .{ .workflow_run_id = workflow_run.id });
       defer allocator.free(queued_jobs);
       
       try testing.expect(queued_jobs.len > 0);
       
       for (queued_jobs) |job| {
           try testing.expectEqual(workflow_run.id, job.workflow_run_id);
           try testing.expectEqual(JobExecution.JobStatus.queued, job.status);
       }
   }
   
   test "handles multiple ref updates in single push" {
       const allocator = testing.allocator;
       
       var hook_handler = try PostReceiveHook.init(allocator, test_config);
       defer hook_handler.deinit(allocator);
       
       // Simulate pushing to multiple branches
       const hook_input = 
           "abc123000000000000000000000000000000000000 def456789012345678901234567890abcdef123456 refs/heads/main\n" ++
           "000000000000000000000000000000000000000000 789abc012def345678901234567890abcdef456789 refs/heads/develop\n" ++
           "111222333444555666777888999000aaabbbcccddd eee111222333444555666777888999000aaabbbccc refs/tags/v1.0.0\n";
       
       const ref_updates = try hook_handler.parseRefUpdates(allocator, hook_input);
       defer allocator.free(ref_updates);
       
       var total_workflow_runs: u32 = 0;
       
       for (ref_updates) |ref_update| {
           const workflows = try hook_handler.processRefUpdate(allocator, ref_update);
           defer allocator.free(workflows);
           
           total_workflow_runs += @intCast(u32, workflows.len);
           
           // Verify each workflow run has correct context
           for (workflows) |workflow_run| {
               try testing.expect(workflow_run.id > 0);
               
               // Branch pushes should have branch name
               if (std.mem.startsWith(u8, ref_update.ref_name, "refs/heads/")) {
                   const branch_name = ref_update.ref_name[11..]; // Remove "refs/heads/"
                   try testing.expectEqualStrings(branch_name, workflow_run.branch);
               }
           }
       }
       
       try testing.expect(total_workflow_runs > 0);
   }
   ```

2. **Implement workflow run creation and numbering**
3. **Add job queuing and dispatch integration**
4. **Test batch processing and error handling**

</phase_4>

<phase_5>
<title>Phase 5: Performance Optimization and Error Handling (TDD)</title>

1. **Write tests for performance characteristics**
   ```zig
   test "hook execution completes within performance limits" {
       const allocator = testing.allocator;
       
       var hook_handler = try PostReceiveHook.init(allocator, .{
           .performance_monitoring = true,
       });
       defer hook_handler.deinit(allocator);
       
       // Create push event with many commits
       var commits = std.ArrayList(Commit).init(allocator);
       defer commits.deinit();
       
       for (0..100) |i| {
           try commits.append(.{
               .id = try std.fmt.allocPrint(allocator, "commit{:03}", .{i}),
               .message = try std.fmt.allocPrint(allocator, "Commit #{}", .{i}),
               .author = .{ .name = "Test Author", .email = "test@example.com" },
               .timestamp = std.time.timestamp(),
               .added = &.{},
               .modified = &.{"file.txt"},
               .removed = &.{},
           });
       }
       
       const large_push_event = PushEvent{
           .repository_id = test_repo_id,
           .commits = commits.items,
           .timestamp = std.time.timestamp(),
       };
       
       const start_time = std.time.nanoTimestamp();
       const hook_result = try hook_handler.processPushEvent(allocator, large_push_event);
       defer hook_result.deinit(allocator);
       const execution_time = std.time.nanoTimestamp() - start_time;
       
       // Hook should complete within reasonable time (e.g., 5 seconds)
       const max_execution_time = 5 * std.time.ns_per_s;
       try testing.expect(execution_time < max_execution_time);
       
       // Verify execution metrics
       try testing.expect(hook_result.execution_time_ms < 5000);
       try testing.expectEqual(@as(u32, 100), hook_result.processed_commits);
   }
   
   test "handles hook execution errors gracefully" {
       const allocator = testing.allocator;
       
       var hook_handler = try PostReceiveHook.init(allocator, .{
           .error_recovery = true,
       });
       defer hook_handler.deinit(allocator);
       
       // Create push event that will cause partial failures
       const problematic_event = PushEvent{
           .repository_id = 99999, // Non-existent repository
           .ref = "refs/heads/main",
           .commits = &.{},
       };
       
       const hook_result = try hook_handler.processPushEvent(allocator, problematic_event);
       defer hook_result.deinit(allocator);
       
       // Should complete with errors recorded
       try testing.expect(hook_result.errors.len > 0);
       try testing.expectEqual(@as(usize, 0), hook_result.triggered_workflows.len);
       
       // Error should be properly categorized
       const error_info = hook_result.errors[0];
       try testing.expect(std.mem.indexOf(u8, error_info.message, "repository") != null);
   }
   ```

2. **Implement performance monitoring and optimization**
3. **Add comprehensive error handling and recovery**
4. **Test high-load scenarios and failure modes**

</phase_5>

<phase_6>
<title>Phase 6: Integration and Production Features (TDD)</title>

1. **Write tests for complete integration**
2. **Implement audit logging and compliance features**
3. **Add monitoring and alerting integration**
4. **Test end-to-end hook-to-execution pipeline**

</phase_6>

</implementation_steps>

</detailed_specifications>

<quality_assurance>

<testing_requirements>

- **Git Integration**: Real Git repositories with actual commits and refs
- **Workflow Processing**: Complete workflow parsing and trigger evaluation
- **Database Integration**: Workflow runs, job creation, audit logging
- **Performance Testing**: High-frequency pushes, large commit batches
- **Error Recovery**: Network failures, database outages, malformed input
- **Integration Testing**: End-to-end push-to-workflow-execution pipeline

</testing_requirements>

<success_criteria>

1. **All tests pass**: Complete post-receive hook functionality with zero failures
2. **Performance**: Sub-second hook execution, minimal repository impact
3. **Reliability**: 99.9% successful hook processing, comprehensive error handling
4. **GitHub compatibility**: Support all GitHub Actions trigger types and conditions
5. **Scalability**: Handle high-frequency pushes and large repositories
6. **Audit compliance**: Complete audit trails for all hook executions
7. **Production ready**: Monitoring, alerting, graceful degradation, recovery

</success_criteria>

</quality_assurance>

<reference_implementations>

- **GitHub Webhooks**: Push event structure and payload format
- **GitLab Push Events**: Repository hook integration patterns
- **Jenkins Git Plugin**: Git hook processing and job triggering
- **Tekton Triggers**: Event-driven pipeline triggering mechanisms
- **Argo Events**: Git event processing and workflow automation

</reference_implementations>