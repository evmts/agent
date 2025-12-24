//! Local Runner - In-Process Execution for Development
//!
//! Provides fast in-process workflow execution for local development,
//! bypassing Kubernetes runner pods. Executes shell and LLM steps directly
//! within the Zig server process.
//!
//! Architecture:
//! - Shell steps: Direct subprocess execution via std.ChildProcess
//! - LLM steps: Call llm_executor.zig directly
//! - Agent steps: Call llm_executor.zig with agent mode
//! - Streaming: Events sent directly to executor via callback
//!
//! Environment:
//! - No gVisor sandbox (use for dev only!)
//! - No network isolation
//! - Direct filesystem access

const std = @import("std");
const plan = @import("plan.zig");
const executor = @import("executor.zig");
const llm_executor = @import("llm_executor.zig");

const log = std.log.scoped(.local_runner);

/// Local runner for in-process execution
pub const LocalRunner = struct {
    allocator: std.mem.Allocator,
    workspace_dir: []const u8,
    anthropic_api_key: ?[]const u8,

    pub fn init(
        allocator: std.mem.Allocator,
        workspace_dir: []const u8,
        anthropic_api_key: ?[]const u8,
    ) LocalRunner {
        return .{
            .allocator = allocator,
            .workspace_dir = workspace_dir,
            .anthropic_api_key = anthropic_api_key,
        };
    }

    /// Execute a single workflow step
    pub fn executeStep(
        self: *LocalRunner,
        step: *const plan.Step,
        event_callback: *const fn (event: executor.ExecutionEvent) void,
    ) !executor.StepResult {
        const start_time = std.time.timestamp();

        log.info("Executing step: {s} (type: {s})", .{ step.id, @tagName(step.@"type") });

        // Send step_started event
        event_callback(executor.ExecutionEvent{
            .step_started = .{
                .step_id = step.id,
                .name = step.name,
                .@"type" = step.@"type",
            },
        });

        const result = switch (step.@"type") {
            .shell => try self.executeShellStep(step, event_callback),
            .llm => try self.executeLlmStep(step, event_callback),
            .agent => try self.executeAgentStep(step, event_callback),
            .parallel => return error.ParallelNotSupported, // Handled by executor
        };

        const end_time = std.time.timestamp();

        log.info("Step {s} completed with status: {s}", .{ step.id, @tagName(result.status) });

        return executor.StepResult{
            .step_id = try self.allocator.dupe(u8, step.id),
            .status = result.status,
            .exit_code = result.exit_code,
            .output = result.output,
            .error_message = if (result.error_message) |msg|
                try self.allocator.dupe(u8, msg)
            else
                null,
            .turns_used = result.turns_used,
            .tokens_in = result.tokens_in,
            .tokens_out = result.tokens_out,
            .started_at = start_time,
            .completed_at = end_time,
        };
    }

    /// Execute a shell step using std.ChildProcess
    fn executeShellStep(
        self: *LocalRunner,
        step: *const plan.Step,
        event_callback: *const fn (event: executor.ExecutionEvent) void,
    ) !StepExecutionResult {
        // Extract command from config JSON
        const config = step.config.data;
        const cmd = switch (config) {
            .object => |obj| blk: {
                const cmd_value = obj.get("cmd") orelse return error.MissingCommand;
                break :blk switch (cmd_value) {
                    .string => |s| s,
                    else => return error.InvalidCommand,
                };
            },
            else => return error.InvalidConfig,
        };

        log.debug("Executing shell command: {s}", .{cmd});

        // Build environment with step-specific env vars
        var env_map = std.process.EnvMap.init(self.allocator);
        defer env_map.deinit();

        // Copy current environment
        var current_env = try std.process.getEnvMap(self.allocator);
        defer current_env.deinit();
        var env_it = current_env.iterator();
        while (env_it.next()) |entry| {
            try env_map.put(entry.key_ptr.*, entry.value_ptr.*);
        }

        // Add step-specific env vars from config
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

        // Execute command using sh -c to handle complex commands
        const argv = [_][]const u8{ "sh", "-c", cmd };

        var child = std.process.Child.init(&argv, self.allocator);
        child.cwd = self.workspace_dir;
        child.env_map = &env_map;
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;

        child.spawn() catch |err| {
            return StepExecutionResult{
                .status = .failed,
                .exit_code = null,
                .output = null,
                .error_message = @errorName(err),
                .turns_used = null,
                .tokens_in = null,
                .tokens_out = null,
            };
        };

        // Stream stdout
        if (child.stdout) |stdout_pipe| {
            var buf: [4096]u8 = undefined;
            while (true) {
                const bytes_read = stdout_pipe.read(&buf) catch break;
                if (bytes_read == 0) break;

                const line = buf[0..bytes_read];
                event_callback(executor.ExecutionEvent{
                    .step_output = .{
                        .step_id = step.id,
                        .line = line,
                    },
                });
            }
        }

        // Wait for completion
        const term = child.wait() catch |err| {
            return StepExecutionResult{
                .status = .failed,
                .exit_code = null,
                .output = null,
                .error_message = @errorName(err),
                .turns_used = null,
                .tokens_in = null,
                .tokens_out = null,
            };
        };

        const exit_code: i32 = switch (term) {
            .Exited => |code| @intCast(code),
            .Signal => -1,
            .Stopped => -1,
            .Unknown => -1,
        };

        const success = exit_code == 0;

        return StepExecutionResult{
            .status = if (success) .succeeded else .failed,
            .exit_code = exit_code,
            .output = null,
            .error_message = if (!success) "Command failed" else null,
            .turns_used = null,
            .tokens_in = null,
            .tokens_out = null,
        };
    }

    /// Execute an LLM step using llm_executor
    fn executeLlmStep(
        self: *LocalRunner,
        step: *const plan.Step,
        event_callback: *const fn (event: executor.ExecutionEvent) void,
    ) !StepExecutionResult {
        // Create LLM executor with workspace
        var llm_exec = llm_executor.LlmExecutor.initWithWorkspace(
            self.allocator,
            null, // No DB pool for local runner
            self.workspace_dir,
        );

        // Set up event forwarding callback
        const CallbackCtx = struct {
            event_callback: *const fn (event: executor.ExecutionEvent) void,

            fn handleEvent(event: llm_executor.LlmExecutionEvent, ctx: ?*anyopaque) void {
                const self_ctx: *@This() = @alignCast(@ptrCast(ctx.?));

                // Convert LlmExecutionEvent to ExecutionEvent
                const exec_event: executor.ExecutionEvent = switch (event) {
                    .token => |t| .{ .llm_token = .{ .step_id = t.step_id, .text = t.text } },
                    .tool_start => |t| .{ .tool_call_start = .{ .step_id = t.step_id, .tool_name = t.tool_name, .tool_input = t.tool_input } },
                    .tool_end => |t| .{ .tool_call_end = .{ .step_id = t.step_id, .tool_name = t.tool_name, .tool_output = t.tool_output, .success = t.success } },
                    .turn_complete => |t| .{ .agent_turn_complete = .{ .step_id = t.step_id, .turn_number = t.turn_number } },
                };

                self_ctx.event_callback(exec_event);
            }
        };

        var callback_ctx = CallbackCtx{ .event_callback = event_callback };
        llm_exec.setEventCallback(CallbackCtx.handleEvent, &callback_ctx);

        // Execute LLM step
        const result = llm_exec.executeLlmStep(step.id, &step.config) catch |err| {
            return StepExecutionResult{
                .status = .failed,
                .exit_code = null,
                .output = null,
                .error_message = @errorName(err),
                .turns_used = null,
                .tokens_in = null,
                .tokens_out = null,
            };
        };

        const status: executor.StepStatus = if (result.error_message != null) .failed else .succeeded;

        return StepExecutionResult{
            .status = status,
            .exit_code = null,
            .output = result.output,
            .error_message = result.error_message,
            .turns_used = @as(i32, @intCast(result.turns_used)),
            .tokens_in = @as(i32, @intCast(result.tokens_in)),
            .tokens_out = @as(i32, @intCast(result.tokens_out)),
        };
    }

    /// Execute an agent step using llm_executor
    fn executeAgentStep(
        self: *LocalRunner,
        step: *const plan.Step,
        event_callback: *const fn (event: executor.ExecutionEvent) void,
    ) !StepExecutionResult {
        // Create LLM executor with workspace
        var llm_exec = llm_executor.LlmExecutor.initWithWorkspace(
            self.allocator,
            null, // No DB pool for local runner
            self.workspace_dir,
        );

        // Set up event forwarding callback
        const CallbackCtx = struct {
            event_callback: *const fn (event: executor.ExecutionEvent) void,

            fn handleEvent(event: llm_executor.LlmExecutionEvent, ctx: ?*anyopaque) void {
                const self_ctx: *@This() = @alignCast(@ptrCast(ctx.?));

                // Convert LlmExecutionEvent to ExecutionEvent
                const exec_event: executor.ExecutionEvent = switch (event) {
                    .token => |t| .{ .llm_token = .{ .step_id = t.step_id, .text = t.text } },
                    .tool_start => |t| .{ .tool_call_start = .{ .step_id = t.step_id, .tool_name = t.tool_name, .tool_input = t.tool_input } },
                    .tool_end => |t| .{ .tool_call_end = .{ .step_id = t.step_id, .tool_name = t.tool_name, .tool_output = t.tool_output, .success = t.success } },
                    .turn_complete => |t| .{ .agent_turn_complete = .{ .step_id = t.step_id, .turn_number = t.turn_number } },
                };

                self_ctx.event_callback(exec_event);
            }
        };

        var callback_ctx = CallbackCtx{ .event_callback = event_callback };
        llm_exec.setEventCallback(CallbackCtx.handleEvent, &callback_ctx);

        // Execute agent step
        const result = llm_exec.executeAgentStep(step.id, &step.config) catch |err| {
            return StepExecutionResult{
                .status = .failed,
                .exit_code = null,
                .output = null,
                .error_message = @errorName(err),
                .turns_used = null,
                .tokens_in = null,
                .tokens_out = null,
            };
        };

        const status: executor.StepStatus = if (result.error_message != null) .failed else .succeeded;

        return StepExecutionResult{
            .status = status,
            .exit_code = null,
            .output = result.output,
            .error_message = result.error_message,
            .turns_used = @as(i32, @intCast(result.turns_used)),
            .tokens_in = @as(i32, @intCast(result.tokens_in)),
            .tokens_out = @as(i32, @intCast(result.tokens_out)),
        };
    }
};

/// Internal result type for step execution
const StepExecutionResult = struct {
    status: executor.StepStatus,
    exit_code: ?i32,
    output: ?std.json.Value,
    error_message: ?[]const u8,
    turns_used: ?i32,
    tokens_in: ?i32,
    tokens_out: ?i32,
};

// ============================================================================
// Tests
// ============================================================================

test "LocalRunner: basic init" {
    const allocator = std.testing.allocator;

    const runner = LocalRunner.init(
        allocator,
        "/tmp",
        null,
    );

    try std.testing.expect(runner.workspace_dir.len > 0);
    try std.testing.expectEqualStrings("/tmp", runner.workspace_dir);
}

test "LocalRunner: init with api key" {
    const allocator = std.testing.allocator;

    const runner = LocalRunner.init(
        allocator,
        "/workspace",
        "test-api-key",
    );

    try std.testing.expectEqualStrings("/workspace", runner.workspace_dir);
    try std.testing.expect(runner.anthropic_api_key != null);
    try std.testing.expectEqualStrings("test-api-key", runner.anthropic_api_key.?);
}
