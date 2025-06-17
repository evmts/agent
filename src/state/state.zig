const std = @import("std");
const PromptState = @import("prompt_state.zig");
const TerminalState = @import("terminal_state.zig");
const WebState = @import("web_state.zig");
const VimState = @import("vim_state.zig");
const AgentState = @import("agent_state.zig");
const FarcasterState = @import("farcaster_state.zig");
const EditorState = @import("editor_state.zig");

// Core application state
pub const AppState = @This();

// A C compatible version of AppState
const cstate = @import("cstate.zig");
pub const CAppState = cstate.CAppState;
pub fn toCAppState(self: *const AppState) !CAppState {
    return cstate.fromApp(self);
}

// Events that can be dispatched to AppState.process
pub const Event = @import("event.zig");
pub fn process(self: *AppState, event: *const Event) !void {
    return event.process(self);
}

current_tab: Tab,
is_initialized: bool,
error_message: ?[]const u8,
openai_available: bool,
current_theme: Theme,

prompt: PromptState,
terminal: TerminalState,
web: WebState,
vim: VimState,
agent: AgentState,
farcaster: FarcasterState,
editor: EditorState,

allocator: std.mem.Allocator,

pub const Tab = enum(c_int) {
    prompt = 0,
    farcaster = 1,
    agent = 2,
    terminal = 3,
    web = 4,
    editor = 5,
    diff = 6,
    worktree = 7,
};
pub const Theme = enum(c_int) {
    dark = 0,
    light = 1,
};

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
            .last_message = try allocator.dupe(u8, ""),
            .conversation_count = 1,
            .current_conversation_index = 0,
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
            .last_message = try allocator.dupe(u8, ""),
            .conversation_count = 1,
            .current_conversation_index = 0,
        },
        .farcaster = .{
            .selected_channel = try allocator.dupe(u8, "home"),
            .is_loading = false,
            .is_posting = false,
        },
        .editor = .{
            .file_path = try allocator.dupe(u8, ""),
            .content = try allocator.dupe(u8, ""),
            .is_modified = false,
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
    self.allocator.free(self.prompt.last_message);
    self.allocator.free(self.terminal.content);
    self.allocator.free(self.web.current_url);
    self.allocator.free(self.web.page_title);
    self.allocator.free(self.vim.content);
    self.allocator.free(self.vim.status_line);
    self.allocator.free(self.agent.last_message);
    self.allocator.free(self.farcaster.selected_channel);
    self.allocator.free(self.editor.file_path);
    self.allocator.free(self.editor.content);
    self.allocator.destroy(self);
}
