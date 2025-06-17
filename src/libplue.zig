const std = @import("std");
const ghostty_terminal = @import("ghostty_terminal");
const terminal = @import("terminal");
const state_mod = @import("state");
const AppState = state_mod.AppState;
const cstate = state_mod.cstate;

/// Simple global state - just use GPA directly
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var app_state: ?*AppState = null;

/// Callback function type for state updates
pub const StateUpdateCallback = ?*const fn () callconv(.C) void;
var state_update_callback: StateUpdateCallback = null;

/// Initialize the global state
export fn plue_init() c_int {
    const allocator = gpa.allocator();
    app_state = AppState.init(allocator) catch return -1;
    return 0;
}

/// Cleanup all resources
export fn plue_deinit() void {
    if (app_state) |state| {
        state.deinit();
        app_state = null;
    }
    _ = gpa.deinit();
}

/// Get current state as C struct
/// Returns: CAppState struct - caller MUST call plue_free_state() when done
export fn plue_get_state() AppState.CAppState {
    const state = app_state orelse return std.mem.zeroes(AppState.CAppState);
    return state.toCAppState() catch return std.mem.zeroes(AppState.CAppState);
}

/// Free resources allocated in CAppState
export fn plue_free_state(c_state: AppState.CAppState) void {
    var mutable_state = c_state;
    cstate.deinit(&mutable_state, gpa.allocator());
}

/// Process an event with JSON data
/// Returns: 0 on success, -1 on error
export fn plue_process_event(event_type: c_int, json_data: ?[*:0]const u8) c_int {
    const state = app_state orelse return -1;
    const data_ptr = json_data orelse return -1;
    const data = std.mem.span(data_ptr);

    // Create event data
    var event = state_mod.Event{
        .type = @enumFromInt(event_type),
    };

    // Parse additional JSON data if provided
    if (data.len > 0) {
        // For simple string values, just use the data directly
        // In a real implementation, we'd parse JSON properly
        event.string_value = data;
    }

    // Process the event
    state.process(&event) catch return -1;
    
    // Notify Swift of state change
    notifyStateChange();
    
    return 0;
}

/// Get error message from last operation
export fn plue_get_error() ?[*:0]const u8 {
    return null; // TODO: Implement error tracking
}

/// Register a callback for state updates
export fn plue_register_state_callback(callback: StateUpdateCallback) void {
    state_update_callback = callback;
}

/// Notify Swift of state changes
pub fn notifyStateChange() void {
    if (state_update_callback) |callback| {
        callback();
    }
}

// Terminal functions
export fn terminal_init() c_int {
    return terminal.terminal_init();
}

export fn terminal_start() c_int {
    return terminal.terminal_start();
}

export fn terminal_stop() void {
    terminal.terminal_stop();
}

export fn terminal_deinit() void {
    terminal.terminal_deinit();
}

export fn terminal_send_text(text: [*:0]const u8) void {
    terminal.terminal_send_text(text);
}

export fn terminal_resize(cols: c_ushort, rows: c_ushort) void {
    terminal.terminal_resize(cols, rows);
}

export fn terminal_get_fd() c_int {
    return terminal.terminal_get_fd();
}

export fn terminal_read(buffer: [*]u8, size: usize) isize {
    return terminal.terminal_read(buffer, size);
}