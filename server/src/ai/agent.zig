const std = @import("std");
const client = @import("client.zig");
const types = @import("types.zig");
const registry = @import("registry.zig");
const tools_mod = @import("tools/mod.zig");

const StreamEvent = types.StreamEvent;
const AgentOptions = types.AgentOptions;
const StreamCallbacks = types.StreamCallbacks;
const ToolContext = types.ToolContext;

/// Run agent (non-streaming) and return final text
pub fn runAgent(
    allocator: std.mem.Allocator,
    messages: []const client.Message,
    options: AgentOptions,
    ctx: ToolContext,
) ![]const u8 {
    const config = registry.getAgentConfig(options.agent_name);

    // Get enabled tools for this agent
    const enabled_tools = try tools_mod.getEnabledTools(
        allocator,
        options.agent_name,
        config.tools_enabled,
    );
    defer allocator.free(enabled_tools);

    // Get API key
    const api_key = std.process.getEnvVarOwned(allocator, "ANTHROPIC_API_KEY") catch {
        return error.ApiKeyNotSet;
    };
    defer allocator.free(api_key);

    // Create client
    const anthropic = client.AnthropicClient.init(allocator, api_key);

    // Run agent loop
    var current_messages = std.ArrayList(client.Message){};
    defer current_messages.deinit(allocator);

    for (messages) |msg| {
        try current_messages.append(allocator, msg);
    }

    var steps: u32 = 0;
    const max_steps: u32 = 10;

    while (steps < max_steps) {
        const response = try anthropic.sendMessages(
            options.model_id,
            current_messages.items,
            config.system_prompt,
            enabled_tools,
            config.temperature,
            4096,
        );

        // Check for tool calls
        var has_tool_calls = false;
        var text_result: ?[]const u8 = null;

        for (response.content) |block| {
            switch (block) {
                .text => |text| {
                    text_result = text;
                },
                .tool_use => {
                    has_tool_calls = true;
                },
            }
        }

        if (!has_tool_calls) {
            // No tool calls, return text
            return text_result orelse error.NoContent;
        }

        // Process tool calls
        var assistant_parts = std.ArrayList(client.ContentPart){};
        var tool_results = std.ArrayList(client.ContentPart){};

        for (response.content) |block| {
            switch (block) {
                .text => |text| {
                    try assistant_parts.append(allocator, .{
                        .text = .{ .text = text },
                    });
                },
                .tool_use => |tu| {
                    try assistant_parts.append(allocator, .{
                        .tool_use = .{
                            .id = tu.id,
                            .name = tu.name,
                            .input = tu.input,
                        },
                    });

                    // Execute tool - parse JSON string to Value
                    const parsed_input = try std.json.parseFromSlice(std.json.Value, allocator, tu.input, .{});
                    defer parsed_input.deinit();

                    const output = tools_mod.executeTool(allocator, tu.name, parsed_input.value, ctx) catch |err| {
                        try tool_results.append(allocator, .{
                            .tool_result = .{
                                .tool_use_id = tu.id,
                                .content = @errorName(err),
                            },
                        });
                        continue;
                    };

                    try tool_results.append(allocator, .{
                        .tool_result = .{
                            .tool_use_id = tu.id,
                            .content = output,
                        },
                    });
                },
            }
        }

        // Add assistant message
        try current_messages.append(allocator, .{
            .role = .assistant,
            .content = .{ .parts = try assistant_parts.toOwnedSlice(allocator) },
        });

        // Add tool results as user message
        try current_messages.append(allocator, .{
            .role = .user,
            .content = .{ .parts = try tool_results.toOwnedSlice(allocator) },
        });

        steps += 1;
    }

    return error.MaxStepsReached;
}

/// Stream agent execution with callbacks
pub fn streamAgent(
    allocator: std.mem.Allocator,
    messages: []const client.Message,
    options: AgentOptions,
    ctx: ToolContext,
    callbacks: StreamCallbacks,
) !void {
    const config = registry.getAgentConfig(options.agent_name);

    // Get enabled tools for this agent
    const enabled_tools = try tools_mod.getEnabledTools(
        allocator,
        options.agent_name,
        config.tools_enabled,
    );
    defer allocator.free(enabled_tools);

    // Get API key
    const api_key = std.process.getEnvVarOwned(allocator, "ANTHROPIC_API_KEY") catch {
        callbacks.on_event(.{ .error_event = .{ .message = "ANTHROPIC_API_KEY not set" } }, callbacks.context);
        return;
    };
    defer allocator.free(api_key);

    // Create client
    const anthropic = client.AnthropicClient.init(allocator, api_key);

    // Run agent loop with streaming events
    var current_messages = std.ArrayList(client.Message){};
    defer current_messages.deinit(allocator);

    for (messages) |msg| {
        try current_messages.append(allocator, msg);
    }

    var steps: u32 = 0;
    const max_steps: u32 = 10;

    while (steps < max_steps) {
        const response = anthropic.sendMessages(
            options.model_id,
            current_messages.items,
            config.system_prompt,
            enabled_tools,
            config.temperature,
            4096,
        ) catch |err| {
            callbacks.on_event(.{ .error_event = .{ .message = @errorName(err) } }, callbacks.context);
            return;
        };

        // Emit events for response content
        var has_tool_calls = false;

        for (response.content) |block| {
            switch (block) {
                .text => |text| {
                    callbacks.on_event(.{ .text = .{ .data = text } }, callbacks.context);
                },
                .tool_use => |tu| {
                    has_tool_calls = true;
                    callbacks.on_event(.{
                        .tool_call = .{
                            .tool_name = tu.name,
                            .tool_id = tu.id,
                            .args = tu.input,
                        },
                    }, callbacks.context);
                },
            }
        }

        if (!has_tool_calls) {
            // Done
            callbacks.on_event(.{ .done = {} }, callbacks.context);
            return;
        }

        // Process tool calls
        var assistant_parts = std.ArrayList(client.ContentPart){};
        var tool_results = std.ArrayList(client.ContentPart){};

        for (response.content) |block| {
            switch (block) {
                .text => |text| {
                    try assistant_parts.append(allocator, .{
                        .text = .{ .text = text },
                    });
                },
                .tool_use => |tu| {
                    try assistant_parts.append(allocator, .{
                        .tool_use = .{
                            .id = tu.id,
                            .name = tu.name,
                            .input = tu.input,
                        },
                    });

                    // Execute tool - parse JSON string to Value
                    const parsed_input = try std.json.parseFromSlice(std.json.Value, allocator, tu.input, .{});
                    defer parsed_input.deinit();

                    const output = tools_mod.executeTool(allocator, tu.name, parsed_input.value, ctx) catch |err| {
                        callbacks.on_event(.{
                            .tool_result = .{
                                .tool_id = tu.id,
                                .tool_output = @errorName(err),
                            },
                        }, callbacks.context);

                        try tool_results.append(allocator, .{
                            .tool_result = .{
                                .tool_use_id = tu.id,
                                .content = @errorName(err),
                            },
                        });
                        continue;
                    };

                    callbacks.on_event(.{
                        .tool_result = .{
                            .tool_id = tu.id,
                            .tool_output = output,
                        },
                    }, callbacks.context);

                    try tool_results.append(allocator, .{
                        .tool_result = .{
                            .tool_use_id = tu.id,
                            .content = output,
                        },
                    });
                },
            }
        }

        // Add assistant message
        try current_messages.append(allocator, .{
            .role = .assistant,
            .content = .{ .parts = try assistant_parts.toOwnedSlice(allocator) },
        });

        // Add tool results as user message
        try current_messages.append(allocator, .{
            .role = .user,
            .content = .{ .parts = try tool_results.toOwnedSlice(allocator) },
        });

        steps += 1;
    }

    callbacks.on_event(.{ .error_event = .{ .message = "Max steps reached" } }, callbacks.context);
}

test "registry integration" {
    const config = registry.getAgentConfig("build");
    try std.testing.expectEqualStrings("build", config.name);
}
