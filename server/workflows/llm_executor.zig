//! LLM and Agent Step Execution
//!
//! Integrates the workflow executor with the existing AI system (/server/src/ai/)
//! to execute LLM and agent steps with streaming output.

const std = @import("std");
const plan = @import("plan.zig");
const prompt_mod = @import("prompt.zig");
const validation = @import("validation.zig");
const ai = @import("../ai/agent.zig");
const client = @import("../ai/client.zig");
const types = @import("../ai/types.zig");
const db = @import("db");
const json = @import("../lib/json.zig");

/// Callback for LLM execution events
pub const LlmEventCallback = *const fn (event: LlmExecutionEvent, ctx: ?*anyopaque) void;

/// Events emitted during LLM/agent execution
pub const LlmExecutionEvent = union(enum) {
    /// Token received from LLM
    token: struct {
        step_id: []const u8,
        text: []const u8,
    },
    /// Tool call started
    tool_start: struct {
        step_id: []const u8,
        tool_name: []const u8,
        tool_input: []const u8,
    },
    /// Tool call completed
    tool_end: struct {
        step_id: []const u8,
        tool_name: []const u8,
        tool_output: []const u8,
        success: bool,
    },
    /// Agent turn completed
    turn_complete: struct {
        step_id: []const u8,
        turn_number: u32,
    },
};

/// Result of LLM/agent execution
pub const LlmExecutionResult = struct {
    output: std.json.Value,
    turns_used: u32,
    tokens_in: u32,
    tokens_out: u32,
    error_message: ?[]const u8,

    pub fn deinit(self: *LlmExecutionResult, allocator: std.mem.Allocator) void {
        if (self.error_message) |msg| {
            allocator.free(msg);
        }
        freeJsonValue(allocator, &self.output);
    }
};

/// Recursively free a JSON value and all its nested allocations
fn freeJsonValue(allocator: std.mem.Allocator, value: *std.json.Value) void {
    switch (value.*) {
        .string => |s| {
            allocator.free(s);
        },
        .array => |*arr| {
            for (arr.items) |*item| {
                freeJsonValue(allocator, item);
            }
            arr.deinit(allocator);
        },
        .object => |*obj| {
            var it = obj.iterator();
            while (it.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                freeJsonValue(allocator, entry.value_ptr);
            }
            obj.deinit(allocator);
        },
        else => {}, // null, bool, integer, float don't need freeing
    }
}

/// LLM step executor
pub const LlmExecutor = struct {
    allocator: std.mem.Allocator,
    event_callback: ?LlmEventCallback,
    event_ctx: ?*anyopaque,
    db_pool: ?*db.Pool,
    workspace_dir: []const u8,

    pub fn init(allocator: std.mem.Allocator, db_pool: ?*db.Pool) LlmExecutor {
        return initWithWorkspace(allocator, db_pool, "/tmp/workflow-workspace");
    }

    pub fn initWithWorkspace(allocator: std.mem.Allocator, db_pool: ?*db.Pool, workspace_dir: []const u8) LlmExecutor {
        return .{
            .allocator = allocator,
            .event_callback = null,
            .event_ctx = null,
            .db_pool = db_pool,
            .workspace_dir = workspace_dir,
        };
    }

    pub fn setEventCallback(self: *LlmExecutor, callback: LlmEventCallback, ctx: ?*anyopaque) void {
        self.event_callback = callback;
        self.event_ctx = ctx;
    }

    /// Execute an LLM step (single-shot, no tools)
    pub fn executeLlmStep(
        self: *LlmExecutor,
        step_id: []const u8,
        step_config: *const plan.StepConfig,
    ) !LlmExecutionResult {
        // 1. Get prompt definition path from config
        const prompt_path = step_config.data.object.get("prompt_path") orelse return error.MissingPromptPath;
        const prompt_path_str = prompt_path.string;

        // 2. Parse prompt definition
        var prompt_def = try prompt_mod.parsePromptFile(self.allocator, prompt_path_str);
        defer prompt_def.deinit();

        // 3. Get inputs from config
        const inputs = step_config.data.object.get("inputs") orelse return error.MissingInputs;

        // 4. Validate inputs against prompt schema
        var input_validation = try prompt_mod.validateJson(
            self.allocator,
            prompt_def.inputs_schema,
            inputs,
        );
        defer input_validation.deinit();

        if (!input_validation.valid) {
            _ = if (input_validation.errors.len > 0)
                input_validation.errors[0]
            else
                "Input validation failed";
            return error.InvalidInputs;
        }

        // 5. Convert inputs to JSON string for template rendering
        const inputs_str = try json.valueToString(self.allocator, inputs);
        defer self.allocator.free(inputs_str);

        // 6. Render prompt template with inputs
        const rendered_prompt = try prompt_mod.renderTemplate(
            self.allocator,
            prompt_def.body_template,
            inputs_str,
        );
        defer self.allocator.free(rendered_prompt);

        // 6. Get API key
        const api_key = try std.process.getEnvVarOwned(self.allocator, "ANTHROPIC_API_KEY");
        defer self.allocator.free(api_key);

        // 7. Create message
        const message = client.Message{
            .role = .user,
            .content = .{ .text = rendered_prompt },
        };

        // 8. Get model from config or use default
        const model_id = if (step_config.data.object.get("client")) |c|
            c.string
        else
            "claude-sonnet-4-20250514";

        // 9. Call Claude API (non-streaming for now)
        const anthropic = client.AnthropicClient.init(self.allocator, api_key);

        const response = anthropic.sendMessages(
            model_id,
            &[_]client.Message{message},
            null, // no system prompt for LLM steps
            null, // no tools for pure LLM steps
            1.0, // temperature
            4096, // max_tokens
        ) catch |err| {
            const err_msg = try std.fmt.allocPrint(
                self.allocator,
                "LLM API error: {s}",
                .{@errorName(err)},
            );
            return LlmExecutionResult{
                .output = .null,
                .turns_used = 1,
                .tokens_in = 0,
                .tokens_out = 0,
                .error_message = err_msg,
            };
        };

        // Extract text content from response
        var output_text: []const u8 = "";
        const tokens_in: u32 = @intCast(response.usage.input_tokens);
        const tokens_out: u32 = @intCast(response.usage.output_tokens);

        for (response.content) |content_block| {
            switch (content_block) {
                .text => |text| {
                    output_text = text;
                    // Emit token event for the complete response
                    if (self.event_callback) |cb| {
                        cb(.{
                            .token = .{
                                .step_id = step_id,
                                .text = output_text,
                            },
                        }, self.event_ctx);
                    }
                    break;
                },
                .tool_use => {},
            }
        }

        // 11. Parse output against expected schema
        const parsed_output = std.json.parseFromSlice(
            std.json.Value,
            self.allocator,
            output_text,
            .{},
        ) catch {
            // If output is not valid JSON, wrap it as text
            const wrapped = try std.fmt.allocPrint(
                self.allocator,
                "{{\"text\": \"{s}\"}}",
                .{output_text},
            );
            defer self.allocator.free(wrapped);

            const parsed = try std.json.parseFromSlice(
                std.json.Value,
                self.allocator,
                wrapped,
                .{},
            );
            // Extract token usage from API response
            return LlmExecutionResult{
                .output = parsed.value,
                .turns_used = 1,
                .tokens_in = tokens_in,
                .tokens_out = tokens_out,
                .error_message = null,
            };
        };

        // 12. Validate output against expected schema
        var output_validation = try prompt_mod.validateJson(
            self.allocator,
            prompt_def.output_schema,
            parsed_output.value,
        );
        defer output_validation.deinit();

        if (!output_validation.valid) {
            const err_msg = if (output_validation.errors.len > 0)
                try self.allocator.dupe(u8, output_validation.errors[0])
            else
                try self.allocator.dupe(u8, "Output validation failed");

            return LlmExecutionResult{
                .output = parsed_output.value,
                .turns_used = 1,
                .tokens_in = 0,
                .tokens_out = 0,
                .error_message = err_msg,
            };
        }

        return LlmExecutionResult{
            .output = parsed_output.value,
            .turns_used = 1,
            .tokens_in = tokens_in,
            .tokens_out = tokens_out,
            .error_message = null,
        };
    }

    /// Execute an agent step (multi-turn with tools)
    pub fn executeAgentStep(
        self: *LlmExecutor,
        step_id: []const u8,
        step_config: *const plan.StepConfig,
    ) !LlmExecutionResult {
        // 1. Get prompt definition path from config
        const prompt_path = step_config.data.object.get("prompt_path") orelse return error.MissingPromptPath;
        const prompt_path_str = prompt_path.string;

        // 2. Parse prompt definition
        var prompt_def = try prompt_mod.parsePromptFile(self.allocator, prompt_path_str);
        defer prompt_def.deinit();

        // 3. Get inputs from config
        const inputs = step_config.data.object.get("inputs") orelse return error.MissingInputs;

        // 4. Validate inputs against prompt schema
        var input_validation = try prompt_mod.validateJson(
            self.allocator,
            prompt_def.inputs_schema,
            inputs,
        );
        defer input_validation.deinit();

        if (!input_validation.valid) {
            return error.InvalidInputs;
        }

        // 5. Convert inputs to JSON string for template rendering
        const inputs_str = try json.valueToString(self.allocator, inputs);
        defer self.allocator.free(inputs_str);

        // 6. Render prompt template with inputs
        const rendered_prompt = try prompt_mod.renderTemplate(
            self.allocator,
            prompt_def.body_template,
            inputs_str,
        );
        defer self.allocator.free(rendered_prompt);

        // 6. Create initial message
        const message = client.Message{
            .role = .user,
            .content = .{ .text = rendered_prompt },
        };

        // 7. Get model from config or use default
        const model_id = if (step_config.data.object.get("client")) |c|
            c.string
        else
            "claude-sonnet-4-20250514";

        // 8. Get max_turns from config or prompt definition (currently unused in agent options)
        _ = blk: {
            if (step_config.data.object.get("max_turns")) |mt| {
                break :blk @as(u32, @intCast(mt.integer));
            } else {
                break :blk prompt_def.max_turns;
            }
        };

        // 9. Set up agent options
        const agent_options = types.AgentOptions{
            .agent_name = "workflow-agent",
            .model_id = model_id,
            .working_dir = self.workspace_dir,
        };

        // 10. Set up tool context (empty for now, will be enhanced with tool scoping)
        const tool_ctx = types.ToolContext{
            .allocator = self.allocator,
            .working_dir = self.workspace_dir,
            .file_tracker = null,
            .session_id = null,
        };

        // 11. Set up callback context to collect results
        const CallbackContext = struct {
            allocator: std.mem.Allocator,
            step_id: []const u8,
            executor: *LlmExecutor,
            turns: u32 = 0,
            tokens_in: u32 = 0,
            tokens_out: u32 = 0,
            final_text: ?[]const u8 = null,
            error_message: ?[]const u8 = null,

            fn handleEvent(event: types.StreamEvent, ctx: ?*anyopaque) void {
                const self_ctx: *@This() = @ptrCast(@alignCast(ctx.?));

                switch (event) {
                    .text => |text_event| {
                        if (text_event.data) |data| {
                            // Store final text (will be overwritten with latest text)
                            self_ctx.final_text = data;

                            // Emit token event if executor has callback
                            if (self_ctx.executor.event_callback) |cb| {
                                cb(.{
                                    .token = .{
                                        .step_id = self_ctx.step_id,
                                        .text = data,
                                    },
                                }, self_ctx.executor.event_ctx);
                            }
                        }
                    },
                    .tool_call => |tool_call_event| {
                        if (self_ctx.executor.event_callback) |cb| {
                            cb(.{
                                .tool_start = .{
                                    .step_id = self_ctx.step_id,
                                    .tool_name = tool_call_event.tool_name orelse "unknown",
                                    .tool_input = tool_call_event.args orelse "{}",
                                },
                            }, self_ctx.executor.event_ctx);
                        }
                    },
                    .tool_result => |tool_result_event| {
                        self_ctx.turns += 1;

                        if (self_ctx.executor.event_callback) |cb| {
                            cb(.{
                                .tool_end = .{
                                    .step_id = self_ctx.step_id,
                                    .tool_name = "unknown", // tool_result doesn't include name
                                    .tool_output = tool_result_event.tool_output orelse "",
                                    .success = true, // Assume success if we got output
                                },
                            }, self_ctx.executor.event_ctx);

                            cb(.{
                                .turn_complete = .{
                                    .step_id = self_ctx.step_id,
                                    .turn_number = self_ctx.turns,
                                },
                            }, self_ctx.executor.event_ctx);
                        }
                    },
                    .error_event => |error_event| {
                        if (error_event.message) |msg| {
                            // Try to allocate and store error message
                            self_ctx.error_message = self_ctx.allocator.dupe(u8, msg) catch null;
                        }
                    },
                    .done => {
                        // Agent completed successfully
                    },
                }
            }
        };

        var callback_ctx = CallbackContext{
            .allocator = self.allocator,
            .step_id = step_id,
            .executor = self,
        };

        const callbacks = types.StreamCallbacks{
            .on_event = CallbackContext.handleEvent,
            .context = &callback_ctx,
        };

        // 12. Run agent with streaming
        const usage = ai.streamAgent(
            self.allocator,
            &[_]client.Message{message},
            agent_options,
            tool_ctx,
            callbacks,
        ) catch |err| {
            const err_msg = try std.fmt.allocPrint(
                self.allocator,
                "Agent execution failed: {s}",
                .{@errorName(err)},
            );
            return LlmExecutionResult{
                .output = .null,
                .turns_used = callback_ctx.turns,
                .tokens_in = 0,
                .tokens_out = 0,
                .error_message = err_msg,
            };
        };
        callback_ctx.tokens_in = usage.tokens_in;
        callback_ctx.tokens_out = usage.tokens_out;

        // 13. Parse final output if we have text
        if (callback_ctx.final_text) |text| {
            const parsed_output = std.json.parseFromSlice(
                std.json.Value,
                self.allocator,
                text,
                .{},
            ) catch {
                // If output is not valid JSON, wrap it as text
                const wrapped = try std.fmt.allocPrint(
                    self.allocator,
                    "{{\"text\": \"{s}\"}}",
                    .{text},
                );
                defer self.allocator.free(wrapped);

                const parsed = try std.json.parseFromSlice(
                    std.json.Value,
                    self.allocator,
                    wrapped,
                    .{},
                );
                return LlmExecutionResult{
                    .output = parsed.value,
                    .turns_used = callback_ctx.turns,
                    .tokens_in = callback_ctx.tokens_in,
                    .tokens_out = callback_ctx.tokens_out,
                    .error_message = callback_ctx.error_message,
                };
            };

            // Validate output against expected schema
            var output_validation = try prompt_mod.validateJson(
                self.allocator,
                prompt_def.output_schema,
                parsed_output.value,
            );
            defer output_validation.deinit();

            if (!output_validation.valid) {
                const err_msg = if (output_validation.errors.len > 0)
                    try self.allocator.dupe(u8, output_validation.errors[0])
                else
                    try self.allocator.dupe(u8, "Output validation failed");

                return LlmExecutionResult{
                    .output = parsed_output.value,
                    .turns_used = callback_ctx.turns,
                    .tokens_in = callback_ctx.tokens_in,
                    .tokens_out = callback_ctx.tokens_out,
                    .error_message = err_msg,
                };
            }

            return LlmExecutionResult{
                .output = parsed_output.value,
                .turns_used = callback_ctx.turns,
                .tokens_in = callback_ctx.tokens_in,
                .tokens_out = callback_ctx.tokens_out,
                .error_message = callback_ctx.error_message,
            };
        }

        // No output received
        return LlmExecutionResult{
            .output = .null,
            .turns_used = callback_ctx.turns,
            .tokens_in = callback_ctx.tokens_in,
            .tokens_out = callback_ctx.tokens_out,
            .error_message = callback_ctx.error_message,
        };
    }
};

// Tests
test "llm_executor - basic initialization" {
    const allocator = std.testing.allocator;
    const executor = LlmExecutor.init(allocator, null);
    _ = executor;
}

test "llm_executor - set event callback" {
    const allocator = std.testing.allocator;
    var executor = LlmExecutor.init(allocator, null);

    const TestCtx = struct {
        called: bool = false,
    };

    var ctx = TestCtx{};

    const callback = struct {
        fn cb(event: LlmExecutionEvent, context: ?*anyopaque) void {
            _ = event;
            const test_ctx: *TestCtx = @ptrCast(@alignCast(context.?));
            test_ctx.called = true;
        }
    }.cb;

    executor.setEventCallback(callback, &ctx);

    try std.testing.expect(executor.event_callback != null);
}

test "llm_executor - agent step callback structure" {
    // This test verifies the agent callback structure compiles correctly
    // Actual execution would require ANTHROPIC_API_KEY and real API calls
    const allocator = std.testing.allocator;

    const EventCollector = struct {
        allocator: std.mem.Allocator,
        tokens: std.ArrayList([]const u8),
        tool_calls: std.ArrayList([]const u8),
        turns: u32 = 0,

        fn init(alloc: std.mem.Allocator) @This() {
            return .{
                .allocator = alloc,
                .tokens = std.ArrayList([]const u8){},
                .tool_calls = std.ArrayList([]const u8){},
            };
        }

        fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
            self.tokens.deinit(alloc);
            self.tool_calls.deinit(alloc);
        }

        fn handleEvent(event: LlmExecutionEvent, ctx: ?*anyopaque) void {
            const collector: *@This() = @ptrCast(@alignCast(ctx.?));

            switch (event) {
                .token => |token_event| {
                    collector.tokens.append(collector.allocator, token_event.text) catch {};
                },
                .tool_start => |tool_start| {
                    collector.tool_calls.append(collector.allocator, tool_start.tool_name) catch {};
                },
                .tool_end => {},
                .turn_complete => |turn| {
                    collector.turns = turn.turn_number;
                },
            }
        }
    };

    var collector = EventCollector.init(allocator);
    defer collector.deinit(allocator);

    var executor = LlmExecutor.init(allocator, null);
    executor.setEventCallback(EventCollector.handleEvent, &collector);

    // Verify callback is set
    try std.testing.expect(executor.event_callback != null);

    // Simulate events (verifies type signatures are correct)
    if (executor.event_callback) |cb| {
        cb(.{ .token = .{ .step_id = "test", .text = "hello" } }, executor.event_ctx);
        cb(.{ .tool_start = .{ .step_id = "test", .tool_name = "read_file", .tool_input = "{}" } }, executor.event_ctx);
        cb(.{ .turn_complete = .{ .step_id = "test", .turn_number = 1 } }, executor.event_ctx);
    }

    try std.testing.expectEqual(@as(usize, 1), collector.tokens.items.len);
    try std.testing.expectEqual(@as(usize, 1), collector.tool_calls.items.len);
    try std.testing.expectEqual(@as(u32, 1), collector.turns);
}
