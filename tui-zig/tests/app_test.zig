const std = @import("std");
const testing = std.testing;

const App = @import("../src/app.zig").App;
const AppState = @import("../src/state/app_state.zig").AppState;
const PlueClient = @import("../src/client/client.zig").PlueClient;
const EventQueue = @import("../src/client/sse.zig").EventQueue;
const types = @import("../src/types.zig");

test "App initialization" {
    const allocator = testing.allocator;

    var state = try AppState.init(allocator, "http://localhost:4000");
    defer state.deinit();

    var client = PlueClient.init(allocator, "http://localhost:4000");
    defer client.deinit();

    var event_queue = EventQueue.init(allocator);
    defer event_queue.deinit();

    var app = App.init(&state, &client, &event_queue);

    // Verify widget can be created
    const widget = app.widget();
    try testing.expect(widget.userdata != null);
    try testing.expect(widget.eventHandler != null);
    try testing.expect(widget.drawFn != null);
}

test "Mode switching" {
    const allocator = testing.allocator;

    var state = try AppState.init(allocator, "http://localhost:4000");
    defer state.deinit();

    // Start in chat mode
    try testing.expectEqual(types.UiMode.chat, state.mode);

    // Switch to help mode
    state.mode = .help;
    try testing.expectEqual(types.UiMode.help, state.mode);

    // Switch to model_select
    state.mode = .model_select;
    try testing.expectEqual(types.UiMode.model_select, state.mode);

    // Back to chat
    state.mode = .chat;
    try testing.expectEqual(types.UiMode.chat, state.mode);
}

test "Input buffer operations" {
    const allocator = testing.allocator;

    var state = try AppState.init(allocator, "http://localhost:4000");
    defer state.deinit();

    // Initial state
    try testing.expectEqual(@as(usize, 0), state.input_buffer.items.len);
    try testing.expectEqual(@as(usize, 0), state.input_cursor);

    // Insert text
    try state.insertText("hello");
    try testing.expectEqualStrings("hello", state.getInput());
    try testing.expectEqual(@as(usize, 5), state.input_cursor);

    // Insert more text
    try state.insertText(" world");
    try testing.expectEqualStrings("hello world", state.getInput());
    try testing.expectEqual(@as(usize, 11), state.input_cursor);

    // Clear input
    state.clearInput();
    try testing.expectEqual(@as(usize, 0), state.input_buffer.items.len);
    try testing.expectEqual(@as(usize, 0), state.input_cursor);
}

test "Cursor movement" {
    const allocator = testing.allocator;

    var state = try AppState.init(allocator, "http://localhost:4000");
    defer state.deinit();

    try state.insertText("hello");
    try testing.expectEqual(@as(usize, 5), state.input_cursor);

    // Move left
    state.moveCursor(-2);
    try testing.expectEqual(@as(usize, 3), state.input_cursor);

    // Move right
    state.moveCursor(1);
    try testing.expectEqual(@as(usize, 4), state.input_cursor);

    // Move to start (clamped)
    state.moveCursor(-100);
    try testing.expectEqual(@as(usize, 0), state.input_cursor);

    // Move to end (clamped)
    state.moveCursor(100);
    try testing.expectEqual(@as(usize, 5), state.input_cursor);
}

test "Delete operations" {
    const allocator = testing.allocator;

    var state = try AppState.init(allocator, "http://localhost:4000");
    defer state.deinit();

    try state.insertText("hello");
    try testing.expectEqualStrings("hello", state.getInput());

    // Delete backward
    state.deleteBackward();
    try testing.expectEqualStrings("hell", state.getInput());
    try testing.expectEqual(@as(usize, 4), state.input_cursor);

    // Move cursor to middle
    state.moveCursor(-2);
    try testing.expectEqual(@as(usize, 2), state.input_cursor);

    // Delete forward
    state.deleteForward();
    try testing.expectEqualStrings("hel", state.getInput());
    try testing.expectEqual(@as(usize, 2), state.input_cursor);
}

test "History navigation" {
    const allocator = testing.allocator;

    var state = try AppState.init(allocator, "http://localhost:4000");
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

    // Navigate back
    state.navigateHistory(-1);
    try testing.expectEqualStrings("third", state.getInput());

    state.navigateHistory(-1);
    try testing.expectEqualStrings("second", state.getInput());

    state.navigateHistory(-1);
    try testing.expectEqualStrings("first", state.getInput());

    // Can't go back further (clamped)
    state.navigateHistory(-1);
    try testing.expectEqualStrings("first", state.getInput());

    // Navigate forward
    state.navigateHistory(1);
    try testing.expectEqualStrings("second", state.getInput());

    state.navigateHistory(1);
    try testing.expectEqualStrings("third", state.getInput());

    // At end, clears input
    state.navigateHistory(1);
    try testing.expectEqual(@as(usize, 0), state.input_buffer.items.len);
}

test "Connection state transitions" {
    const allocator = testing.allocator;

    var state = try AppState.init(allocator, "http://localhost:4000");
    defer state.deinit();

    // Initial state
    try testing.expectEqual(types.ConnectionState.disconnected, state.connection);

    // Connecting
    state.connection = .connecting;
    try testing.expectEqual(types.ConnectionState.connecting, state.connection);

    // Connected
    state.connection = .connected;
    try testing.expectEqual(types.ConnectionState.connected, state.connection);

    // Error
    try state.setError("Test error");
    try testing.expectEqual(types.ConnectionState.err, state.connection);
    try testing.expect(state.last_error != null);
    try testing.expectEqualStrings("Test error", state.last_error.?);

    // Clear error
    state.clearError();
    try testing.expect(state.last_error == null);
    try testing.expectEqual(types.ConnectionState.disconnected, state.connection);
}

test "EventQueue push and pop" {
    const allocator = testing.allocator;
    const StreamEvent = @import("../src/client/protocol.zig").StreamEvent;

    var queue = EventQueue.init(allocator);
    defer queue.deinit();

    try testing.expect(queue.isEmpty());

    // Push event
    const event = StreamEvent{ .done = {} };
    queue.push(event);

    try testing.expect(!queue.isEmpty());
    try testing.expectEqual(@as(usize, 1), queue.len());

    // Pop event
    const popped = queue.pop();
    try testing.expect(popped != null);
    try testing.expect(popped.? == .done);

    try testing.expect(queue.isEmpty());
}

test "Selected index bounds" {
    const allocator = testing.allocator;

    var state = try AppState.init(allocator, "http://localhost:4000");
    defer state.deinit();

    // Initial index
    try testing.expectEqual(@as(usize, 0), state.selected_index);

    // Can increment
    state.selected_index += 1;
    try testing.expectEqual(@as(usize, 1), state.selected_index);

    // Can set to arbitrary value
    state.selected_index = 5;
    try testing.expectEqual(@as(usize, 5), state.selected_index);

    // Reset
    state.selected_index = 0;
    try testing.expectEqual(@as(usize, 0), state.selected_index);
}

test "Token usage tracking" {
    const allocator = testing.allocator;

    var state = try AppState.init(allocator, "http://localhost:4000");
    defer state.deinit();

    // Initial values
    try testing.expectEqual(@as(u64, 0), state.token_usage.input);
    try testing.expectEqual(@as(u64, 0), state.token_usage.output);
    try testing.expectEqual(@as(u64, 0), state.token_usage.cached);

    // Update values
    state.token_usage.input = 100;
    state.token_usage.output = 50;
    state.token_usage.cached = 25;

    try testing.expectEqual(@as(u64, 100), state.token_usage.input);
    try testing.expectEqual(@as(u64, 50), state.token_usage.output);
    try testing.expectEqual(@as(u64, 25), state.token_usage.cached);

    // Total
    try testing.expectEqual(@as(u64, 150), state.token_usage.total());
}
