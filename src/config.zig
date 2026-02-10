//! Configuration types for libsmithers runtime.
const std = @import("std");
const capi = @import("capi.zig");

/// Wakeup callback signature. Zig calls this when state was updated.
pub const WakeupFn = *const fn (userdata: ?*anyopaque) callconv(.c) void;

/// Action callback signature. Zig notifies host about specific events.
pub const ActionFn = *const fn (
    userdata: ?*anyopaque,
    tag: capi.smithers_action_tag_e,
    data: ?[*]const u8,
    len: usize,
) callconv(.c) void;

/// Runtime configuration passed at app creation time.
pub const RuntimeConfig = struct {
    wakeup: ?WakeupFn = null,
    action: ?ActionFn = null,
    userdata: ?*anyopaque = null,
};

test "config instantiate" {
    const testing = std.testing;
    const cfg: RuntimeConfig = .{};
    try testing.expect(cfg.wakeup == null and cfg.action == null and cfg.userdata == null);
}

// Self test discovery only.
test {
    std.testing.refAllDecls(@This());
}
