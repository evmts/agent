//! Workflow Plan Data Structures
//!
//! Represents the output of workflow evaluation - a DAG of steps to be executed.

const std = @import("std");

/// Recursively free a JSON value and all its contents
/// Note: This assumes all strings/objects/arrays were allocated with the same allocator
/// and are owned by this JSON value. Don't use this if the JSON contains references
/// to static strings or externally-owned data.
fn deinitJsonValue(value: std.json.Value, allocator: std.mem.Allocator) void {
    switch (value) {
        .object => |*obj| {
            // First, recursively free all values
            var iter = obj.iterator();
            while (iter.next()) |entry| {
                deinitJsonValue(entry.value_ptr.*, allocator);
            }
            // Then free all keys (ObjectMap stores pointers to keys, doesn't copy them)
            iter = obj.iterator();
            while (iter.next()) |entry| {
                allocator.free(entry.key_ptr.*);
            }
            // Finally, deinit the ObjectMap structure itself
            @constCast(obj).deinit();
        },
        .array => |*arr| {
            for (arr.items) |item| {
                deinitJsonValue(item, allocator);
            }
            @constCast(arr).deinit();
        },
        .string => |str| {
            allocator.free(str);
        },
        .number_string => |str| {
            allocator.free(str);
        },
        // Other types (bool, null, integer, float) don't need cleanup
        else => {},
    }
}

/// Step type discriminator
pub const StepType = enum {
    shell, // Shell command execution
    llm, // Single LLM call with input/output
    agent, // Multi-turn agent with tools
    parallel, // Parallel execution group

    pub fn toString(self: StepType) []const u8 {
        return switch (self) {
            .shell => "shell",
            .llm => "llm",
            .agent => "agent",
            .parallel => "parallel",
        };
    }
};

/// Trigger type discriminator
pub const TriggerType = enum {
    push,
    pull_request,
    issue_comment,
    manual,
    schedule,

    pub fn toString(self: TriggerType) []const u8 {
        return switch (self) {
            .push => "push",
            .pull_request => "pull_request",
            .issue_comment => "issue_comment",
            .manual => "manual",
            .schedule => "schedule",
        };
    }
};

/// Trigger configuration
pub const Trigger = struct {
    type: TriggerType,
    config: std.json.Value, // JSON config specific to trigger type

    pub fn deinit(self: *Trigger, allocator: std.mem.Allocator) void {
        // Recursively free JSON value
        deinitJsonValue(self.config, allocator);
    }
};

/// Step configuration (type-specific)
pub const StepConfig = struct {
    data: std.json.Value, // JSON blob with step-specific config

    pub fn deinit(self: *StepConfig, allocator: std.mem.Allocator) void {
        // Recursively free JSON value
        deinitJsonValue(self.data, allocator);
    }
};

/// A single step in the workflow plan
pub const Step = struct {
    id: []const u8, // Unique step identifier
    name: []const u8, // Human-readable name
    type: StepType, // Type of step (JSON field is "type", not "step_type")
    config: StepConfig, // Type-specific configuration
    depends_on: []const []const u8, // IDs of steps this depends on

    pub fn deinit(self: *Step, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.name);
        self.config.deinit(allocator);
        for (self.depends_on) |dep| {
            allocator.free(dep);
        }
        allocator.free(self.depends_on);
    }
};

/// Complete workflow definition
pub const WorkflowDefinition = struct {
    name: []const u8, // Workflow name (from function name)
    triggers: []Trigger, // Trigger configurations
    image: ?[]const u8, // Docker image (or null for default)
    dockerfile: ?[]const u8, // Path to Dockerfile (or null)
    steps: []Step, // Ordered list of steps

    pub fn deinit(self: *WorkflowDefinition, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        for (self.triggers) |*trigger| {
            trigger.deinit(allocator);
        }
        allocator.free(self.triggers);
        if (self.image) |image| {
            allocator.free(image);
        }
        if (self.dockerfile) |dockerfile| {
            allocator.free(dockerfile);
        }
        for (self.steps) |*step| {
            step.deinit(allocator);
        }
        allocator.free(self.steps);
    }

    /// Convert workflow definition to JSON for storage
    pub fn toJson(self: *const WorkflowDefinition, allocator: std.mem.Allocator) !std.json.Value {
        var obj = std.json.ObjectMap.init(allocator);
        errdefer obj.deinit();

        try obj.put("name", .{ .string = self.name });

        // Convert triggers
        var triggers_array = std.json.Array.init(allocator);
        for (self.triggers) |trigger| {
            var trigger_obj = std.json.ObjectMap.init(allocator);
            try trigger_obj.put("type", .{ .string = trigger.type.toString() });
            try trigger_obj.put("config", trigger.config);
            try triggers_array.append(.{ .object = trigger_obj });
        }
        try obj.put("triggers", .{ .array = triggers_array });

        // Image and dockerfile
        if (self.image) |image| {
            try obj.put("image", .{ .string = image });
        } else {
            try obj.put("image", .null);
        }
        if (self.dockerfile) |dockerfile| {
            try obj.put("dockerfile", .{ .string = dockerfile });
        } else {
            try obj.put("dockerfile", .null);
        }

        // Convert steps
        var steps_array = std.json.Array.init(allocator);
        for (self.steps) |step| {
            var step_obj = std.json.ObjectMap.init(allocator);
            try step_obj.put("id", .{ .string = step.id });
            try step_obj.put("name", .{ .string = step.name });
            try step_obj.put("type", .{ .string = step.type.toString() });

            // Wrap config.data in an object so it can be parsed back into StepConfig
            var config_wrapper = std.json.ObjectMap.init(allocator);
            try config_wrapper.put("data", step.config.data);
            try step_obj.put("config", .{ .object = config_wrapper });

            var deps_array = std.json.Array.init(allocator);
            for (step.depends_on) |dep| {
                try deps_array.append(.{ .string = dep });
            }
            try step_obj.put("depends_on", .{ .array = deps_array });

            try steps_array.append(.{ .object = step_obj });
        }
        try obj.put("steps", .{ .array = steps_array });

        return .{ .object = obj };
    }
};

/// Result of evaluating a workflow file
pub const PlanSet = struct {
    workflows: []WorkflowDefinition, // All workflows defined in the file
    errors: []PlanError, // Any errors encountered

    pub fn deinit(self: *PlanSet, allocator: std.mem.Allocator) void {
        for (self.workflows) |*workflow| {
            workflow.deinit(allocator);
        }
        allocator.free(self.workflows);
        for (self.errors) |*err| {
            err.deinit(allocator);
        }
        allocator.free(self.errors);
    }
};

/// Error during plan generation
pub const PlanError = struct {
    message: []const u8,
    file: ?[]const u8,
    line: ?usize,
    column: ?usize,

    pub fn deinit(self: *PlanError, allocator: std.mem.Allocator) void {
        allocator.free(self.message);
        if (self.file) |file| {
            allocator.free(file);
        }
    }
};

test "Step lifecycle" {
    const allocator = std.testing.allocator;

    var config_map = std.json.ObjectMap.init(allocator);
    // Allocate both key and value so they can be properly freed
    const key = try allocator.dupe(u8, "cmd");
    try config_map.put(key, .{ .string = try allocator.dupe(u8, "echo hello") });

    var step = Step{
        .id = try allocator.dupe(u8, "step_1"),
        .name = try allocator.dupe(u8, "test"),
        .type = .shell,
        .config = .{ .data = .{ .object = config_map } },
        .depends_on = &.{},
    };

    try std.testing.expectEqualStrings("step_1", step.id);
    try std.testing.expectEqualStrings("test", step.name);
    try std.testing.expectEqual(StepType.shell, step.type);

    // step.deinit() will free the config_map and all its contents (keys and values)
    step.deinit(allocator);
}
