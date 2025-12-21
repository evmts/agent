# 17: Testing & Polish

## Goal

Implement comprehensive testing, handle edge cases, and add final polish to the Zig TUI.

## Context

- All core components are implemented
- Need unit tests for key modules
- Need integration tests for UI flows
- Polish: error handling, edge cases, performance

## Tasks

### 1. Unit Tests (src/tests/)

#### Test Protocol Parsing (src/tests/protocol_test.zig)

```zig
const std = @import("std");
const testing = std.testing;
const protocol = @import("../client/protocol.zig");

test "parse text event" {
    const json = "{\"type\":\"text\",\"data\":\"Hello world\"}";
    const event = try protocol.StreamEvent.parse(testing.allocator, json);
    defer testing.allocator.free(event.text.data.?);

    try testing.expect(event == .text);
    try testing.expectEqualStrings("Hello world", event.text.data.?);
}

test "parse tool call event" {
    const json =
        \\{"type":"tool.call","tool_name":"grep","tool_id":"123","args":"{}"}
    ;
    const event = try protocol.StreamEvent.parse(testing.allocator, json);
    defer {
        testing.allocator.free(event.tool_call.tool_name);
        testing.allocator.free(event.tool_call.tool_id);
        testing.allocator.free(event.tool_call.args);
    }

    try testing.expect(event == .tool_call);
    try testing.expectEqualStrings("grep", event.tool_call.tool_name);
}

test "parse usage event" {
    const json = "{\"type\":\"usage\",\"input_tokens\":100,\"output_tokens\":50}";
    const event = try protocol.StreamEvent.parse(testing.allocator, json);

    try testing.expect(event == .usage);
    try testing.expectEqual(@as(u64, 100), event.usage.input_tokens);
    try testing.expectEqual(@as(u64, 50), event.usage.output_tokens);
}

test "parse done event" {
    const json = "{\"type\":\"done\"}";
    const event = try protocol.StreamEvent.parse(testing.allocator, json);
    try testing.expect(event == .done);
}
```

#### Test Markdown Parser (src/tests/markdown_test.zig)

```zig
const std = @import("std");
const testing = std.testing;
const MarkdownRenderer = @import("../render/markdown.zig").MarkdownRenderer;

test "render header" {
    var renderer = MarkdownRenderer.init(testing.allocator);
    const segments = try renderer.render("# Hello World");
    defer testing.allocator.free(segments);

    try testing.expect(segments.len > 0);
    try testing.expect(segments[0].style.bold);
}

test "render bold text" {
    var renderer = MarkdownRenderer.init(testing.allocator);
    const segments = try renderer.render("This is **bold** text");
    defer testing.allocator.free(segments);

    // Find bold segment
    var found_bold = false;
    for (segments) |seg| {
        if (seg.style.bold) {
            found_bold = true;
            try testing.expectEqualStrings("bold", seg.text);
        }
    }
    try testing.expect(found_bold);
}

test "render code block" {
    var renderer = MarkdownRenderer.init(testing.allocator);
    const input =
        \\```zig
        \\const x = 1;
        \\```
    ;
    const segments = try renderer.render(input);
    defer testing.allocator.free(segments);

    // Code blocks should have dim style
    var found_code = false;
    for (segments) |seg| {
        if (seg.style.dim) {
            found_code = true;
            break;
        }
    }
    try testing.expect(found_code);
}

test "render list items" {
    var renderer = MarkdownRenderer.init(testing.allocator);
    const segments = try renderer.render("- Item one\n- Item two");
    defer testing.allocator.free(segments);

    // Should contain bullet points
    var found_bullet = false;
    for (segments) |seg| {
        if (std.mem.indexOf(u8, seg.text, "•") != null) {
            found_bullet = true;
            break;
        }
    }
    try testing.expect(found_bullet);
}
```

#### Test Command Parser (src/tests/command_test.zig)

```zig
const std = @import("std");
const testing = std.testing;
const parser = @import("../commands/parser.zig");
const registry = @import("../commands/registry.zig");

test "parse simple command" {
    const result = try parser.parse(testing.allocator, "/help");
    try testing.expectEqualStrings("help", result.command.name);
    try testing.expectEqual(@as(usize, 0), result.args.len);
}

test "parse command with args" {
    const result = try parser.parse(testing.allocator, "/switch abc123");
    try testing.expectEqualStrings("switch", result.command.name);
    try testing.expectEqual(@as(usize, 1), result.args.len);
    try testing.expectEqualStrings("abc123", result.args[0]);
}

test "parse command alias" {
    const result = try parser.parse(testing.allocator, "/q");
    try testing.expectEqualStrings("quit", result.command.name);
}

test "unknown command error" {
    const result = parser.parse(testing.allocator, "/foobar");
    try testing.expectError(parser.ParseError.UnknownCommand, result);
}

test "not a command" {
    const result = parser.parse(testing.allocator, "hello world");
    try testing.expectError(parser.ParseError.NotACommand, result);
}

test "find command" {
    const cmd = registry.findCommand("model");
    try testing.expect(cmd != null);
    try testing.expectEqualStrings("model", cmd.?.name);
}

test "get completions" {
    const completions = registry.getCompletions("mod");
    try testing.expect(completions.len > 0);
    try testing.expectEqualStrings("model", completions[0]);
}
```

#### Test Diff Parser (src/tests/diff_test.zig)

```zig
const std = @import("std");
const testing = std.testing;
const DiffRenderer = @import("../render/diff.zig").DiffRenderer;

test "parse unified diff" {
    var renderer = DiffRenderer.init(testing.allocator);

    const diff_text =
        \\--- a/file.txt
        \\+++ b/file.txt
        \\@@ -1,3 +1,4 @@
        \\ context
        \\-removed
        \\+added
        \\+more
        \\ context
    ;

    const diff = try renderer.parse(diff_text);

    try testing.expectEqualStrings("a/file.txt", diff.old_file.?);
    try testing.expectEqualStrings("b/file.txt", diff.new_file.?);
    try testing.expectEqual(@as(usize, 1), diff.hunks.items.len);

    const stats = diff.getStats();
    try testing.expectEqual(@as(u32, 2), stats.additions);
    try testing.expectEqual(@as(u32, 1), stats.deletions);
}
```

### 2. Integration Tests (src/tests/integration/)

#### Test App Lifecycle (src/tests/integration/app_test.zig)

```zig
const std = @import("std");
const testing = std.testing;
const App = @import("../../app.zig").App;
const AppState = @import("../../state/app_state.zig").AppState;

test "app initialization" {
    var state = try AppState.init(testing.allocator, "http://localhost:4000");
    defer state.deinit();

    var app = App.init(&state);
    _ = app;

    // App should start in chat mode
    try testing.expectEqual(AppState.UiMode.chat, state.mode);
    try testing.expectEqual(AppState.ConnectionState.disconnected, state.connection);
}

test "input handling" {
    var state = try AppState.init(testing.allocator, "http://localhost:4000");
    defer state.deinit();

    // Test text input
    try state.insertText("hello");
    try testing.expectEqualStrings("hello", state.getInput());

    // Test cursor movement
    state.moveCursor(-2);
    try testing.expectEqual(@as(usize, 3), state.input_cursor);

    // Test delete
    state.deleteForward();
    try testing.expectEqualStrings("helo", state.getInput());
}

test "history navigation" {
    var state = try AppState.init(testing.allocator, "http://localhost:4000");
    defer state.deinit();

    // Add to history
    try state.insertText("first");
    try state.saveToHistory();
    state.clearInput();

    try state.insertText("second");
    try state.saveToHistory();
    state.clearInput();

    // Navigate up
    state.navigateHistory(-1);
    try testing.expectEqualStrings("second", state.getInput());

    state.navigateHistory(-1);
    try testing.expectEqualStrings("first", state.getInput());

    // Navigate back down
    state.navigateHistory(1);
    try testing.expectEqualStrings("second", state.getInput());
}
```

### 3. Error Handling Polish

#### Graceful Network Errors (src/client/error.zig)

```zig
const std = @import("std");

pub const ClientError = error{
    ConnectionFailed,
    Timeout,
    ServerError,
    ParseError,
    Unauthorized,
    NotFound,
    RateLimited,
};

pub fn handleHttpError(status: std.http.Status) ClientError {
    return switch (@intFromEnum(status)) {
        401 => ClientError.Unauthorized,
        404 => ClientError.NotFound,
        429 => ClientError.RateLimited,
        500...599 => ClientError.ServerError,
        else => ClientError.ServerError,
    };
}

pub fn formatError(err: ClientError) []const u8 {
    return switch (err) {
        .ConnectionFailed => "Could not connect to server",
        .Timeout => "Request timed out",
        .ServerError => "Server error occurred",
        .ParseError => "Invalid response from server",
        .Unauthorized => "Authentication required",
        .NotFound => "Resource not found",
        .RateLimited => "Rate limited - please wait",
    };
}
```

### 4. Performance Optimizations

#### Lazy Rendering (src/render/lazy.zig)

```zig
const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

/// Only render visible portion of content
pub fn LazyList(comptime T: type) type {
    return struct {
        items: []const T,
        visible_start: usize = 0,
        visible_count: usize = 0,
        item_height: u16 = 1,
        render_fn: *const fn (*const T, *vxfw.Surface, u16, u16) void,

        const Self = @This();

        pub fn setVisibleRange(self: *Self, viewport_height: u16, scroll_offset: usize) void {
            self.visible_count = viewport_height / self.item_height;
            self.visible_start = scroll_offset;

            // Clamp to valid range
            if (self.visible_start + self.visible_count > self.items.len) {
                self.visible_start = if (self.items.len > self.visible_count)
                    self.items.len - self.visible_count
                else
                    0;
            }
        }

        pub fn render(self: *Self, surface: *vxfw.Surface, width: u16) void {
            const end = @min(self.visible_start + self.visible_count, self.items.len);

            var row: u16 = 0;
            for (self.items[self.visible_start..end]) |*item| {
                self.render_fn(item, surface, row, width);
                row += self.item_height;
            }
        }

        pub fn getTotalHeight(self: *Self) u16 {
            return @intCast(self.items.len * self.item_height);
        }
    };
}
```

### 5. Final Polish Checklist

#### UI Polish

- [ ] Consistent color scheme across all widgets
- [ ] Proper unicode character rendering
- [ ] Handle terminal resize events
- [ ] Cursor visibility management
- [ ] Focus indicators on interactive elements
- [ ] Loading states for async operations

#### Input Polish

- [ ] Handle paste events (bracketed paste)
- [ ] Handle special keys (function keys, etc.)
- [ ] Mouse wheel scrolling
- [ ] Click to focus widgets
- [ ] Proper clipboard integration

#### Error Polish

- [ ] Show user-friendly error messages
- [ ] Auto-retry on network failures
- [ ] Preserve input on error
- [ ] Clear error on successful operation
- [ ] Log errors for debugging

#### Performance Polish

- [ ] Lazy render large message history
- [ ] Debounce rapid input events
- [ ] Cache rendered content
- [ ] Efficient diff updates
- [ ] Memory cleanup on session switch

### 6. Build & Run Tests

Add to `build.zig`:

```zig
// Add test step
const test_step = b.step("test", "Run all tests");

const test_dirs = [_][]const u8{
    "src/tests/protocol_test.zig",
    "src/tests/markdown_test.zig",
    "src/tests/command_test.zig",
    "src/tests/diff_test.zig",
    "src/tests/integration/app_test.zig",
};

for (test_dirs) |path| {
    const unit_tests = b.addTest(.{
        .root_source_file = b.path(path),
        .target = target,
        .optimize = optimize,
    });
    unit_tests.root_module.addImport("vaxis", vaxis_dep.module("vaxis"));
    test_step.dependOn(&b.addRunArtifact(unit_tests).step);
}
```

## Acceptance Criteria

- [ ] All unit tests pass
- [ ] Protocol parsing handles all event types
- [ ] Markdown renderer handles all syntax
- [ ] Command parser validates input correctly
- [ ] Diff parser handles edge cases
- [ ] App handles keyboard/mouse input
- [ ] History navigation works
- [ ] Error messages are user-friendly
- [ ] No memory leaks
- [ ] Performance acceptable with large history

## Files to Create

1. `tui-zig/src/tests/protocol_test.zig`
2. `tui-zig/src/tests/markdown_test.zig`
3. `tui-zig/src/tests/command_test.zig`
4. `tui-zig/src/tests/diff_test.zig`
5. `tui-zig/src/tests/integration/app_test.zig`
6. `tui-zig/src/client/error.zig`
7. `tui-zig/src/render/lazy.zig`

## Completion

After completing all prompts (01-17), you will have a fully functional Zig TUI with:

- Complete libvaxis-based terminal UI
- SSE streaming for real-time responses
- Markdown rendering with syntax highlighting
- Diff visualization
- Tool call display
- Approval overlays
- Session management
- Slash commands
- File mentions
- Comprehensive testing

The TUI will have 100% feature parity with the codex TUI reference implementation.
