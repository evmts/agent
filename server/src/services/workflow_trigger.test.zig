//! Tests for workflow trigger service

const std = @import("std");
const testing = std.testing;
const WorkflowTrigger = @import("workflow_trigger.zig").WorkflowTrigger;

test "parseWorkflowFile - basic workflow" {
    const allocator = testing.allocator;

    // Create temporary test file
    const test_dir = testing.tmpDir(.{});
    defer test_dir.cleanup();

    const workflow_content =
        \\from plue import workflow, step
        \\
        \\@workflow(name="Test Workflow", on=["push", "pull_request"])
        \\async def test_wf(ctx):
        \\    pass
    ;

    const file_path = "test_workflow.py";
    try test_dir.dir.writeFile(.{
        .sub_path = file_path,
        .data = workflow_content,
    });

    const abs_path = try test_dir.dir.realpathAlloc(allocator, file_path);
    defer allocator.free(abs_path);

    var mock_pool: @import("../lib/db.zig").Pool = undefined;
    var trigger = WorkflowTrigger.init(allocator, &mock_pool);

    var metadata = try trigger.parseWorkflowFile(abs_path, file_path);
    defer metadata.deinit();

    try testing.expectEqualStrings("Test Workflow", metadata.name);
    try testing.expectEqualStrings(file_path, metadata.file_path);
    try testing.expectEqual(@as(usize, 2), metadata.events.len);
    try testing.expectEqualStrings("push", metadata.events[0]);
    try testing.expectEqualStrings("pull_request", metadata.events[1]);
    try testing.expectEqual(false, metadata.is_agent_workflow);
}

test "parseWorkflowFile - agent workflow" {
    const allocator = testing.allocator;

    const test_dir = testing.tmpDir(.{});
    defer test_dir.cleanup();

    const workflow_content =
        \\from plue import workflow
        \\
        \\@workflow(name="AI Assistant", on=["issue", "chat"], agent=True)
        \\async def assistant(ctx):
        \\    pass
    ;

    const file_path = "agent_workflow.py";
    try test_dir.dir.writeFile(.{
        .sub_path = file_path,
        .data = workflow_content,
    });

    const abs_path = try test_dir.dir.realpathAlloc(allocator, file_path);
    defer allocator.free(abs_path);

    var mock_pool: @import("../lib/db.zig").Pool = undefined;
    var trigger = WorkflowTrigger.init(allocator, &mock_pool);

    var metadata = try trigger.parseWorkflowFile(abs_path, file_path);
    defer metadata.deinit();

    try testing.expectEqualStrings("AI Assistant", metadata.name);
    try testing.expectEqual(@as(usize, 2), metadata.events.len);
    try testing.expectEqualStrings("issue", metadata.events[0]);
    try testing.expectEqualStrings("chat", metadata.events[1]);
    try testing.expectEqual(true, metadata.is_agent_workflow);
}

test "parseWorkflowFile - no decorator" {
    const allocator = testing.allocator;

    const test_dir = testing.tmpDir(.{});
    defer test_dir.cleanup();

    const workflow_content =
        \\# Just a regular Python file
        \\def some_function():
        \\    pass
    ;

    const file_path = "not_workflow.py";
    try test_dir.dir.writeFile(.{
        .sub_path = file_path,
        .data = workflow_content,
    });

    const abs_path = try test_dir.dir.realpathAlloc(allocator, file_path);
    defer allocator.free(abs_path);

    var mock_pool: @import("../lib/db.zig").Pool = undefined;
    var trigger = WorkflowTrigger.init(allocator, &mock_pool);

    var metadata = try trigger.parseWorkflowFile(abs_path, file_path);
    defer metadata.deinit();

    // Should use filename as fallback name
    try testing.expectEqualStrings("not_workflow", metadata.name);
    try testing.expectEqual(@as(usize, 0), metadata.events.len);
}

test "shouldTrigger - matching event" {
    const allocator = testing.allocator;

    var mock_pool: @import("../lib/db.zig").Pool = undefined;
    var trigger = WorkflowTrigger.init(allocator, &mock_pool);

    const events = [_][]const u8{ "push", "pull_request" };
    var metadata = WorkflowTrigger.WorkflowMetadata{
        .name = "test",
        .file_path = "test.py",
        .events = @constCast(&events),
        .is_agent_workflow = false,
        .allocator = allocator,
    };

    try testing.expect(try trigger.shouldTrigger(&metadata, "push"));
    try testing.expect(try trigger.shouldTrigger(&metadata, "pull_request"));
    try testing.expect(!try trigger.shouldTrigger(&metadata, "issue"));
}

test "eventsToJson" {
    const allocator = testing.allocator;

    var mock_pool: @import("../lib/db.zig").Pool = undefined;
    var trigger = WorkflowTrigger.init(allocator, &mock_pool);

    const events = [_][]const u8{ "push", "pull_request", "issue" };
    const json = try trigger.eventsToJson(&events);
    defer allocator.free(json);

    try testing.expectEqualStrings("[\"push\",\"pull_request\",\"issue\"]", json);
}

test "eventsToJson - empty" {
    const allocator = testing.allocator;

    var mock_pool: @import("../lib/db.zig").Pool = undefined;
    var trigger = WorkflowTrigger.init(allocator, &mock_pool);

    const events = [_][]const u8{};
    const json = try trigger.eventsToJson(&events);
    defer allocator.free(json);

    try testing.expectEqualStrings("[]", json);
}

test "WorkflowEvent conversion" {
    const WorkflowEvent = @import("workflow_trigger.zig").WorkflowEvent;

    try testing.expectEqual(WorkflowEvent.push, WorkflowEvent.fromString("push"));
    try testing.expectEqual(WorkflowEvent.pull_request, WorkflowEvent.fromString("pull_request"));
    try testing.expectEqual(WorkflowEvent.issue, WorkflowEvent.fromString("issue"));
    try testing.expectEqual(WorkflowEvent.chat, WorkflowEvent.fromString("chat"));
    try testing.expectEqual(@as(?WorkflowEvent, null), WorkflowEvent.fromString("invalid"));

    try testing.expectEqualStrings("push", WorkflowEvent.push.toString());
    try testing.expectEqualStrings("pull_request", WorkflowEvent.pull_request.toString());
    try testing.expectEqualStrings("issue", WorkflowEvent.issue.toString());
    try testing.expectEqualStrings("chat", WorkflowEvent.chat.toString());
}
