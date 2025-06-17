const std = @import("std");
const testing = std.testing;
const app = @import("app");
const app_event = @import("app");

test "toCApp converts AppState to CAppState correctly" {
    const allocator = testing.allocator;

    // Create an AppState
    const state = try app.init(allocator);
    defer state.deinit();

    // Convert to CAppState
    const c_state = try state.toCApp(allocator);
    defer app.freeCApp(c_state, allocator);

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

    const state = try app.init(allocator);
    defer state.deinit();

    const c_state = try state.toCApp(allocator);
    defer app.freeCApp(c_state, allocator);

    // error_message should be empty string when null
    try testing.expectEqualStrings("", std.mem.span(c_state.error_message));
}

test "toCApp handles non-null error_message correctly" {
    const allocator = testing.allocator;

    const state = try app.init(allocator);
    defer state.deinit();

    // Set an error message
    state.error_message = try allocator.dupe(u8, "Test error");

    const c_state = try state.toCApp(allocator);
    defer app.freeCApp(c_state, allocator);

    // error_message should contain the expected text
    try testing.expectEqualStrings("Test error", std.mem.span(c_state.error_message));
}

test "freeCApp properly frees allocated memory" {
    const allocator = testing.allocator;

    const state = try app.init(allocator);
    defer state.deinit();

    // Set an error message to test null pointer handling
    state.error_message = try allocator.dupe(u8, "Test error");

    const c_state = try state.toCApp(allocator);

    // This should not leak memory
    app.freeCApp(c_state, allocator);
}

test "processEvent handles tab switching" {
    const allocator = testing.allocator;

    const state = try app.init(allocator);
    defer state.deinit();

    // Initial tab should be prompt
    try testing.expectEqual(app.TabType.prompt, state.current_tab);

    // Switch to terminal tab
    const event = app.EventData{
        .type = .tab_switched,
        .int_value = @intFromEnum(app.TabType.terminal),
    };
    try state.processEvent(event);

    try testing.expectEqual(app.TabType.terminal, state.current_tab);
}

test "processEvent handles theme toggling" {
    const allocator = testing.allocator;

    const state = try app.init(allocator);
    defer state.deinit();

    // Initial theme should be dark
    try testing.expectEqual(app.Theme.dark, state.current_theme);

    // Toggle theme
    const event = app.EventData{
        .type = .theme_toggled,
    };
    try state.processEvent(event);

    try testing.expectEqual(app.Theme.light, state.current_theme);

    // Toggle again
    try state.processEvent(event);
    try testing.expectEqual(app.Theme.dark, state.current_theme);
}

test "processEvent handles terminal input" {
    const allocator = testing.allocator;

    const state = try app.init(allocator);
    defer state.deinit();

    // Initial terminal content should be empty
    try testing.expectEqualStrings("", state.terminal.content);

    // Send some input
    const event = app.EventData{
        .type = .terminal_input,
        .string_value = "Hello, Terminal!",
    };
    try state.processEvent(event);

    try testing.expectEqualStrings("Hello, Terminal!", state.terminal.content);

    // Send more input
    const event2 = app.EventData{
        .type = .terminal_input,
        .string_value = " More text",
    };
    try state.processEvent(event2);

    try testing.expectEqualStrings("Hello, Terminal! More text", state.terminal.content);
}

test "processEvent handles terminal resize" {
    const allocator = testing.allocator;

    const state = try app.init(allocator);
    defer state.deinit();

    // Initial size
    try testing.expectEqual(@as(u32, 24), state.terminal.rows);
    try testing.expectEqual(@as(u32, 80), state.terminal.cols);

    // Resize terminal
    const event = app.EventData{
        .type = .terminal_resize,
        .int_value = 40,
        .int_value2 = 120,
    };
    try state.processEvent(event);

    try testing.expectEqual(@as(u32, 40), state.terminal.rows);
    try testing.expectEqual(@as(u32, 120), state.terminal.cols);
}

test "processEvent handles prompt content update" {
    const allocator = testing.allocator;

    const state = try app.init(allocator);
    defer state.deinit();

    const new_content = "# Updated Prompt\n\nNew content here";
    const event = app.EventData{
        .type = .prompt_content_updated,
        .string_value = new_content,
    };
    try state.processEvent(event);

    try testing.expectEqualStrings(new_content, state.prompt.current_content);
}

test "processEvent handles prompt message sent" {
    const allocator = testing.allocator;

    const state = try app.init(allocator);
    defer state.deinit();

    // Initially not processing
    try testing.expectEqual(false, state.prompt.processing);

    const event = app.EventData{
        .type = .prompt_message_sent,
    };
    try state.processEvent(event);

    // Should be processing after sending message
    try testing.expectEqual(true, state.prompt.processing);
}

test "processEvent handles agent events" {
    const allocator = testing.allocator;

    const state = try app.init(allocator);
    defer state.deinit();

    // Test agent message sent
    try testing.expectEqual(false, state.agent.processing);
    
    const event1 = app.EventData{
        .type = .agent_message_sent,
    };
    try state.processEvent(event1);
    try testing.expectEqual(true, state.agent.processing);

    // Test dagger session start
    try testing.expectEqual(false, state.agent.dagger_connected);
    
    const event2 = app.EventData{
        .type = .agent_start_dagger_session,
    };
    try state.processEvent(event2);
    try testing.expectEqual(true, state.agent.dagger_connected);

    // Test dagger session stop
    const event3 = app.EventData{
        .type = .agent_stop_dagger_session,
    };
    try state.processEvent(event3);
    try testing.expectEqual(false, state.agent.dagger_connected);
}

test "processEvent handles vim keypress" {
    const allocator = testing.allocator;

    const state = try app.init(allocator);
    defer state.deinit();

    // Initial vim content should be empty
    try testing.expectEqualStrings("", state.vim.content);

    // Send keypress
    const event = app.EventData{
        .type = .vim_keypress,
        .string_value = "i",
    };
    try state.processEvent(event);

    try testing.expectEqualStrings("i", state.vim.content);

    // Send more keypresses
    const event2 = app.EventData{
        .type = .vim_keypress,
        .string_value = "Hello",
    };
    try state.processEvent(event2);

    try testing.expectEqualStrings("iHello", state.vim.content);
}

test "processEvent handles vim set content" {
    const allocator = testing.allocator;

    const state = try app.init(allocator);
    defer state.deinit();

    const new_content = "This is new vim content";
    const event = app.EventData{
        .type = .vim_set_content,
        .string_value = new_content,
    };
    try state.processEvent(event);

    try testing.expectEqualStrings(new_content, state.vim.content);
}

test "processEvent handles web navigation" {
    const allocator = testing.allocator;

    const state = try app.init(allocator);
    defer state.deinit();

    // Initial URL
    try testing.expectEqualStrings("https://www.apple.com", state.web.current_url);
    try testing.expectEqual(false, state.web.is_loading);

    // Navigate to new URL
    const new_url = "https://www.google.com";
    const event = app.EventData{
        .type = .web_navigate,
        .string_value = new_url,
    };
    try state.processEvent(event);

    try testing.expectEqualStrings(new_url, state.web.current_url);
    try testing.expectEqual(true, state.web.is_loading);
}

test "processEvent handles web back/forward/reload" {
    const allocator = testing.allocator;

    const state = try app.init(allocator);
    defer state.deinit();

    // Test go back
    state.web.can_go_back = true;
    const event1 = app.EventData{
        .type = .web_go_back,
    };
    try state.processEvent(event1);
    try testing.expectEqual(false, state.web.can_go_back);

    // Test go forward
    state.web.can_go_forward = true;
    const event2 = app.EventData{
        .type = .web_go_forward,
    };
    try state.processEvent(event2);
    try testing.expectEqual(false, state.web.can_go_forward);

    // Test reload
    state.web.is_loading = false;
    const event3 = app.EventData{
        .type = .web_reload,
    };
    try state.processEvent(event3);
    try testing.expectEqual(true, state.web.is_loading);
}
