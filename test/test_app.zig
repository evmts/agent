const std = @import("std");
const testing = std.testing;
const app = @import("app");

test "toCApp converts AppState to CAppState correctly" {
    const allocator = testing.allocator;

    // Create an AppState
    const state = try app.AppState.init(allocator);
    defer state.deinit();

    // Convert to CAppState
    const c_state = try state.toCApp(allocator);
    defer app.AppState.freeCApp(c_state, allocator);

    // Verify basic fields
    try testing.expectEqual(app.TabType.prompt, c_state.current_tab);
    try testing.expectEqual(true, c_state.is_initialized);
    try testing.expectEqual(false, c_state.openai_available);
    try testing.expectEqual(app.Theme.dark, c_state.current_theme);

    // Verify prompt state
    try testing.expectEqual(false, c_state.prompt.processing);
    try testing.expectEqualStrings("# Your Prompt\n\nStart typing your prompt here.", std.mem.span(c_state.prompt.current_content));

    // Verify terminal state
    try testing.expectEqual(@as(u32, 24), c_state.terminal.rows);
    try testing.expectEqual(@as(u32, 80), c_state.terminal.cols);
    try testing.expectEqual(false, c_state.terminal.is_running);
    try testing.expectEqualStrings("", std.mem.span(c_state.terminal.content));

    // Verify web state
    try testing.expectEqual(false, c_state.web.can_go_back);
    try testing.expectEqual(false, c_state.web.can_go_forward);
    try testing.expectEqual(false, c_state.web.is_loading);
    try testing.expectEqualStrings("https://www.apple.com", std.mem.span(c_state.web.current_url));
    try testing.expectEqualStrings("New Tab", std.mem.span(c_state.web.page_title));

    // Verify vim state
    try testing.expectEqual(app.VimMode.normal, c_state.vim.mode);
    try testing.expectEqualStrings("", std.mem.span(c_state.vim.content));
    try testing.expectEqual(@as(u32, 0), c_state.vim.cursor_row);
    try testing.expectEqual(@as(u32, 0), c_state.vim.cursor_col);
    try testing.expectEqualStrings("-- NORMAL --", std.mem.span(c_state.vim.status_line));

    // Verify agent state
    try testing.expectEqual(false, c_state.agent.processing);
    try testing.expectEqual(false, c_state.agent.dagger_connected);
}

test "toCApp handles null error_message correctly" {
    const allocator = testing.allocator;

    const state = try app.AppState.init(allocator);
    defer state.deinit();

    const c_state = try state.toCApp(allocator);
    defer app.AppState.freeCApp(c_state, allocator);

    // error_message should be empty string when null
    try testing.expectEqualStrings("", std.mem.span(c_state.error_message));
}

test "toCApp handles non-null error_message correctly" {
    const allocator = testing.allocator;

    const state = try app.AppState.init(allocator);
    defer state.deinit();

    // Set an error message
    state.error_message = try allocator.dupe(u8, "Test error");

    const c_state = try state.toCApp(allocator);
    defer app.AppState.freeCApp(c_state, allocator);

    // error_message should contain the expected text
    try testing.expectEqualStrings("Test error", std.mem.span(c_state.error_message));
}

test "freeCApp properly frees allocated memory" {
    const allocator = testing.allocator;

    const state = try app.AppState.init(allocator);
    defer state.deinit();

    // Set an error message to test null pointer handling
    state.error_message = try allocator.dupe(u8, "Test error");

    const c_state = try state.toCApp(allocator);
    
    // This should not leak memory
    app.AppState.freeCApp(c_state, allocator);
}