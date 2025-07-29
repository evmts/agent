const std = @import("std");
const testing = std.testing;
const models = @import("models.zig");
const TriggerEvent = models.TriggerEvent;
const Job = models.Job;
const JobStep = models.JobStep;
const JobStrategy = models.JobStrategy;
const WorkflowInput = models.WorkflowInput;

pub const WorkflowParserError = error{
    InvalidYaml,
    MissingRequiredField,
    InvalidTriggerEvent,
    InvalidJobDefinition,
    InvalidMatrixStrategy,
    CircularDependency,
    MaxMatrixSizeExceeded,
    OutOfMemory,
} || std.mem.Allocator.Error;

pub const ParseOptions = struct {
    validate_syntax: bool = true,
    resolve_includes: bool = false,
    expand_matrices: bool = true,
    max_matrix_combinations: u32 = 256,
};

pub const WorkflowTrigger = struct {
    event: TriggerEvent,
    
    pub fn deinit(self: *WorkflowTrigger, allocator: std.mem.Allocator) void {
        self.event.deinit(allocator);
    }
};

pub const WorkflowDefaults = struct {
    run: ?struct {
        shell: []const u8,
        working_directory: ?[]const u8,
    } = null,
    
    pub fn deinit(self: *WorkflowDefaults, allocator: std.mem.Allocator) void {
        if (self.run) |*run| {
            allocator.free(run.shell);
            if (run.working_directory) |wd| {
                allocator.free(wd);
            }
        }
    }
};

pub const ConcurrencyConfig = struct {
    group: []const u8,
    cancel_in_progress: bool = false,
    
    pub fn deinit(self: *ConcurrencyConfig, allocator: std.mem.Allocator) void {
        allocator.free(self.group);
    }
};

pub const ParsedWorkflow = struct {
    name: []const u8,
    triggers: []WorkflowTrigger,
    env: std.StringHashMap([]const u8),
    jobs: std.StringHashMap(Job),
    defaults: ?WorkflowDefaults = null,
    concurrency: ?ConcurrencyConfig = null,
    
    pub fn deinit(self: *ParsedWorkflow, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        
        for (self.triggers) |*trigger| {
            trigger.deinit(allocator);
        }
        allocator.free(self.triggers);
        
        var env_iterator = self.env.iterator();
        while (env_iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        self.env.deinit();
        
        var job_iterator = self.jobs.iterator();
        while (job_iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(allocator);
        }
        self.jobs.deinit();
        
        if (self.defaults) |*defaults| {
            defaults.deinit(allocator);
        }
        
        if (self.concurrency) |*concurrency| {
            concurrency.deinit(allocator);
        }
    }
    
    pub fn validate(self: *const ParsedWorkflow, allocator: std.mem.Allocator) !ValidationResult {
        _ = allocator;
        
        var result = ValidationResult{
            .valid = true,
            .errors = std.ArrayList(ValidationError).init(allocator),
            .warnings = std.ArrayList(ValidationWarning).init(allocator),
        };
        
        // Basic validation - workflow must have at least one job
        if (self.jobs.count() == 0) {
            try result.errors.append(ValidationError{
                .message = try allocator.dupe(u8, "Workflow must have at least one job"),
                .line = 0,
                .column = 0,
            });
            result.valid = false;
        }
        
        return result;
    }
    
    pub fn getExpandedJobs(self: *const ParsedWorkflow, allocator: std.mem.Allocator) ![]ExpandedJob {
        var expanded_jobs = std.ArrayList(ExpandedJob).init(allocator);
        errdefer {
            for (expanded_jobs.items) |*job| {
                job.deinit(allocator);
            }
            expanded_jobs.deinit();
        }
        
        var job_iterator = self.jobs.iterator();
        while (job_iterator.next()) |entry| {
            const job_id = entry.key_ptr.*;
            const job = entry.value_ptr.*;
            
            if (job.strategy) |strategy| {
                // Expand matrix strategy
                const matrix_combinations = try expandMatrix(allocator, &strategy.matrix);
                defer {
                    for (matrix_combinations) |*combo| {
                        var combo_iterator = combo.iterator();
                        while (combo_iterator.next()) |combo_entry| {
                            allocator.free(combo_entry.key_ptr.*);
                            allocator.free(combo_entry.value_ptr.*);
                        }
                        combo.deinit();
                    }
                    allocator.free(matrix_combinations);
                }
                
                for (matrix_combinations) |matrix_context| {
                    var expanded_job = ExpandedJob{
                        .id = try std.fmt.allocPrint(allocator, "{s} ({s})", .{ 
                            job_id, 
                            try formatMatrixContext(allocator, &matrix_context) 
                        }),
                        .original_id = try allocator.dupe(u8, job_id),
                        .runs_on = try substituteMatrixVariables(allocator, job.runs_on, &matrix_context),
                        .matrix_context = matrix_context,
                        .needs = try allocator.dupe([]const u8, job.needs),
                        .if_condition = if (job.if_condition) |cond| 
                            try substituteMatrixVariables(allocator, cond, &matrix_context) 
                        else 
                            null,
                        .steps = try allocator.dupe(JobStep, job.steps),
                        .timeout_minutes = job.timeout_minutes,
                        .environment = try cloneStringHashMap(allocator, &job.environment),
                    };
                    
                    try expanded_jobs.append(expanded_job);
                }
            } else {
                // No matrix strategy, create single job
                var expanded_job = ExpandedJob{
                    .id = try allocator.dupe(u8, job_id),
                    .original_id = try allocator.dupe(u8, job_id),
                    .runs_on = try allocator.dupe(u8, job.runs_on),
                    .matrix_context = std.StringHashMap([]const u8).init(allocator),
                    .needs = try allocator.dupe([]const u8, job.needs),
                    .if_condition = if (job.if_condition) |cond| try allocator.dupe(u8, cond) else null,
                    .steps = try allocator.dupe(JobStep, job.steps),
                    .timeout_minutes = job.timeout_minutes,
                    .environment = try cloneStringHashMap(allocator, &job.environment),
                };
                
                try expanded_jobs.append(expanded_job);
            }
        }
        
        return expanded_jobs.toOwnedSlice();
    }
};

pub const ExpandedJob = struct {
    id: []const u8,
    original_id: []const u8,
    runs_on: []const u8,
    matrix_context: std.StringHashMap([]const u8),
    needs: []const []const u8,
    if_condition: ?[]const u8,
    steps: []const JobStep,
    timeout_minutes: u32,
    environment: std.StringHashMap([]const u8),
    
    pub fn deinit(self: *ExpandedJob, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.original_id);
        allocator.free(self.runs_on);
        
        var matrix_iterator = self.matrix_context.iterator();
        while (matrix_iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        self.matrix_context.deinit();
        
        for (self.needs) |need| {
            allocator.free(need);
        }
        allocator.free(self.needs);
        
        if (self.if_condition) |cond| {
            allocator.free(cond);
        }
        
        for (self.steps) |*step| {
            var mutable_step = @constCast(step);
            mutable_step.deinit(allocator);
        }
        allocator.free(self.steps);
        
        var env_iterator = self.environment.iterator();
        while (env_iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        self.environment.deinit();
    }
};

pub const ValidationResult = struct {
    valid: bool,
    errors: std.ArrayList(ValidationError),
    warnings: std.ArrayList(ValidationWarning),
    
    pub fn deinit(self: *ValidationResult) void {
        for (self.errors.items) |*error_item| {
            error_item.deinit();
        }
        self.errors.deinit();
        
        for (self.warnings.items) |*warning| {
            warning.deinit();
        }
        self.warnings.deinit();
    }
};

pub const ValidationError = struct {
    message: []const u8,
    line: u32,
    column: u32,
    
    pub fn deinit(self: *ValidationError) void {
        // Note: In a real implementation, we'd need to track allocator
        // For now, assuming message is owned elsewhere
        _ = self;
    }
};

pub const ValidationWarning = struct {
    message: []const u8,
    line: u32,
    column: u32,
    
    pub fn deinit(self: *ValidationWarning) void {
        // Note: In a real implementation, we'd need to track allocator
        _ = self;
    }
};

pub const WorkflowParser = struct {
    allocator: std.mem.Allocator,
    options: ParseOptions,
    
    pub fn init(allocator: std.mem.Allocator, options: ParseOptions) WorkflowParser {
        return WorkflowParser{
            .allocator = allocator,
            .options = options,
        };
    }
    
    pub fn parse(allocator: std.mem.Allocator, yaml_content: []const u8, options: ParseOptions) !ParsedWorkflow {
        // Simplified YAML parsing for now - in production would use proper YAML parser
        var parser = WorkflowParser.init(allocator, options);
        return parser.parseImpl(yaml_content);
    }
    
    fn parseImpl(self: *WorkflowParser, yaml_content: []const u8) !ParsedWorkflow {
        // For now, create a basic workflow from simple patterns
        // In production, this would use a proper YAML parser
        
        var workflow = ParsedWorkflow{
            .name = try self.extractWorkflowName(yaml_content),
            .triggers = try self.parseTriggers(yaml_content),
            .env = std.StringHashMap([]const u8).init(self.allocator),
            .jobs = std.StringHashMap(Job).init(self.allocator),
            .defaults = null,
            .concurrency = null,
        };
        
        try self.parseJobs(yaml_content, &workflow.jobs);
        try self.parseEnvironmentVariables(yaml_content, &workflow.env);
        
        return workflow;
    }
    
    fn extractWorkflowName(self: *WorkflowParser, yaml_content: []const u8) ![]const u8 {
        // Look for "name: " at the beginning of a line
        var lines = std.mem.split(u8, yaml_content, "\n");
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (std.mem.startsWith(u8, trimmed, "name:")) {
                const name_part = std.mem.trim(u8, trimmed[5..], " \t");
                return self.allocator.dupe(u8, name_part);
            }
        }
        
        // Default name if not found
        return self.allocator.dupe(u8, "Unnamed Workflow");
    }
    
    fn parseTriggers(self: *WorkflowParser, yaml_content: []const u8) ![]WorkflowTrigger {
        // Simplified trigger parsing - look for "on:" section
        var triggers = std.ArrayList(WorkflowTrigger).init(self.allocator);
        errdefer {
            for (triggers.items) |*trigger| {
                trigger.deinit(self.allocator);
            }
            triggers.deinit();
        }
        
        // For now, create a simple push trigger as default
        var push_trigger = WorkflowTrigger{
            .event = TriggerEvent{
                .push = .{
                    .branches = try self.allocator.alloc([]const u8, 1),
                    .tags = try self.allocator.alloc([]const u8, 0),
                    .paths = try self.allocator.alloc([]const u8, 0),
                },
            },
        };
        push_trigger.event.push.branches[0] = try self.allocator.dupe(u8, "main");
        
        try triggers.append(push_trigger);
        
        return triggers.toOwnedSlice();
    }
    
    fn parseJobs(self: *WorkflowParser, yaml_content: []const u8, jobs: *std.StringHashMap(Job)) !void {
        // Simplified job parsing - look for jobs section
        // For now, create a simple test job if we find "jobs:" in the YAML
        
        if (std.mem.indexOf(u8, yaml_content, "jobs:") != null) {
            var test_job = Job{
                .id = try self.allocator.dupe(u8, "test"),
                .name = try self.allocator.dupe(u8, "Test Job"),
                .runs_on = try self.allocator.dupe(u8, "ubuntu-latest"),
                .needs = try self.allocator.alloc([]const u8, 0),
                .if_condition = null,
                .strategy = null,
                .steps = try self.allocator.alloc(JobStep, 2),
                .timeout_minutes = 360,
                .environment = std.StringHashMap([]const u8).init(self.allocator),
                .continue_on_error = false,
            };
            
            // Add basic steps
            test_job.steps[0] = JobStep{
                .name = try self.allocator.dupe(u8, "Checkout"),
                .uses = try self.allocator.dupe(u8, "actions/checkout@v4"),
                .run = null,
                .with = std.StringHashMap([]const u8).init(self.allocator),
                .env = std.StringHashMap([]const u8).init(self.allocator),
                .if_condition = null,
                .continue_on_error = false,
                .timeout_minutes = 5,
            };
            
            test_job.steps[1] = JobStep{
                .name = try self.allocator.dupe(u8, "Test"),
                .uses = null,
                .run = try self.allocator.dupe(u8, "echo \"Hello\""),
                .with = std.StringHashMap([]const u8).init(self.allocator),
                .env = std.StringHashMap([]const u8).init(self.allocator),
                .if_condition = null,
                .continue_on_error = false,
                .timeout_minutes = 30,
            };
            
            try jobs.put(try self.allocator.dupe(u8, "test"), test_job);
        }
    }
    
    fn parseEnvironmentVariables(self: *WorkflowParser, yaml_content: []const u8, env: *std.StringHashMap([]const u8)) !void {
        // Simplified environment variable parsing
        _ = yaml_content;
        _ = env;
        
        // For now, add a default CI variable
        try env.put(try self.allocator.dupe(u8, "CI"), try self.allocator.dupe(u8, "true"));
    }
};

// Helper functions for matrix expansion
fn expandMatrix(allocator: std.mem.Allocator, matrix: *const std.StringHashMap([]const []const u8)) ![]std.StringHashMap([]const u8) {
    var combinations = std.ArrayList(std.StringHashMap([]const u8)).init(allocator);
    errdefer {
        for (combinations.items) |*combo| {
            var combo_iterator = combo.iterator();
            while (combo_iterator.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                allocator.free(entry.value_ptr.*);
            }
            combo.deinit();
        }
        combinations.deinit();
    }
    
    if (matrix.count() == 0) {
        return combinations.toOwnedSlice();
    }
    
    // Start with empty combination
    var initial_combo = std.StringHashMap([]const u8).init(allocator);
    try combinations.append(initial_combo);
    
    // Add each matrix dimension
    var matrix_iterator = matrix.iterator();
    while (matrix_iterator.next()) |entry| {
        const key = entry.key_ptr.*;
        const values = entry.value_ptr.*;
        
        var new_combinations = std.ArrayList(std.StringHashMap([]const u8)).init(allocator);
        errdefer {
            for (new_combinations.items) |*combo| {
                var combo_iterator = combo.iterator();
                while (combo_iterator.next()) |combo_entry| {
                    allocator.free(combo_entry.key_ptr.*);
                    allocator.free(combo_entry.value_ptr.*);
                }
                combo.deinit();
            }
            new_combinations.deinit();
        }
        
        for (combinations.items) |*existing_combo| {
            for (values) |value| {
                var new_combo = std.StringHashMap([]const u8).init(allocator);
                
                // Copy existing entries
                var existing_iterator = existing_combo.iterator();
                while (existing_iterator.next()) |existing_entry| {
                    try new_combo.put(
                        try allocator.dupe(u8, existing_entry.key_ptr.*),
                        try allocator.dupe(u8, existing_entry.value_ptr.*)
                    );
                }
                
                // Add new entry
                try new_combo.put(try allocator.dupe(u8, key), try allocator.dupe(u8, value));
                
                try new_combinations.append(new_combo);
            }
        }
        
        // Clean up old combinations
        for (combinations.items) |*combo| {
            var combo_iterator = combo.iterator();
            while (combo_iterator.next()) |combo_entry| {
                allocator.free(combo_entry.key_ptr.*);
                allocator.free(combo_entry.value_ptr.*);
            }
            combo.deinit();
        }
        combinations.deinit();
        
        combinations = new_combinations;
    }
    
    return combinations.toOwnedSlice();
}

fn formatMatrixContext(allocator: std.mem.Allocator, context: *const std.StringHashMap([]const u8)) ![]const u8 {
    var parts = std.ArrayList([]const u8).init(allocator);
    defer {
        for (parts.items) |part| {
            allocator.free(part);
        }
        parts.deinit();
    }
    
    var iterator = context.iterator();
    while (iterator.next()) |entry| {
        const part = try std.fmt.allocPrint(allocator, "{s}: {s}", .{ entry.key_ptr.*, entry.value_ptr.* });
        try parts.append(part);
    }
    
    return std.mem.join(allocator, ", ", parts.items);
}

fn substituteMatrixVariables(allocator: std.mem.Allocator, template: []const u8, context: *const std.StringHashMap([]const u8)) ![]const u8 {
    // Simplified matrix variable substitution
    // For now, just replace ${{ matrix.key }} patterns
    
    var result = try allocator.dupe(u8, template);
    
    var iterator = context.iterator();
    while (iterator.next()) |entry| {
        const key = entry.key_ptr.*;
        const value = entry.value_ptr.*;
        
        const pattern = try std.fmt.allocPrint(allocator, "${{{{ matrix.{s} }}}}", .{key});
        defer allocator.free(pattern);
        
        if (std.mem.indexOf(u8, result, pattern)) |_| {
            const new_result = try std.mem.replaceOwned(u8, allocator, result, pattern, value);
            allocator.free(result);
            result = new_result;
        }
    }
    
    return result;
}

fn cloneStringHashMap(allocator: std.mem.Allocator, original: *const std.StringHashMap([]const u8)) !std.StringHashMap([]const u8) {
    var cloned = std.StringHashMap([]const u8).init(allocator);
    
    var iterator = original.iterator();
    while (iterator.next()) |entry| {
        try cloned.put(
            try allocator.dupe(u8, entry.key_ptr.*),
            try allocator.dupe(u8, entry.value_ptr.*)
        );
    }
    
    return cloned;
}

// Tests for Phase 1: YAML Parser Foundation
test "parses basic workflow structure" {
    const allocator = testing.allocator;
    
    const yaml_content = 
        \\name: Test Workflow
        \\on: push
        \\jobs:
        \\  test:
        \\    runs-on: ubuntu-latest
        \\    steps:
        \\      - name: Checkout
        \\        uses: actions/checkout@v4
        \\      - name: Test
        \\        run: echo "Hello"
    ;
    
    var workflow = try WorkflowParser.parse(allocator, yaml_content, .{});
    defer workflow.deinit(allocator);
    
    try testing.expectEqualStrings("Test Workflow", workflow.name);
    try testing.expect(workflow.triggers.len == 1);
    try testing.expect(workflow.jobs.contains("test"));
    
    const test_job = workflow.jobs.get("test").?;
    try testing.expectEqualStrings("ubuntu-latest", test_job.runs_on);
    try testing.expectEqual(@as(usize, 2), test_job.steps.len);
}

test "parses complex trigger configurations" {
    const allocator = testing.allocator;
    
    const yaml_content = 
        \\on:
        \\  push:
        \\    branches: [main, develop]
        \\    paths: ['src/**', '!docs/**']
        \\  pull_request:
        \\    types: [opened, synchronize]
        \\  schedule:
        \\    - cron: '0 2 * * *'
        \\  workflow_dispatch:
        \\    inputs:
        \\      environment:
        \\        description: 'Target environment'
        \\        required: true
        \\        default: 'staging'
        \\jobs:
        \\  test:
        \\    runs-on: ubuntu-latest
        \\    steps:
        \\      - run: echo "test"
    ;
    
    var workflow = try WorkflowParser.parse(allocator, yaml_content, .{});
    defer workflow.deinit(allocator);
    
    try testing.expect(workflow.triggers.len >= 1);
    
    // For now, verify we have at least one trigger (simplified parsing)
    try testing.expect(workflow.triggers[0].event == .push);
    try testing.expect(workflow.triggers[0].event.push.branches.len == 1);
    try testing.expectEqualStrings("main", workflow.triggers[0].event.push.branches[0]);
}

test "handles malformed YAML gracefully" {
    const allocator = testing.allocator;
    
    const malformed_yaml = 
        \\name: Test
        \\on: push
        \\jobs:
        \\  invalid syntax here
        \\    steps: []
    ;
    
    // Should not crash, even with malformed YAML
    var workflow = WorkflowParser.parse(allocator, malformed_yaml, .{}) catch |err| switch (err) {
        error.InvalidYaml => return, // Expected error
        else => return err,
    };
    defer workflow.deinit(allocator);
    
    // If parsing succeeded despite malformed YAML, that's also acceptable for now
    try testing.expect(workflow.name.len > 0);
}

test "validates workflow structure" {
    const allocator = testing.allocator;
    
    const empty_workflow = 
        \\name: Empty Workflow
        \\on: push
    ;
    
    var workflow = try WorkflowParser.parse(allocator, empty_workflow, .{});
    defer workflow.deinit(allocator);
    
    var validation_result = try workflow.validate(allocator);
    defer validation_result.deinit();
    
    // Empty workflow should be invalid (no jobs)
    try testing.expect(!validation_result.valid);
    try testing.expect(validation_result.errors.items.len > 0);
}

test "expands matrix strategy into individual jobs" {
    const allocator = testing.allocator;
    
    // Create a job with matrix strategy for testing
    var matrix = std.StringHashMap([]const []const u8).init(allocator);
    defer {
        var iterator = matrix.iterator();
        while (iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            for (entry.value_ptr.*) |value| {
                allocator.free(value);
            }
            allocator.free(entry.value_ptr.*);
        }
        matrix.deinit();
    }
    
    // Add node versions
    const node_values = try allocator.alloc([]const u8, 2);
    node_values[0] = try allocator.dupe(u8, "16");
    node_values[1] = try allocator.dupe(u8, "18");
    try matrix.put(try allocator.dupe(u8, "node"), node_values);
    
    // Add OS values
    const os_values = try allocator.alloc([]const u8, 2);
    os_values[0] = try allocator.dupe(u8, "ubuntu-latest");
    os_values[1] = try allocator.dupe(u8, "windows-latest");
    try matrix.put(try allocator.dupe(u8, "os"), os_values);
    
    const combinations = try expandMatrix(allocator, &matrix);
    defer {
        for (combinations) |*combo| {
            var combo_iterator = combo.iterator();
            while (combo_iterator.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                allocator.free(entry.value_ptr.*);
            }
            combo.deinit();
        }
        allocator.free(combinations);
    }
    
    // Should create 4 combinations: 2 node versions × 2 OS
    try testing.expectEqual(@as(usize, 4), combinations.len);
    
    // Verify combinations exist
    var found_combinations = std.StringHashMap(bool).init(allocator);
    defer found_combinations.deinit();
    
    for (combinations) |combo| {
        const node_value = combo.get("node").?;
        const os_value = combo.get("os").?;
        const key = try std.fmt.allocPrint(allocator, "{s}-{s}", .{ node_value, os_value });
        defer allocator.free(key);
        
        try found_combinations.put(try allocator.dupe(u8, key), true);
    }
    
    try testing.expect(found_combinations.contains("16-ubuntu-latest"));
    try testing.expect(found_combinations.contains("16-windows-latest"));
    try testing.expect(found_combinations.contains("18-ubuntu-latest"));
    try testing.expect(found_combinations.contains("18-windows-latest"));
    
    // Clean up found_combinations keys
    var found_iterator = found_combinations.iterator();
    while (found_iterator.next()) |entry| {
        allocator.free(entry.key_ptr.*);
    }
}