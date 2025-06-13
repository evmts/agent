const std = @import("std");

// Core library state
pub const PlueCore = struct {
    allocator: std.mem.Allocator,
    initialized: bool,

    pub fn init(allocator: std.mem.Allocator) PlueCore {
        return PlueCore{
            .allocator = allocator,
            .initialized = true,
        };
    }

    pub fn deinit(self: *PlueCore) void {
        self.initialized = false;
    }

    pub fn processMessage(self: *PlueCore, message: []const u8) ?[]const u8 {
        // Simple echo response for now
        const response = std.fmt.allocPrint(self.allocator, "Echo: {s}", .{message}) catch return null;
        return response;
    }
};

// C API exports
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var core: ?PlueCore = null;

export fn plue_init() c_int {
    const allocator = gpa.allocator();
    core = PlueCore.init(allocator);
    return if (core != null) 0 else -1;
}

export fn plue_deinit() void {
    if (core) |*c| {
        c.deinit();
        core = null;
    }
    _ = gpa.deinit();
}

export fn plue_process_message(message: [*:0]const u8) [*:0]const u8 {
    if (core) |*c| {
        const msg = std.mem.span(message);
        if (c.processMessage(msg)) |response| {
            // Convert to null-terminated string for C
            const c_str = c.allocator.dupeZ(u8, response) catch return "";
            c.allocator.free(response);
            return c_str.ptr;
        }
    }
    return "";
}

export fn plue_free_string(str: [*:0]const u8) void {
    if (core) |*c| {
        const slice = std.mem.span(str);
        c.allocator.free(slice);
    }
}