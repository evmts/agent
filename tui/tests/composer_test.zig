const std = @import("std");
const testing = std.testing;
const AppState = @import("../state/app_state.zig").AppState;
const Composer = @import("../widgets/composer.zig").Composer;

test "cursor movement - left and right" {
    var state = try AppState.init(testing.allocator, "http://localhost:4000");
    defer state.deinit();

    // Insert some text
    try state.insertText("hello");
    try testing.expectEqual(@as(usize, 5), state.input_cursor);

    // Move left
    state.moveCursor(-1);
    try testing.expectEqual(@as(usize, 4), state.input_cursor);

    state.moveCursor(-2);
    try testing.expectEqual(@as(usize, 2), state.input_cursor);

    // Move right
    state.moveCursor(1);
    try testing.expectEqual(@as(usize, 3), state.input_cursor);

    // Test bounds - can't go below 0
    state.moveCursor(-10);
    try testing.expectEqual(@as(usize, 0), state.input_cursor);

    // Test bounds - can't go beyond length
    state.moveCursor(20);
    try testing.expectEqual(@as(usize, 5), state.input_cursor);
}

test "cursor movement - home and end" {
    var state = try AppState.init(testing.allocator, "http://localhost:4000");
    defer state.deinit();

    try state.insertText("hello world");
    try testing.expectEqual(@as(usize, 11), state.input_cursor);

    // Home
    state.input_cursor = 0;
    try testing.expectEqual(@as(usize, 0), state.input_cursor);

    // End
    state.input_cursor = state.input_buffer.items.len;
    try testing.expectEqual(@as(usize, 11), state.input_cursor);
}

test "backspace deletes character before cursor" {
    var state = try AppState.init(testing.allocator, "http://localhost:4000");
    defer state.deinit();

    try state.insertText("hello");
    try testing.expectEqualStrings("hello", state.input_buffer.items);

    // Delete 'o'
    state.deleteBackward();
    try testing.expectEqualStrings("hell", state.input_buffer.items);
    try testing.expectEqual(@as(usize, 4), state.input_cursor);

    // Move cursor to middle
    state.input_cursor = 2;
    state.deleteBackward();
    try testing.expectEqualStrings("hll", state.input_buffer.items);
    try testing.expectEqual(@as(usize, 1), state.input_cursor);

    // Try to delete at start (should not crash)
    state.input_cursor = 0;
    state.deleteBackward();
    try testing.expectEqualStrings("hll", state.input_buffer.items);
}

test "delete forward removes character at cursor" {
    var state = try AppState.init(testing.allocator, "http://localhost:4000");
    defer state.deinit();

    try state.insertText("hello");
    state.input_cursor = 0;

    // Delete 'h'
    state.deleteForward();
    try testing.expectEqualStrings("ello", state.input_buffer.items);
    try testing.expectEqual(@as(usize, 0), state.input_cursor);

    // Move to end and try to delete (should not crash)
    state.input_cursor = state.input_buffer.items.len;
    state.deleteForward();
    try testing.expectEqualStrings("ello", state.input_buffer.items);
}

test "delete word backward - Ctrl+W" {
    var state = try AppState.init(testing.allocator, "http://localhost:4000");
    defer state.deinit();

    var composer = Composer{
        .state = &state,
    };

    try state.insertText("hello world test");
    try testing.expectEqualStrings("hello world test", state.input_buffer.items);

    // Delete "test"
    composer.deleteWordBackward();
    try testing.expectEqualStrings("hello world ", state.input_buffer.items);

    // Delete "world "
    composer.deleteWordBackward();
    try testing.expectEqualStrings("hello ", state.input_buffer.items);

    // Delete "hello "
    composer.deleteWordBackward();
    try testing.expectEqualStrings("", state.input_buffer.items);
    try testing.expectEqual(@as(usize, 0), state.input_cursor);
}

test "delete word backward with multiple spaces" {
    var state = try AppState.init(testing.allocator, "http://localhost:4000");
    defer state.deinit();

    var composer = Composer{
        .state = &state,
    };

    try state.insertText("hello   world");
    composer.deleteWordBackward();
    try testing.expectEqualStrings("hello   ", state.input_buffer.items);
}

test "delete to start - Ctrl+U" {
    var state = try AppState.init(testing.allocator, "http://localhost:4000");
    defer state.deinit();

    var composer = Composer{
        .state = &state,
    };

    try state.insertText("hello world");
    state.input_cursor = 5; // After "hello"

    composer.deleteToStart();
    try testing.expectEqualStrings(" world", state.input_buffer.items);
    try testing.expectEqual(@as(usize, 0), state.input_cursor);
}

test "delete to end - Ctrl+K" {
    var state = try AppState.init(testing.allocator, "http://localhost:4000");
    defer state.deinit();

    var composer = Composer{
        .state = &state,
    };

    try state.insertText("hello world");
    state.input_cursor = 5; // After "hello"

    composer.deleteToEnd();
    try testing.expectEqualStrings("hello", state.input_buffer.items);
    try testing.expectEqual(@as(usize, 5), state.input_cursor);
}

test "slash command detection" {
    var state = try AppState.init(testing.allocator, "http://localhost:4000");
    defer state.deinit();

    var composer = Composer{
        .state = &state,
    };

    try state.insertText("/help");
    const end = composer.getSlashCmdEnd(state.input_buffer.items);
    try testing.expectEqual(@as(usize, 5), end);

    state.clearInput();
    try state.insertText("/help me");
    const end2 = composer.getSlashCmdEnd(state.input_buffer.items);
    try testing.expectEqual(@as(usize, 5), end2); // Should stop at space

    state.clearInput();
    try state.insertText("not a command");
    const end3 = composer.getSlashCmdEnd(state.input_buffer.items);
    try testing.expectEqual(@as(usize, 0), end3);
}

test "@mention detection" {
    var state = try AppState.init(testing.allocator, "http://localhost:4000");
    defer state.deinit();

    var composer = Composer{
        .state = &state,
    };

    try state.insertText("@file.txt");

    // Characters in @file.txt should be detected as mention
    try testing.expect(composer.isInMention(state.input_buffer.items, 0)); // @
    try testing.expect(composer.isInMention(state.input_buffer.items, 1)); // f
    try testing.expect(composer.isInMention(state.input_buffer.items, 5)); // .

    state.clearInput();
    try state.insertText("hello @file");
    try testing.expect(!composer.isInMention(state.input_buffer.items, 0)); // h
    try testing.expect(!composer.isInMention(state.input_buffer.items, 5)); // space
    try testing.expect(composer.isInMention(state.input_buffer.items, 6)); // @
    try testing.expect(composer.isInMention(state.input_buffer.items, 10)); // e

    state.clearInput();
    try state.insertText("@file hello");
    try testing.expect(composer.isInMention(state.input_buffer.items, 4)); // e
    try testing.expect(!composer.isInMention(state.input_buffer.items, 6)); // space ends mention
}

test "history navigation" {
    var state = try AppState.init(testing.allocator, "http://localhost:4000");
    defer state.deinit();

    // Add some history
    try state.insertText("first");
    try state.saveToHistory();
    state.clearInput();

    try state.insertText("second");
    try state.saveToHistory();
    state.clearInput();

    try state.insertText("third");
    try state.saveToHistory();
    state.clearInput();

    try testing.expectEqual(@as(usize, 3), state.input_history.items.len);

    // Navigate up
    state.navigateHistory(-1);
    try testing.expectEqualStrings("third", state.input_buffer.items);

    state.navigateHistory(-1);
    try testing.expectEqualStrings("second", state.input_buffer.items);

    state.navigateHistory(-1);
    try testing.expectEqualStrings("first", state.input_buffer.items);

    // Try to go before first (should stay at first)
    state.navigateHistory(-1);
    try testing.expectEqualStrings("first", state.input_buffer.items);

    // Navigate down
    state.navigateHistory(1);
    try testing.expectEqualStrings("second", state.input_buffer.items);

    // Navigate past end (should clear)
    state.navigateHistory(1);
    state.navigateHistory(1);
    try testing.expectEqualStrings("", state.input_buffer.items);
}

test "text insertion at cursor" {
    var state = try AppState.init(testing.allocator, "http://localhost:4000");
    defer state.deinit();

    try state.insertText("hello");
    state.input_cursor = 0;
    try state.insertText("X");
    try testing.expectEqualStrings("Xhello", state.input_buffer.items);
    try testing.expectEqual(@as(usize, 1), state.input_cursor);

    state.input_cursor = 3;
    try state.insertText("Y");
    try testing.expectEqualStrings("XheYllo", state.input_buffer.items);
    try testing.expectEqual(@as(usize, 4), state.input_cursor);
}

test "composer helper methods" {
    var state = try AppState.init(testing.allocator, "http://localhost:4000");
    defer state.deinit();

    var composer = Composer{
        .state = &state,
    };

    // isEmpty
    try testing.expect(composer.isEmpty());

    try state.insertText("hello");
    try testing.expect(!composer.isEmpty());

    // getText
    try testing.expectEqualStrings("hello", composer.getText());

    // clear
    composer.clear();
    try testing.expect(composer.isEmpty());
    try testing.expectEqualStrings("", composer.getText());
}
