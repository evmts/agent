const std = @import("std");
const testing = std.testing;
const AppState = @import("state/state.zig");
const Event = @import("state/event.zig");
const cstate = @import("state/cstate.zig");

test "AppState initialization and deinitialization" {
    const allocator = testing.allocator;
    
    const state = try AppState.init(allocator);
    defer state.deinit();
    
    // Verify initial state
    try testing.expectEqual(AppState.Tab.prompt, state.current_tab);
    try testing.expectEqual(true, state.is_initialized);
    try testing.expectEqual(@as(?[]const u8, null), state.error_message);
    try testing.expectEqual(false, state.openai_available);
    try testing.expectEqual(AppState.Theme.dark, state.current_theme);
}

test "AppState toCAppState conversion" {
    const allocator = testing.allocator;
    
    const state = try AppState.init(allocator);
    defer state.deinit();
    
    const c_state = try state.toCAppState();
    defer cstate.deinit(&c_state, allocator);
    
    // Verify the conversion worked
    try testing.expectEqual(@intFromEnum(AppState.Tab.prompt), @intFromEnum(c_state.current_tab));
    try testing.expectEqual(true, c_state.is_initialized);
    try testing.expectEqual(false, c_state.openai_available);
    try testing.expectEqual(@intFromEnum(AppState.Theme.dark), @intFromEnum(c_state.current_theme));
}

test "Event processing - tab switching" {
    const allocator = testing.allocator;
    
    const state = try AppState.init(allocator);
    defer state.deinit();
    
    // Create tab switch event
    const event = Event{
        .type = .tab_switched,
        .int_value = @intFromEnum(AppState.Tab.terminal),
    };
    
    try state.process(&event);
    
    try testing.expectEqual(AppState.Tab.terminal, state.current_tab);
}

test "Event processing - theme toggling" {
    const allocator = testing.allocator;
    
    const state = try AppState.init(allocator);
    defer state.deinit();
    
    // Initial theme should be dark
    try testing.expectEqual(AppState.Theme.dark, state.current_theme);
    
    // Toggle theme
    const event = Event{
        .type = .theme_toggled,
    };
    
    try state.process(&event);
    try testing.expectEqual(AppState.Theme.light, state.current_theme);
    
    // Toggle again
    try state.process(&event);
    try testing.expectEqual(AppState.Theme.dark, state.current_theme);
}

test "Event processing - terminal input" {
    const allocator = testing.allocator;
    
    const state = try AppState.init(allocator);
    defer state.deinit();
    
    // Send terminal input
    const event = Event{
        .type = .terminal_input,
        .string_value = "test input",
    };
    
    try state.process(&event);
    
    try testing.expectEqualStrings("test input", state.terminal.content);
}

test "Event processing - terminal resize" {
    const allocator = testing.allocator;
    
    const state = try AppState.init(allocator);
    defer state.deinit();
    
    const event = Event{
        .type = .terminal_resize,
        .int_value = 50,
        .int_value2 = 100,
    };
    
    try state.process(&event);
    
    try testing.expectEqual(@as(u32, 50), state.terminal.rows);
    try testing.expectEqual(@as(u32, 100), state.terminal.cols);
}

test "Event processing - prompt content update" {
    const allocator = testing.allocator;
    
    const state = try AppState.init(allocator);
    defer state.deinit();
    
    const new_content = "Updated prompt content";
    const event = Event{
        .type = .prompt_content_updated,
        .string_value = new_content,
    };
    
    try state.process(&event);
    
    try testing.expectEqualStrings(new_content, state.prompt.current_content);
}

test "Event processing - prompt message sent" {
    const allocator = testing.allocator;
    
    const state = try AppState.init(allocator);
    defer state.deinit();
    
    // Initially not processing
    try testing.expectEqual(false, state.prompt.processing);
    
    const event = Event{
        .type = .prompt_message_sent,
    };
    
    try state.process(&event);
    
    // Should be processing after event
    try testing.expectEqual(true, state.prompt.processing);
}

test "Event processing - agent events" {
    const allocator = testing.allocator;
    
    const state = try AppState.init(allocator);
    defer state.deinit();
    
    // Test agent message sent
    const event1 = Event{
        .type = .agent_message_sent,
    };
    try state.process(&event1);
    try testing.expectEqual(true, state.agent.processing);
    
    // Test dagger session start
    const event2 = Event{
        .type = .agent_start_dagger_session,
    };
    try state.process(&event2);
    try testing.expectEqual(true, state.agent.dagger_connected);
    
    // Test dagger session stop
    const event3 = Event{
        .type = .agent_stop_dagger_session,
    };
    try state.process(&event3);
    try testing.expectEqual(false, state.agent.dagger_connected);
}

test "Event processing - vim keypress" {
    const allocator = testing.allocator;
    
    const state = try AppState.init(allocator);
    defer state.deinit();
    
    const event = Event{
        .type = .vim_keypress,
        .string_value = "i",
    };
    
    try state.process(&event);
    
    try testing.expectEqualStrings("i", state.vim.content);
}

test "Event processing - vim set content" {
    const allocator = testing.allocator;
    
    const state = try AppState.init(allocator);
    defer state.deinit();
    
    const new_content = "New vim content";
    const event = Event{
        .type = .vim_set_content,
        .string_value = new_content,
    };
    
    try state.process(&event);
    
    try testing.expectEqualStrings(new_content, state.vim.content);
}

test "Event processing - web navigation" {
    const allocator = testing.allocator;
    
    const state = try AppState.init(allocator);
    defer state.deinit();
    
    const new_url = "https://example.com";
    const event = Event{
        .type = .web_navigate,
        .string_value = new_url,
    };
    
    try state.process(&event);
    
    try testing.expectEqualStrings(new_url, state.web.current_url);
    try testing.expectEqual(true, state.web.is_loading);
}

test "Event processing - web back/forward/reload" {
    const allocator = testing.allocator;
    
    const state = try AppState.init(allocator);
    defer state.deinit();
    
    // Test go back
    state.web.can_go_back = true;
    const event1 = Event{
        .type = .web_go_back,
    };
    try state.process(&event1);
    try testing.expectEqual(false, state.web.can_go_back);
    
    // Test go forward
    state.web.can_go_forward = true;
    const event2 = Event{
        .type = .web_go_forward,
    };
    try state.process(&event2);
    try testing.expectEqual(false, state.web.can_go_forward);
    
    // Test reload
    state.web.is_loading = false;
    const event3 = Event{
        .type = .web_reload,
    };
    try state.process(&event3);
    try testing.expectEqual(true, state.web.is_loading);
}

test "Event processing - unknown event type" {
    const allocator = testing.allocator;
    
    const state = try AppState.init(allocator);
    defer state.deinit();
    
    // Use an event type that falls into the else case
    const event = Event{
        .type = .file_opened,
        .string_value = "test.txt",
    };
    
    // Should not error out
    try state.process(&event);
}