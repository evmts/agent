const std = @import("std");
const PromptState = @import("prompt_state.zig");
const TerminalState = @import("terminal_state.zig");
const WebState = @import("web_state.zig");
const VimState = @import("vim_state.zig");
const AgentState = @import("agent_state.zig");
const FarcasterState = @import("farcaster_state.zig");
const EditorState = @import("editor_state.zig");
const AppState = @import("state.zig");

pub const CAppState = extern struct {
    current_tab: AppState.Tab,
    is_initialized: bool,
    error_message: [*:0]const u8,
    openai_available: bool,
    current_theme: AppState.Theme,

    prompt: PromptState.CPromptState,
    terminal: TerminalState.CTerminalState,
    web: WebState.CWebState,
    vim: VimState.CVimState,
    agent: AgentState.CAgentState,
    farcaster: FarcasterState.CFarcasterState,
    editor: EditorState.CEditorState,
};

// C-compatible application state
pub fn fromApp(app: *const AppState) !CAppState {
    // Helper function to convert slice to null-terminated string
    const toNullTerminated = struct {
        fn convert(alloc: std.mem.Allocator, slice: []const u8) ![*:0]const u8 {
            const result = try alloc.allocSentinel(u8, slice.len, 0);
            @memcpy(result, slice);
            return result;
        }
    }.convert;

    return CAppState{
        .current_tab = app.current_tab,
        .is_initialized = app.is_initialized,
        .error_message = if (app.error_message) |msg| try toNullTerminated(app.allocator, msg) else try toNullTerminated(app.allocator, ""),
        .openai_available = app.openai_available,
        .current_theme = app.current_theme,
        .prompt = .{
            .processing = app.prompt.processing,
            .current_content = try toNullTerminated(app.allocator, app.prompt.current_content),
        },
        .terminal = .{
            .rows = app.terminal.rows,
            .cols = app.terminal.cols,
            .content = try toNullTerminated(app.allocator, app.terminal.content),
            .is_running = app.terminal.is_running,
        },
        .web = .{
            .can_go_back = app.web.can_go_back,
            .can_go_forward = app.web.can_go_forward,
            .is_loading = app.web.is_loading,
            .current_url = try toNullTerminated(app.allocator, app.web.current_url),
            .page_title = try toNullTerminated(app.allocator, app.web.page_title),
        },
        .vim = .{
            .mode = app.vim.mode,
            .content = try toNullTerminated(app.allocator, app.vim.content),
            .cursor_row = app.vim.cursor_row,
            .cursor_col = app.vim.cursor_col,
            .status_line = try toNullTerminated(app.allocator, app.vim.status_line),
        },
        .agent = .{
            .processing = app.agent.processing,
            .dagger_connected = app.agent.dagger_connected,
        },
        .farcaster = .{
            .selected_channel = try toNullTerminated(app.allocator, app.farcaster.selected_channel),
            .is_loading = app.farcaster.is_loading,
            .is_posting = app.farcaster.is_posting,
        },
        .editor = .{
            .file_path = try toNullTerminated(app.allocator, app.editor.file_path),
            .content = try toNullTerminated(app.allocator, app.editor.content),
            .is_modified = app.editor.is_modified,
        },
    };
}

pub fn deinit(self: *CAppState, allocator: std.mem.Allocator) void {
    // Free all allocated strings
    // Always free error_message since we always allocate it now
    allocator.free(std.mem.span(self.error_message));
    allocator.free(std.mem.span(self.prompt.current_content));
    allocator.free(std.mem.span(self.terminal.content));
    allocator.free(std.mem.span(self.web.current_url));
    allocator.free(std.mem.span(self.web.page_title));
    allocator.free(std.mem.span(self.vim.content));
    allocator.free(std.mem.span(self.vim.status_line));
    allocator.free(std.mem.span(self.farcaster.selected_channel));
    allocator.free(std.mem.span(self.editor.file_path));
    allocator.free(std.mem.span(self.editor.content));
}
