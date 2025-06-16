const std = @import("std");

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

pub const PromptState = struct {
    processing: bool,
    current_content: []const u8,
};

pub const TerminalState = struct {
    rows: u32,
    cols: u32,
    content: []const u8,
    is_running: bool,
};

pub const WebState = struct {
    can_go_back: bool,
    can_go_forward: bool,
    is_loading: bool,
    current_url: []const u8,
    page_title: []const u8,
};

pub const VimState = struct {
    mode: VimMode,
    content: []const u8,
    cursor_row: u32,
    cursor_col: u32,
    status_line: []const u8,
};

pub const AgentState = struct {
    processing: bool,
    dagger_connected: bool,
};

// C-compatible state structs
pub const CPromptState = extern struct {
    processing: bool,
    current_content: [*:0]const u8,
};

pub const CTerminalState = extern struct {
    rows: u32,
    cols: u32,
    content: [*:0]const u8,
    is_running: bool,
};

pub const CWebState = extern struct {
    can_go_back: bool,
    can_go_forward: bool,
    is_loading: bool,
    current_url: [*:0]const u8,
    page_title: [*:0]const u8,
};

pub const CVimState = extern struct {
    mode: VimMode,
    content: [*:0]const u8,
    cursor_row: u32,
    cursor_col: u32,
    status_line: [*:0]const u8,
};

pub const CAgentState = extern struct {
    processing: bool,
    dagger_connected: bool,
};

// C-compatible application state
pub const CAppState = extern struct {
    current_tab: TabType,
    is_initialized: bool,
    error_message: [*:0]const u8,
    openai_available: bool,
    current_theme: Theme,
    
    prompt: CPromptState,
    terminal: CTerminalState,
    web: CWebState,
    vim: CVimState,
    agent: CAgentState,
};

// Core application state
pub const AppState = struct {
    current_tab: TabType,
    is_initialized: bool,
    error_message: ?[]const u8,
    openai_available: bool,
    current_theme: Theme,

    prompt: PromptState,
    terminal: TerminalState,
    web: WebState,
    vim: VimState,
    agent: AgentState,

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !*AppState {
        const state = try allocator.create(AppState);
        state.* = .{
            .current_tab = .prompt,
            .is_initialized = true,
            .error_message = null,
            .openai_available = false,
            .current_theme = .dark,
            .prompt = .{
                .processing = false,
                .current_content = try allocator.dupe(u8, "# Your Prompt\n\nStart typing your prompt here."),
            },
            .terminal = .{
                .rows = 24,
                .cols = 80,
                .content = try allocator.dupe(u8, ""),
                .is_running = false,
            },
            .web = .{
                .can_go_back = false,
                .can_go_forward = false,
                .is_loading = false,
                .current_url = try allocator.dupe(u8, "https://www.apple.com"),
                .page_title = try allocator.dupe(u8, "New Tab"),
            },
            .vim = .{
                .mode = .normal,
                .content = try allocator.dupe(u8, ""),
                .cursor_row = 0,
                .cursor_col = 0,
                .status_line = try allocator.dupe(u8, "-- NORMAL --"),
            },
            .agent = .{
                .processing = false,
                .dagger_connected = false,
            },
            .allocator = allocator,
        };
        return state;
    }

    pub fn deinit(self: *AppState) void {
        if (self.error_message) |msg| {
            self.allocator.free(msg);
        }
        self.allocator.free(self.prompt.current_content);
        self.allocator.free(self.terminal.content);
        self.allocator.free(self.web.current_url);
        self.allocator.free(self.web.page_title);
        self.allocator.free(self.vim.content);
        self.allocator.free(self.vim.status_line);
        self.allocator.destroy(self);
    }

    pub fn toCApp(self: *const AppState, allocator: std.mem.Allocator) !CAppState {
        // Helper function to convert slice to null-terminated string
        const toNullTerminated = struct {
            fn convert(alloc: std.mem.Allocator, slice: []const u8) ![*:0]const u8 {
                const result = try alloc.allocSentinel(u8, slice.len, 0);
                @memcpy(result, slice);
                return result;
            }
        }.convert;

        return CAppState{
            .current_tab = self.current_tab,
            .is_initialized = self.is_initialized,
            .error_message = if (self.error_message) |msg| try toNullTerminated(allocator, msg) else @as([*:0]const u8, @ptrCast("")),
            .openai_available = self.openai_available,
            .current_theme = self.current_theme,
            .prompt = .{
                .processing = self.prompt.processing,
                .current_content = try toNullTerminated(allocator, self.prompt.current_content),
            },
            .terminal = .{
                .rows = self.terminal.rows,
                .cols = self.terminal.cols,
                .content = try toNullTerminated(allocator, self.terminal.content),
                .is_running = self.terminal.is_running,
            },
            .web = .{
                .can_go_back = self.web.can_go_back,
                .can_go_forward = self.web.can_go_forward,
                .is_loading = self.web.is_loading,
                .current_url = try toNullTerminated(allocator, self.web.current_url),
                .page_title = try toNullTerminated(allocator, self.web.page_title),
            },
            .vim = .{
                .mode = self.vim.mode,
                .content = try toNullTerminated(allocator, self.vim.content),
                .cursor_row = self.vim.cursor_row,
                .cursor_col = self.vim.cursor_col,
                .status_line = try toNullTerminated(allocator, self.vim.status_line),
            },
            .agent = .{
                .processing = self.agent.processing,
                .dagger_connected = self.agent.dagger_connected,
            },
        };
    }

    pub fn freeCApp(c_state: CAppState, allocator: std.mem.Allocator) void {
        // Free all allocated strings
        // Check if error_message is not the empty string literal
        if (std.mem.span(c_state.error_message).len > 0) {
            allocator.free(std.mem.span(c_state.error_message));
        }
        allocator.free(std.mem.span(c_state.prompt.current_content));
        allocator.free(std.mem.span(c_state.terminal.content));
        allocator.free(std.mem.span(c_state.web.current_url));
        allocator.free(std.mem.span(c_state.web.page_title));
        allocator.free(std.mem.span(c_state.vim.content));
        allocator.free(std.mem.span(c_state.vim.status_line));
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
