# Complete Actions CI/CD Integration

## Issue Found

While individual Actions components were implemented (dispatcher, runner, execution), the full integration between all components and the Git workflow is incomplete. The system cannot actually trigger and run workflows end-to-end.

## Missing Integration Points

**What exists in isolation**:
- ✅ Actions data models (prompt 11)
- ❌ Workflow parsing (prompt 12 - empty files)
- ✅ Dispatcher system (prompt 15)
- ✅ Runner registration (prompt 16)
- ✅ Job execution (prompt 17)
- ⚠️ Post-receive hook (prompt 18 - partial)

**Critical gaps**:
1. No workflow parsing means no workflows can be read
2. Post-receive hook doesn't create workflow runs
3. No integration between components
4. Missing workflow run UI/API
5. No artifact access via API
6. No build status reporting

## Complete Integration Implementation

### Workflow Discovery and Loading

```zig
const WorkflowManager = struct {
    allocator: std.mem.Allocator,
    dao: *DataAccessObject,
    parser: *WorkflowParser,
    cache: std.StringHashMap(CachedWorkflow),
    
    pub fn init(allocator: std.mem.Allocator, dao: *DataAccessObject) !WorkflowManager {
        return WorkflowManager{
            .allocator = allocator,
            .dao = dao,
            .parser = try WorkflowParser.init(allocator),
            .cache = std.StringHashMap(CachedWorkflow).init(allocator),
        };
    }
    
    pub fn loadRepositoryWorkflows(
        self: *WorkflowManager,
        repo_id: u32,
        repo_path: []const u8,
    ) ![]Workflow {
        // Check cache first
        const cache_key = try std.fmt.allocPrint(self.allocator, "repo:{}", .{repo_id});
        defer self.allocator.free(cache_key);
        
        if (self.cache.get(cache_key)) |cached| {
            if (std.time.timestamp() - cached.timestamp < 300) { // 5 min cache
                return cached.workflows;
            }
        }
        
        // Scan .github/workflows directory
        const workflows_dir = try std.fs.path.join(self.allocator, &.{
            repo_path, ".github", "workflows"
        });
        defer self.allocator.free(workflows_dir);
        
        var workflows = std.ArrayList(Workflow).init(self.allocator);
        defer workflows.deinit();
        
        var dir = std.fs.openDirAbsolute(workflows_dir, .{ .iterate = true }) catch |err| {
            switch (err) {
                error.FileNotFound => return &[_]Workflow{}, // No workflows
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
            
            const file_path = try std.fs.path.join(self.allocator, &.{
                workflows_dir, entry.name
            });
            defer self.allocator.free(file_path);
            
            // Read and parse workflow
            const content = try std.fs.cwd().readFileAlloc(self.allocator, file_path, 1024 * 1024);
            defer self.allocator.free(content);
            
            const workflow = try self.parser.parseWorkflowFile(content);
            workflow.file_path = try self.allocator.dupe(u8, entry.name);
            workflow.repository_id = repo_id;
            
            // Store in database
            const workflow_id = try self.dao.createOrUpdateWorkflow(self.allocator, workflow);
            workflow.id = workflow_id;
            
            try workflows.append(workflow);
        }
        
        // Update cache
        try self.cache.put(cache_key, .{
            .workflows = try workflows.toOwnedSlice(),
            .timestamp = std.time.timestamp(),
        });
        
        return workflows.items;
    }
};
```

### Complete Post-Receive Integration

```zig
// Update the existing post-receive hook to actually create workflow runs
pub fn processPushEvent(self: *PostReceiveHook, allocator: std.mem.Allocator, event: PushEvent) !HookResult {
    var triggered_runs = std.ArrayList(WorkflowRun).init(allocator);
    defer triggered_runs.deinit();
    
    // Load repository workflows
    const workflows = try self.workflow_manager.loadRepositoryWorkflows(
        event.repository_id,
        event.repository_path,
    );
    defer allocator.free(workflows);
    
    // Find matching workflows
    for (workflows) |workflow| {
        const should_trigger = try self.workflow_trigger.evaluateTrigger(
            allocator,
            workflow.triggers,
            event,
        );
        
        if (!should_trigger) continue;
        
        // Create workflow run
        const run = try self.createWorkflowRun(allocator, workflow, event);
        try triggered_runs.append(run);
        
        // Create jobs from workflow
        const jobs = try self.createJobsFromWorkflow(allocator, workflow, run);
        
        // Queue jobs with dispatcher
        for (jobs) |job| {
            try self.job_dispatcher.enqueueJob(allocator, job);
        }
        
        log.info("Triggered workflow '{}' run #{} with {} jobs", .{
            workflow.name,
            run.run_number,
            jobs.len,
        });
    }
    
    return HookResult{
        .triggered_workflows = try triggered_runs.toOwnedSlice(),
        .execution_time_ms = std.time.milliTimestamp() - start_time,
    };
}

fn createWorkflowRun(
    self: *PostReceiveHook,
    allocator: std.mem.Allocator,
    workflow: Workflow,
    event: PushEvent,
) !WorkflowRun {
    // Get next run number
    const run_number = try self.dao.getNextWorkflowRunNumber(
        allocator,
        workflow.repository_id,
        workflow.id,
    );
    
    // Create workflow run record
    const run = try self.dao.createWorkflowRun(allocator, .{
        .repository_id = workflow.repository_id,
        .workflow_id = workflow.id,
        .run_number = run_number,
        .event = "push",
        .event_payload = try std.json.stringify(event, .{}, allocator),
        .ref = event.ref,
        .sha = event.after,
        .status = .queued,
        .conclusion = null,
        .created_at = std.time.timestamp(),
    });
    
    return run;
}

fn createJobsFromWorkflow(
    self: *PostReceiveHook,
    allocator: std.mem.Allocator,
    workflow: Workflow,
    run: WorkflowRun,
) ![]QueuedJob {
    var jobs = std.ArrayList(QueuedJob).init(allocator);
    defer jobs.deinit();
    
    // Build execution context
    const context = try self.buildExecutionContext(allocator, workflow, run);
    defer context.deinit();
    
    // Process each job in workflow
    for (workflow.jobs) |job_def| {
        // Evaluate job conditions
        if (job_def.if_condition) |condition| {
            const should_run = try self.expression_evaluator.evaluateCondition(
                allocator,
                condition,
                context,
            );
            if (!should_run) continue;
        }
        
        // Handle matrix builds
        if (job_def.strategy.matrix) |matrix| {
            const matrix_combinations = try expandMatrix(allocator, matrix);
            defer matrix_combinations.deinit();
            
            for (matrix_combinations) |combination| {
                const matrix_job = try createMatrixJob(
                    allocator,
                    job_def,
                    combination,
                    run,
                    context,
                );
                try jobs.append(matrix_job);
            }
        } else {
            // Single job instance
            const job = try self.createJob(allocator, job_def, run, context);
            try jobs.append(job);
        }
    }
    
    // Resolve job dependencies
    try resolveJobDependencies(allocator, &jobs);
    
    return jobs.toOwnedSlice();
}
```

### Workflow Run API

```zig
const WorkflowRunHandler = struct {
    pub fn listWorkflowRuns(r: zap.Request, ctx: *Context) !void {
        // GET /api/v1/repos/{owner}/{repo}/actions/runs
        const owner = r.getRouteParam("owner") orelse return error.MissingParam;
        const repo_name = r.getRouteParam("repo") orelse return error.MissingParam;
        
        const repo = try ctx.dao.getRepositoryByName(ctx.allocator, owner, repo_name) orelse
            return sendJsonError(r, 404, "Repository not found");
        
        const filters = WorkflowRunFilters{
            .actor = r.getQuery("actor"),
            .branch = r.getQuery("branch"),
            .event = r.getQuery("event"),
            .status = if (r.getQuery("status")) |s| try parseStatus(s) else null,
            .workflow_id = if (r.getQuery("workflow_id")) |id| try std.fmt.parseInt(u32, id, 10) else null,
            .page = if (r.getQuery("page")) |p| try std.fmt.parseInt(u32, p, 10) else 1,
            .per_page = if (r.getQuery("per_page")) |pp| try std.fmt.parseInt(u32, pp, 10) else 30,
        };
        
        const runs = try ctx.dao.listWorkflowRuns(ctx.allocator, repo.id, filters);
        defer runs.deinit();
        
        var run_responses = std.ArrayList(WorkflowRunResponse).init(ctx.allocator);
        defer run_responses.deinit();
        
        for (runs.items) |run| {
            try run_responses.append(try formatWorkflowRun(ctx.allocator, run));
        }
        
        try r.sendJson(.{
            .total_count = runs.total_count,
            .workflow_runs = run_responses.items,
        });
    }
    
    pub fn getWorkflowRun(r: zap.Request, ctx: *Context) !void {
        // GET /api/v1/repos/{owner}/{repo}/actions/runs/{run_id}
        const run_id = try parseU32(r.getRouteParam("run_id") orelse return error.MissingParam);
        
        const run = try ctx.dao.getWorkflowRun(ctx.allocator, run_id) orelse
            return sendJsonError(r, 404, "Workflow run not found");
        defer run.deinit();
        
        // Get jobs for this run
        const jobs = try ctx.dao.getWorkflowRunJobs(ctx.allocator, run_id);
        defer jobs.deinit();
        
        try r.sendJson(WorkflowRunResponse{
            .id = run.id,
            .name = run.workflow.name,
            .node_id = try generateNodeId("WorkflowRun", run.id),
            .head_branch = run.head_branch,
            .head_sha = run.sha,
            .run_number = run.run_number,
            .event = run.event,
            .status = run.status,
            .conclusion = run.conclusion,
            .workflow_id = run.workflow_id,
            .url = try generateApiUrl(ctx, "/repos/{s}/{s}/actions/runs/{}", .{
                owner, repo_name, run.id
            }),
            .html_url = try generateWebUrl(ctx, "{s}/{s}/actions/runs/{}", .{
                owner, repo_name, run.id
            }),
            .created_at = run.created_at,
            .updated_at = run.updated_at,
            .jobs_url = try generateApiUrl(ctx, "/repos/{s}/{s}/actions/runs/{}/jobs", .{
                owner, repo_name, run.id
            }),
            .logs_url = try generateApiUrl(ctx, "/repos/{s}/{s}/actions/runs/{}/logs", .{
                owner, repo_name, run.id
            }),
            .artifacts_url = try generateApiUrl(ctx, "/repos/{s}/{s}/actions/runs/{}/artifacts", .{
                owner, repo_name, run.id
            }),
        });
    }
    
    pub fn rerunWorkflow(r: zap.Request, ctx: *Context) !void {
        // POST /api/v1/repos/{owner}/{repo}/actions/runs/{run_id}/rerun
        const run_id = try parseU32(r.getRouteParam("run_id") orelse return error.MissingParam);
        
        // Verify permissions
        const auth = try authenticateRequest(r, ctx);
        if (!try hasWriteAccess(ctx, auth.user_id, repo.id)) {
            return sendJsonError(r, 403, "Write access required");
        }
        
        // Get original run
        const original_run = try ctx.dao.getWorkflowRun(ctx.allocator, run_id) orelse
            return sendJsonError(r, 404, "Workflow run not found");
        defer original_run.deinit();
        
        // Create new run with same parameters
        const new_run = try ctx.workflow_manager.rerunWorkflow(
            ctx.allocator,
            original_run,
            auth.user_id,
        );
        
        r.setStatus(201);
        try r.sendJson(try formatWorkflowRun(ctx.allocator, new_run));
    }
    
    pub fn cancelWorkflowRun(r: zap.Request, ctx: *Context) !void {
        // POST /api/v1/repos/{owner}/{repo}/actions/runs/{run_id}/cancel
        const run_id = try parseU32(r.getRouteParam("run_id") orelse return error.MissingParam);
        
        // Cancel all jobs in the run
        const jobs = try ctx.dao.getWorkflowRunJobs(ctx.allocator, run_id);
        defer jobs.deinit();
        
        for (jobs.items) |job| {
            if (job.status == .queued or job.status == .in_progress) {
                try ctx.job_dispatcher.cancelJob(ctx.allocator, job.id);
            }
        }
        
        // Update run status
        try ctx.dao.updateWorkflowRun(ctx.allocator, run_id, .{
            .status = .completed,
            .conclusion = .cancelled,
            .completed_at = std.time.timestamp(),
        });
        
        r.setStatus(202);
        try r.sendJson(.{});
    }
};
```

### Build Status Integration

```zig
const StatusHandler = struct {
    pub fn createCommitStatus(r: zap.Request, ctx: *Context) !void {
        // POST /api/v1/repos/{owner}/{repo}/statuses/{sha}
        const sha = r.getRouteParam("sha") orelse return error.MissingParam;
        
        const body = try r.readJsonAlloc(ctx.allocator, CreateStatusRequest, .{});
        defer body.deinit();
        
        // Create status
        const status = try ctx.dao.createCommitStatus(ctx.allocator, .{
            .repository_id = repo.id,
            .sha = sha,
            .state = body.value.state,
            .target_url = body.value.target_url,
            .description = body.value.description,
            .context = body.value.context,
            .creator_id = auth.user_id,
        });
        
        r.setStatus(201);
        try r.sendJson(formatCommitStatus(status));
    }
    
    pub fn updateCheckRun(r: zap.Request, ctx: *Context) !void {
        // PATCH /api/v1/repos/{owner}/{repo}/check-runs/{check_run_id}
        const check_run_id = try parseU32(r.getRouteParam("check_run_id") orelse return error.MissingParam);
        
        const body = try r.readJsonAlloc(ctx.allocator, UpdateCheckRunRequest, .{});
        defer body.deinit();
        
        // Update check run from job execution
        try ctx.dao.updateCheckRun(ctx.allocator, check_run_id, .{
            .status = body.value.status,
            .conclusion = body.value.conclusion,
            .completed_at = if (body.value.status == .completed) std.time.timestamp() else null,
            .output = body.value.output,
        });
        
        // If job completed, update workflow run status
        if (body.value.status == .completed) {
            try ctx.workflow_manager.updateWorkflowRunStatus(
                ctx.allocator,
                check_run.workflow_run_id,
            );
        }
        
        try r.sendJson(formatCheckRun(updated_check_run));
    }
};
```

### Artifact Access API

```zig
const ArtifactHandler = struct {
    pub fn listArtifacts(r: zap.Request, ctx: *Context) !void {
        // GET /api/v1/repos/{owner}/{repo}/actions/artifacts
        const run_id = if (r.getQuery("run_id")) |id| try std.fmt.parseInt(u32, id, 10) else null;
        
        const artifacts = try ctx.dao.listArtifacts(ctx.allocator, .{
            .repository_id = repo.id,
            .run_id = run_id,
            .name = r.getQuery("name"),
        });
        defer artifacts.deinit();
        
        var artifact_responses = std.ArrayList(ArtifactResponse).init(ctx.allocator);
        defer artifact_responses.deinit();
        
        for (artifacts.items) |artifact| {
            try artifact_responses.append(.{
                .id = artifact.id,
                .node_id = try generateNodeId("Artifact", artifact.id),
                .name = artifact.name,
                .size_in_bytes = artifact.size,
                .url = try generateApiUrl(ctx, "/repos/{s}/{s}/actions/artifacts/{}", .{
                    owner, repo_name, artifact.id
                }),
                .archive_download_url = try generateApiUrl(
                    ctx,
                    "/repos/{s}/{s}/actions/artifacts/{}/zip",
                    .{ owner, repo_name, artifact.id }
                ),
                .expired = artifact.expires_at < std.time.timestamp(),
                .created_at = artifact.created_at,
                .expires_at = artifact.expires_at,
            });
        }
        
        try r.sendJson(.{
            .total_count = artifacts.total_count,
            .artifacts = artifact_responses.items,
        });
    }
    
    pub fn downloadArtifact(r: zap.Request, ctx: *Context) !void {
        // GET /api/v1/repos/{owner}/{repo}/actions/artifacts/{artifact_id}/zip
        const artifact_id = try parseU32(r.getRouteParam("artifact_id") orelse return error.MissingParam);
        
        const artifact = try ctx.dao.getArtifact(ctx.allocator, artifact_id) orelse
            return sendJsonError(r, 404, "Artifact not found");
        defer artifact.deinit();
        
        // Verify access
        if (artifact.repository_id != repo.id) {
            return sendJsonError(r, 404, "Artifact not found");
        }
        
        // Stream artifact zip file
        r.setStatus(200);
        r.setHeader("Content-Type", "application/zip");
        r.setHeader("Content-Disposition", try std.fmt.allocPrint(
            ctx.allocator,
            "attachment; filename=\"{s}.zip\"",
            .{artifact.name}
        ));
        
        try streamFile(r, artifact.storage_path);
    }
};
```

## Implementation Steps

### Phase 1: Fix Workflow Parsing
1. Implement the missing WorkflowParser (see prompt 22)
2. Test with real GitHub Actions workflows
3. Ensure all trigger types are supported

### Phase 2: Complete Hook Integration
1. Update post-receive hook to create workflow runs
2. Implement job creation from workflows
3. Connect to job dispatcher

### Phase 3: API Endpoints
1. Implement workflow run listing/details
2. Add job status and logs endpoints
3. Create artifact access endpoints
4. Add check runs and commit status

### Phase 4: End-to-End Testing
1. Test complete workflow lifecycle
2. Verify status reporting
3. Test artifact upload/download
4. Integration with runners

## Test Requirements

```zig
test "complete Actions workflow lifecycle" {
    // Push to repository
    const push_result = try gitPush(test_repo, "main", "test-commit");
    
    // Verify workflow triggered
    const runs = try getWorkflowRuns(test_repo);
    try testing.expectEqual(@as(usize, 1), runs.len);
    
    // Wait for completion
    const final_run = try waitForWorkflowCompletion(runs[0].id, 60);
    try testing.expectEqual(WorkflowStatus.completed, final_run.status);
    try testing.expectEqual(WorkflowConclusion.success, final_run.conclusion);
    
    // Check artifacts
    const artifacts = try getArtifacts(test_repo, final_run.id);
    try testing.expect(artifacts.len > 0);
    
    // Verify commit status
    const statuses = try getCommitStatuses(test_repo, push_result.sha);
    try testing.expect(hasSuccessStatus(statuses, "continuous-integration"));
}
```

## Priority: CRITICAL

This integration is essential for the Actions system to function. Without it:
- Workflows cannot be triggered
- CI/CD is non-functional
- No visibility into build status
- No artifact management
- Incomplete GitHub compatibility

## Estimated Effort: 8-10 days (including workflow parser)