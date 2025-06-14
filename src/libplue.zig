const std = @import("std");

/// This global state is necessary so we can expose a C API
/// We should not use it for anything else but the C API
pub const GlobalState = struct {
    allocator: std.mem.Allocator,
    initialized: bool,

    pub fn init(allocator: std.mem.Allocator) GlobalState {
        return GlobalState{
            .allocator = allocator,
            .initialized = true,
        };
    }

    pub fn deinit(self: *GlobalState) void {
        self.initialized = false;
    }

    pub fn processMessage(self: *GlobalState, message: []const u8) ?[]const u8 {
        return try std.fmt.allocPrint(self.allocator, "Echo: {s}", .{message});
    }
};

// C API exports
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var global_state: ?GlobalState = null;

export fn plue_init() c_int {
    const allocator = gpa.allocator();
    global_state = GlobalState
        .init(allocator);
    return if (global_state != null) 0 else -1;
}

export fn plue_deinit() void {
    var s = global_state orelse return;
    s.deinit();
    global_state = null;
    _ = gpa.deinit();
}

export fn plue_process_message(message: [*:0]const u8) [*:0]const u8 {
    var s = global_state orelse return "";
    const msg = std.mem.span(message);
    const response = s.processMessage(msg) catch unreachable;
    defer s.allocator.free(response);
    const c_str = s.allocator.dupeZ(u8, response) catch return "";
    return c_str.ptr;
}

export fn plue_free_string(str: [*:0]const u8) void {
    var s = global_state orelse unreachable;
    s.allocator.free(std.mem.span(str));
}
