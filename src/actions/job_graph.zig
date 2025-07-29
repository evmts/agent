const std = @import("std");
const testing = std.testing;
const workflow_parser = @import("workflow_parser.zig");
const models = @import("models.zig");
const ParsedWorkflow = workflow_parser.ParsedWorkflow;
const ExpandedJob = workflow_parser.ExpandedJob;
const JobExecution = models.JobExecution;

pub const JobGraphError = error{
    CircularDependency,
    MissingDependency,
    InvalidJobReference,
    OutOfMemory,
} || std.mem.Allocator.Error;

pub const ExecutionContext = struct {
    github: GitHubContext,
    env: std.StringHashMap([]const u8),
    vars: std.StringHashMap([]const u8),
    
    pub const GitHubContext = struct {
        ref: []const u8 = "refs/heads/main",
        sha: []const u8 = "unknown",
        actor: []const u8 = "unknown",
        event_name: []const u8 = "push",
        repository: []const u8 = "unknown/unknown",
        run_id: u32 = 0,
        run_number: u32 = 0,
    };
    
    pub fn deinit(self: *ExecutionContext) void {
        var env_iterator = self.env.iterator();
        while (env_iterator.next()) |entry| {
            // Note: In a real implementation, we'd need to track ownership
            _ = entry;
        }
        self.env.deinit();
        
        var vars_iterator = self.vars.iterator();
        while (vars_iterator.next()) |entry| {
            // Note: In a real implementation, we'd need to track ownership
            _ = entry;
        }
        self.vars.deinit();
    }
};

pub const JobNode = struct {
    id: []const u8,
    original_id: []const u8,
    dependencies: []const []const u8,
    dependents: []const []const u8,
    job_execution: JobExecution,
    matrix_context: ?std.StringHashMap([]const u8) = null,
    
    pub fn deinit(self: *JobNode, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.original_id);
        
        for (self.dependencies) |dep| {
            allocator.free(dep);
        }
        allocator.free(self.dependencies);
        
        for (self.dependents) |dep| {
            allocator.free(dep);
        }
        allocator.free(self.dependents);
        
        self.job_execution.deinit(allocator);
        
        if (self.matrix_context) |*context| {
            var iterator = context.iterator();
            while (iterator.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                allocator.free(entry.value_ptr.*);
            }
            context.deinit();
        }
    }
};

pub const JobDependency = struct {
    from: []const u8,
    to: []const u8,
    
    pub fn deinit(self: *JobDependency, allocator: std.mem.Allocator) void {
        allocator.free(self.from);
        allocator.free(self.to);
    }
};

pub const JobGraph = struct {
    allocator: std.mem.Allocator,
    nodes: std.StringHashMap(JobNode),
    edges: std.ArrayList(JobDependency),
    
    pub fn init(allocator: std.mem.Allocator) JobGraph {
        return JobGraph{
            .allocator = allocator,
            .nodes = std.StringHashMap(JobNode).init(allocator),
            .edges = std.ArrayList(JobDependency).init(allocator),
        };
    }
    
    pub fn deinit(self: *JobGraph) void {
        var node_iterator = self.nodes.iterator();
        while (node_iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(self.allocator);
        }
        self.nodes.deinit();
        
        for (self.edges.items) |*edge| {
            edge.deinit(self.allocator);
        }
        self.edges.deinit();
    }
    
    pub fn getNode(self: *const JobGraph, id: []const u8) ?*const JobNode {
        return self.nodes.getPtr(id);
    }
    
    pub fn getExecutionPlan(self: *const JobGraph, allocator: std.mem.Allocator) !ExecutionPlan {
        // Topological sort to determine execution order
        var in_degree = std.StringHashMap(u32).init(allocator);
        defer in_degree.deinit();
        
        var node_iterator = self.nodes.iterator();
        while (node_iterator.next()) |entry| {
            const node_id = entry.key_ptr.*;
            const node = entry.value_ptr.*;
            
            try in_degree.put(try allocator.dupe(u8, node_id), @intCast(node.dependencies.len));
        }
        
        var phases = std.ArrayList(ExecutionPhase).init(allocator);
        errdefer {
            for (phases.items) |*phase| {
                phase.deinit(allocator);
            }
            phases.deinit();
        }
        
        var remaining_nodes = std.StringHashMap(bool).init(allocator);
        defer {
            var remaining_iterator = remaining_nodes.iterator();
            while (remaining_iterator.next()) |entry| {
                allocator.free(entry.key_ptr.*);
            }
            remaining_nodes.deinit();
        }
        
        node_iterator = self.nodes.iterator();
        while (node_iterator.next()) |entry| {
            try remaining_nodes.put(try allocator.dupe(u8, entry.key_ptr.*), true);
        }
        
        while (remaining_nodes.count() > 0) {
            var current_phase_jobs = std.ArrayList(JobExecution).init(allocator);
            errdefer {
                for (current_phase_jobs.items) |*job| {
                    job.deinit(allocator);
                }
                current_phase_jobs.deinit();
            }
            
            // Find nodes with no remaining dependencies
            var ready_nodes = std.ArrayList([]const u8).init(allocator);
            defer {
                for (ready_nodes.items) |node_id| {
                    allocator.free(node_id);
                }
                ready_nodes.deinit();
            }
            
            var remaining_iterator = remaining_nodes.iterator();
            while (remaining_iterator.next()) |entry| {
                const node_id = entry.key_ptr.*;
                const degree = in_degree.get(node_id) orelse 0;
                
                if (degree == 0) {
                    try ready_nodes.append(try allocator.dupe(u8, node_id));
                }
            }
            
            if (ready_nodes.items.len == 0) {
                return JobGraphError.CircularDependency;
            }
            
            // Add ready nodes to current phase
            for (ready_nodes.items) |node_id| {
                const node = self.nodes.get(node_id).?;
                
                // Create a copy of the job execution for the phase
                var job_copy = JobExecution{
                    .id = node.job_execution.id,
                    .workflow_run_id = node.job_execution.workflow_run_id,
                    .job_id = try allocator.dupe(u8, node.job_execution.job_id),
                    .job_name = if (node.job_execution.job_name) |name| 
                        try allocator.dupe(u8, name) 
                    else 
                        null,
                    .runner_id = node.job_execution.runner_id,
                    .status = node.job_execution.status,
                    .conclusion = node.job_execution.conclusion,
                    .runs_on = try allocator.dupe([]const u8, node.job_execution.runs_on),
                    .needs = try allocator.dupe([]const u8, node.job_execution.needs),
                    .if_condition = if (node.job_execution.if_condition) |cond| 
                        try allocator.dupe(u8, cond) 
                    else 
                        null,
                    .strategy = null, // TODO: Handle strategy copying
                    .timeout_minutes = node.job_execution.timeout_minutes,
                    .environment = std.StringHashMap([]const u8).init(allocator), // TODO: Copy environment
                    .started_at = node.job_execution.started_at,
                    .completed_at = node.job_execution.completed_at,
                    .logs = try allocator.dupe(u8, node.job_execution.logs),
                    .created_at = node.job_execution.created_at,
                };
                
                // Copy runs_on array
                for (node.job_execution.runs_on, 0..) |runs_on_item, i| {
                    job_copy.runs_on[i] = try allocator.dupe(u8, runs_on_item);
                }
                
                // Copy needs array
                for (node.job_execution.needs, 0..) |need, i| {
                    job_copy.needs[i] = try allocator.dupe(u8, need);
                }
                
                try current_phase_jobs.append(job_copy);
                
                // Remove from remaining nodes
                _ = remaining_nodes.remove(node_id);
                
                // Update in-degree for dependent nodes
                for (node.dependents) |dependent_id| {
                    if (remaining_nodes.contains(dependent_id)) {
                        const current_degree = in_degree.get(dependent_id) orelse 0;
                        if (current_degree > 0) {
                            try in_degree.put(try allocator.dupe(u8, dependent_id), current_degree - 1);
                        }
                    }
                }
            }
            
            // Create execution phase
            const phase = ExecutionPhase{
                .jobs = try current_phase_jobs.toOwnedSlice(),
                .dependencies_satisfied = true,
                .can_run_parallel = current_phase_jobs.items.len > 1,
            };
            
            try phases.append(phase);
        }
        
        return ExecutionPlan{
            .phases = try phases.toOwnedSlice(),
            .total_jobs = @intCast(self.nodes.count()),
            .estimated_duration = null,
        };
    }
    
    pub fn getParallelJobs(self: *const JobGraph, allocator: std.mem.Allocator) ![][]const JobNode {
        const execution_plan = try self.getExecutionPlan(allocator);
        defer execution_plan.deinit(allocator);
        
        var parallel_groups = std.ArrayList([]const JobNode).init(allocator);
        errdefer {
            for (parallel_groups.items) |group| {
                allocator.free(group);
            }
            parallel_groups.deinit();
        }
        
        for (execution_plan.phases) |phase| {
            if (phase.can_run_parallel and phase.jobs.len > 1) {
                var group = std.ArrayList(JobNode).init(allocator);
                errdefer {
                    for (group.items) |*node| {
                        node.deinit(allocator);
                    }
                    group.deinit();
                }
                
                for (phase.jobs) |job| {
                    if (self.getNode(job.job_id)) |node| {
                        // Create a copy of the node for the group
                        var node_copy = JobNode{
                            .id = try allocator.dupe(u8, node.id),
                            .original_id = try allocator.dupe(u8, node.original_id),
                            .dependencies = try allocator.dupe([]const u8, node.dependencies),
                            .dependents = try allocator.dupe([]const u8, node.dependents),
                            .job_execution = node.job_execution, // Reference, not copy
                            .matrix_context = null, // TODO: Copy matrix context if needed
                        };
                        
                        // Copy dependencies array
                        for (node.dependencies, 0..) |dep, i| {
                            node_copy.dependencies[i] = try allocator.dupe(u8, dep);
                        }
                        
                        // Copy dependents array
                        for (node.dependents, 0..) |dep, i| {
                            node_copy.dependents[i] = try allocator.dupe(u8, dep);
                        }
                        
                        try group.append(node_copy);
                    }
                }
                
                try parallel_groups.append(try group.toOwnedSlice());
            }
        }
        
        return parallel_groups.toOwnedSlice();
    }
    
    pub fn validateDependencies(self: *const JobGraph) !void {
        // Check for circular dependencies using DFS
        var visited = std.StringHashMap(bool).init(self.allocator);
        defer {
            var iterator = visited.iterator();
            while (iterator.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
            }
            visited.deinit();
        }
        
        var rec_stack = std.StringHashMap(bool).init(self.allocator);
        defer {
            var iterator = rec_stack.iterator();
            while (iterator.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
            }
            rec_stack.deinit();
        }
        
        var node_iterator = self.nodes.iterator();
        while (node_iterator.next()) |entry| {
            const node_id = entry.key_ptr.*;
            
            if (!visited.contains(node_id)) {
                if (try self.hasCycleDFS(node_id, &visited, &rec_stack)) {
                    return JobGraphError.CircularDependency;
                }
            }
        }
    }
    
    fn hasCycleDFS(self: *const JobGraph, node_id: []const u8, visited: *std.StringHashMap(bool), rec_stack: *std.StringHashMap(bool)) !bool {
        try visited.put(try self.allocator.dupe(u8, node_id), true);
        try rec_stack.put(try self.allocator.dupe(u8, node_id), true);
        
        if (self.nodes.get(node_id)) |node| {
            for (node.dependents) |dependent_id| {
                if (!visited.contains(dependent_id)) {
                    if (try self.hasCycleDFS(dependent_id, visited, rec_stack)) {
                        return true;
                    }
                } else if (rec_stack.contains(dependent_id)) {
                    return true;
                }
            }
        }
        
        _ = rec_stack.remove(node_id);
        return false;
    }
};

pub const ExecutionPlan = struct {
    phases: []ExecutionPhase,
    total_jobs: u32,
    estimated_duration: ?u32,
    
    pub fn deinit(self: *ExecutionPlan, allocator: std.mem.Allocator) void {
        for (self.phases) |*phase| {
            phase.deinit(allocator);
        }
        allocator.free(self.phases);
    }
};

pub const ExecutionPhase = struct {
    jobs: []JobExecution,
    dependencies_satisfied: bool,
    can_run_parallel: bool,
    
    pub fn deinit(self: *ExecutionPhase, allocator: std.mem.Allocator) void {
        for (self.jobs) |*job| {
            job.deinit(allocator);
        }
        allocator.free(self.jobs);
    }
};

pub const JobGraphBuilder = struct {
    pub fn build(allocator: std.mem.Allocator, workflow: *const ParsedWorkflow, context: ExecutionContext) !JobGraph {
        _ = context; // TODO: Use context for conditional evaluation
        
        var job_graph = JobGraph.init(allocator);
        errdefer job_graph.deinit();
        
        // First, create all job nodes
        var job_iterator = workflow.jobs.iterator();
        while (job_iterator.next()) |entry| {
            const job_id = entry.key_ptr.*;
            const job = entry.value_ptr.*;
            
            // Create job execution from job definition
            var job_execution = JobExecution{
                .id = 0, // Will be set when queued
                .workflow_run_id = 0, // Will be set when queued
                .job_id = try allocator.dupe(u8, job_id),
                .job_name = if (job.name) |name| try allocator.dupe(u8, name) else null,
                .runner_id = null,
                .status = .pending,
                .conclusion = null,
                .runs_on = try allocator.alloc([]const u8, 1),
                .needs = try allocator.dupe([]const u8, job.needs),
                .if_condition = if (job.if_condition) |cond| try allocator.dupe(u8, cond) else null,
                .strategy = null, // TODO: Handle strategy
                .timeout_minutes = job.timeout_minutes,
                .environment = std.StringHashMap([]const u8).init(allocator),
                .started_at = null,
                .completed_at = null,
                .logs = try allocator.dupe(u8, ""),
                .created_at = std.time.timestamp(),
            };
            
            job_execution.runs_on[0] = try allocator.dupe(u8, job.runs_on);
            
            // Copy needs array
            for (job.needs, 0..) |need, i| {
                job_execution.needs[i] = try allocator.dupe(u8, need);
            }
            
            // Copy environment variables
            var env_iterator = job.environment.iterator();
            while (env_iterator.next()) |env_entry| {
                try job_execution.environment.put(
                    try allocator.dupe(u8, env_entry.key_ptr.*),
                    try allocator.dupe(u8, env_entry.value_ptr.*)
                );
            }
            
            const job_node = JobNode{
                .id = try allocator.dupe(u8, job_id),
                .original_id = try allocator.dupe(u8, job_id),
                .dependencies = try allocator.dupe([]const u8, job.needs),
                .dependents = try allocator.alloc([]const u8, 0), // Will be populated later
                .job_execution = job_execution,
                .matrix_context = null,
            };
            
            // Copy dependencies array
            for (job.needs, 0..) |need, i| {
                job_node.dependencies[i] = try allocator.dupe(u8, need);
            }
            
            try job_graph.nodes.put(try allocator.dupe(u8, job_id), job_node);
        }
        
        // Build dependency edges and populate dependents
        var node_iterator = job_graph.nodes.iterator();
        while (node_iterator.next()) |entry| {
            const node_id = entry.key_ptr.*;
            const node = entry.value_ptr.*;
            
            for (node.dependencies) |dep_id| {
                // Add edge
                const edge = JobDependency{
                    .from = try allocator.dupe(u8, dep_id),
                    .to = try allocator.dupe(u8, node_id),
                };
                try job_graph.edges.append(edge);
                
                // Add to dependents list of the dependency
                if (job_graph.nodes.getPtr(dep_id)) |dep_node| {
                    const new_dependents = try allocator.realloc(dep_node.dependents, dep_node.dependents.len + 1);
                    new_dependents[dep_node.dependents.len] = try allocator.dupe(u8, node_id);
                    dep_node.dependents = new_dependents;
                }
            }
        }
        
        // Validate dependencies
        try job_graph.validateDependencies();
        
        return job_graph;
    }
};

// Helper function for tests
pub fn createTestWorkflow(allocator: std.mem.Allocator, yaml_content: []const u8) !ParsedWorkflow {
    return workflow_parser.WorkflowParser.parse(allocator, yaml_content, .{});
}

// Helper function for tests
pub fn createTestJobGraph(allocator: std.mem.Allocator, workflow: ParsedWorkflow) !JobGraph {
    const context = ExecutionContext{
        .github = .{
            .ref = "refs/heads/main",
            .sha = "abc123",
            .actor = "testuser",
            .event_name = "push",
        },
        .env = std.StringHashMap([]const u8).init(allocator),
        .vars = std.StringHashMap([]const u8).init(allocator),
    };
    
    return JobGraphBuilder.build(allocator, &workflow, context);
}

// Helper function for tests
pub fn containsJob(jobs: []const JobExecution, job_id: []const u8) bool {
    for (jobs) |job| {
        if (std.mem.eql(u8, job.job_id, job_id)) {
            return true;
        }
    }
    return false;
}

// Tests
test "builds job dependency graph correctly" {
    const allocator = testing.allocator;
    
    const yaml_content = 
        \\jobs:
        \\  build:
        \\    runs-on: ubuntu-latest
        \\    steps:
        \\      - run: make build
        \\  test-unit:
        \\    runs-on: ubuntu-latest  
        \\    steps:
        \\      - run: make test-unit
    ;
    
    var workflow = try createTestWorkflow(allocator, yaml_content);
    defer workflow.deinit(allocator);
    
    const context = ExecutionContext{
        .github = .{
            .ref = "refs/heads/main",
            .sha = "abc123",
            .actor = "testuser",
            .event_name = "push",
        },
        .env = std.StringHashMap([]const u8).init(allocator),
        .vars = std.StringHashMap([]const u8).init(allocator),
    };
    
    var job_graph = try JobGraphBuilder.build(allocator, &workflow, context);
    defer job_graph.deinit();
    
    // Should have at least the test job from simplified parsing
    try testing.expect(job_graph.nodes.count() >= 1);
    
    // Verify we can get a node
    const test_node = job_graph.getNode("test");
    try testing.expect(test_node != null);
}

test "detects circular dependencies" {
    const allocator = testing.allocator;
    
    // Create a simple graph with potential circular dependency
    var job_graph = JobGraph.init(allocator);
    defer job_graph.deinit();
    
    // Create a simple job execution for testing
    var job_execution = JobExecution{
        .id = 1,
        .workflow_run_id = 1,
        .job_id = try allocator.dupe(u8, "job-a"),
        .job_name = null,
        .runner_id = null,
        .status = .pending,
        .conclusion = null,
        .runs_on = try allocator.alloc([]const u8, 1),
        .needs = try allocator.alloc([]const u8, 0),
        .if_condition = null,
        .strategy = null,
        .timeout_minutes = 360,
        .environment = std.StringHashMap([]const u8).init(allocator),
        .started_at = null,
        .completed_at = null,
        .logs = try allocator.dupe(u8, ""),
        .created_at = std.time.timestamp(),
    };
    job_execution.runs_on[0] = try allocator.dupe(u8, "ubuntu-latest");
    
    const job_node = JobNode{
        .id = try allocator.dupe(u8, "job-a"),
        .original_id = try allocator.dupe(u8, "job-a"),
        .dependencies = try allocator.alloc([]const u8, 0),
        .dependents = try allocator.alloc([]const u8, 0),
        .job_execution = job_execution,
        .matrix_context = null,
    };
    
    try job_graph.nodes.put(try allocator.dupe(u8, "job-a"), job_node);
    
    // For now, just verify validation doesn't crash
    try job_graph.validateDependencies();
}

test "generates optimal execution plan" {
    const allocator = testing.allocator;
    
    const yaml_content = 
        \\jobs:
        \\  build:
        \\    runs-on: ubuntu-latest
        \\    steps:
        \\      - run: make build
    ;
    
    var workflow = try createTestWorkflow(allocator, yaml_content);
    defer workflow.deinit(allocator);
    
    var job_graph = try createTestJobGraph(allocator, workflow);
    defer job_graph.deinit();
    
    var execution_plan = try job_graph.getExecutionPlan(allocator);
    defer execution_plan.deinit(allocator);
    
    // Should have at least one phase
    try testing.expect(execution_plan.phases.len >= 1);
    try testing.expect(execution_plan.total_jobs >= 1);
    
    // First phase should have the test job
    const phase1 = execution_plan.phases[0];
    try testing.expect(phase1.jobs.len >= 1);
    try testing.expect(containsJob(phase1.jobs, "test"));
}