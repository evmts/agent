const std = @import("std");
const ghostty_terminal = @import("ghostty_terminal");
const terminal = @import("terminal");
const AppState = @import("state/state.zig");
const cstate = @import("state/cstate.zig");

/// Simple global state - just use GPA directly
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var app_state: ?*AppState = null;

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
    var event = AppState.Event{
        .type = @enumFromInt(event_type),
    };

    // Parse additional JSON data if provided
    if (data.len > 0) {
        // For simple string values, just use the data directly
        // In a real implementation, we'd parse JSON properly
        event.string_value = data;
    }

    state.process(&event) catch return -1;
    return 0;
}

/// Process message and return response (deprecated, use plue_process_event)
/// Returns: owned null-terminated string - caller MUST call plue_free_string()
export fn plue_process_message(message: ?[*:0]const u8) ?[*:0]const u8 {
    const msg_ptr = message orelse return null;
    const msg = std.mem.span(msg_ptr);
    if (msg.len == 0 or msg.len > 10 * 1024) {
        return null;
    }
    const allocator = gpa.allocator();
    const response = std.fmt.allocPrintZ(allocator, "Echo: {s}", .{msg}) catch return null;
    return response.ptr;
}

/// Free string allocated by plue functions
export fn plue_free_string(str: [*:0]const u8) void {
    gpa.allocator().free(std.mem.span(str));
}

// Re-export Ghostty terminal functions for Swift FFI
pub usingnamespace ghostty_terminal;

// Re-export unified terminal functions for Swift FFI
pub usingnamespace terminal;
