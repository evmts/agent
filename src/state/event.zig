const std = @import("std");
const AppState = @import("state.zig");

pub const Event = @This();

type: EventType,
string_value: ?[]const u8 = null,
int_value: ?i32 = null,
int_value2: ?i32 = null,

pub const EventType = enum(c_int) {
    tab_switched = 0,
    theme_toggled = 1,
    terminal_input = 2,
    terminal_resize = 3,
    vim_keypress = 4,
    vim_set_content = 5,
    web_navigate = 6,
    web_go_back = 7,
    web_go_forward = 8,
    web_reload = 9,
    editor_content_changed = 10,
    editor_save = 11,
    farcaster_select_channel = 12,
    farcaster_like_post = 13,
    farcaster_recast_post = 14,
    farcaster_reply_to_post = 15,
    farcaster_create_post = 16,
    farcaster_refresh_feed = 17,
    prompt_message_sent = 18,
    prompt_content_updated = 19,
    prompt_new_conversation = 20,
    prompt_select_conversation = 21,
    agent_message_sent = 22,
    agent_new_conversation = 23,
    agent_select_conversation = 24,
    agent_create_worktree = 25,
    agent_switch_worktree = 26,
    agent_delete_worktree = 27,
    agent_refresh_worktrees = 28,
    agent_start_dagger_session = 29,
    agent_stop_dagger_session = 30,
    agent_execute_workflow = 31,
    agent_cancel_workflow = 32,
    chat_message_sent = 33,
    file_opened = 34,
    file_saved = 35,
};

// Handle process events into state
pub fn process(event: *const Event, state: *AppState) !void {
    switch (event.type) {
        .tab_switched => {
            if (event.int_value) |tab_index| {
                state.current_tab = @enumFromInt(tab_index);
            }
        },
        .theme_toggled => {
            state.current_theme = if (state.current_theme == .dark) .light else .dark;
        },
        .terminal_input => {
            if (event.string_value) |input| {
                // Process terminal input
                const new_content = try std.fmt.allocPrint(state.allocator, "{s}{s}", .{ state.terminal.content, input });
                state.allocator.free(state.terminal.content);
                state.terminal.content = new_content;
            }
        },
        .terminal_resize => {
            if (event.int_value) |rows| {
                if (event.int_value2) |cols| {
                    state.terminal.rows = @intCast(rows);
                    state.terminal.cols = @intCast(cols);
                }
            }
        },
        .prompt_content_updated => {
            if (event.string_value) |content| {
                const new_content = try state.allocator.dupe(u8, content);
                state.allocator.free(state.prompt.current_content);
                state.prompt.current_content = new_content;
            }
        },
        .prompt_message_sent => {
            state.prompt.processing = true;
            // In a real implementation, this would trigger AI processing
            // For now, we'll just toggle the processing state
        },
        .agent_message_sent => {
            state.agent.processing = true;
        },
        .agent_start_dagger_session => {
            state.agent.dagger_connected = true;
        },
        .agent_stop_dagger_session => {
            state.agent.dagger_connected = false;
        },
        .vim_keypress => {
            if (event.string_value) |key| {
                // Handle vim key events
                // For now, just update content as a placeholder
                const new_content = try std.fmt.allocPrint(state.allocator, "{s}{s}", .{ state.vim.content, key });
                state.allocator.free(state.vim.content);
                state.vim.content = new_content;
            }
        },
        .vim_set_content => {
            if (event.string_value) |content| {
                const new_content = try state.allocator.dupe(u8, content);
                state.allocator.free(state.vim.content);
                state.vim.content = new_content;
            }
        },
        .web_navigate => {
            if (event.string_value) |url| {
                const new_url = try state.allocator.dupe(u8, url);
                state.allocator.free(state.web.current_url);
                state.web.current_url = new_url;
                state.web.is_loading = true;
            }
        },
        .web_go_back => {
            state.web.can_go_back = false; // Will be updated by webview
        },
        .web_go_forward => {
            state.web.can_go_forward = false; // Will be updated by webview
        },
        .web_reload => {
            state.web.is_loading = true;
        },
        else => {
            // Handle other events as needed
        },
    }
}
