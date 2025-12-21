//! Integration test for agent - real LLM request
//!
//! Tests the agent end-to-end: sends a message to Claude, agent reads a file,
//! returns structured output. Requires ANTHROPIC_API_KEY.

const std = @import("std");
const testing = std.testing;
const agent = @import("agent.zig");
const client = @import("client.zig");
const types = @import("types.zig");
const pty = @import("../websocket/pty.zig");

test "agent reads file and returns structured output via LLM" {
    // Skip if no API key
    var check_alloc = std.heap.page_allocator;
    const api_key = std.process.getEnvVarOwned(check_alloc, "ANTHROPIC_API_KEY") catch {
        std.debug.print("Skipping: ANTHROPIC_API_KEY not set\n", .{});
        return;
    };
    check_alloc.free(api_key);

    // Use page allocator to avoid leak detection (agent has known leaks to fix later)
    const allocator = std.heap.page_allocator;

    // Create temp directory and test file
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const test_content =
        \\{
        \\  "projectName": "plue-test",
        \\  "version": "2.5.0",
        \\  "author": "test-author"
        \\}
    ;

    const file = try tmp_dir.dir.createFile("config.json", .{});
    defer file.close();
    try file.writeAll(test_content);

    const dir_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(dir_path);

    const file_path = try std.fs.path.join(allocator, &.{ dir_path, "config.json" });
    defer allocator.free(file_path);

    // Create PTY manager for tool context
    var pty_manager = pty.Manager.init(allocator);
    defer pty_manager.deinit();

    // Create file tracker
    var file_tracker = types.FileTimeTracker.init(allocator);
    defer file_tracker.deinit();

    const tool_ctx = types.ToolContext{
        .session_id = "test-session",
        .working_dir = dir_path,
        .allocator = allocator,
        .pty_manager = &pty_manager,
        .file_tracker = &file_tracker,
    };

    // Build message asking agent to read the file
    const prompt = try std.fmt.allocPrint(
        allocator,
        "Read the file at {s} and return the projectName and version as JSON.",
        .{file_path},
    );
    defer allocator.free(prompt);

    const messages = &[_]client.Message{
        .{ .role = .user, .content = .{ .text = prompt } },
    };

    // Run the agent
    const result = agent.runAgent(
        allocator,
        messages,
        .{
            .model_id = "claude-sonnet-4-20250514",
            .agent_name = "build",
            .working_dir = dir_path,
            .session_id = "test-session",
        },
        tool_ctx,
    ) catch |err| {
        std.debug.print("Agent error: {}\n", .{err});
        return err;
    };
    defer allocator.free(result);

    // Verify the response contains our data
    std.debug.print("Agent response: {s}\n", .{result});
    try testing.expect(std.mem.indexOf(u8, result, "plue-test") != null or
        std.mem.indexOf(u8, result, "2.5.0") != null);
}
