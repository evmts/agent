//! CodexClient stub: emits streaming chat events for SMITHERS_ACTION_CHAT_SEND.
const std = @import("std");
const log = std.log.scoped(.codex_client);
const capi = @import("capi.zig");
const configpkg = @import("config.zig");

/// Start streaming chat on a background thread and return it for tests.
pub fn streamChatJoinable(runtime: configpkg.RuntimeConfig, message: []const u8) !std.Thread {
    _ = message; // unused in stub
    const Spawn = struct {
        fn run(rt: configpkg.RuntimeConfig) void {
            const chunks = [_][]const u8{ "Thinking… ", "Okay. ", "Done." };
            if (rt.action) |cb| {
                for (chunks) |ch| {
                    cb(rt.userdata, .event_chat_delta, ch.ptr, ch.len);
                    std.Thread.sleep(10 * std.time.ns_per_ms);
                }
                cb(rt.userdata, .event_turn_complete, null, 0);
            }
        }
    };
    return try std.Thread.spawn(.{}, Spawn.run, .{runtime});
}

/// Convenience wrapper used in production: fire-and-forget.
pub fn streamChat(runtime: configpkg.RuntimeConfig, message: []const u8) void {
    if (streamChatJoinable(runtime, message)) |th| {
        th.detach();
    } else |err| {
        // Do not silently swallow errors; log for diagnostics per project rules.
        log.warn("failed to spawn chat thread err={}", .{err});
    }
}

test "streaming emits >=2 deltas then complete (deterministic join)" {
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
    const th = try streamChatJoinable(rt, "hi");
    th.join();

    ctx.mutex.lock();
    defer ctx.mutex.unlock();
    try testing.expectEqual(@as(u32, 1), ctx.complete_count);
    try testing.expect(ctx.delta_count >= 2);
    try testing.expect(ctx.deltas_before_complete >= 2);
}
