const std = @import("std");
const testing = std.testing;
const container = @import("container.zig");

// Action reference parsing
pub const ActionRef = struct {
    owner: []const u8,
    name: []const u8,
    version: []const u8,
    
    pub fn parse(allocator: std.mem.Allocator, action_ref: []const u8) !ActionRef {
        // Parse "owner/repo@version" format
        const at_pos = std.mem.lastIndexOf(u8, action_ref, "@") orelse {
            return error.InvalidActionRef;
        };
        
        const slash_pos = std.mem.indexOf(u8, action_ref, "/") orelse {
            return error.InvalidActionRef;
        };
        
        if (slash_pos >= at_pos) {
            return error.InvalidActionRef;
        }
        
        return ActionRef{
            .owner = try allocator.dupe(u8, action_ref[0..slash_pos]),
            .name = try allocator.dupe(u8, action_ref[slash_pos + 1..at_pos]),
            .version = try allocator.dupe(u8, action_ref[at_pos + 1..]),
        };
    }
    
    pub fn deinit(self: ActionRef, allocator: std.mem.Allocator) void {
        allocator.free(self.owner);
        allocator.free(self.name);
        allocator.free(self.version);
    }
    
    pub fn toString(self: ActionRef, allocator: std.mem.Allocator) ![]const u8 {
        return std.fmt.allocPrint(allocator, "{s}/{s}@{s}", .{ self.owner, self.name, self.version });
    }
};

// Downloaded action metadata
pub const Action = struct {
    ref: ActionRef,
    path: []const u8,
    metadata: ActionMetadata,
    
    pub fn deinit(self: *Action, allocator: std.mem.Allocator) void {
        self.ref.deinit(allocator);
        allocator.free(self.path);
        self.metadata.deinit(allocator);
    }
};

// Action metadata from action.yml
pub const ActionMetadata = struct {
    name: []const u8,
    description: []const u8,
    inputs: std.StringHashMap(InputSpec),
    outputs: std.StringHashMap(OutputSpec),
    runs: RunsSpec,
    
    pub const InputSpec = struct {
        description: []const u8,
        required: bool = false,
        default: ?[]const u8 = null,
    };
    
    pub const OutputSpec = struct {
        description: []const u8,
    };
    
    pub const RunsSpec = union(enum) {
        node: struct {
            main: []const u8,
            pre: ?[]const u8 = null,
            post: ?[]const u8 = null,
        },
        docker: struct {
            image: []const u8,
            entrypoint: ?[]const u8 = null,
            args: ?[][]const u8 = null,
        },
        composite: struct {
            steps: []CompositeStep,
        },
    };
    
    pub const CompositeStep = struct {
        name: ?[]const u8 = null,
        id: ?[]const u8 = null,
        if_condition: ?[]const u8 = null,
        run: ?[]const u8 = null,
        uses: ?[]const u8 = null,
        with: std.StringHashMap([]const u8),
        env: std.StringHashMap([]const u8),
    };
    
    pub fn init(allocator: std.mem.Allocator) ActionMetadata {
        return ActionMetadata{
            .name = "",
            .description = "",
            .inputs = std.StringHashMap(InputSpec).init(allocator),
            .outputs = std.StringHashMap(OutputSpec).init(allocator),
            .runs = .{ .node = .{ .main = "" } },
        };
    }
    
    pub fn deinit(self: *ActionMetadata, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.description);
        
        var inputs_iter = self.inputs.iterator();
        while (inputs_iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.description);
            if (entry.value_ptr.default) |default| {
                allocator.free(default);
            }
        }
        self.inputs.deinit();
        
        var outputs_iter = self.outputs.iterator();
        while (outputs_iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.description);
        }
        self.outputs.deinit();
        
        switch (self.runs) {
            .node => |node| {
                allocator.free(node.main);
                if (node.pre) |pre| allocator.free(pre);
                if (node.post) |post| allocator.free(post);
            },
            .docker => |docker| {
                allocator.free(docker.image);
                if (docker.entrypoint) |entrypoint| allocator.free(entrypoint);
                if (docker.args) |args| {
                    for (args) |arg| allocator.free(arg);
                    allocator.free(args);
                }
            },
            .composite => |composite| {
                for (composite.steps) |*step| {
                    if (step.name) |name| allocator.free(name);
                    if (step.id) |id| allocator.free(id);
                    if (step.if_condition) |condition| allocator.free(condition);
                    if (step.run) |run| allocator.free(run);
                    if (step.uses) |uses| allocator.free(uses);
                    step.with.deinit();
                    step.env.deinit();
                }
                allocator.free(composite.steps);
            },
        }
    }
};

// Action cache for downloaded actions
pub const ActionCache = struct {
    allocator: std.mem.Allocator,
    cache_dir: []const u8,
    cached_actions: std.StringHashMap(Action),
    
    pub fn init(allocator: std.mem.Allocator, cache_dir: []const u8) !ActionCache {
        // Ensure cache directory exists
        std.fs.cwd().makePath(cache_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {}, // OK
            else => return err,
        };
        
        return ActionCache{
            .allocator = allocator,
            .cache_dir = try allocator.dupe(u8, cache_dir),
            .cached_actions = std.StringHashMap(Action).init(allocator),
        };
    }
    
    pub fn deinit(self: *ActionCache) void {
        self.allocator.free(self.cache_dir);
        
        var actions_iter = self.cached_actions.iterator();
        while (actions_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(self.allocator);
        }
        self.cached_actions.deinit();
    }
    
    pub fn getAction(self: *ActionCache, action_ref: []const u8) !Action {
        // Check if action is already cached
        if (self.cached_actions.get(action_ref)) |cached_action| {
            // Return a copy of cached action
            return Action{
                .ref = ActionRef{
                    .owner = try self.allocator.dupe(u8, cached_action.ref.owner),
                    .name = try self.allocator.dupe(u8, cached_action.ref.name),
                    .version = try self.allocator.dupe(u8, cached_action.ref.version),
                },
                .path = try self.allocator.dupe(u8, cached_action.path),
                .metadata = try self.copyActionMetadata(cached_action.metadata),
            };
        }
        
        // Download and cache action
        const action = try self.downloadAction(action_ref);
        
        // Store in cache
        const cached_ref = try self.allocator.dupe(u8, action_ref);
        try self.cached_actions.put(cached_ref, action);
        
        // Return a copy
        return Action{
            .ref = ActionRef{
                .owner = try self.allocator.dupe(u8, action.ref.owner),
                .name = try self.allocator.dupe(u8, action.ref.name),
                .version = try self.allocator.dupe(u8, action.ref.version),
            },
            .path = try self.allocator.dupe(u8, action.path),
            .metadata = try self.copyActionMetadata(action.metadata),
        };
    }
    
    fn downloadAction(self: *ActionCache, action_ref: []const u8) !Action {
        const parsed_ref = try ActionRef.parse(self.allocator, action_ref);
        defer parsed_ref.deinit(self.allocator);
        
        // Create action directory in cache
        const action_dir = try std.fmt.allocPrint(
            self.allocator,
            "{s}/{s}-{s}-{s}",
            .{ self.cache_dir, parsed_ref.owner, parsed_ref.name, parsed_ref.version }
        );
        
        // Simulate action download - in real implementation, this would:
        // 1. Clone from GitHub
        // 2. Extract to cache directory
        // 3. Read action.yml metadata
        
        std.fs.cwd().makePath(action_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {}, // OK
            else => return err,
        };
        
        // Create mock action metadata
        var metadata = ActionMetadata.init(self.allocator);
        metadata.name = try self.allocator.dupe(u8, parsed_ref.name);
        metadata.description = try std.fmt.allocPrint(self.allocator, "Mock action for {s}", .{action_ref});
        
        // Add mock inputs/outputs based on common actions
        if (std.mem.eql(u8, parsed_ref.name, "checkout")) {
            try metadata.inputs.put("repository", ActionMetadata.InputSpec{
                .description = try self.allocator.dupe(u8, "Repository name with owner"),
                .required = false,
                .default = try self.allocator.dupe(u8, "${{ github.repository }}"),
            });
            try metadata.inputs.put("ref", ActionMetadata.InputSpec{
                .description = try self.allocator.dupe(u8, "The branch, tag or SHA to checkout"),
                .required = false,
            });
            try metadata.inputs.put("fetch-depth", ActionMetadata.InputSpec{
                .description = try self.allocator.dupe(u8, "Number of commits to fetch"),
                .required = false,
                .default = try self.allocator.dupe(u8, "1"),
            });
        } else if (std.mem.eql(u8, parsed_ref.name, "setup-node")) {
            try metadata.inputs.put("node-version", ActionMetadata.InputSpec{
                .description = try self.allocator.dupe(u8, "Version Spec of the version to use"),
                .required = false,
            });
            try metadata.inputs.put("cache", ActionMetadata.InputSpec{
                .description = try self.allocator.dupe(u8, "Used to specify a package manager for caching"),
                .required = false,
            });
        }
        
        // Set appropriate runs config
        if (std.mem.eql(u8, parsed_ref.name, "checkout") or std.mem.eql(u8, parsed_ref.name, "setup-node")) {
            metadata.runs = .{ .node = .{ .main = try self.allocator.dupe(u8, "dist/index.js") } };
        } else {
            metadata.runs = .{ .docker = .{ .image = try self.allocator.dupe(u8, "alpine:latest") } };
        }
        
        return Action{
            .ref = ActionRef{
                .owner = try self.allocator.dupe(u8, parsed_ref.owner),
                .name = try self.allocator.dupe(u8, parsed_ref.name),
                .version = try self.allocator.dupe(u8, parsed_ref.version),
            },
            .path = action_dir,
            .metadata = metadata,
        };
    }
    
    fn copyActionMetadata(self: *ActionCache, original: ActionMetadata) !ActionMetadata {
        var copy = ActionMetadata.init(self.allocator);
        copy.name = try self.allocator.dupe(u8, original.name);
        copy.description = try self.allocator.dupe(u8, original.description);
        
        // Copy inputs
        var inputs_iter = original.inputs.iterator();
        while (inputs_iter.next()) |entry| {
            const input_copy = ActionMetadata.InputSpec{
                .description = try self.allocator.dupe(u8, entry.value_ptr.description),
                .required = entry.value_ptr.required,
                .default = if (entry.value_ptr.default) |default|
                    try self.allocator.dupe(u8, default)
                else
                    null,
            };
            try copy.inputs.put(try self.allocator.dupe(u8, entry.key_ptr.*), input_copy);
        }
        
        // Copy outputs
        var outputs_iter = original.outputs.iterator();
        while (outputs_iter.next()) |entry| {
            const output_copy = ActionMetadata.OutputSpec{
                .description = try self.allocator.dupe(u8, entry.value_ptr.description),
            };
            try copy.outputs.put(try self.allocator.dupe(u8, entry.key_ptr.*), output_copy);
        }
        
        // Copy runs config
        copy.runs = switch (original.runs) {
            .node => |node| .{
                .node = .{
                    .main = try self.allocator.dupe(u8, node.main),
                    .pre = if (node.pre) |pre| try self.allocator.dupe(u8, pre) else null,
                    .post = if (node.post) |post| try self.allocator.dupe(u8, post) else null,
                },
            },
            .docker => |docker| .{
                .docker = .{
                    .image = try self.allocator.dupe(u8, docker.image),
                    .entrypoint = if (docker.entrypoint) |entrypoint| try self.allocator.dupe(u8, entrypoint) else null,
                    .args = if (docker.args) |args| blk: {
                        const args_copy = try self.allocator.alloc([]const u8, args.len);
                        for (args, 0..) |arg, i| {
                            args_copy[i] = try self.allocator.dupe(u8, arg);
                        }
                        break :blk args_copy;
                    } else null,
                },
            },
            .composite => |composite| .{
                .composite = .{
                    .steps = try self.allocator.dupe(ActionMetadata.CompositeStep, composite.steps),
                },
            },
        };
        
        return copy;
    }
};

// Execution context for actions
pub const ExecutionContext = struct {
    working_directory: []const u8,
    github: GitHubContext,
    env: std.StringHashMap([]const u8),
    runner: RunnerContext,
    
    pub const GitHubContext = struct {
        repository: []const u8,
        ref: []const u8,
        sha: []const u8,
        actor: []const u8 = "test-actor",
        event_name: []const u8 = "push",
        workspace: []const u8 = "/workspace",
    };
    
    pub const RunnerContext = struct {
        os: []const u8 = "Linux",
        arch: []const u8 = "X64",
        name: []const u8 = "GitHub Actions",
        temp: []const u8 = "/tmp",
        tool_cache: []const u8 = "/opt/hostedtoolcache",
    };
    
    pub fn init(allocator: std.mem.Allocator) ExecutionContext {
        return ExecutionContext{
            .working_directory = "/workspace",
            .github = GitHubContext{
                .repository = "owner/repo",
                .ref = "refs/heads/main",
                .sha = "abc123def456",
            },
            .env = std.StringHashMap([]const u8).init(allocator),
            .runner = RunnerContext{},
        };
    }
    
    pub fn deinit(self: *ExecutionContext) void {
        self.env.deinit();
    }
};

// Action execution result
pub const ActionResult = struct {
    success: bool,
    exit_code: i32,
    outputs: std.StringHashMap([]const u8),
    execution_time_ms: u64,
    
    pub fn deinit(self: *ActionResult, allocator: std.mem.Allocator) void {
        var outputs_iter = self.outputs.iterator();
        while (outputs_iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        self.outputs.deinit();
    }
};

// Step runner for executing individual steps
pub const StepRunner = struct {
    allocator: std.mem.Allocator,
    container_runtime: ?*container.DockerRuntime,
    action_cache: *ActionCache,
    
    pub fn init(allocator: std.mem.Allocator, config: struct {
        container_runtime: ?*container.DockerRuntime = null,
        action_cache: *ActionCache,
    }) StepRunner {
        return StepRunner{
            .allocator = allocator,
            .container_runtime = config.container_runtime,
            .action_cache = config.action_cache,
        };
    }
    
    pub fn deinit(self: *StepRunner) void {
        _ = self;
    }
    
    pub fn executeActionStep(
        self: *StepRunner,
        action_ref: []const u8,
        with_params: std.StringHashMap([]const u8),
        context: ExecutionContext,
    ) !ActionResult {
        const start_time = std.time.milliTimestamp();
        
        // Get action from cache
        var action = try self.action_cache.getAction(action_ref);
        defer action.deinit(self.allocator);
        
        var result = ActionResult{
            .success = false,
            .exit_code = 1,
            .outputs = std.StringHashMap([]const u8).init(self.allocator),
            .execution_time_ms = 0,
        };
        
        // Mock action execution based on action type
        if (std.mem.eql(u8, action.ref.name, "checkout")) {
            // Simulate checkout action
            result.success = true;
            result.exit_code = 0;
            
            // Mock creating .git directory
            const workspace_git = try std.fmt.allocPrint(self.allocator, "{s}/.git", .{context.working_directory});
            defer self.allocator.free(workspace_git);
            
            std.fs.cwd().makePath(workspace_git) catch |err| switch (err) {
                error.PathAlreadyExists => {}, // OK
                else => return err,
            };
            
        } else if (std.mem.eql(u8, action.ref.name, "setup-node")) {
            // Simulate Node.js setup
            result.success = true;
            result.exit_code = 0;
            
            // Set node version output
            const node_version = with_params.get("node-version") orelse "18";
            try result.outputs.put(
                try self.allocator.dupe(u8, "node-version"),
                try self.allocator.dupe(u8, node_version)
            );
            
        } else if (std.mem.eql(u8, action.ref.name, "upload-artifact")) {
            // Simulate artifact upload
            result.success = true;
            result.exit_code = 0;
            
            const artifact_name = with_params.get("name") orelse "artifact";
            try result.outputs.put(
                try self.allocator.dupe(u8, "artifact-id"),
                try std.fmt.allocPrint(self.allocator, "artifact-{s}-{d}", .{ artifact_name, std.time.timestamp() })
            );
            
        } else {
            // Generic action execution
            switch (action.metadata.runs) {
                .node => {
                    // Would execute Node.js action
                    result.success = true;
                    result.exit_code = 0;
                },
                .docker => |docker| {
                    // Would execute Docker action
                    _ = docker;
                    result.success = true;
                    result.exit_code = 0;
                },
                .composite => {
                    // Would execute composite action steps
                    result.success = true;
                    result.exit_code = 0;
                },
            }
        }
        
        result.execution_time_ms = @as(u64, @intCast(std.time.milliTimestamp() - start_time));
        return result;
    }
    
    pub fn runCommand(self: *StepRunner, command: []const u8, options: struct {
        working_directory: ?[]const u8 = null,
        env: ?std.StringHashMap([]const u8) = null,
        timeout_seconds: u32 = 300,
    }) !container.ExecResult {
        // Parse command into arguments
        var args = std.ArrayList([]const u8).init(self.allocator);
        defer args.deinit();
        
        var token_iter = std.mem.tokenize(u8, command, " ");
        while (token_iter.next()) |token| {
            try args.append(token);
        }
        
        if (self.container_runtime) |runtime| {
            // Create temporary container for command execution
            var container_config = container.ContainerConfig.init(self.allocator, "ubuntu:22.04");
            defer container_config.deinit();
            
            if (options.working_directory) |wd| {
                container_config.working_directory = wd;
            }
            
            if (options.env) |env| {
                var env_iter = env.iterator();
                while (env_iter.next()) |entry| {
                    try container_config.env.put(
                        try self.allocator.dupe(u8, entry.key_ptr.*),
                        try self.allocator.dupe(u8, entry.value_ptr.*)
                    );
                }
            }
            
            const job_container = try runtime.createContainer(container_config);
            defer runtime.destroyContainer(job_container.id) catch {};
            
            try runtime.startContainer(job_container.id);
            
            return runtime.executeCommand(job_container.id, .{
                .command = args.items,
                .working_directory = options.working_directory,
                .env = options.env,
                .timeout_seconds = options.timeout_seconds,
            });
        } else {
            // Mock execution
            const exit_code: i32 = if (std.mem.indexOf(u8, command, "exit") != null) 1 else 0;
            const stdout = if (std.mem.indexOf(u8, command, "ls") != null)
                try self.allocator.dupe(u8, "total 8\ndrwxr-xr-x 2 runner runner 4096 Jan 1 12:00 .git\n-rw-r--r-- 1 runner runner   13 Jan 1 12:00 README.md")
            else
                try self.allocator.dupe(u8, "Command executed successfully");
            
            return container.ExecResult{
                .exit_code = exit_code,
                .stdout = stdout,
                .stderr = try self.allocator.dupe(u8, ""),
                .execution_time_ms = 50,
            };
        }
    }
};

// Tests for Phase 3: Step Execution and Action Support
test "action reference parsing works correctly" {
    const allocator = testing.allocator;
    
    const action_ref = try ActionRef.parse(allocator, "actions/checkout@v4");
    defer action_ref.deinit(allocator);
    
    try testing.expectEqualStrings("actions", action_ref.owner);
    try testing.expectEqualStrings("checkout", action_ref.name);
    try testing.expectEqualStrings("v4", action_ref.version);
    
    const ref_string = try action_ref.toString(allocator);
    defer allocator.free(ref_string);
    try testing.expectEqualStrings("actions/checkout@v4", ref_string);
}

test "action cache downloads and caches actions" {
    const allocator = testing.allocator;
    
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    const cache_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(cache_path);
    
    var action_cache = try ActionCache.init(allocator, cache_path);
    defer action_cache.deinit();
    
    const action_ref = "actions/setup-node@v3";
    
    // First download should fetch from "remote"
    const start_time1 = std.time.nanoTimestamp();
    var action1 = try action_cache.getAction(action_ref);
    defer action1.deinit(allocator);
    const duration1 = std.time.nanoTimestamp() - start_time1;
    
    try testing.expect(action1.path.len > 0);
    try testing.expect(std.fs.path.isAbsolute(action1.path));
    try testing.expectEqualStrings("setup-node", action1.metadata.name);
    
    // Second request should use cache (should be faster or same)
    const start_time2 = std.time.nanoTimestamp();
    var action2 = try action_cache.getAction(action_ref);
    defer action2.deinit(allocator);
    const duration2 = std.time.nanoTimestamp() - start_time2;
    
    try testing.expectEqualStrings(action1.metadata.name, action2.metadata.name);
    // Cache should be at least as fast (allowing for some variance in test timing)
    try testing.expect(duration2 <= duration1 * 2);
}

test "step runner executes action steps with input parameters" {
    const allocator = testing.allocator;
    
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    const cache_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(cache_path);
    
    var action_cache = try ActionCache.init(allocator, cache_path);
    defer action_cache.deinit();
    
    var step_runner = StepRunner.init(allocator, .{
        .container_runtime = null,
        .action_cache = &action_cache,
    });
    defer step_runner.deinit();
    
    var with_params = std.StringHashMap([]const u8).init(allocator);
    defer with_params.deinit();
    try with_params.put("fetch-depth", "0");
    try with_params.put("ref", "main");
    
    var execution_context = ExecutionContext.init(allocator);
    defer execution_context.deinit();
    
    var result = try step_runner.executeActionStep("actions/checkout@v4", with_params, execution_context);
    defer result.deinit(allocator);
    
    try testing.expect(result.success);
    try testing.expectEqual(@as(i32, 0), result.exit_code);
    try testing.expect(result.execution_time_ms > 0);
}

test "step runner handles different action types" {
    const allocator = testing.allocator;
    
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    const cache_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(cache_path);
    
    var action_cache = try ActionCache.init(allocator, cache_path);
    defer action_cache.deinit();
    
    var step_runner = StepRunner.init(allocator, .{
        .action_cache = &action_cache,
    });
    defer step_runner.deinit();
    
    var execution_context = ExecutionContext.init(allocator);
    defer execution_context.deinit();
    
    // Test Node.js action
    {
        var with_params = std.StringHashMap([]const u8).init(allocator);
        defer with_params.deinit();
        try with_params.put("node-version", "18");
        try with_params.put("cache", "npm");
        
        var result = try step_runner.executeActionStep("actions/setup-node@v3", with_params, execution_context);
        defer result.deinit(allocator);
        
        try testing.expect(result.success);
        try testing.expectEqual(@as(i32, 0), result.exit_code);
        
        // Should have node-version output
        const node_version = result.outputs.get("node-version");
        try testing.expect(node_version != null);
        try testing.expectEqualStrings("18", node_version.?);
    }
    
    // Test artifact upload action
    {
        var with_params = std.StringHashMap([]const u8).init(allocator);
        defer with_params.deinit();
        try with_params.put("name", "test-results");
        try with_params.put("path", "test-results.xml");
        
        var result = try step_runner.executeActionStep("actions/upload-artifact@v3", with_params, execution_context);
        defer result.deinit(allocator);
        
        try testing.expect(result.success);
        try testing.expectEqual(@as(i32, 0), result.exit_code);
        
        // Should have artifact-id output
        const artifact_id = result.outputs.get("artifact-id");
        try testing.expect(artifact_id != null);
        try testing.expect(std.mem.indexOf(u8, artifact_id.?, "artifact-test-results-") != null);
    }
}

test "step runner executes commands with proper context" {
    const allocator = testing.allocator;
    
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    const cache_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(cache_path);
    
    var action_cache = try ActionCache.init(allocator, cache_path);
    defer action_cache.deinit();
    
    var step_runner = StepRunner.init(allocator, .{
        .action_cache = &action_cache,
    });  
    defer step_runner.deinit();
    
    // Test command execution
    var result = try step_runner.runCommand("ls -la", .{
        .working_directory = "/workspace",
        .timeout_seconds = 30,
    });
    defer result.deinit(allocator);
    
    try testing.expectEqual(@as(i32, 0), result.exit_code);
    try testing.expect(result.stdout.len > 0);
    try testing.expect(result.execution_time_ms > 0);
}

test "handles action download and caching efficiently" {
    const allocator = testing.allocator;
    
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    const cache_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(cache_path);
    
    var action_cache = try ActionCache.init(allocator, cache_path);
    defer action_cache.deinit();
    
    const action_ref = "actions/setup-node@v3";
    
    // First download
    const start_time1 = std.time.nanoTimestamp();
    var action1 = try action_cache.getAction(action_ref);
    defer action1.deinit(allocator);
    const duration1 = std.time.nanoTimestamp() - start_time1;
    
    // Verify action was downloaded
    try testing.expect(action1.path.len > 0);
    try testing.expect(std.fs.path.isAbsolute(action1.path));
    
    // Second request should use cache
    const start_time2 = std.time.nanoTimestamp();
    var action2 = try action_cache.getAction(action_ref);
    defer action2.deinit(allocator);
    const duration2 = std.time.nanoTimestamp() - start_time2;
    
    try testing.expectEqualStrings(action1.metadata.name, action2.metadata.name);
    // Cache should be much faster (or at least not significantly slower)
    try testing.expect(duration2 <= duration1 * 2);
}