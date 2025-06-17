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
            if (event.string_value) |message| {
                state.prompt.processing = true;
                // Store the message for AI processing
                const new_message = try state.allocator.dupe(u8, message);
                state.allocator.free(state.prompt.last_message);
                state.prompt.last_message = new_message;
                // In production, this would trigger OpenAI API call
            }
        },
        .agent_message_sent => {
            if (event.string_value) |message| {
                state.agent.processing = true;
                // Store message for agent processing
                const new_message = try state.allocator.dupe(u8, message);
                state.allocator.free(state.agent.last_message);
                state.agent.last_message = new_message;
            }
        },
        .agent_start_dagger_session => {
            state.agent.dagger_connected = true;
        },
        .agent_stop_dagger_session => {
            state.agent.dagger_connected = false;
        },
        .vim_keypress => {
            if (event.string_value) |key| {
                // Handle vim key events based on current mode
                switch (state.vim.mode) {
                    .insert => {
                        // In insert mode, append to content
                        const new_content = try std.fmt.allocPrint(state.allocator, "{s}{s}", .{ state.vim.content, key });
                        state.allocator.free(state.vim.content);
                        state.vim.content = new_content;
                        state.vim.cursor_col += 1;
                    },
                    .normal => {
                        // Handle normal mode commands
                        if (std.mem.eql(u8, key, "i")) {
                            state.vim.mode = .insert;
                            try updateVimStatusLine(state, "-- INSERT --");
                        } else if (std.mem.eql(u8, key, "v")) {
                            state.vim.mode = .visual;
                            try updateVimStatusLine(state, "-- VISUAL --");
                        } else if (std.mem.eql(u8, key, ":")) {
                            state.vim.mode = .command;
                            try updateVimStatusLine(state, ":");
                        }
                        // Handle movement keys
                        else if (std.mem.eql(u8, key, "h") and state.vim.cursor_col > 0) {
                            state.vim.cursor_col -= 1;
                        } else if (std.mem.eql(u8, key, "l")) {
                            state.vim.cursor_col += 1;
                        } else if (std.mem.eql(u8, key, "j") and state.vim.cursor_row < 50) {
                            state.vim.cursor_row += 1;
                        } else if (std.mem.eql(u8, key, "k") and state.vim.cursor_row > 0) {
                            state.vim.cursor_row -= 1;
                        }
                    },
                    .visual => {
                        // Handle visual mode
                        if (std.mem.eql(u8, key, "ESC")) {
                            state.vim.mode = .normal;
                            try updateVimStatusLine(state, "");
                        }
                    },
                    .command => {
                        // Handle command mode
                        if (std.mem.eql(u8, key, "ESC")) {
                            state.vim.mode = .normal;
                            try updateVimStatusLine(state, "");
                        } else if (std.mem.eql(u8, key, "ENTER")) {
                            // Execute command
                            state.vim.mode = .normal;
                            try updateVimStatusLine(state, "");
                        } else {
                            // Append to command line
                            const new_status = try std.fmt.allocPrint(state.allocator, "{s}{s}", .{ state.vim.status_line, key });
                            state.allocator.free(state.vim.status_line);
                            state.vim.status_line = new_status;
                        }
                    },
                }
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
        .farcaster_select_channel => {
            if (event.string_value) |channel| {
                const new_channel = try state.allocator.dupe(u8, channel);
                state.allocator.free(state.farcaster.selected_channel);
                state.farcaster.selected_channel = new_channel;
            }
        },
        .farcaster_create_post => {
            if (event.string_value) |_| {
                state.farcaster.is_posting = true;
                // In production, this would call Farcaster API
            }
        },
        .farcaster_refresh_feed => {
            state.farcaster.is_loading = true;
        },
        .editor_content_changed => {
            if (event.string_value) |content| {
                const new_content = try state.allocator.dupe(u8, content);
                state.allocator.free(state.editor.content);
                state.editor.content = new_content;
                state.editor.is_modified = true;
            }
        },
        .editor_save => {
            state.editor.is_modified = false;
            // In production, save to file system
        },
        .file_opened => {
            if (event.string_value) |path| {
                const new_path = try state.allocator.dupe(u8, path);
                state.allocator.free(state.editor.file_path);
                state.editor.file_path = new_path;
                state.editor.is_modified = false;
            }
        },
        .prompt_new_conversation => {
            state.prompt.conversation_count += 1;
            state.prompt.current_conversation_index = state.prompt.conversation_count - 1;
        },
        .prompt_select_conversation => {
            if (event.int_value) |index| {
                state.prompt.current_conversation_index = @intCast(index);
            }
        },
        .agent_new_conversation => {
            state.agent.conversation_count += 1;
            state.agent.current_conversation_index = state.agent.conversation_count - 1;
        },
        .agent_select_conversation => {
            if (event.int_value) |index| {
                state.agent.current_conversation_index = @intCast(index);
            }
        },
        else => {
            // Log unhandled events in debug mode
            std.log.debug("Unhandled event type: {}", .{event.type});
        },
    }
}

fn updateVimStatusLine(state: *AppState, status: []const u8) !void {
    const new_status = try state.allocator.dupe(u8, status);
    state.allocator.free(state.vim.status_line);
    state.vim.status_line = new_status;
}
