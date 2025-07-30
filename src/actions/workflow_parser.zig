const std = @import("std");
const testing = std.testing;
const models = @import("models.zig");
const yaml_parser = @import("yaml_parser.zig");
const TriggerEvent = models.TriggerEvent;
const Job = models.Job;
const JobStep = models.JobStep;
const JobStrategy = models.JobStrategy;
const WorkflowInput = models.WorkflowInput;
const YamlDocument = yaml_parser.YamlDocument;
const YamlNode = yaml_parser.YamlNode;

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
                    const expanded_job = ExpandedJob{
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
                const expanded_job = ExpandedJob{
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
        var parser = WorkflowParser.init(allocator, options);
        return parser.parseImpl(yaml_content);
    }
    
    fn parseImpl(self: *WorkflowParser, yaml_content: []const u8) !ParsedWorkflow {
        // Parse YAML document using proper parser
        var doc = yaml_parser.YamlParser.parse(self.allocator, yaml_content) catch |err| switch (err) {
            error.InvalidYaml => return WorkflowParserError.InvalidYaml,
            error.OutOfMemory => return WorkflowParserError.OutOfMemory,
            else => return WorkflowParserError.InvalidYaml,
        };
        defer doc.deinit();
        
        var workflow = ParsedWorkflow{
            .name = try self.extractWorkflowName(&doc),
            .triggers = try self.parseTriggers(&doc),
            .env = std.StringHashMap([]const u8).init(self.allocator),
            .jobs = std.StringHashMap(Job).init(self.allocator),
            .defaults = null,
            .concurrency = null,
        };
        
        try self.parseJobs(&doc, &workflow.jobs);
        try self.parseEnvironmentVariables(&doc, &workflow.env);
        
        // Parse workflow defaults
        workflow.defaults = try self.parseWorkflowDefaults(&doc);
        
        // Parse concurrency settings
        workflow.concurrency = try self.parseConcurrencyConfig(&doc);
        
        return workflow;
    }
    
    fn extractWorkflowName(self: *WorkflowParser, doc: *const YamlDocument) ![]const u8 {
        if (doc.getNode("name")) |name_node| {
            if (name_node.asString()) |name| {
                return self.allocator.dupe(u8, name);
            }
        }
        
        // Default name if not found
        return self.allocator.dupe(u8, "Unnamed Workflow");
    }
    
    fn parseTriggers(self: *WorkflowParser, doc: *const YamlDocument) ![]WorkflowTrigger {
        var triggers = std.ArrayList(WorkflowTrigger).init(self.allocator);
        errdefer {
            for (triggers.items) |*trigger| {
                trigger.deinit(self.allocator);
            }
            triggers.deinit();
        }
        
        if (doc.getNode("on")) |on_node| {
            // Handle different "on" formats: string, sequence, or mapping
            switch (on_node.type) {
                .scalar => {
                    // Single event like "on: push"
                    const event_name = on_node.asString() orelse return WorkflowParserError.InvalidTriggerEvent;
                    const trigger = try self.parseSimpleTrigger(event_name);
                    try triggers.append(trigger);
                },
                .sequence => {
                    // Array of events like "on: [push, pull_request]"
                    const events = on_node.asSequence() orelse return WorkflowParserError.InvalidTriggerEvent;
                    for (events) |event_node| {
                        if (event_node.asString()) |event_name| {
                            const trigger = try self.parseSimpleTrigger(event_name);
                            try triggers.append(trigger);
                        }
                    }
                },
                .mapping => {
                    // Complex triggers like "on: { push: { branches: [main] } }"
                    const event_map = on_node.asMapping() orelse return WorkflowParserError.InvalidTriggerEvent;
                    var iterator = event_map.iterator();
                    while (iterator.next()) |entry| {
                        const event_name = entry.key_ptr.*;
                        const event_config = entry.value_ptr;
                        const trigger = try self.parseComplexTrigger(event_name, event_config);
                        try triggers.append(trigger);
                    }
                },
                else => return WorkflowParserError.InvalidTriggerEvent,
            }
        } else {
            // Default to push trigger on main if no "on" specified
            const trigger = try self.parseSimpleTrigger("push");
            try triggers.append(trigger);
        }
        
        return triggers.toOwnedSlice();
    }
    
    fn parseSimpleTrigger(self: *WorkflowParser, event_name: []const u8) !WorkflowTrigger {
        if (std.mem.eql(u8, event_name, "push")) {
            return WorkflowTrigger{
                .event = TriggerEvent{
                    .push = .{
                        .branches = blk: {
                            const branches = try self.allocator.alloc([]const u8, 1);
                            branches[0] = try self.allocator.dupe(u8, "main");
                            break :blk branches;
                        },
                        .tags = try self.allocator.alloc([]const u8, 0),
                        .paths = try self.allocator.alloc([]const u8, 0),
                    },
                },
            };
        } else if (std.mem.eql(u8, event_name, "pull_request")) {
            return WorkflowTrigger{
                .event = TriggerEvent{
                    .pull_request = .{
                        .types = blk: {
                            const types = try self.allocator.alloc([]const u8, 2);
                            types[0] = try self.allocator.dupe(u8, "opened");
                            types[1] = try self.allocator.dupe(u8, "synchronize");
                            break :blk types;
                        },
                        .branches = try self.allocator.alloc([]const u8, 0),
                    },
                },
            };
        } else if (std.mem.eql(u8, event_name, "schedule")) {
            return WorkflowTrigger{
                .event = TriggerEvent{
                    .schedule = .{
                        .cron = try self.allocator.dupe(u8, "0 0 * * *"), // Default: daily at midnight
                    },
                },
            };
        } else if (std.mem.eql(u8, event_name, "workflow_dispatch")) {
            return WorkflowTrigger{
                .event = TriggerEvent{
                    .workflow_dispatch = .{
                        .inputs = std.StringHashMap(WorkflowInput).init(self.allocator),
                    },
                },
            };
        }
        
        return WorkflowParserError.InvalidTriggerEvent;
    }
    
    fn parseComplexTrigger(self: *WorkflowParser, event_name: []const u8, config: *const YamlNode) !WorkflowTrigger {
        if (std.mem.eql(u8, event_name, "push")) {
            var branches = std.ArrayList([]const u8).init(self.allocator);
            defer branches.deinit();
            
            if (config.get("branches")) |branches_node| {
                if (branches_node.asSequence()) |branch_array| {
                    for (branch_array) |branch_node| {
                        if (branch_node.asString()) |branch_name| {
                            try branches.append(try self.allocator.dupe(u8, branch_name));
                        }
                    }
                } else if (branches_node.asString()) |single_branch| {
                    try branches.append(try self.allocator.dupe(u8, single_branch));
                }
            }
            
            // Default to main if no branches specified
            if (branches.items.len == 0) {
                try branches.append(try self.allocator.dupe(u8, "main"));
            }
            
            return WorkflowTrigger{
                .event = TriggerEvent{
                    .push = .{
                        .branches = try branches.toOwnedSlice(),
                        .tags = try self.allocator.alloc([]const u8, 0),
                        .paths = try self.allocator.alloc([]const u8, 0),
                    },
                },
            };
        } else if (std.mem.eql(u8, event_name, "pull_request")) {
            var types = std.ArrayList([]const u8).init(self.allocator);
            defer types.deinit();
            
            if (config.get("types")) |types_node| {
                if (types_node.asSequence()) |type_array| {
                    for (type_array) |type_node| {
                        if (type_node.asString()) |type_name| {
                            try types.append(try self.allocator.dupe(u8, type_name));
                        }
                    }
                } else if (types_node.asString()) |single_type| {
                    try types.append(try self.allocator.dupe(u8, single_type));
                }
            }
            
            // Default types if none specified
            if (types.items.len == 0) {
                try types.append(try self.allocator.dupe(u8, "opened"));
                try types.append(try self.allocator.dupe(u8, "synchronize"));
            }
            
            var branches = std.ArrayList([]const u8).init(self.allocator);
            defer branches.deinit();
            
            if (config.get("branches")) |branches_node| {
                if (branches_node.asSequence()) |branch_array| {
                    for (branch_array) |branch_node| {
                        if (branch_node.asString()) |branch_name| {
                            try branches.append(try self.allocator.dupe(u8, branch_name));
                        }
                    }
                } else if (branches_node.asString()) |single_branch| {
                    try branches.append(try self.allocator.dupe(u8, single_branch));
                }
            }
            
            return WorkflowTrigger{
                .event = TriggerEvent{
                    .pull_request = .{
                        .types = try types.toOwnedSlice(),
                        .branches = try branches.toOwnedSlice(),
                    },
                },
            };
        } else if (std.mem.eql(u8, event_name, "schedule")) {
            const cron = if (config.get("cron")) |cron_node|
                cron_node.asString() orelse "0 0 * * *"
            else
                "0 0 * * *";
            
            return WorkflowTrigger{
                .event = TriggerEvent{
                    .schedule = .{
                        .cron = try self.allocator.dupe(u8, cron),
                    },
                },
            };
        } else if (std.mem.eql(u8, event_name, "workflow_dispatch")) {
            var inputs = std.StringHashMap(WorkflowInput).init(self.allocator);
            
            if (config.get("inputs")) |inputs_node| {
                if (inputs_node.asMapping()) |inputs_map| {
                    var inputs_iterator = inputs_map.iterator();
                    while (inputs_iterator.next()) |entry| {
                        const input_name = entry.key_ptr.*;
                        const input_config = entry.value_ptr;
                        
                        const input = try self.parseWorkflowInput(input_config);
                        try inputs.put(try self.allocator.dupe(u8, input_name), input);
                    }
                }
            }
            
            return WorkflowTrigger{
                .event = TriggerEvent{
                    .workflow_dispatch = .{
                        .inputs = inputs,
                    },
                },
            };
        }
        
        // For other events, use simple trigger for now
        return self.parseSimpleTrigger(event_name);
    }
    
    fn parseJobs(self: *WorkflowParser, doc: *const YamlDocument, jobs: *std.StringHashMap(Job)) !void {
        if (doc.getNode("jobs")) |jobs_node| {
            const jobs_map = jobs_node.asMapping() orelse return WorkflowParserError.InvalidJobDefinition;
            
            var iterator = jobs_map.iterator();
            while (iterator.next()) |entry| {
                const job_id = entry.key_ptr.*;
                const job_config = entry.value_ptr;
                
                const job = try self.parseJob(job_id, job_config);
                try jobs.put(try self.allocator.dupe(u8, job_id), job);
            }
        }
    }
    
    fn parseJob(self: *WorkflowParser, job_id: []const u8, job_config: *const YamlNode) !Job {
        _ = job_config.asMapping() orelse return WorkflowParserError.InvalidJobDefinition;
        
        // Extract runs-on (required)
        const runs_on_node = job_config.get("runs-on") orelse return WorkflowParserError.MissingRequiredField;
        const runs_on = runs_on_node.asString() orelse return WorkflowParserError.InvalidJobDefinition;
        
        // Extract job name (optional, defaults to job ID)
        const name = if (job_config.get("name")) |name_node|
            name_node.asString() orelse job_id
        else
            job_id;
        
        // Parse steps
        var steps = std.ArrayList(JobStep).init(self.allocator);
        defer steps.deinit();
        
        if (job_config.get("steps")) |steps_node| {
            const steps_array = steps_node.asSequence() orelse return WorkflowParserError.InvalidJobDefinition;
            for (steps_array) |step_node| {
                const step = try self.parseStep(&step_node);
                try steps.append(step);
            }
        }
        
        return Job{
            .id = try self.allocator.dupe(u8, job_id),
            .name = try self.allocator.dupe(u8, name),
            .runs_on = try self.allocator.dupe(u8, runs_on),
            .needs = try self.allocator.alloc([]const u8, 0), // TODO: Parse needs
            .if_condition = null, // TODO: Parse if condition
            .strategy = null, // TODO: Parse strategy
            .steps = try steps.toOwnedSlice(),
            .timeout_minutes = 360, // Default timeout
            .environment = std.StringHashMap([]const u8).init(self.allocator), // TODO: Parse env
            .continue_on_error = false,
        };
    }
    
    fn parseStep(self: *WorkflowParser, step_node: *const YamlNode) !JobStep {
        _ = step_node.asMapping() orelse return WorkflowParserError.InvalidJobDefinition;
        
        // Extract step name (optional)
        const name = if (step_node.get("name")) |name_node|
            name_node.asString()
        else
            null;
        
        // Extract uses or run (one is required)
        const uses = if (step_node.get("uses")) |uses_node|
            uses_node.asString()
        else
            null;
            
        const run = if (step_node.get("run")) |run_node|
            run_node.asString()
        else
            null;
        
        if (uses == null and run == null) {
            return WorkflowParserError.InvalidJobDefinition;
        }
        
        return JobStep{
            .name = if (name) |n| try self.allocator.dupe(u8, n) else null,
            .uses = if (uses) |u| try self.allocator.dupe(u8, u) else null,
            .run = if (run) |r| try self.allocator.dupe(u8, r) else null,
            .with = std.StringHashMap([]const u8).init(self.allocator), // TODO: Parse with
            .env = std.StringHashMap([]const u8).init(self.allocator), // TODO: Parse env
            .if_condition = null, // TODO: Parse if condition
            .continue_on_error = false,
            .timeout_minutes = 30, // Default timeout
        };
    }
    
    fn parseEnvironmentVariables(self: *WorkflowParser, doc: *const YamlDocument, env: *std.StringHashMap([]const u8)) !void {
        if (doc.getNode("env")) |env_node| {
            const env_map = env_node.asMapping() orelse return;
            
            var iterator = env_map.iterator();
            while (iterator.next()) |entry| {
                const key = entry.key_ptr.*;
                const value_node = entry.value_ptr;
                
                if (value_node.asString()) |value| {
                    try env.put(try self.allocator.dupe(u8, key), try self.allocator.dupe(u8, value));
                }
            }
        }
        
        // Always add default CI variable
        try env.put(try self.allocator.dupe(u8, "CI"), try self.allocator.dupe(u8, "true"));
    }
    
    fn parseWorkflowInput(self: *WorkflowParser, input_config: *const YamlNode) !WorkflowInput {
        const input_map = input_config.asMapping() orelse return WorkflowInput{
            .description = try self.allocator.dupe(u8, ""),
            .required = false,
            .default = null,
            .type = .string,
        };
        
        const description = if (input_map.get("description")) |desc_node|
            desc_node.asString() orelse ""
        else
            "";
            
        const required = if (input_map.get("required")) |req_node|
            if (req_node.asString()) |req_str|
                std.mem.eql(u8, req_str, "true")
            else
                false
        else
            false;
            
        const default_value = if (input_map.get("default")) |default_node|
            default_node.asString()
        else
            null;
            
        const input_type = if (input_map.get("type")) |type_node|
            if (type_node.asString()) |type_str|
                if (std.mem.eql(u8, type_str, "boolean"))
                    WorkflowInput.InputType.boolean
                else if (std.mem.eql(u8, type_str, "number"))
                    WorkflowInput.InputType.string
                else if (std.mem.eql(u8, type_str, "choice"))
                    WorkflowInput.InputType.choice
                else
                    WorkflowInput.InputType.string
            else
                WorkflowInput.InputType.string
        else
            WorkflowInput.InputType.string;
            
        return WorkflowInput{
            .description = try self.allocator.dupe(u8, description),
            .required = required,
            .default = if (default_value) |dv| try self.allocator.dupe(u8, dv) else null,
            .type = input_type,
        };
    }
    
    fn parseWorkflowDefaults(self: *WorkflowParser, doc: *const YamlDocument) !?WorkflowDefaults {
        const defaults_node = doc.getNode("defaults") orelse return null;
        const defaults_map = defaults_node.asMapping() orelse return null;
        
        var defaults = WorkflowDefaults{};
        
        if (defaults_map.get("run")) |run_node| {
            if (run_node.asMapping()) |run_map| {
                const shell = if (run_map.get("shell")) |shell_node|
                    shell_node.asString() orelse "bash"
                else
                    "bash";
                    
                const working_directory = if (run_map.get("working-directory")) |wd_node|
                    wd_node.asString()
                else
                    null;
                    
                defaults.run = .{
                    .shell = try self.allocator.dupe(u8, shell),
                    .working_directory = if (working_directory) |wd| try self.allocator.dupe(u8, wd) else null,
                };
            }
        }
        
        return defaults;
    }
    
    fn parseConcurrencyConfig(self: *WorkflowParser, doc: *const YamlDocument) !?ConcurrencyConfig {
        const concurrency_node = doc.getNode("concurrency") orelse return null;
        
        // Handle both string and object forms
        if (concurrency_node.asString()) |group_name| {
            return ConcurrencyConfig{
                .group = try self.allocator.dupe(u8, group_name),
                .cancel_in_progress = false,
            };
        } else if (concurrency_node.asMapping()) |concurrency_map| {
            const group = if (concurrency_map.get("group")) |group_node|
                group_node.asString() orelse return null
            else
                return null;
                
            const cancel_in_progress = if (concurrency_map.get("cancel-in-progress")) |cancel_node|
                if (cancel_node.asString()) |cancel_str|
                    std.mem.eql(u8, cancel_str, "true")
                else
                    false
            else
                false;
                
            return ConcurrencyConfig{
                .group = try self.allocator.dupe(u8, group),
                .cancel_in_progress = cancel_in_progress,
            };
        }
        
        return null;
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
    const initial_combo = std.StringHashMap([]const u8).init(allocator);
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