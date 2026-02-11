//! App: root libsmithers object. Owns allocators and runtime config.
const std = @import("std");
const Allocator = std.mem.Allocator;
const configpkg = @import("config.zig");
const action = @import("action.zig");
const codex = @import("codex_client.zig");
const log = std.log.scoped(.app);

const App = @This();

/// Primary allocator for this instance.
alloc: Allocator,
/// Arena for app-owned allocations.
arena: std.heap.ArenaAllocator,
/// Runtime callbacks provided by host.
runtime: configpkg.RuntimeConfig,

pub const CreateError = Allocator.Error;

/// Allocate and initialize a new App.
pub fn create(alloc: Allocator, runtime: configpkg.RuntimeConfig) CreateError!*App {
    var self = try alloc.create(App);
    errdefer alloc.destroy(self);
    try self.init(alloc, runtime);
    return self;
}

/// Initialize an already-allocated App.
pub fn init(self: *App, alloc: Allocator, runtime: configpkg.RuntimeConfig) CreateError!void {
    self.* = .{
        .alloc = alloc,
        .arena = std.heap.ArenaAllocator.init(alloc),
        .runtime = runtime,
    };
}

/// Free resources but not the allocation itself.
pub fn deinit(self: *App) void {
    self.arena.deinit();
    self.* = undefined; // poison for use-after-free detection
}

/// Destroy (free) this instance.
pub fn destroy(self: *App) void {
    const a = self.alloc;
    self.deinit();
    a.destroy(self);
}

/// Handle an action from the UI layer. Stub for now.
pub fn performAction(self: *App, payload: action.Payload) void {
    const tag = std.meta.activeTag(payload);
    // For now just log; wire real routing later.
    log.info("performAction tag={s}", .{@tagName(tag)});
    switch (payload) {
        .chat_send => |cs| {
            // Arena-dupe not needed in stub: pass slice directly to streamer.
            // Streaming occurs on a background thread and does not mutate
            // synchronous state here.
            codex.streamChat(self.runtime, cs.message);
        },
        else => {
            // For actions that synchronously mutate observable state (none in
            // this stub), the host expects a wakeup. Left in place for future
            // cases.
            if (self.runtime.wakeup) |cb| cb(self.runtime.userdata);
        },
    }
}

/// Convenience: get an arena-backed allocator for request-scoped work.
pub fn arenaAllocator(self: *App) Allocator {
    return self.arena.allocator();
}

test "app create/destroy" {
    const testing = std.testing;
    var a = try App.create(testing.allocator, .{});
    defer a.destroy();
}

test "app does not wakeup on chat_send (no sync state change)" {
    const testing = std.testing;
    var called: bool = false;
    const Wake = struct {
        fn cb(userdata: ?*anyopaque) callconv(.c) void {
            const p: *bool = @ptrCast(@alignCast(userdata.?));
            p.* = true;
        }
    };
    var a = try App.create(testing.allocator, .{ .wakeup = Wake.cb, .userdata = @ptrCast(&called) });
    defer a.destroy();
    a.performAction(.{ .chat_send = .{ .message = "hi" } });
    try testing.expect(!called);
}

test {
    std.testing.refAllDecls(@This());
}
