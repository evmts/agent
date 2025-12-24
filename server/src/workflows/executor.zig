//! Workflow Execution Engine
//!
//! Orchestrates execution of workflow plans (DAGs) with dependency tracking,
//! parallel execution, and streaming output.

const std = @import("std");
const plan = @import("plan.zig");
const db = @import("db");
const workflows_dao = db.workflows;
const llm_executor_mod = @import("llm_executor.zig");
const json = @import("../lib/json.zig");

fn buildToolLogPayload(
    allocator: std.mem.Allocator,
    tool_name: []const u8,
    tool_input: ?[]const u8,
    tool_output: ?[]const u8,
    success: ?bool,
) ![]const u8 {
    var list = std.ArrayList(u8){};
    errdefer list.deinit(allocator);

    const writer = list.writer(allocator);
    try writer.writeByte('{');
    try json.writeKey(writer, "tool_name");
    try json.writeString(writer, tool_name);
    if (tool_input) |input| {
        try json.writeSeparator(writer);
        try json.writeKey(writer, "tool_input");
        try json.writeString(writer, input);
    }
    if (tool_output) |output| {
        try json.writeSeparator(writer);
        try json.writeKey(writer, "tool_output");
        try json.writeString(writer, output);
    }
    if (success) |ok| {
        try json.writeSeparator(writer);
        try json.writeKey(writer, "success");
        try json.writeBool(writer, ok);
    }
    try writer.writeByte('}');

    return try list.toOwnedSlice(allocator);
}

const ParallelWorker = struct {
    step: *const plan.Step,
    status: StepStatus = .failed,
    exit_code: ?i32 = null,
    started_at: i64 = 0,
    completed_at: i64 = 0,
};

fn parallelWorkerMain(worker: *ParallelWorker, db_pool: ?*db.Pool, run_id: i32) void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var exec = Executor.init(arena.allocator(), db_pool, run_id);
    var result = exec.executeStep(worker.step) catch {
        worker.status = .failed;
        worker.exit_code = null;
        worker.started_at = std.time.timestamp();
        worker.completed_at = std.time.timestamp();
        return;
    };

    worker.status = result.status;
    worker.exit_code = result.exit_code;
    worker.started_at = result.started_at;
    worker.completed_at = result.completed_at;
    result.deinit(arena.allocator());
}

/// Step execution status
pub const StepStatus = enum {
    pending,    // Not yet started
    running,    // Currently executing
    succeeded,  // Completed successfully
    failed,     // Failed with error
    skipped,    // Skipped due to dependency failure
    cancelled,  // Manually cancelled

    pub fn toString(self: StepStatus) []const u8 {
        return switch (self) {
            .pending => "pending",
            .running => "running",
            .succeeded => "succeeded",
            .failed => "failed",
            .skipped => "skipped",
            .cancelled => "cancelled",
        };
    }
};

/// Step execution result
pub const StepResult = struct {
    step_id: []const u8,
    status: StepStatus,
    exit_code: ?i32,
    output: ?std.json.Value,
    error_message: ?[]const u8,
    turns_used: ?i32,
    tokens_in: ?i32,
    tokens_out: ?i32,
    started_at: i64,    // Unix timestamp
    completed_at: i64,  // Unix timestamp

    pub fn deinit(self: *StepResult, allocator: std.mem.Allocator) void {
        allocator.free(self.step_id);
        if (self.error_message) |msg| {
            allocator.free(msg);
        }
        // Deallocate output JSON if present
        if (self.output) |output| {
            switch (output) {
                .object => |obj| {
                    // Free all strings in the object
                    var iter = obj.iterator();
                    while (iter.next()) |entry| {
                        if (entry.value_ptr.* == .string) {
                            allocator.free(entry.value_ptr.string);
                        }
                    }
                    // ObjectMap owns its memory, so deinit it
                    var mutable_obj = obj;
                    mutable_obj.deinit();
                },
                else => {},
            }
        }
    }
};

/// Event emitted during execution
pub const ExecutionEvent = union(enum) {
    run_started: struct {
        run_id: i32,
        workflow: []const u8,
    },
    step_started: struct {
        step_id: []const u8,
        name: []const u8,
        @"type": plan.StepType,
    },
    step_output: struct {
        step_id: []const u8,
        line: []const u8,
    },
    llm_token: struct {
        step_id: []const u8,
        text: []const u8,
    },
    tool_call_start: struct {
        step_id: []const u8,
        tool_name: []const u8,
        tool_input: []const u8,
    },
    tool_call_end: struct {
        step_id: []const u8,
        tool_name: []const u8,
        tool_output: []const u8,
        success: bool,
    },
    agent_turn_complete: struct {
        step_id: []const u8,
        turn_number: u32,
    },
    step_completed: struct {
        step_id: []const u8,
        success: bool,
        output: ?std.json.Value,
        error_message: ?[]const u8,
    },
    run_completed: struct {
        success: bool,
        outputs: ?std.json.Value,
        error_message: ?[]const u8,
    },

    pub fn deinit(self: *ExecutionEvent, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .run_started => |data| {
                allocator.free(data.workflow);
            },
            .step_started => |data| {
                allocator.free(data.step_id);
                allocator.free(data.name);
            },
            .step_output => |data| {
                allocator.free(data.step_id);
                allocator.free(data.line);
            },
            .llm_token => |data| {
                allocator.free(data.step_id);
                allocator.free(data.text);
            },
            .tool_call_start => |data| {
                allocator.free(data.step_id);
                allocator.free(data.tool_name);
                allocator.free(data.tool_input);
            },
            .tool_call_end => |data| {
                allocator.free(data.step_id);
                allocator.free(data.tool_name);
                allocator.free(data.tool_output);
            },
            .agent_turn_complete => |data| {
                allocator.free(data.step_id);
            },
            .step_completed => |data| {
                allocator.free(data.step_id);
                if (data.error_message) |msg| {
                    allocator.free(msg);
                }
            },
            .run_completed => |data| {
                if (data.error_message) |msg| {
                    allocator.free(msg);
                }
            },
        }
    }
};

/// Callback for streaming events
pub const EventCallback = *const fn (event: ExecutionEvent, ctx: ?*anyopaque) void;

/// Workflow executor
pub const Executor = struct {
    allocator: std.mem.Allocator,
    event_callback: ?EventCallback,
    event_ctx: ?*anyopaque,
    db_pool: ?*db.Pool,
    run_id: i32,

    pub fn init(allocator: std.mem.Allocator, db_pool: ?*db.Pool, run_id: i32) Executor {
        return .{
            .allocator = allocator,
            .event_callback = null,
            .event_ctx = null,
            .db_pool = db_pool,
            .run_id = run_id,
        };
    }

    pub fn setEventCallback(self: *Executor, callback: EventCallback, ctx: ?*anyopaque) void {
        self.event_callback = callback;
        self.event_ctx = ctx;
    }

    /// Execute a workflow plan
    pub fn execute(
        self: *Executor,
        workflow: *const plan.WorkflowDefinition,
        run_id: i32,
    ) ![]StepResult {
        // Emit run started event
        if (self.event_callback) |callback| {
            const event = ExecutionEvent{
                .run_started = .{
                    .run_id = run_id,
                    .workflow = try self.allocator.dupe(u8, workflow.name),
                },
            };
            callback(event, self.event_ctx);
        }

        // Build execution order using topological sort
        const execution_order = try self.topologicalSort(workflow);
        defer self.allocator.free(execution_order);

        // Track step results
        var results = std.ArrayList(StepResult){};
        defer results.deinit(self.allocator);

        var status_map = std.StringHashMap(StepStatus).init(self.allocator);
        defer status_map.deinit();

        var executed_steps = std.StringHashMap(void).init(self.allocator);
        defer executed_steps.deinit();

        // Execute steps in order
        for (execution_order) |step_index| {
            const step = &workflow.steps[step_index];

            if (executed_steps.contains(step.id)) {
                continue;
            }

            // Check if dependencies succeeded
            const deps_ok = try self.checkDependencies(step, &status_map);
            if (!deps_ok) {
                // Skip this step
                try status_map.put(step.id, .skipped);
                try results.append(self.allocator, .{
                    .step_id = try self.allocator.dupe(u8, step.id),
                    .status = .skipped,
                    .exit_code = null,
                    .output = null,
                    .error_message = try self.allocator.dupe(u8, "Dependency failed"),
                    .turns_used = null,
                    .tokens_in = null,
                    .tokens_out = null,
                    .started_at = std.time.timestamp(),
                    .completed_at = std.time.timestamp(),
                });
                try executed_steps.put(step.id, {});
                continue;
            }

            if (step.@"type" == .parallel) {
                const group_results = try self.executeParallelGroup(workflow, step, &status_map, &executed_steps);
                for (group_results) |group_result| {
                    try results.append(self.allocator, group_result);
                }
                self.allocator.free(group_results);
                continue;
            }

            // Execute the step
            const result = try self.executeStep(step);
            try status_map.put(step.id, result.status);
            try executed_steps.put(step.id, {});
            try results.append(self.allocator, result);

            // If step failed and it's not a parallel group, we might want to stop
            // For now, continue execution
        }

        // Emit run completed event
        if (self.event_callback) |callback| {
            const all_succeeded = blk: {
                for (results.items) |result| {
                    if (result.status != .succeeded and result.status != .skipped) {
                        break :blk false;
                    }
                }
                break :blk true;
            };

            const event = ExecutionEvent{
                .run_completed = .{
                    .success = all_succeeded,
                    .outputs = null,
                    .error_message = if (!all_succeeded)
                        try self.allocator.dupe(u8, "One or more steps failed")
                    else
                        null,
                },
            };
            callback(event, self.event_ctx);
        }

        return try results.toOwnedSlice(self.allocator);
    }

    /// Execute a single step
    fn executeStep(self: *Executor, step: *const plan.Step) !StepResult {
        const started_at = std.time.timestamp();

        // Create step record in database if db_pool is available
        var db_step_id: ?i32 = null;
        if (self.db_pool) |pool| {
            // Convert step config to JSON string
            const config_str = try json.valueToString(self.allocator, step.config.data);
            defer self.allocator.free(config_str);

            // Convert step type to string
            const step_type_str = switch (step.@"type") {
                .shell => "shell",
                .llm => "llm",
                .agent => "agent",
                .parallel => "parallel",
            };

            db_step_id = try workflows_dao.createWorkflowStep(
                pool,
                self.run_id,
                step.id,
                step.name,
                step_type_str,
                config_str,
            );

            // Update status to running
            try workflows_dao.updateWorkflowStepStatus(pool, db_step_id.?, "running");
        }

        // Emit step started event
        if (self.event_callback) |callback| {
            const event = ExecutionEvent{
                .step_started = .{
                    .step_id = try self.allocator.dupe(u8, step.id),
                    .name = try self.allocator.dupe(u8, step.name),
                    .@"type" = step.@"type",
                },
            };
            callback(event, self.event_ctx);
        }

        // Execute based on step type
        const result = switch (step.@"type") {
            .shell => try self.executeShellStep(step, db_step_id),
            .parallel => try self.executeParallelStep(step),
            .llm => try self.executeLlmStep(step, db_step_id, started_at),
            .agent => try self.executeAgentStep(step, db_step_id, started_at),
        };

        // Complete step in database
        if (self.db_pool) |pool| {
            if (db_step_id) |step_db_id| {
                // Convert output to JSON string if present
                var output_str: ?[]const u8 = null;
                if (result.output) |output| {
                    output_str = try json.valueToString(self.allocator, output);
                }
                defer if (output_str) |s| self.allocator.free(s);

                try workflows_dao.completeWorkflowStep(
                    pool,
                    step_db_id,
                    result.exit_code,
                    output_str,
                    result.error_message,
                    result.turns_used,
                    result.tokens_in,
                    result.tokens_out,
                );
            }
        }

        // Emit step completed event
        if (self.event_callback) |callback| {
            const event = ExecutionEvent{
                .step_completed = .{
                    .step_id = try self.allocator.dupe(u8, step.id),
                    .success = result.status == .succeeded,
                    .output = result.output,
                    .error_message = if (result.error_message) |msg|
                        try self.allocator.dupe(u8, msg)
                    else
                        null,
                },
            };
            callback(event, self.event_ctx);
        }

        return result;
    }

    /// Execute an LLM step (single-shot, no tools)
    fn executeLlmStep(self: *Executor, step: *const plan.Step, db_step_id: ?i32, started_at: i64) !StepResult {
        // Create LLM executor
        var llm_exec = llm_executor_mod.LlmExecutor.init(self.allocator, self.db_pool);
        var log_sequence: i32 = 0;

        // Set up event callback to forward events
        const LlmCallbackCtx = struct {
            executor: *Executor,
            step_id: []const u8,
            db_step_id: ?i32,
            log_sequence: *i32,
        };

        var callback_ctx = LlmCallbackCtx{
            .executor = self,
            .step_id = step.id,
            .db_step_id = db_step_id,
            .log_sequence = &log_sequence,
        };

        const callback = struct {
            fn cb(event: llm_executor_mod.LlmExecutionEvent, ctx: ?*anyopaque) void {
                const context: *LlmCallbackCtx = @alignCast(@ptrCast(ctx.?));
                const executor = context.executor;

                switch (event) {
                    .token => |token_data| {
                        if (context.db_step_id) |step_db_id| {
                            if (executor.db_pool) |pool| {
                                _ = workflows_dao.appendWorkflowLog(
                                    pool,
                                    step_db_id,
                                    "token",
                                    token_data.text,
                                    context.log_sequence.*,
                                ) catch {};
                                context.log_sequence.* += 1;
                            }
                        }

                        if (executor.event_callback) |exec_callback| {
                            const exec_event = ExecutionEvent{
                                .llm_token = .{
                                    .step_id = executor.allocator.dupe(u8, token_data.step_id) catch return,
                                    .text = executor.allocator.dupe(u8, token_data.text) catch return,
                                },
                            };
                            exec_callback(exec_event, executor.event_ctx);
                        }
                    },
                    .tool_start => |tool_data| {
                        if (context.db_step_id) |step_db_id| {
                            if (executor.db_pool) |pool| {
                                const payload = buildToolLogPayload(
                                    executor.allocator,
                                    tool_data.tool_name,
                                    tool_data.tool_input,
                                    null,
                                    null,
                                ) catch return;
                                defer executor.allocator.free(payload);
                                _ = workflows_dao.appendWorkflowLog(
                                    pool,
                                    step_db_id,
                                    "tool_call",
                                    payload,
                                    context.log_sequence.*,
                                ) catch {};
                                context.log_sequence.* += 1;
                            }
                        }

                        if (executor.event_callback) |exec_callback| {
                            const exec_event = ExecutionEvent{
                                .tool_call_start = .{
                                    .step_id = executor.allocator.dupe(u8, tool_data.step_id) catch return,
                                    .tool_name = executor.allocator.dupe(u8, tool_data.tool_name) catch return,
                                    .tool_input = executor.allocator.dupe(u8, tool_data.tool_input) catch return,
                                },
                            };
                            exec_callback(exec_event, executor.event_ctx);
                        }
                    },
                    .tool_end => |tool_data| {
                        if (context.db_step_id) |step_db_id| {
                            if (executor.db_pool) |pool| {
                                const payload = buildToolLogPayload(
                                    executor.allocator,
                                    tool_data.tool_name,
                                    null,
                                    tool_data.tool_output,
                                    tool_data.success,
                                ) catch return;
                                defer executor.allocator.free(payload);
                                _ = workflows_dao.appendWorkflowLog(
                                    pool,
                                    step_db_id,
                                    "tool_result",
                                    payload,
                                    context.log_sequence.*,
                                ) catch {};
                                context.log_sequence.* += 1;
                            }
                        }

                        if (executor.event_callback) |exec_callback| {
                            const exec_event = ExecutionEvent{
                                .tool_call_end = .{
                                    .step_id = executor.allocator.dupe(u8, tool_data.step_id) catch return,
                                    .tool_name = executor.allocator.dupe(u8, tool_data.tool_name) catch return,
                                    .tool_output = executor.allocator.dupe(u8, tool_data.tool_output) catch return,
                                    .success = tool_data.success,
                                },
                            };
                            exec_callback(exec_event, executor.event_ctx);
                        }
                    },
                    .turn_complete => |turn_data| {
                        if (executor.event_callback) |exec_callback| {
                            const exec_event = ExecutionEvent{
                                .agent_turn_complete = .{
                                    .step_id = executor.allocator.dupe(u8, turn_data.step_id) catch return,
                                    .turn_number = turn_data.turn_number,
                                },
                            };
                            exec_callback(exec_event, executor.event_ctx);
                        }
                    },
                }
            }
        }.cb;

        llm_exec.setEventCallback(callback, &callback_ctx);

        // Execute LLM step
        const llm_result = llm_exec.executeLlmStep(step.id, &step.config) catch |err| {
            return StepResult{
                .step_id = try self.allocator.dupe(u8, step.id),
                .status = .failed,
                .exit_code = null,
                .output = null,
                .error_message = try std.fmt.allocPrint(
                    self.allocator,
                    "LLM execution failed: {s}",
                    .{@errorName(err)},
                ),
                .turns_used = null,
                .tokens_in = null,
                .tokens_out = null,
                .started_at = started_at,
                .completed_at = std.time.timestamp(),
            };
        };

        // Record LLM usage in database if step was persisted
        if (self.db_pool) |pool| {
            if (db_step_id) |step_db_id| {
                const completed_at = std.time.timestamp();
                const latency_ms = @as(i32, @intCast(completed_at - started_at)) * 1000;

                // Get prompt name from config
                const prompt_name: ?[]const u8 = if (step.config.data.object.get("prompt_path")) |p|
                    p.string
                else
                    null;

                // Get model from config or use default
                const model = if (step.config.data.object.get("client")) |c|
                    c.string
                else
                    "claude-sonnet-4-20250514";

                // Record usage
                _ = workflows_dao.recordLlmUsage(
                    pool,
                    step_db_id,
                    prompt_name,
                    model,
                    @as(i32, @intCast(llm_result.tokens_in)),
                    @as(i32, @intCast(llm_result.tokens_out)),
                    latency_ms,
                ) catch |err| {
                    std.log.err("Failed to record LLM usage: {s}", .{@errorName(err)});
                };
            }
        }

        // Convert to StepResult
        const status: StepStatus = if (llm_result.error_message != null) .failed else .succeeded;

        return StepResult{
            .step_id = try self.allocator.dupe(u8, step.id),
            .status = status,
            .exit_code = null,
            .output = llm_result.output,
            .error_message = llm_result.error_message,
            .turns_used = @as(i32, @intCast(llm_result.turns_used)),
            .tokens_in = @as(i32, @intCast(llm_result.tokens_in)),
            .tokens_out = @as(i32, @intCast(llm_result.tokens_out)),
            .started_at = started_at,
            .completed_at = std.time.timestamp(),
        };
    }

    /// Execute an agent step (multi-turn with tools)
    fn executeAgentStep(self: *Executor, step: *const plan.Step, db_step_id: ?i32, started_at: i64) !StepResult {
        // Create LLM executor
        var llm_exec = llm_executor_mod.LlmExecutor.init(self.allocator, self.db_pool);
        var log_sequence: i32 = 0;

        // Set up event callback to forward events
        const AgentCallbackCtx = struct {
            executor: *Executor,
            step_id: []const u8,
            db_step_id: ?i32,
            log_sequence: *i32,
        };

        var callback_ctx = AgentCallbackCtx{
            .executor = self,
            .step_id = step.id,
            .db_step_id = db_step_id,
            .log_sequence = &log_sequence,
        };

        const callback = struct {
            fn cb(event: llm_executor_mod.LlmExecutionEvent, ctx: ?*anyopaque) void {
                const context: *AgentCallbackCtx = @alignCast(@ptrCast(ctx.?));
                const executor = context.executor;

                switch (event) {
                    .token => |token_data| {
                        if (context.db_step_id) |step_db_id| {
                            if (executor.db_pool) |pool| {
                                _ = workflows_dao.appendWorkflowLog(
                                    pool,
                                    step_db_id,
                                    "token",
                                    token_data.text,
                                    context.log_sequence.*,
                                ) catch {};
                                context.log_sequence.* += 1;
                            }
                        }

                        if (executor.event_callback) |exec_callback| {
                            const exec_event = ExecutionEvent{
                                .llm_token = .{
                                    .step_id = executor.allocator.dupe(u8, token_data.step_id) catch return,
                                    .text = executor.allocator.dupe(u8, token_data.text) catch return,
                                },
                            };
                            exec_callback(exec_event, executor.event_ctx);
                        }
                    },
                    .tool_start => |tool_data| {
                        if (context.db_step_id) |step_db_id| {
                            if (executor.db_pool) |pool| {
                                const payload = buildToolLogPayload(
                                    executor.allocator,
                                    tool_data.tool_name,
                                    tool_data.tool_input,
                                    null,
                                    null,
                                ) catch return;
                                defer executor.allocator.free(payload);
                                _ = workflows_dao.appendWorkflowLog(
                                    pool,
                                    step_db_id,
                                    "tool_call",
                                    payload,
                                    context.log_sequence.*,
                                ) catch {};
                                context.log_sequence.* += 1;
                            }
                        }

                        if (executor.event_callback) |exec_callback| {
                            const exec_event = ExecutionEvent{
                                .tool_call_start = .{
                                    .step_id = executor.allocator.dupe(u8, tool_data.step_id) catch return,
                                    .tool_name = executor.allocator.dupe(u8, tool_data.tool_name) catch return,
                                    .tool_input = executor.allocator.dupe(u8, tool_data.tool_input) catch return,
                                },
                            };
                            exec_callback(exec_event, executor.event_ctx);
                        }
                    },
                    .tool_end => |tool_data| {
                        if (context.db_step_id) |step_db_id| {
                            if (executor.db_pool) |pool| {
                                const payload = buildToolLogPayload(
                                    executor.allocator,
                                    tool_data.tool_name,
                                    null,
                                    tool_data.tool_output,
                                    tool_data.success,
                                ) catch return;
                                defer executor.allocator.free(payload);
                                _ = workflows_dao.appendWorkflowLog(
                                    pool,
                                    step_db_id,
                                    "tool_result",
                                    payload,
                                    context.log_sequence.*,
                                ) catch {};
                                context.log_sequence.* += 1;
                            }
                        }

                        if (executor.event_callback) |exec_callback| {
                            const exec_event = ExecutionEvent{
                                .tool_call_end = .{
                                    .step_id = executor.allocator.dupe(u8, tool_data.step_id) catch return,
                                    .tool_name = executor.allocator.dupe(u8, tool_data.tool_name) catch return,
                                    .tool_output = executor.allocator.dupe(u8, tool_data.tool_output) catch return,
                                    .success = tool_data.success,
                                },
                            };
                            exec_callback(exec_event, executor.event_ctx);
                        }
                    },
                    .turn_complete => |turn_data| {
                        if (executor.event_callback) |exec_callback| {
                            const exec_event = ExecutionEvent{
                                .agent_turn_complete = .{
                                    .step_id = executor.allocator.dupe(u8, turn_data.step_id) catch return,
                                    .turn_number = turn_data.turn_number,
                                },
                            };
                            exec_callback(exec_event, executor.event_ctx);
                        }
                    },
                }
            }
        }.cb;

        llm_exec.setEventCallback(callback, &callback_ctx);

        // Execute agent step
        const agent_result = llm_exec.executeAgentStep(step.id, &step.config) catch |err| {
            return StepResult{
                .step_id = try self.allocator.dupe(u8, step.id),
                .status = .failed,
                .exit_code = null,
                .output = null,
                .error_message = try std.fmt.allocPrint(
                    self.allocator,
                    "Agent execution failed: {s}",
                    .{@errorName(err)},
                ),
                .turns_used = null,
                .tokens_in = null,
                .tokens_out = null,
                .started_at = started_at,
                .completed_at = std.time.timestamp(),
            };
        };

        // Record LLM usage in database if step was persisted
        if (self.db_pool) |pool| {
            if (db_step_id) |step_db_id| {
                const completed_at = std.time.timestamp();
                const latency_ms = @as(i32, @intCast(completed_at - started_at)) * 1000;

                // Get prompt name from config
                const prompt_name: ?[]const u8 = if (step.config.data.object.get("prompt_path")) |p|
                    p.string
                else
                    null;

                // Get model from config or use default
                const model = if (step.config.data.object.get("client")) |c|
                    c.string
                else
                    "claude-sonnet-4-20250514";

                // Record usage
                _ = workflows_dao.recordLlmUsage(
                    pool,
                    step_db_id,
                    prompt_name,
                    model,
                    @as(i32, @intCast(agent_result.tokens_in)),
                    @as(i32, @intCast(agent_result.tokens_out)),
                    latency_ms,
                ) catch |err| {
                    std.log.err("Failed to record agent LLM usage: {s}", .{@errorName(err)});
                };
            }
        }

        // Convert to StepResult
        const status: StepStatus = if (agent_result.error_message != null) .failed else .succeeded;

        return StepResult{
            .step_id = try self.allocator.dupe(u8, step.id),
            .status = status,
            .exit_code = null,
            .output = agent_result.output,
            .error_message = agent_result.error_message,
            .turns_used = @as(i32, @intCast(agent_result.turns_used)),
            .tokens_in = @as(i32, @intCast(agent_result.tokens_in)),
            .tokens_out = @as(i32, @intCast(agent_result.tokens_out)),
            .started_at = started_at,
            .completed_at = std.time.timestamp(),
        };
    }

    /// Execute a shell step
    fn executeShellStep(self: *Executor, step: *const plan.Step, db_step_id: ?i32) !StepResult {
        const started_at = std.time.timestamp();
        var log_sequence: i32 = 0;

        // Extract command from config
        const config = step.config.data;
        const cmd = switch (config) {
            .object => |obj| blk: {
                const cmd_value = obj.get("cmd") orelse {
                    return StepResult{
                        .step_id = try self.allocator.dupe(u8, step.id),
                        .status = .failed,
                        .exit_code = null,
                        .output = null,
                        .error_message = try self.allocator.dupe(u8, "Missing 'cmd' in shell step config"),
                        .turns_used = null,
                        .tokens_in = null,
                        .tokens_out = null,
                        .started_at = started_at,
                        .completed_at = std.time.timestamp(),
                    };
                };
                break :blk switch (cmd_value) {
                    .string => |s| s,
                    else => {
                        return StepResult{
                            .step_id = try self.allocator.dupe(u8, step.id),
                            .status = .failed,
                            .exit_code = null,
                            .output = null,
                            .error_message = try self.allocator.dupe(u8, "'cmd' must be a string"),
                            .turns_used = null,
                            .tokens_in = null,
                            .tokens_out = null,
                            .started_at = started_at,
                            .completed_at = std.time.timestamp(),
                        };
                    },
                };
            },
            else => {
                return StepResult{
                    .step_id = try self.allocator.dupe(u8, step.id),
                    .status = .failed,
                    .exit_code = null,
                    .output = null,
                    .error_message = try self.allocator.dupe(u8, "Shell step config must be an object"),
                    .turns_used = null,
                    .tokens_in = null,
                    .tokens_out = null,
                    .started_at = started_at,
                    .completed_at = std.time.timestamp(),
                };
            },
        };

        // Extract environment variables if present
        var env_map = std.process.EnvMap.init(self.allocator);
        defer env_map.deinit();

        // Copy current environment
        var current_env = try std.process.getEnvMap(self.allocator);
        defer current_env.deinit();
        var env_it = current_env.iterator();
        while (env_it.next()) |entry| {
            try env_map.put(entry.key_ptr.*, entry.value_ptr.*);
        }

        // Add step-specific env vars
        if (config == .object) {
            if (config.object.get("env")) |env_value| {
                if (env_value == .object) {
                    var it = env_value.object.iterator();
                    while (it.next()) |entry| {
                        const value_str = switch (entry.value_ptr.*) {
                            .string => |s| s,
                            else => continue,
                        };
                        try env_map.put(entry.key_ptr.*, value_str);
                    }
                }
            }
        }

        // WARNING: Commands come from workflow YAML. Do not include untrusted user input in cmd.
        // For complex shell features, workflows should use a dedicated shell step type.
        // TODO: Add a "trusted" shell step type that allows `sh -c` for advanced use cases.
        //
        // Parse command into argv array for safer execution without shell interpretation
        // This prevents command injection if untrusted data somehow flows into cmd.
        var argv_list = std.ArrayList([]const u8){};
        defer argv_list.deinit(self.allocator);

        // Simple whitespace tokenization (doesn't handle quotes/escapes)
        // This is intentionally limited to prevent shell metacharacter interpretation
        var iter = std.mem.tokenizeAny(u8, cmd, " \t\n\r");
        while (iter.next()) |token| {
            try argv_list.append(self.allocator, token);
        }

        if (argv_list.items.len == 0) {
            return StepResult{
                .step_id = try self.allocator.dupe(u8, step.id),
                .status = .failed,
                .exit_code = null,
                .output = null,
                .error_message = try self.allocator.dupe(u8, "Empty command"),
                .turns_used = null,
                .tokens_in = null,
                .tokens_out = null,
                .started_at = started_at,
                .completed_at = std.time.timestamp(),
            };
        }

        // Use direct argv execution instead of sh -c to avoid shell injection

        var child = std.process.Child.init(argv_list.items, self.allocator);
        child.env_map = &env_map;
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;

        child.spawn() catch |err| {
            return StepResult{
                .step_id = try self.allocator.dupe(u8, step.id),
                .status = .failed,
                .exit_code = null,
                .output = null,
                .error_message = try std.fmt.allocPrint(
                    self.allocator,
                    "Failed to spawn command: {s}",
                    .{@errorName(err)},
                ),
                .turns_used = null,
                .tokens_in = null,
                .tokens_out = null,
                .started_at = started_at,
                .completed_at = std.time.timestamp(),
            };
        };

        var stdout_acc = std.ArrayList(u8){};
        defer stdout_acc.deinit(self.allocator);
        var stderr_acc = std.ArrayList(u8){};
        defer stderr_acc.deinit(self.allocator);

        var stdout_open = true;
        var stderr_open = true;

        var poll_fds = [_]std.posix.pollfd{
            .{ .fd = child.stdout.?.handle, .events = std.posix.POLL.IN, .revents = 0 },
            .{ .fd = child.stderr.?.handle, .events = std.posix.POLL.IN, .revents = 0 },
        };

        var stdout_buf: [4096]u8 = undefined;
        var stderr_buf: [4096]u8 = undefined;

        while (stdout_open or stderr_open) {
            _ = try std.posix.poll(&poll_fds, -1);

            if (stdout_open and poll_fds[0].revents != 0) {
                const bytes_read = child.stdout.?.read(&stdout_buf) catch |err| {
                    _ = child.kill() catch {};
                    return StepResult{
                        .step_id = try self.allocator.dupe(u8, step.id),
                        .status = .failed,
                        .exit_code = null,
                        .output = null,
                        .error_message = try std.fmt.allocPrint(
                            self.allocator,
                            "Failed to read stdout: {s}",
                            .{@errorName(err)},
                        ),
                        .turns_used = null,
                        .tokens_in = null,
                        .tokens_out = null,
                        .started_at = started_at,
                        .completed_at = std.time.timestamp(),
                    };
                };

                if (bytes_read == 0) {
                    stdout_open = false;
                    poll_fds[0].fd = -1;
                } else {
                    const chunk = stdout_buf[0..bytes_read];
                    try stdout_acc.appendSlice(self.allocator, chunk);

                    if (self.db_pool) |pool| {
                        if (db_step_id) |step_db_id| {
                            _ = try workflows_dao.appendWorkflowLog(
                                pool,
                                step_db_id,
                                "stdout",
                                chunk,
                                log_sequence,
                            );
                            log_sequence += 1;
                        }
                    }

                    if (self.event_callback) |callback| {
                        const event = ExecutionEvent{
                            .step_output = .{
                                .step_id = try self.allocator.dupe(u8, step.id),
                                .line = try self.allocator.dupe(u8, chunk),
                            },
                        };
                        callback(event, self.event_ctx);
                    }
                }
            }

            if (stderr_open and poll_fds[1].revents != 0) {
                const bytes_read = child.stderr.?.read(&stderr_buf) catch |err| {
                    _ = child.kill() catch {};
                    return StepResult{
                        .step_id = try self.allocator.dupe(u8, step.id),
                        .status = .failed,
                        .exit_code = null,
                        .output = null,
                        .error_message = try std.fmt.allocPrint(
                            self.allocator,
                            "Failed to read stderr: {s}",
                            .{@errorName(err)},
                        ),
                        .turns_used = null,
                        .tokens_in = null,
                        .tokens_out = null,
                        .started_at = started_at,
                        .completed_at = std.time.timestamp(),
                    };
                };

                if (bytes_read == 0) {
                    stderr_open = false;
                    poll_fds[1].fd = -1;
                } else {
                    const chunk = stderr_buf[0..bytes_read];
                    try stderr_acc.appendSlice(self.allocator, chunk);

                    if (self.db_pool) |pool| {
                        if (db_step_id) |step_db_id| {
                            _ = try workflows_dao.appendWorkflowLog(
                                pool,
                                step_db_id,
                                "stderr",
                                chunk,
                                log_sequence,
                            );
                            log_sequence += 1;
                        }
                    }

                    if (self.event_callback) |callback| {
                        const event = ExecutionEvent{
                            .step_output = .{
                                .step_id = try self.allocator.dupe(u8, step.id),
                                .line = try self.allocator.dupe(u8, chunk),
                            },
                        };
                        callback(event, self.event_ctx);
                    }
                }
            }
        }

        // Wait for completion
        const term = child.wait() catch |err| {
            return StepResult{
                .step_id = try self.allocator.dupe(u8, step.id),
                .status = .failed,
                .exit_code = null,
                .output = null,
                .error_message = try std.fmt.allocPrint(
                    self.allocator,
                    "Failed to wait for command: {s}",
                    .{@errorName(err)},
                ),
                .turns_used = null,
                .tokens_in = null,
                .tokens_out = null,
                .started_at = started_at,
                .completed_at = std.time.timestamp(),
            };
        };

        // Build output JSON
        var output_obj = std.json.ObjectMap.init(self.allocator);
        // Duplicate strings since stdout/stderr will be freed by defer
        try output_obj.put("stdout", .{ .string = try self.allocator.dupe(u8, stdout_acc.items) });
        try output_obj.put("stderr", .{ .string = try self.allocator.dupe(u8, stderr_acc.items) });

        const exit_code: i32 = switch (term) {
            .Exited => |code| @intCast(code),
            .Signal => -1,
            .Stopped => -1,
            .Unknown => -1,
        };

        const success = exit_code == 0;
        const error_message = if (!success and stderr_acc.items.len > 0)
            try self.allocator.dupe(u8, stderr_acc.items)
        else
            null;

        return StepResult{
            .step_id = try self.allocator.dupe(u8, step.id),
            .status = if (success) .succeeded else .failed,
            .exit_code = exit_code,
            .output = .{ .object = output_obj },
            .error_message = error_message,
            .turns_used = null,
            .tokens_in = null,
            .tokens_out = null,
            .started_at = started_at,
            .completed_at = std.time.timestamp(),
        };
    }

    /// Execute a parallel step group
    fn executeParallelStep(self: *Executor, step: *const plan.Step) !StepResult {
        // TODO: Implement actual parallel execution
        // For now, just return success
        return StepResult{
            .step_id = try self.allocator.dupe(u8, step.id),
            .status = .succeeded,
            .exit_code = null,
            .output = null,
            .error_message = null,
            .turns_used = null,
            .tokens_in = null,
            .tokens_out = null,
            .started_at = std.time.timestamp(),
            .completed_at = std.time.timestamp(),
        };
    }

    fn executeParallelGroup(
        self: *Executor,
        workflow: *const plan.WorkflowDefinition,
        parallel_step: *const plan.Step,
        status_map: *std.StringHashMap(StepStatus),
        executed_steps: *std.StringHashMap(void),
    ) ![]StepResult {
        var results = std.ArrayList(StepResult){};
        errdefer results.deinit(self.allocator);

        const config = parallel_step.config.data;
        const step_ids_value = if (config == .object) config.object.get("step_ids") else null;
        if (step_ids_value == null or step_ids_value.? != .array) {
            try results.append(self.allocator, .{
                .step_id = try self.allocator.dupe(u8, parallel_step.id),
                .status = .failed,
                .exit_code = null,
                .output = null,
                .error_message = try self.allocator.dupe(u8, "Parallel step missing step_ids"),
                .turns_used = null,
                .tokens_in = null,
                .tokens_out = null,
                .started_at = std.time.timestamp(),
                .completed_at = std.time.timestamp(),
            });
            try status_map.put(parallel_step.id, .failed);
            try executed_steps.put(parallel_step.id, {});
            return try results.toOwnedSlice(self.allocator);
        }

        var step_lookup = std.StringHashMap(*const plan.Step).init(self.allocator);
        defer step_lookup.deinit();
        for (workflow.steps) |*step| {
            _ = step_lookup.put(step.id, step) catch {};
        }

        var to_run = std.ArrayList(*const plan.Step){};
        defer to_run.deinit(self.allocator);

        const started_at = std.time.timestamp();
        for (step_ids_value.?.array.items) |item| {
            if (item != .string) continue;
            const step_id = item.string;
            const step_ptr = step_lookup.get(step_id) orelse continue;

            const deps_ok = try self.checkDependencies(step_ptr, status_map);
            if (!deps_ok) {
                try status_map.put(step_ptr.id, .skipped);
                try executed_steps.put(step_ptr.id, {});
                try results.append(self.allocator, .{
                    .step_id = try self.allocator.dupe(u8, step_ptr.id),
                    .status = .skipped,
                    .exit_code = null,
                    .output = null,
                    .error_message = try self.allocator.dupe(u8, "Dependency failed"),
                    .turns_used = null,
                    .tokens_in = null,
                    .tokens_out = null,
                    .started_at = std.time.timestamp(),
                    .completed_at = std.time.timestamp(),
                });
            } else {
                try to_run.append(self.allocator, step_ptr);
            }
        }

        if (to_run.items.len > 0) {
            const worker_count = to_run.items.len;
            var workers = try self.allocator.alloc(ParallelWorker, worker_count);
            defer self.allocator.free(workers);
            var threads = try self.allocator.alloc(std.Thread, worker_count);
            defer self.allocator.free(threads);

            for (to_run.items, 0..) |step_ptr, i| {
                workers[i] = .{ .step = step_ptr };
                threads[i] = try std.Thread.spawn(.{}, parallelWorkerMain, .{ &workers[i], self.db_pool, self.run_id });
            }

            for (threads) |thread| {
                thread.join();
            }

            for (workers) |worker| {
                try status_map.put(worker.step.id, worker.status);
                try executed_steps.put(worker.step.id, {});
                try results.append(self.allocator, .{
                    .step_id = try self.allocator.dupe(u8, worker.step.id),
                    .status = worker.status,
                    .exit_code = worker.exit_code,
                    .output = null,
                    .error_message = null,
                    .turns_used = null,
                    .tokens_in = null,
                    .tokens_out = null,
                    .started_at = worker.started_at,
                    .completed_at = worker.completed_at,
                });
            }
        }

        const group_success = blk: {
            for (results.items) |result| {
                if (result.status != .succeeded and result.status != .skipped) break :blk false;
            }
            break :blk true;
        };

        const completed_at = std.time.timestamp();
        try status_map.put(parallel_step.id, if (group_success) .succeeded else .failed);
        try executed_steps.put(parallel_step.id, {});
        try results.append(self.allocator, .{
            .step_id = try self.allocator.dupe(u8, parallel_step.id),
            .status = if (group_success) .succeeded else .failed,
            .exit_code = null,
            .output = null,
            .error_message = if (group_success) null else try self.allocator.dupe(u8, "Parallel group failed"),
            .turns_used = null,
            .tokens_in = null,
            .tokens_out = null,
            .started_at = started_at,
            .completed_at = completed_at,
        });

        return try results.toOwnedSlice(self.allocator);
    }

    /// Check if all dependencies of a step have succeeded
    fn checkDependencies(
        self: *Executor,
        step: *const plan.Step,
        status_map: *std.StringHashMap(StepStatus),
    ) !bool {
        _ = self;
        for (step.depends_on) |dep_id| {
            const status = status_map.get(dep_id) orelse return false;
            if (status != .succeeded) {
                return false;
            }
        }
        return true;
    }

    /// Perform topological sort on workflow steps
    /// Returns array of step indices in execution order
    fn topologicalSort(self: *Executor, workflow: *const plan.WorkflowDefinition) ![]usize {
        const n = workflow.steps.len;
        if (n == 0) return try self.allocator.alloc(usize, 0);

        // Build adjacency list and in-degree count
        var adj_list = try self.allocator.alloc(std.ArrayList(usize), n);
        defer {
            for (adj_list) |*list| {
                list.deinit(self.allocator);
            }
            self.allocator.free(adj_list);
        }

        var in_degree = try self.allocator.alloc(usize, n);
        defer self.allocator.free(in_degree);

        // Initialize
        for (0..n) |i| {
            adj_list[i] = std.ArrayList(usize){};
            in_degree[i] = 0;
        }

        // Build step ID to index map
        var id_to_index = std.StringHashMap(usize).init(self.allocator);
        defer id_to_index.deinit();
        for (workflow.steps, 0..) |step, i| {
            try id_to_index.put(step.id, i);
        }

        // Build graph
        for (workflow.steps, 0..) |step, i| {
            for (step.depends_on) |dep_id| {
                const dep_index = id_to_index.get(dep_id) orelse continue;
                try adj_list[dep_index].append(self.allocator, i);
                in_degree[i] += 1;
            }
        }

        // Kahn's algorithm for topological sort
        var queue = std.ArrayList(usize){};
        defer queue.deinit(self.allocator);

        // Add all nodes with in-degree 0
        for (in_degree, 0..) |degree, i| {
            if (degree == 0) {
                try queue.append(self.allocator, i);
            }
        }

        var result = std.ArrayList(usize){};
        errdefer result.deinit(self.allocator);

        while (queue.items.len > 0) {
            const u = queue.orderedRemove(0);
            try result.append(self.allocator, u);

            // Reduce in-degree of neighbors
            for (adj_list[u].items) |v| {
                in_degree[v] -= 1;
                if (in_degree[v] == 0) {
                    try queue.append(self.allocator, v);
                }
            }
        }

        // Check if all nodes were processed (no cycles)
        if (result.items.len != n) {
            return error.CycleDetected;
        }

        return try result.toOwnedSlice(self.allocator);
    }
};

// Tests
test "topological sort - linear dependencies" {
    const allocator = std.testing.allocator;

    var executor = Executor.init(allocator, null, 1);

    // Create workflow: step1 -> step2 -> step3
    // Allocate empty depends_on array on heap for step1
    const step1_deps = try allocator.alloc([]const u8, 0);
    var step1 = plan.Step{
        .id = try allocator.dupe(u8, "step1"),
        .name = try allocator.dupe(u8, "Step 1"),
        .@"type" = .shell,
        .config = .{ .data = .null },
        .depends_on = step1_deps,
    };
    defer step1.deinit(allocator);

    // Allocate depends_on array on heap for step2
    const step2_deps = try allocator.alloc([]const u8, 1);
    step2_deps[0] = try allocator.dupe(u8, "step1");
    var step2 = plan.Step{
        .id = try allocator.dupe(u8, "step2"),
        .name = try allocator.dupe(u8, "Step 2"),
        .@"type" = .shell,
        .config = .{ .data = .null },
        .depends_on = step2_deps,
    };
    defer {
        step2.deinit(allocator);
    }

    // Allocate depends_on array on heap for step3
    const step3_deps = try allocator.alloc([]const u8, 1);
    step3_deps[0] = try allocator.dupe(u8, "step2");
    var step3 = plan.Step{
        .id = try allocator.dupe(u8, "step3"),
        .name = try allocator.dupe(u8, "Step 3"),
        .@"type" = .shell,
        .config = .{ .data = .null },
        .depends_on = step3_deps,
    };
    defer {
        step3.deinit(allocator);
    }

    var steps = [_]plan.Step{ step1, step2, step3 };
    const workflow = plan.WorkflowDefinition{
        .name = "test",
        .triggers = @constCast(&[_]plan.Trigger{}),
        .image = null,
        .dockerfile = null,
        .steps = &steps,
    };

    const order = try executor.topologicalSort(&workflow);
    defer allocator.free(order);

    try std.testing.expectEqual(@as(usize, 3), order.len);
    try std.testing.expectEqual(@as(usize, 0), order[0]); // step1
    try std.testing.expectEqual(@as(usize, 1), order[1]); // step2
    try std.testing.expectEqual(@as(usize, 2), order[2]); // step3
}

test "topological sort - parallel steps" {
    const allocator = std.testing.allocator;

    var executor = Executor.init(allocator, null, 1);

    // Create workflow: step1 -> (step2, step3) -> step4
    // Allocate empty depends_on array on heap for step1
    const step1_deps = try allocator.alloc([]const u8, 0);
    var step1 = plan.Step{
        .id = try allocator.dupe(u8, "step1"),
        .name = try allocator.dupe(u8, "Step 1"),
        .@"type" = .shell,
        .config = .{ .data = .null },
        .depends_on = step1_deps,
    };
    defer step1.deinit(allocator);

    // Allocate depends_on array on heap for step2
    const step2_deps = try allocator.alloc([]const u8, 1);
    step2_deps[0] = try allocator.dupe(u8, "step1");
    var step2 = plan.Step{
        .id = try allocator.dupe(u8, "step2"),
        .name = try allocator.dupe(u8, "Step 2"),
        .@"type" = .shell,
        .config = .{ .data = .null },
        .depends_on = step2_deps,
    };
    defer {
        step2.deinit(allocator);
    }

    // Allocate depends_on array on heap for step3
    const step3_deps = try allocator.alloc([]const u8, 1);
    step3_deps[0] = try allocator.dupe(u8, "step1");
    var step3 = plan.Step{
        .id = try allocator.dupe(u8, "step3"),
        .name = try allocator.dupe(u8, "Step 3"),
        .@"type" = .shell,
        .config = .{ .data = .null },
        .depends_on = step3_deps,
    };
    defer {
        step3.deinit(allocator);
    }

    // Allocate depends_on array on heap for step4
    const step4_deps = try allocator.alloc([]const u8, 2);
    step4_deps[0] = try allocator.dupe(u8, "step2");
    step4_deps[1] = try allocator.dupe(u8, "step3");
    var step4 = plan.Step{
        .id = try allocator.dupe(u8, "step4"),
        .name = try allocator.dupe(u8, "Step 4"),
        .@"type" = .shell,
        .config = .{ .data = .null },
        .depends_on = step4_deps,
    };
    defer step4.deinit(allocator);

    var steps = [_]plan.Step{ step1, step2, step3, step4 };
    const workflow = plan.WorkflowDefinition{
        .name = "test",
        .triggers = @constCast(&[_]plan.Trigger{}),
        .image = null,
        .dockerfile = null,
        .steps = &steps,
    };

    const order = try executor.topologicalSort(&workflow);
    defer allocator.free(order);

    try std.testing.expectEqual(@as(usize, 4), order.len);
    try std.testing.expectEqual(@as(usize, 0), order[0]); // step1 first
    // step2 and step3 can be in any order
    try std.testing.expectEqual(@as(usize, 3), order[3]); // step4 last
}

test "executor - simple shell step execution" {
    const allocator = std.testing.allocator;

    var executor = Executor.init(allocator, null, 1);

    // Create simple workflow with one shell step
    var config_obj = std.json.ObjectMap.init(allocator);
    // Allocate both key and value so they can be properly freed
    const key1 = try allocator.dupe(u8, "cmd");
    try config_obj.put(key1, .{ .string = try allocator.dupe(u8, "echo hello") });

    var step1 = plan.Step{
        .id = try allocator.dupe(u8, "step1"),
        .name = try allocator.dupe(u8, "Echo test"),
        .@"type" = .shell,
        .config = .{ .data = .{ .object = config_obj } },
        .depends_on = &[_][]const u8{},
    };
    defer step1.deinit(allocator);

    var steps = [_]plan.Step{step1};
    const workflow = plan.WorkflowDefinition{
        .name = "test",
        .triggers = @constCast(&[_]plan.Trigger{}),
        .image = null,
        .dockerfile = null,
        .steps = &steps,
    };

    const results = try executor.execute(&workflow, 1);
    defer {
        for (results) |*result| {
            result.deinit(allocator);
        }
        allocator.free(results);
    }

    try std.testing.expectEqual(@as(usize, 1), results.len);
    try std.testing.expectEqual(StepStatus.succeeded, results[0].status);
    try std.testing.expectEqual(@as(i32, 0), results[0].exit_code.?);
}

test "executor - shell step with actual output" {
    const allocator = std.testing.allocator;

    var executor = Executor.init(allocator, null, 1);

    // Create workflow that produces output
    var config_obj = std.json.ObjectMap.init(allocator);
    // Allocate both key and value so they can be properly freed
    const key1 = try allocator.dupe(u8, "cmd");
    try config_obj.put(key1, .{ .string = try allocator.dupe(u8, "echo 'test output'") });

    var step1 = plan.Step{
        .id = try allocator.dupe(u8, "step1"),
        .name = try allocator.dupe(u8, "Output test"),
        .@"type" = .shell,
        .config = .{ .data = .{ .object = config_obj } },
        .depends_on = &[_][]const u8{},
    };
    defer step1.deinit(allocator);

    var steps = [_]plan.Step{step1};
    const workflow = plan.WorkflowDefinition{
        .name = "test",
        .triggers = @constCast(&[_]plan.Trigger{}),
        .image = null,
        .dockerfile = null,
        .steps = &steps,
    };

    const results = try executor.execute(&workflow, 1);
    defer {
        for (results) |*result| {
            result.deinit(allocator);
        }
        allocator.free(results);
    }

    try std.testing.expectEqual(@as(usize, 1), results.len);
    try std.testing.expectEqual(StepStatus.succeeded, results[0].status);

    // Check output exists
    try std.testing.expect(results[0].output != null);
    if (results[0].output) |output| {
        try std.testing.expect(output == .object);
        const stdout = output.object.get("stdout");
        try std.testing.expect(stdout != null);
    }
}

test "executor - shell step failure" {
    const allocator = std.testing.allocator;

    var executor = Executor.init(allocator, null, 1);

    // Create workflow with failing command
    var config_obj = std.json.ObjectMap.init(allocator);
    // Allocate both key and value so they can be properly freed
    const key1 = try allocator.dupe(u8, "cmd");
    try config_obj.put(key1, .{ .string = try allocator.dupe(u8, "exit 1") });

    var step1 = plan.Step{
        .id = try allocator.dupe(u8, "step1"),
        .name = try allocator.dupe(u8, "Failing step"),
        .@"type" = .shell,
        .config = .{ .data = .{ .object = config_obj } },
        .depends_on = &[_][]const u8{},
    };
    defer step1.deinit(allocator);

    var steps = [_]plan.Step{step1};
    const workflow = plan.WorkflowDefinition{
        .name = "test",
        .triggers = @constCast(&[_]plan.Trigger{}),
        .image = null,
        .dockerfile = null,
        .steps = &steps,
    };

    const results = try executor.execute(&workflow, 1);
    defer {
        for (results) |*result| {
            result.deinit(allocator);
        }
        allocator.free(results);
    }

    try std.testing.expectEqual(@as(usize, 1), results.len);
    try std.testing.expectEqual(StepStatus.failed, results[0].status);
    try std.testing.expectEqual(@as(i32, 1), results[0].exit_code.?);
}

test "executor - dependency skipping" {
    const allocator = std.testing.allocator;

    var executor = Executor.init(allocator, null, 1);

    // Create workflow: step1 (fails) -> step2 (should be skipped)
    var config1_obj = std.json.ObjectMap.init(allocator);
    // Allocate both key and value so they can be properly freed by step.deinit()
    const key1 = try allocator.dupe(u8, "cmd");
    try config1_obj.put(key1, .{ .string = try allocator.dupe(u8, "exit 1") });

    const step1_deps = try allocator.alloc([]const u8, 0);
    var step1 = plan.Step{
        .id = try allocator.dupe(u8, "step1"),
        .name = try allocator.dupe(u8, "Failing step"),
        .@"type" = .shell,
        .config = .{ .data = .{ .object = config1_obj } },
        .depends_on = step1_deps,
    };
    defer step1.deinit(allocator);

    var config2_obj = std.json.ObjectMap.init(allocator);
    // Allocate both key and value so they can be properly freed by step.deinit()
    const key2 = try allocator.dupe(u8, "cmd");
    try config2_obj.put(key2, .{ .string = try allocator.dupe(u8, "echo 'should not run'") });

    const step2_deps = try allocator.alloc([]const u8, 1);
    step2_deps[0] = try allocator.dupe(u8, "step1");
    var step2 = plan.Step{
        .id = try allocator.dupe(u8, "step2"),
        .name = try allocator.dupe(u8, "Dependent step"),
        .@"type" = .shell,
        .config = .{ .data = .{ .object = config2_obj } },
        .depends_on = step2_deps,
    };
    defer {
        step2.deinit(allocator);
    }

    var steps = [_]plan.Step{ step1, step2 };
    const workflow = plan.WorkflowDefinition{
        .name = "test",
        .triggers = @constCast(&[_]plan.Trigger{}),
        .image = null,
        .dockerfile = null,
        .steps = &steps,
    };

    const results = try executor.execute(&workflow, 1);
    defer {
        for (results) |*result| {
            result.deinit(allocator);
        }
        allocator.free(results);
    }

    try std.testing.expectEqual(@as(usize, 2), results.len);
    try std.testing.expectEqual(StepStatus.failed, results[0].status);
    try std.testing.expectEqual(StepStatus.skipped, results[1].status);
}

test "executor - environment variables" {
    const allocator = std.testing.allocator;

    var executor = Executor.init(allocator, null, 1);

    // Create workflow with environment variables
    var config_obj = std.json.ObjectMap.init(allocator);
    // Allocate both keys and values so they can be properly freed by step.deinit()
    const key_cmd = try allocator.dupe(u8, "cmd");
    try config_obj.put(key_cmd, .{ .string = try allocator.dupe(u8, "echo $TEST_VAR") });

    var env_obj = std.json.ObjectMap.init(allocator);
    const key_test_var = try allocator.dupe(u8, "TEST_VAR");
    try env_obj.put(key_test_var, .{ .string = try allocator.dupe(u8, "test_value") });
    const key_env = try allocator.dupe(u8, "env");
    try config_obj.put(key_env, .{ .object = env_obj });

    const step1_deps = try allocator.alloc([]const u8, 0);
    var step1 = plan.Step{
        .id = try allocator.dupe(u8, "step1"),
        .name = try allocator.dupe(u8, "Env test"),
        .@"type" = .shell,
        .config = .{ .data = .{ .object = config_obj } },
        .depends_on = step1_deps,
    };
    defer step1.deinit(allocator);

    var steps = [_]plan.Step{step1};
    const workflow = plan.WorkflowDefinition{
        .name = "test",
        .triggers = @constCast(&[_]plan.Trigger{}),
        .image = null,
        .dockerfile = null,
        .steps = &steps,
    };

    const results = try executor.execute(&workflow, 1);
    defer {
        for (results) |*result| {
            result.deinit(allocator);
        }
        allocator.free(results);
    }

    try std.testing.expectEqual(@as(usize, 1), results.len);
    try std.testing.expectEqual(StepStatus.succeeded, results[0].status);

    // Check that environment variable was used
    if (results[0].output) |output| {
        if (output == .object) {
            if (output.object.get("stdout")) |stdout_value| {
                if (stdout_value == .string) {
                    try std.testing.expect(std.mem.indexOf(u8, stdout_value.string, "test_value") != null);
                }
            }
        }
    }
}
