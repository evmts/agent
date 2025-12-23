//! Workflow Plan Validation
//!
//! Validates workflow plans for:
//! - DAG acyclicity (no circular dependencies)
//! - Unique step IDs
//! - Valid step dependencies (all deps exist)
//! - Proper step configuration

const std = @import("std");
const plan = @import("plan.zig");

pub const ValidationError = error{
    DuplicateStepId,
    MissingDependency,
    CircularDependency,
    EmptyStepId,
    EmptyWorkflowName,
    NoSteps,
    OutOfMemory,
};

pub const ValidationResult = struct {
    valid: bool,
    errors: []ValidationIssue,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *ValidationResult) void {
        for (self.errors) |*err| {
            self.allocator.free(err.message);
        }
        self.allocator.free(self.errors);
    }

    pub fn isValid(self: *const ValidationResult) bool {
        return self.errors.len == 0;
    }
};

pub const ValidationIssue = struct {
    step_id: ?[]const u8, // null for workflow-level issues
    message: []const u8,
};

/// Validate a complete workflow definition
pub fn validateWorkflow(
    allocator: std.mem.Allocator,
    workflow: *const plan.WorkflowDefinition,
) !ValidationResult {
    var issues: std.ArrayList(ValidationIssue) = .{};
    errdefer {
        for (issues.items) |*issue| {
            allocator.free(issue.message);
        }
        issues.deinit(allocator);
    }

    // Validate workflow name
    if (workflow.name.len == 0) {
        try issues.append(allocator, .{
            .step_id = null,
            .message = try allocator.dupe(u8, "Workflow name cannot be empty"),
        });
    }

    // Validate has steps
    if (workflow.steps.len == 0) {
        try issues.append(allocator, .{
            .step_id = null,
            .message = try allocator.dupe(u8, "Workflow must have at least one step"),
        });
        return ValidationResult{
            .valid = false,
            .errors = try issues.toOwnedSlice(allocator),
            .allocator = allocator,
        };
    }

    // Check for duplicate step IDs
    try checkDuplicateStepIds(allocator, workflow.steps, &issues);

    // Check for empty step IDs
    for (workflow.steps) |step| {
        if (step.id.len == 0) {
            try issues.append(allocator, .{
                .step_id = null,
                .message = try allocator.dupe(u8, "Step has empty ID"),
            });
        }
    }

    // Check dependencies exist
    try checkDependenciesExist(allocator, workflow.steps, &issues);

    // Check for cycles
    try checkForCycles(allocator, workflow.steps, &issues);

    return ValidationResult{
        .valid = issues.items.len == 0,
        .errors = try issues.toOwnedSlice(allocator),
        .allocator = allocator,
    };
}

/// Check for duplicate step IDs
fn checkDuplicateStepIds(
    allocator: std.mem.Allocator,
    steps: []const plan.Step,
    issues: *std.ArrayList(ValidationIssue),
) !void {
    var seen = std.StringHashMap(void).init(allocator);
    defer seen.deinit();

    for (steps) |step| {
        const result = try seen.getOrPut(step.id);
        if (result.found_existing) {
            const msg = try std.fmt.allocPrint(
                allocator,
                "Duplicate step ID: {s}",
                .{step.id},
            );
            try issues.append(allocator, .{
                .step_id = step.id,
                .message = msg,
            });
        }
    }
}

/// Check that all dependencies refer to existing steps
fn checkDependenciesExist(
    allocator: std.mem.Allocator,
    steps: []const plan.Step,
    issues: *std.ArrayList(ValidationIssue),
) !void {
    // Build set of all step IDs
    var step_ids = std.StringHashMap(void).init(allocator);
    defer step_ids.deinit();

    for (steps) |step| {
        try step_ids.put(step.id, {});
    }

    // Check each dependency
    for (steps) |step| {
        for (step.depends_on) |dep_id| {
            if (!step_ids.contains(dep_id)) {
                const msg = try std.fmt.allocPrint(
                    allocator,
                    "Step '{s}' depends on non-existent step '{s}'",
                    .{ step.id, dep_id },
                );
                try issues.append(allocator, .{
                    .step_id = step.id,
                    .message = msg,
                });
            }
        }
    }
}

/// Visit state for cycle detection
const VisitState = enum { unvisited, visiting, visited };

/// Check for circular dependencies using depth-first search
fn checkForCycles(
    allocator: std.mem.Allocator,
    steps: []const plan.Step,
    issues: *std.ArrayList(ValidationIssue),
) !void {
    // Build adjacency list
    var graph = std.StringHashMap([]const []const u8).init(allocator);
    defer {
        var it = graph.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
        }
        graph.deinit();
    }

    for (steps) |step| {
        // Check if this step ID already exists in the graph
        if (!graph.contains(step.id)) {
            const key = try allocator.dupe(u8, step.id);
            try graph.put(key, step.depends_on);
        }
        // If it's a duplicate, just skip it (validation will catch it later)
    }

    // Track visited states for cycle detection
    var visit_state = std.StringHashMap(VisitState).init(allocator);
    defer visit_state.deinit();

    for (steps) |step| {
        try visit_state.put(step.id, .unvisited);
    }

    // Detect cycles using DFS
    var cycle_path: std.ArrayList([]const u8) = .{};
    defer cycle_path.deinit(allocator);

    for (steps) |step| {
        const state = visit_state.get(step.id) orelse .unvisited;
        if (state == .unvisited) {
            if (try hasCycle(step.id, &graph, &visit_state, &cycle_path, allocator)) {
                // Found a cycle - report it
                var path_str: std.ArrayList(u8) = .{};
                defer path_str.deinit(allocator);

                for (cycle_path.items, 0..) |id, i| {
                    if (i > 0) try path_str.appendSlice(allocator, " -> ");
                    try path_str.appendSlice(allocator, id);
                }

                const msg = try std.fmt.allocPrint(
                    allocator,
                    "Circular dependency detected: {s}",
                    .{path_str.items},
                );
                try issues.append(allocator, .{
                    .step_id = step.id,
                    .message = msg,
                });

                // Only report first cycle found
                return;
            }
        }
    }
}

/// Recursive DFS to detect cycles
fn hasCycle(
    node: []const u8,
    graph: *std.StringHashMap([]const []const u8),
    visit_state: *std.StringHashMap(VisitState),
    path: *std.ArrayList([]const u8),
    allocator: std.mem.Allocator,
) !bool {
    // Mark as visiting
    try visit_state.put(node, .visiting);
    try path.append(allocator, node);

    // Visit dependencies
    if (graph.get(node)) |deps| {
        for (deps) |dep| {
            const state = visit_state.get(dep) orelse .unvisited;

            if (state == .visiting) {
                // Found a back edge - cycle detected
                try path.append(allocator, dep);
                return true;
            }

            if (state == .unvisited) {
                if (try hasCycle(dep, graph, visit_state, path, allocator)) {
                    return true;
                }
            }
        }
    }

    // Mark as visited and remove from path
    try visit_state.put(node, .visited);
    _ = path.pop();

    return false;
}

// ============================================================================
// Tests
// ============================================================================

test "valid workflow passes validation" {
    const allocator = std.testing.allocator;

    var steps = [_]plan.Step{
        .{
            .id = "step1",
            .name = "First step",
            .step_type = .shell,
            .config = .{ .data = .{ .object = std.json.ObjectMap.init(allocator) } },
            .depends_on = &.{},
        },
        .{
            .id = "step2",
            .name = "Second step",
            .step_type = .shell,
            .config = .{ .data = .{ .object = std.json.ObjectMap.init(allocator) } },
            .depends_on = &.{"step1"},
        },
    };

    const workflow = plan.WorkflowDefinition{
        .name = "test-workflow",
        .triggers = &.{},
        .image = null,
        .dockerfile = null,
        .steps = &steps,
    };

    var result = try validateWorkflow(allocator, &workflow);
    defer result.deinit();

    try std.testing.expect(result.isValid());
    try std.testing.expectEqual(@as(usize, 0), result.errors.len);
}

test "detects duplicate step IDs" {
    const allocator = std.testing.allocator;

    var steps = [_]plan.Step{
        .{
            .id = "step1",
            .name = "First step",
            .step_type = .shell,
            .config = .{ .data = .{ .object = std.json.ObjectMap.init(allocator) } },
            .depends_on = &.{},
        },
        .{
            .id = "step1", // Duplicate!
            .name = "Second step",
            .step_type = .shell,
            .config = .{ .data = .{ .object = std.json.ObjectMap.init(allocator) } },
            .depends_on = &.{},
        },
    };

    const workflow = plan.WorkflowDefinition{
        .name = "test-workflow",
        .triggers = &.{},
        .image = null,
        .dockerfile = null,
        .steps = &steps,
    };

    var result = try validateWorkflow(allocator, &workflow);
    defer result.deinit();

    try std.testing.expect(!result.isValid());
    try std.testing.expect(result.errors.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, result.errors[0].message, "Duplicate") != null);
}

test "detects missing dependencies" {
    const allocator = std.testing.allocator;

    var steps = [_]plan.Step{
        .{
            .id = "step1",
            .name = "First step",
            .step_type = .shell,
            .config = .{ .data = .{ .object = std.json.ObjectMap.init(allocator) } },
            .depends_on = &.{"nonexistent"}, // Missing!
        },
    };

    const workflow = plan.WorkflowDefinition{
        .name = "test-workflow",
        .triggers = &.{},
        .image = null,
        .dockerfile = null,
        .steps = &steps,
    };

    var result = try validateWorkflow(allocator, &workflow);
    defer result.deinit();

    try std.testing.expect(!result.isValid());
    try std.testing.expect(result.errors.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, result.errors[0].message, "non-existent") != null);
}

test "detects circular dependencies" {
    const allocator = std.testing.allocator;

    var steps = [_]plan.Step{
        .{
            .id = "step1",
            .name = "First step",
            .step_type = .shell,
            .config = .{ .data = .{ .object = std.json.ObjectMap.init(allocator) } },
            .depends_on = &.{"step2"},
        },
        .{
            .id = "step2",
            .name = "Second step",
            .step_type = .shell,
            .config = .{ .data = .{ .object = std.json.ObjectMap.init(allocator) } },
            .depends_on = &.{"step1"}, // Cycle: step1 -> step2 -> step1
        },
    };

    const workflow = plan.WorkflowDefinition{
        .name = "test-workflow",
        .triggers = &.{},
        .image = null,
        .dockerfile = null,
        .steps = &steps,
    };

    var result = try validateWorkflow(allocator, &workflow);
    defer result.deinit();

    try std.testing.expect(!result.isValid());
    try std.testing.expect(result.errors.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, result.errors[0].message, "Circular") != null);
}

test "detects empty workflow name" {
    const allocator = std.testing.allocator;

    var steps = [_]plan.Step{
        .{
            .id = "step1",
            .name = "First step",
            .step_type = .shell,
            .config = .{ .data = .{ .object = std.json.ObjectMap.init(allocator) } },
            .depends_on = &.{},
        },
    };

    const workflow = plan.WorkflowDefinition{
        .name = "", // Empty!
        .triggers = &.{},
        .image = null,
        .dockerfile = null,
        .steps = &steps,
    };

    var result = try validateWorkflow(allocator, &workflow);
    defer result.deinit();

    try std.testing.expect(!result.isValid());
    try std.testing.expect(result.errors.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, result.errors[0].message, "name cannot be empty") != null);
}

test "detects workflow with no steps" {
    const allocator = std.testing.allocator;

    const workflow = plan.WorkflowDefinition{
        .name = "test-workflow",
        .triggers = &.{},
        .image = null,
        .dockerfile = null,
        .steps = &.{}, // No steps!
    };

    var result = try validateWorkflow(allocator, &workflow);
    defer result.deinit();

    try std.testing.expect(!result.isValid());
    try std.testing.expect(result.errors.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, result.errors[0].message, "at least one step") != null);
}
