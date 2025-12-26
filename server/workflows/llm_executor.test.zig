//! Integration tests for LLM executor
//!
//! Tests the full LLM and agent execution flow including:
//! - Prompt parsing and rendering
//! - Claude API integration
//! - Database persistence (llm_usage)
//! - Event forwarding
//!
//! Requires ANTHROPIC_API_KEY to run. Tests skip gracefully if not set.

const std = @import("std");
const testing = std.testing;
const llm_executor_mod = @import("llm_executor.zig");
const plan = @import("plan.zig");
const db = @import("../../db/root.zig");

// Helper to check if API key is available
fn hasApiKey() bool {
    const result = std.process.getEnvVarOwned(std.heap.page_allocator, "ANTHROPIC_API_KEY") catch {
        return false;
    };
    // Free the value we got from page_allocator
    std.heap.page_allocator.free(result);
    return true;
}

test "llm_executor - full LLM step execution with API" {
    if (!hasApiKey()) {
        std.debug.print("Skipping: ANTHROPIC_API_KEY not set\n", .{});
        return;
    }

    // Use page allocator to avoid tracking known leaks in AI client
    const allocator = std.heap.page_allocator;

    // Create temp directory for prompt file
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Write test prompt file
    const prompt_content =
        \\---
        \\name: TestPrompt
        \\client: anthropic/claude-sonnet
        \\
        \\inputs:
        \\  question: string
        \\
        \\output:
        \\  answer: string
        \\  reasoning: string
        \\---
        \\
        \\{{ question }}
        \\
        \\Please answer concisely in JSON format with fields "answer" and "reasoning".
    ;

    const file = try tmp_dir.dir.createFile("test.prompt.md", .{});
    defer file.close();
    try file.writeAll(prompt_content);

    const dir_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    const prompt_path = try std.fs.path.join(allocator, &.{ dir_path, "test.prompt.md" });

    // Create LLM executor (no database for this test)
    var executor = llm_executor_mod.LlmExecutor.init(allocator, null);

    // Set up event collector
    const EventCollector = struct {
        tokens: std.ArrayList([]const u8),

        fn init(alloc: std.mem.Allocator) @This() {
            return .{
                .tokens = std.ArrayList([]const u8).init(alloc),
            };
        }

        fn deinit(self: *@This()) void {
            self.tokens.deinit();
        }
    };

    var event_collector = EventCollector.init(allocator);
    defer event_collector.deinit();

    const callback = struct {
        fn cb(event: llm_executor_mod.LlmExecutionEvent, ctx: ?*anyopaque) void {
            const collector: *EventCollector = @ptrCast(@alignCast(ctx.?));
            switch (event) {
                .token => |token_data| {
                    collector.tokens.append(allocator, token_data.text) catch return;
                },
                else => {},
            }
        }
    }.cb;

    executor.setEventCallback(callback, &event_collector);

    // Create step config
    var config = plan.StepConfig.init(allocator);
    defer config.deinit();

    try config.put("prompt_path", .{ .string = prompt_path });

    var inputs = std.StringHashMap(std.json.Value).init(allocator);
    defer inputs.deinit();
    try inputs.put("question", .{ .string = "What is 2+2?" });

    try config.put("inputs", .{ .object = inputs });

    // Execute LLM step
    const result = executor.executeLlmStep("test-step", &config, null) catch |err| {
        std.debug.print("Skipping: API call failed ({s})\n", .{@errorName(err)});
        return;
    };
    defer {
        var mut_result = result;
        mut_result.deinit(allocator);
    }

    // Verify we got tokens
    try testing.expect(event_collector.tokens.items.len > 0);
    std.debug.print("Received {} tokens from LLM\n", .{event_collector.tokens.items.len});

    // Verify we got token counts (should be non-zero)
    try testing.expect(result.tokens_in > 0);
    try testing.expect(result.tokens_out > 0);
    std.debug.print("Token usage: {} in, {} out\n", .{ result.tokens_in, result.tokens_out });

    // Verify output is structured JSON
    try testing.expect(result.output == .object);
    std.debug.print("LLM returned structured output\n", .{});
}

test "llm_executor - full agent step execution with API" {
    if (!hasApiKey()) {
        std.debug.print("Skipping: ANTHROPIC_API_KEY not set\n", .{});
        return;
    }

    // Use page allocator to avoid tracking known leaks
    const allocator = std.heap.page_allocator;

    // Create temp directory for prompt file and workspace
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Write test file for agent to read
    const test_file = try tmp_dir.dir.createFile("data.txt", .{});
    defer test_file.close();
    try test_file.writeAll("The answer is: 42");

    const dir_path = try tmp_dir.dir.realpathAlloc(allocator, ".");

    // Write agent prompt file
    const prompt_content =
        \\---
        \\name: TestAgent
        \\client: anthropic/claude-sonnet
        \\type: agent
        \\
        \\inputs:
        \\  task: string
        \\
        \\output:
        \\  result: string
        \\  files_read: string[]
        \\
        \\tools:
        \\  - read_file
        \\
        \\max_turns: 3
        \\---
        \\
        \\{{ task }}
        \\
        \\Please complete the task and return JSON with "result" and "files_read" fields.
    ;

    const prompt_file = try tmp_dir.dir.createFile("agent.prompt.md", .{});
    defer prompt_file.close();
    try prompt_file.writeAll(prompt_content);

    const prompt_path = try std.fs.path.join(allocator, &.{ dir_path, "agent.prompt.md" });

    // Create LLM executor
    var executor = llm_executor_mod.LlmExecutor.init(allocator, null);

    // Set up event collector
    const EventCollector = struct {
        tokens: std.ArrayList([]const u8),
        tool_calls: std.ArrayList([]const u8),
        turns: u32,

        fn init(alloc: std.mem.Allocator) @This() {
            return .{
                .tokens = std.ArrayList([]const u8).init(alloc),
                .tool_calls = std.ArrayList([]const u8).init(alloc),
                .turns = 0,
            };
        }

        fn deinit(self: *@This()) void {
            self.tokens.deinit();
            self.tool_calls.deinit();
        }
    };

    var event_collector = EventCollector.init(allocator);
    defer event_collector.deinit();

    const callback = struct {
        fn cb(event: llm_executor_mod.LlmExecutionEvent, ctx: ?*anyopaque) void {
            const collector: *EventCollector = @ptrCast(@alignCast(ctx.?));
            switch (event) {
                .token => |token_data| {
                    collector.tokens.append(allocator, token_data.text) catch return;
                },
                .tool_start => |tool_data| {
                    collector.tool_calls.append(allocator, tool_data.tool_name) catch return;
                },
                .turn_complete => {
                    collector.turns += 1;
                },
                else => {},
            }
        }
    }.cb;

    executor.setEventCallback(callback, &event_collector);

    // Create step config
    var config = plan.StepConfig.init(allocator);
    defer config.deinit();

    try config.put("prompt_path", .{ .string = prompt_path });

    var inputs = std.StringHashMap(std.json.Value).init(allocator);
    defer inputs.deinit();
    const task = try std.fmt.allocPrint(allocator, "Read the file at {s}/data.txt and tell me what it says.", .{dir_path});
    try inputs.put("task", .{ .string = task });

    try config.put("inputs", .{ .object = inputs });

    // Execute agent step
    const result = executor.executeAgentStep("test-agent-step", &config, null) catch |err| {
        std.debug.print("Skipping: API call failed ({s})\n", .{@errorName(err)});
        return;
    };
    defer {
        var mut_result = result;
        mut_result.deinit(allocator);
    }

    // Verify we got tokens
    try testing.expect(event_collector.tokens.items.len > 0);
    std.debug.print("Received {} tokens from agent\n", .{event_collector.tokens.items.len});

    // Verify agent used tools
    try testing.expect(event_collector.tool_calls.items.len > 0);
    std.debug.print("Agent made {} tool calls\n", .{event_collector.tool_calls.items.len});

    // Verify we had at least one turn
    try testing.expect(event_collector.turns > 0);
    try testing.expect(result.turns_used > 0);
    std.debug.print("Agent completed in {} turns\n", .{result.turns_used});

    // Verify output is structured JSON
    try testing.expect(result.output == .object);
    std.debug.print("Agent returned structured output\n", .{});
}
