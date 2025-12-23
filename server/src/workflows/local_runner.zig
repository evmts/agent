//! Local Runner - In-Process Execution for Development
//!
//! Provides fast in-process workflow execution for local development,
//! bypassing Kubernetes runner pods. Executes shell and LLM steps directly
//! within the Zig server process.
//!
//! Architecture:
//! - Shell steps: Direct subprocess execution via std.ChildProcess
//! - LLM steps: Call llm_executor.zig directly
//! - Agent steps: Spawn Python runner subprocess for Claude Code SDK
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
        step: *const plan.WorkflowStep,
        event_callback: *const fn (event: executor.ExecutionEvent) void,
    ) !executor.StepResult {
        const start_time = std.time.timestamp();

        log.info("Executing step: {s} (type: {s})", .{ step.id, @tagName(step.step_type) });

        // Send step_started event
        event_callback(executor.ExecutionEvent{
            .step_started = .{
                .step_id = step.id,
                .name = step.name,
                .step_type = step.step_type,
            },
        });

        const result = switch (step.step_type) {
            .shell => try self.executeShellStep(step, event_callback),
            .llm => try self.executeLlmStep(step, event_callback),
            .agent => try self.executeAgentStep(step, event_callback),
            .parallel => error.ParallelNotSupported, // Handled by executor
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
            .started_at = start_time,
            .completed_at = end_time,
        };
    }

    /// Execute a shell step using std.ChildProcess
    fn executeShellStep(
        self: *LocalRunner,
        step: *const plan.WorkflowStep,
        event_callback: *const fn (event: executor.ExecutionEvent) void,
    ) !StepExecutionResult {
        const cmd = step.config.get("cmd") orelse return error.MissingCommand;
        const env_map = step.config.get("env");

        log.debug("Executing shell command: {s}", .{cmd});

        // Build command array (split on spaces - simple approach for now)
        var cmd_iter = std.mem.tokenizeScalar(u8, cmd, ' ');
        var cmd_args = std.ArrayList([]const u8).init(self.allocator);
        defer cmd_args.deinit();

        while (cmd_iter.next()) |arg| {
            try cmd_args.append(arg);
        }

        if (cmd_args.items.len == 0) {
            return StepExecutionResult{
                .status = .failed,
                .exit_code = 1,
                .output = null,
                .error_message = "Empty command",
            };
        }

        // Execute command
        var child = std.ChildProcess.init(cmd_args.items, self.allocator);
        child.cwd = self.workspace_dir;
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;

        // Set environment variables if provided
        if (env_map) |env| {
            // TODO: Parse JSON env map and set child.env_map
            _ = env;
        }

        try child.spawn();

        // Stream stdout
        if (child.stdout) |stdout_pipe| {
            var buf: [4096]u8 = undefined;
            while (true) {
                const bytes_read = try stdout_pipe.read(&buf);
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
        const term = try child.wait();
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
        };
    }

    /// Execute an LLM step using llm_executor
    fn executeLlmStep(
        self: *LocalRunner,
        step: *const plan.WorkflowStep,
        event_callback: *const fn (event: executor.ExecutionEvent) void,
    ) !StepExecutionResult {
        _ = step;
        _ = event_callback;
        _ = self;

        // TODO: Phase 10 - Implement LLM step execution
        // Call llm_executor.zig with prompt and stream tokens back
        log.warn("LLM steps not yet implemented in local runner", .{});

        return StepExecutionResult{
            .status = .failed,
            .exit_code = 1,
            .output = null,
            .error_message = "LLM steps not yet implemented",
        };
    }

    /// Execute an agent step by spawning Python runner subprocess
    fn executeAgentStep(
        self: *LocalRunner,
        step: *const plan.WorkflowStep,
        event_callback: *const fn (event: executor.ExecutionEvent) void,
    ) !StepExecutionResult {
        _ = step;
        _ = event_callback;
        _ = self;

        // TODO: Phase 10 - Implement agent step execution
        // Spawn runner/src/main.py with task config
        log.warn("Agent steps not yet implemented in local runner", .{});

        return StepExecutionResult{
            .status = .failed,
            .exit_code = 1,
            .output = null,
            .error_message = "Agent steps not yet implemented",
        };
    }
};

/// Temporary result type for step execution
const StepExecutionResult = struct {
    status: executor.StepStatus,
    exit_code: ?i32,
    output: ?std.json.Value,
    error_message: ?[]const u8,
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
}
