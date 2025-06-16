const std = @import("std");
const json = std.json;

// Tab types matching Swift TabType enum
pub const TabType = enum(c_int) {
    prompt = 0,
    farcaster = 1,
    agent = 2,
    terminal = 3,
    web = 4,
    editor = 5,
    diff = 6,
    worktree = 7,
};

// Theme types
pub const Theme = enum(c_int) {
    dark = 0,
    light = 1,
};

// Vim modes
pub const VimMode = enum(c_int) {
    normal = 0,
    insert = 1,
    visual = 2,
    command = 3,
};

// Message types
pub const MessageType = enum(c_int) {
    user = 0,
    assistant = 1,
    system = 2,
};

// Core application state
pub const AppState = struct {
    current_tab: TabType,
    is_initialized: bool,
    error_message: ?[]const u8,
    openai_available: bool,
    current_theme: Theme,
    
    // Prompt state
    prompt_processing: bool,
    prompt_current_content: []const u8,
    
    // Terminal state
    terminal_rows: u32,
    terminal_cols: u32,
    terminal_content: []const u8,
    terminal_is_running: bool,
    
    // Web state
    web_can_go_back: bool,
    web_can_go_forward: bool,
    web_is_loading: bool,
    web_current_url: []const u8,
    web_page_title: []const u8,
    
    // Vim state
    vim_mode: VimMode,
    vim_content: []const u8,
    vim_cursor_row: u32,
    vim_cursor_col: u32,
    vim_status_line: []const u8,
    
    // Agent state
    agent_processing: bool,
    agent_dagger_connected: bool,
    
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) !*AppState {
        const state = try allocator.create(AppState);
        state.* = .{
            .current_tab = .prompt,
            .is_initialized = true,
            .error_message = null,
            .openai_available = false,
            .current_theme = .dark,
            .prompt_processing = false,
            .prompt_current_content = try allocator.dupe(u8, "# Your Prompt\n\nStart typing your prompt here."),
            .terminal_rows = 24,
            .terminal_cols = 80,
            .terminal_content = try allocator.dupe(u8, ""),
            .terminal_is_running = false,
            .web_can_go_back = false,
            .web_can_go_forward = false,
            .web_is_loading = false,
            .web_current_url = try allocator.dupe(u8, "https://www.apple.com"),
            .web_page_title = try allocator.dupe(u8, "New Tab"),
            .vim_mode = .normal,
            .vim_content = try allocator.dupe(u8, ""),
            .vim_cursor_row = 0,
            .vim_cursor_col = 0,
            .vim_status_line = try allocator.dupe(u8, "-- NORMAL --"),
            .agent_processing = false,
            .agent_dagger_connected = false,
            .allocator = allocator,
        };
        return state;
    }
    
    pub fn deinit(self: *AppState) void {
        if (self.error_message) |msg| {
            self.allocator.free(msg);
        }
        self.allocator.free(self.prompt_current_content);
        self.allocator.free(self.terminal_content);
        self.allocator.free(self.web_current_url);
        self.allocator.free(self.web_page_title);
        self.allocator.free(self.vim_content);
        self.allocator.free(self.vim_status_line);
        self.allocator.destroy(self);
    }
    
    pub fn toJson(self: *const AppState, allocator: std.mem.Allocator) ![]const u8 {
        var string = std.ArrayList(u8).init(allocator);
        defer string.deinit();
        
        try json.stringify(.{
            .current_tab = @intFromEnum(self.current_tab),
            .is_initialized = self.is_initialized,
            .error_message = self.error_message,
            .openai_available = self.openai_available,
            .current_theme = @intFromEnum(self.current_theme),
            .prompt_processing = self.prompt_processing,
            .prompt_current_content = self.prompt_current_content,
            .terminal_rows = self.terminal_rows,
            .terminal_cols = self.terminal_cols,
            .terminal_content = self.terminal_content,
            .terminal_is_running = self.terminal_is_running,
            .web_can_go_back = self.web_can_go_back,
            .web_can_go_forward = self.web_can_go_forward,
            .web_is_loading = self.web_is_loading,
            .web_current_url = self.web_current_url,
            .web_page_title = self.web_page_title,
            .vim_mode = @intFromEnum(self.vim_mode),
            .vim_content = self.vim_content,
            .vim_cursor_row = self.vim_cursor_row,
            .vim_cursor_col = self.vim_cursor_col,
            .vim_status_line = self.vim_status_line,
            .agent_processing = self.agent_processing,
            .agent_dagger_connected = self.agent_dagger_connected,
        }, .{}, string.writer());
        
        return try string.toOwnedSlice();
    }
};

// Event types matching Swift AppEvent enum
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

// Event data passed from Swift
pub const EventData = struct {
    type: EventType,
    string_value: ?[]const u8 = null,
    int_value: ?i32 = null,
    int_value2: ?i32 = null,
    
    pub fn parse(json_str: []const u8, allocator: std.mem.Allocator) !EventData {
        const parsed = try json.parseFromSlice(EventData, allocator, json_str, .{});
        defer parsed.deinit();
        return parsed.value;
    }
};

// Process events and update state
pub fn processEvent(state: *AppState, event: EventData) !void {
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
                const new_content = try std.fmt.allocPrint(
                    state.allocator,
                    "{s}{s}",
                    .{ state.terminal_content, input }
                );
                state.allocator.free(state.terminal_content);
                state.terminal_content = new_content;
            }
        },
        .terminal_resize => {
            if (event.int_value) |rows| {
                if (event.int_value2) |cols| {
                    state.terminal_rows = @intCast(rows);
                    state.terminal_cols = @intCast(cols);
                }
            }
        },
        .prompt_content_updated => {
            if (event.string_value) |content| {
                const new_content = try state.allocator.dupe(u8, content);
                state.allocator.free(state.prompt_current_content);
                state.prompt_current_content = new_content;
            }
        },
        .prompt_message_sent => {
            state.prompt_processing = true;
            // In a real implementation, this would trigger AI processing
            // For now, we'll just toggle the processing state
        },
        .agent_message_sent => {
            state.agent_processing = true;
        },
        .agent_start_dagger_session => {
            state.agent_dagger_connected = true;
        },
        .agent_stop_dagger_session => {
            state.agent_dagger_connected = false;
        },
        .vim_keypress => {
            if (event.string_value) |key| {
                // Handle vim key events
                // For now, just update content as a placeholder
                const new_content = try std.fmt.allocPrint(
                    state.allocator,
                    "{s}{s}",
                    .{ state.vim_content, key }
                );
                state.allocator.free(state.vim_content);
                state.vim_content = new_content;
            }
        },
        .vim_set_content => {
            if (event.string_value) |content| {
                const new_content = try state.allocator.dupe(u8, content);
                state.allocator.free(state.vim_content);
                state.vim_content = new_content;
            }
        },
        .web_navigate => {
            if (event.string_value) |url| {
                const new_url = try state.allocator.dupe(u8, url);
                state.allocator.free(state.web_current_url);
                state.web_current_url = new_url;
                state.web_is_loading = true;
            }
        },
        .web_go_back => {
            state.web_can_go_back = false; // Will be updated by webview
        },
        .web_go_forward => {
            state.web_can_go_forward = false; // Will be updated by webview
        },
        .web_reload => {
            state.web_is_loading = true;
        },
        else => {
            // Handle other events as needed
        },
    }
}