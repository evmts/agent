const std = @import("std");
const pg = @import("pg");
const db = @import("db");
const evaluator = @import("evaluator.zig");
const prompt = @import("prompt.zig");
const validation = @import("validation.zig");
const plan = @import("plan.zig");
const json = @import("../lib/json.zig");

/// Convert triggers array to JSON string
fn triggersToJsonString(allocator: std.mem.Allocator, triggers: []const plan.Trigger) ![]const u8 {
    var list = try std.ArrayList(u8).initCapacity(allocator, 256);
    errdefer list.deinit(allocator);

    const writer = list.writer(allocator);

    try writer.writeByte('[');
    for (triggers, 0..) |trigger, i| {
        if (i > 0) try writer.writeByte(',');

        try writer.writeByte('{');
        try writer.writeAll("\"type\":\"");
        try writer.writeAll(trigger.type.toString());
        try writer.writeAll("\",\"config\":");

        // Convert config std.json.Value to string
        const config_str = try json.valueToString(allocator, trigger.config);
        defer allocator.free(config_str);
        try writer.writeAll(config_str);

        try writer.writeByte('}');
    }
    try writer.writeByte(']');

    return try list.toOwnedSlice(allocator);
}

/// File discovery and definition registry for workflows and prompts
pub const Registry = struct {
    allocator: std.mem.Allocator,
    pool: *pg.Pool,

    pub fn init(allocator: std.mem.Allocator, pool: *pg.Pool) Registry {
        return .{
            .allocator = allocator,
            .pool = pool,
        };
    }

    /// Discover and parse all workflow and prompt definitions for a repository
    pub fn discoverAndParse(self: *Registry, repo_path: []const u8, repo_id: i32) !DiscoveryResult {
        var result = DiscoveryResult.init(self.allocator);
        errdefer result.deinit(self.allocator);

        // Discover workflow files
        const workflow_dir = try std.fs.path.join(self.allocator, &.{ repo_path, ".plue", "workflows" });
        defer self.allocator.free(workflow_dir);

        try self.discoverWorkflows(workflow_dir, repo_id, &result);

        // Discover prompt files
        const prompt_dir = try std.fs.path.join(self.allocator, &.{ repo_path, ".plue", "prompts" });
        defer self.allocator.free(prompt_dir);

        try self.discoverPrompts(prompt_dir, repo_id, &result);

        return result;
    }

    /// Discover and parse workflow files in a directory
    fn discoverWorkflows(self: *Registry, dir_path: []const u8, repo_id: i32, result: *DiscoveryResult) !void {
        var dir = std.fs.openDirAbsolute(dir_path, .{ .iterate = true }) catch |err| {
            if (err == error.FileNotFound) {
                // .plue/workflows directory doesn't exist - that's okay
                return;
            }
            return err;
        };
        defer dir.close();

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind != .file) continue;
            if (!std.mem.endsWith(u8, entry.name, ".py")) continue;

            const file_path = try std.fs.path.join(self.allocator, &.{ dir_path, entry.name });
            defer self.allocator.free(file_path);

            // Compute content hash
            const content_hash = try computeFileHash(self.allocator, file_path);
            defer self.allocator.free(content_hash);

            // Check if definition already exists with same hash
            const existing = try self.getWorkflowByPath(repo_id, file_path);
            if (existing) |def| {
                defer def.deinit(self.allocator);
                if (std.mem.eql(u8, def.content_hash, content_hash)) {
                    // File unchanged - skip parsing
                    try result.skipped_workflows.append(file_path);
                    continue;
                }
            }

            // Parse workflow
            self.parseAndStoreWorkflow(repo_id, file_path, content_hash, result) catch |err| {
                try result.workflow_errors.append(ParseError{
                    .file_path = try self.allocator.dupe(u8, file_path),
                    .error_message = try std.fmt.allocPrint(self.allocator, "Parse error: {}", .{err}),
                });
                continue;
            };
        }
    }

    /// Discover and parse prompt files in a directory
    fn discoverPrompts(self: *Registry, dir_path: []const u8, repo_id: i32, result: *DiscoveryResult) !void {
        var dir = std.fs.openDirAbsolute(dir_path, .{ .iterate = true }) catch |err| {
            if (err == error.FileNotFound) {
                // .plue/prompts directory doesn't exist - that's okay
                return;
            }
            return err;
        };
        defer dir.close();

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind != .file) continue;
            if (!std.mem.endsWith(u8, entry.name, ".prompt.md")) continue;

            const file_path = try std.fs.path.join(self.allocator, &.{ dir_path, entry.name });
            defer self.allocator.free(file_path);

            // Compute content hash
            const content_hash = try computeFileHash(self.allocator, file_path);
            defer self.allocator.free(content_hash);

            // Check if definition already exists with same hash
            const existing = try self.getPromptByPath(repo_id, file_path);
            if (existing) |def| {
                defer def.deinit();
                if (std.mem.eql(u8, def.content_hash, content_hash)) {
                    // File unchanged - skip parsing
                    try result.skipped_prompts.append(file_path);
                    continue;
                }
            }

            // Parse prompt
            self.parseAndStorePrompt(repo_id, file_path, content_hash, result) catch |err| {
                try result.prompt_errors.append(ParseError{
                    .file_path = try self.allocator.dupe(u8, file_path),
                    .error_message = try std.fmt.allocPrint(self.allocator, "Parse error: {}", .{err}),
                });
                continue;
            };
        }
    }

    /// Parse and store a workflow definition
    fn parseAndStoreWorkflow(self: *Registry, repo_id: i32, file_path: []const u8, content_hash: []const u8, result: *DiscoveryResult) !void {
        // Parse workflow file
        var eval = evaluator.Evaluator.init(self.allocator);
        defer eval.deinit();

        var plan_set = try eval.evaluateFile(file_path);
        defer plan_set.deinit();

        // Each workflow definition in the file
        for (plan_set.workflows.items) |*workflow| {
            // Validate workflow plan
            const validation_result = try validation.validateWorkflow(self.allocator, workflow);
            defer validation_result.deinit();

            if (!validation_result.valid) {
                // Collect validation errors
                var error_msg = std.ArrayList(u8).init(self.allocator);
                defer error_msg.deinit();

                const writer = error_msg.writer();
                try writer.print("Validation failed for workflow '{s}':\n", .{workflow.name});
                for (validation_result.errors.items) |err| {
                    try writer.print("  - {s}\n", .{err});
                }

                try result.workflow_errors.append(ParseError{
                    .file_path = try self.allocator.dupe(u8, file_path),
                    .error_message = try error_msg.toOwnedSlice(),
                });
                continue;
            }

            // Convert to JSON for storage
            const plan_json = try workflow.toJson(self.allocator);
            defer self.allocator.free(plan_json);

            // Manually construct triggers JSON array
            const triggers_json = try triggersToJsonString(self.allocator, workflow.triggers);
            defer self.allocator.free(triggers_json);

            // Store in database (using DAO from db/daos/workflows.zig)
            const workflow_id = try self.upsertWorkflowDefinition(repo_id, workflow.name, file_path, triggers_json, workflow.image, workflow.dockerfile, plan_json, content_hash);

            try result.parsed_workflows.append(WorkflowSummary{
                .id = workflow_id,
                .name = try self.allocator.dupe(u8, workflow.name),
                .file_path = try self.allocator.dupe(u8, file_path),
            });
        }
    }

    /// Parse and store a prompt definition
    fn parseAndStorePrompt(self: *Registry, repo_id: i32, file_path: []const u8, content_hash: []const u8, result: *DiscoveryResult) !void {
        // Parse prompt file
        var prompt_def = try prompt.parsePromptFile(self.allocator, file_path);
        defer prompt_def.deinit();

        // Validate schemas if needed (basic validation already done in parser)
        // Could add more validation here if needed

        // Store in database
        const prompt_id = try self.upsertPromptDefinition(
            repo_id,
            prompt_def.name,
            file_path,
            prompt_def.client,
            prompt_def.prompt_type,
            prompt_def.inputs_schema,
            prompt_def.output_schema,
            prompt_def.tools_json,
            prompt_def.max_turns,
            prompt_def.body_template,
            content_hash,
        );

        try result.parsed_prompts.append(PromptSummary{
            .id = prompt_id,
            .name = try self.allocator.dupe(u8, prompt_def.name),
            .file_path = try self.allocator.dupe(u8, file_path),
        });
    }

    // Database access methods (wrappers around DAO functions)

    fn getWorkflowByPath(self: *Registry, repo_id: i32, file_path: []const u8) !?WorkflowDefinitionSummary {
        const def = try db.workflows.getWorkflowDefinitionByPath(self.pool, repo_id, file_path) orelse return null;

        return WorkflowDefinitionSummary{
            .id = def.id,
            .name = try self.allocator.dupe(u8, def.name),
            .file_path = try self.allocator.dupe(u8, def.file_path),
            .content_hash = try self.allocator.dupe(u8, def.content_hash),
        };
    }

    fn getPromptByPath(self: *Registry, repo_id: i32, file_path: []const u8) !?PromptDefinitionSummary {
        const def = try db.workflows.getPromptDefinitionByPath(self.pool, repo_id, file_path) orelse return null;

        return PromptDefinitionSummary{
            .id = def.id,
            .name = try self.allocator.dupe(u8, def.name),
            .file_path = try self.allocator.dupe(u8, def.file_path),
            .content_hash = try self.allocator.dupe(u8, def.content_hash),
        };
    }

    fn upsertWorkflowDefinition(
        self: *Registry,
        repo_id: i32,
        name: []const u8,
        file_path: []const u8,
        triggers_json: []const u8,
        image: ?[]const u8,
        dockerfile: ?[]const u8,
        plan_json: []const u8,
        content_hash: []const u8,
    ) !i32 {
        return try db.workflows.upsertWorkflowDefinition(
            self.pool,
            repo_id,
            name,
            file_path,
            triggers_json,
            image,
            dockerfile,
            plan_json,
            content_hash,
        );
    }

    fn upsertPromptDefinition(
        self: *Registry,
        repo_id: i32,
        name: []const u8,
        file_path: []const u8,
        client: []const u8,
        prompt_type: []const u8,
        inputs_schema: []const u8,
        output_schema: []const u8,
        tools_json: []const u8,
        max_turns: ?i32,
        body_template: []const u8,
        content_hash: []const u8,
    ) !i32 {
        return try db.workflows.upsertPromptDefinition(
            self.pool,
            repo_id,
            name,
            file_path,
            client,
            prompt_type,
            inputs_schema,
            output_schema,
            tools_json,
            max_turns,
            body_template,
            content_hash,
        );
    }
};

/// Result of discovery and parsing operation
pub const DiscoveryResult = struct {
    parsed_workflows: std.ArrayList(WorkflowSummary),
    parsed_prompts: std.ArrayList(PromptSummary),
    skipped_workflows: std.ArrayList([]const u8),
    skipped_prompts: std.ArrayList([]const u8),
    workflow_errors: std.ArrayList(ParseError),
    prompt_errors: std.ArrayList(ParseError),

    pub fn init(allocator: std.mem.Allocator) DiscoveryResult {
        _ = allocator;
        return .{
            .parsed_workflows = std.ArrayList(WorkflowSummary){},
            .parsed_prompts = std.ArrayList(PromptSummary){},
            .skipped_workflows = std.ArrayList([]const u8){},
            .skipped_prompts = std.ArrayList([]const u8){},
            .workflow_errors = std.ArrayList(ParseError){},
            .prompt_errors = std.ArrayList(ParseError){},
        };
    }

    pub fn deinit(self: *DiscoveryResult, allocator: std.mem.Allocator) void {
        for (self.parsed_workflows.items) |item| {
            item.deinit();
        }
        self.parsed_workflows.deinit(allocator);

        for (self.parsed_prompts.items) |item| {
            item.deinit();
        }
        self.parsed_prompts.deinit(allocator);

        for (self.skipped_workflows.items) |path| {
            // Paths are not owned by DiscoveryResult in skipped lists
            _ = path;
        }
        self.skipped_workflows.deinit(allocator);

        for (self.skipped_prompts.items) |path| {
            _ = path;
        }
        self.skipped_prompts.deinit(allocator);

        for (self.workflow_errors.items) |err| {
            err.deinit();
        }
        self.workflow_errors.deinit(allocator);

        for (self.prompt_errors.items) |err| {
            err.deinit();
        }
        self.prompt_errors.deinit(allocator);
    }
};

pub const WorkflowSummary = struct {
    id: i32,
    name: []const u8,
    file_path: []const u8,

    pub fn deinit(self: WorkflowSummary) void {
        _ = self;
        // Names and paths are owned by caller
    }
};

pub const PromptSummary = struct {
    id: i32,
    name: []const u8,
    file_path: []const u8,

    pub fn deinit(self: PromptSummary) void {
        _ = self;
        // Names and paths are owned by caller
    }
};

pub const ParseError = struct {
    file_path: []const u8,
    error_message: []const u8,

    pub fn deinit(self: ParseError) void {
        _ = self;
        // Owned by allocator
    }
};

pub const WorkflowDefinitionSummary = struct {
    id: i32,
    name: []const u8,
    file_path: []const u8,
    content_hash: []const u8,

    pub fn deinit(self: WorkflowDefinitionSummary, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.file_path);
        allocator.free(self.content_hash);
    }
};

pub const PromptDefinitionSummary = struct {
    id: i32,
    name: []const u8,
    file_path: []const u8,
    content_hash: []const u8,

    pub fn deinit(self: PromptDefinitionSummary) void {
        _ = self;
        // Owned by allocator
    }
};

/// Compute SHA-256 hash of file contents
pub fn computeFileHash(allocator: std.mem.Allocator, file_path: []const u8) ![]const u8 {
    const file = try std.fs.openFileAbsolute(file_path, .{});
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 10 * 1024 * 1024); // 10MB max
    defer allocator.free(content);

    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(content, &hash, .{});

    // Convert to hex string
    const hex = try allocator.alloc(u8, 64);
    _ = try std.fmt.bufPrint(hex, "{s}", .{std.fmt.bytesToHex(hash, .lower)});

    return hex;
}

// Tests
const testing = std.testing;

test "computeFileHash produces consistent hashes" {
    const allocator = testing.allocator;

    // Create a temporary file
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const test_content = "test content for hashing";
    const file_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(file_path);

    const full_path = try std.fs.path.join(allocator, &.{ file_path, "test.txt" });
    defer allocator.free(full_path);

    {
        const file = try std.fs.createFileAbsolute(full_path, .{});
        defer file.close();
        try file.writeAll(test_content);
    }

    // Compute hash twice
    const hash1 = try computeFileHash(allocator, full_path);
    defer allocator.free(hash1);

    const hash2 = try computeFileHash(allocator, full_path);
    defer allocator.free(hash2);

    try testing.expectEqualStrings(hash1, hash2);
    try testing.expect(hash1.len == 64); // SHA-256 in hex is 64 characters
}

test "computeFileHash changes when file content changes" {
    const allocator = testing.allocator;

    // Create a temporary file
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const file_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(file_path);

    const full_path = try std.fs.path.join(allocator, &.{ file_path, "test-workflow.py" });
    defer allocator.free(full_path);

    // Write initial content
    {
        const file = try std.fs.createFileAbsolute(full_path, .{});
        defer file.close();
        try file.writeAll("initial content");
    }

    const hash1 = try computeFileHash(allocator, full_path);
    defer allocator.free(hash1);

    // Modify content
    {
        const file = try std.fs.createFileAbsolute(full_path, .{});
        defer file.close();
        try file.writeAll("modified content");
    }

    const hash2 = try computeFileHash(allocator, full_path);
    defer allocator.free(hash2);

    // Hashes should be different
    try testing.expect(!std.mem.eql(u8, hash1, hash2));
}

test "DiscoveryResult lifecycle" {
    const allocator = testing.allocator;

    var result = DiscoveryResult.init(allocator);
    defer result.deinit(allocator);

    try result.parsed_workflows.append(allocator, WorkflowSummary{
        .id = 1,
        .name = "test",
        .file_path = "/test/path",
    });

    try result.parsed_prompts.append(allocator, PromptSummary{
        .id = 2,
        .name = "TestPrompt",
        .file_path = "/test/path/prompt.md",
    });

    try testing.expectEqual(@as(usize, 1), result.parsed_workflows.items.len);
    try testing.expectEqual(@as(usize, 1), result.parsed_prompts.items.len);
}

test "WorkflowDefinitionSummary lifecycle" {
    const allocator = testing.allocator;

    const workflow_sum = WorkflowDefinitionSummary{
        .id = 1,
        .name = try allocator.dupe(u8, "test-workflow"),
        .file_path = try allocator.dupe(u8, "/path/to/workflow.py"),
        .content_hash = try allocator.dupe(u8, "abc123"),
    };
    defer workflow_sum.deinit(allocator);

    try testing.expectEqual(@as(i32, 1), workflow_sum.id);
    try testing.expectEqualStrings("test-workflow", workflow_sum.name);
}
