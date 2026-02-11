//! CodexClient stub: emits streaming chat events for SMITHERS_ACTION_CHAT_SEND.
const std = @import("std");
const capi = @import("capi.zig");
const configpkg = @import("config.zig");

pub fn streamChat(runtime: configpkg.RuntimeConfig, message: []const u8) void {
    _ = message; // unused in stub
    // Spawn a background thread that emits 2–4 deltas then a completion event.
    const Spawn = struct {
        fn run(rt: configpkg.RuntimeConfig) void {
            // 3 fixed chunks to satisfy ">=2" for tests.
            const chunks = [_][]const u8{ "Thinking… ", "Okay. ", "Done." };
            if (rt.action) |cb| {
                for (chunks) |ch| {
                    cb(rt.userdata, .event_chat_delta, ch.ptr, ch.len);
                    std.posix.nanosleep(0, 10 * std.time.ns_per_ms);
                }
                cb(rt.userdata, .event_turn_complete, null, 0);
            }
        }
    };
    // Ignore spawn errors in stub; production should handle errors.
    const th = std.Thread.spawn(.{}, Spawn.run, .{runtime}) catch return;
    th.detach();
}

test "streaming emits >=2 deltas then complete" {
    const testing = std.testing;
    const Ctx = struct {
        mutex: std.Thread.Mutex = .{},
        delta_count: u32 = 0,
        complete_count: u32 = 0,
        deltas_before_complete: u32 = 0,
        fn cb(userdata: ?*anyopaque, tag: capi.smithers_action_tag_e, data: ?[*]const u8, len: usize) callconv(.c) void {
            _ = data;
            _ = len;
            const self: *@This() = @ptrCast(@alignCast(userdata.?));
            self.mutex.lock();
            defer self.mutex.unlock();
            switch (tag) {
                .event_chat_delta => self.delta_count += 1,
                .event_turn_complete => {
                    self.complete_count += 1;
                    self.deltas_before_complete = self.delta_count;
                },
                else => {},
            }
        }
    };

    var ctx: Ctx = .{};
    const rt: configpkg.RuntimeConfig = .{ .action = Ctx.cb, .userdata = @ptrCast(&ctx) };
    streamChat(rt, "hi");

    // Wait until completion fires or timeout (500ms)
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        {
            ctx.mutex.lock();
            const done = ctx.complete_count == 1;
            ctx.mutex.unlock();
            if (done) break;
        }
        std.posix.nanosleep(0, 5 * std.time.ns_per_ms);
    }

    ctx.mutex.lock();
    defer ctx.mutex.unlock();
    try testing.expectEqual(@as(u32, 1), ctx.complete_count);
    try testing.expect(ctx.delta_count >= 2);
    try testing.expect(ctx.deltas_before_complete >= 2);
}
