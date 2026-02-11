//! C boundary type definitions (extern) mirroring include/libsmithers.h.
const std = @import("std");
const action = @import("action.zig");

pub const smithers_string_s = extern struct { ptr: ?[*]const u8, len: usize };

// Callback typedefs and runtime config passed from C/Swift side.
pub const smithers_wakeup_cb = *const fn (userdata: ?*anyopaque) callconv(.c) void;
pub const smithers_action_cb = *const fn (
    userdata: ?*anyopaque,
    tag: smithers_action_tag_e,
    data: ?[*]const u8,
    len: usize,
) callconv(.c) void;

pub const smithers_runtime_config_s = extern struct {
    wakeup: ?smithers_wakeup_cb = null,
    action: ?smithers_action_cb = null,
    userdata: ?*anyopaque = null,
};

/// Top-level app configuration passed at creation.
pub const smithers_config_s = extern struct {
    runtime: smithers_runtime_config_s,
};

pub const smithers_action_tag_e = enum(u32) {
    chat_send,
    workspace_open,
    workspace_close,
    agent_spawn,
    agent_cancel,
    file_save,
    file_open,
    search,
    jj_commit,
    jj_undo,
    settings_change,
    suggestion_refresh,
    status,
    // events (Zig -> host)
    event_chat_delta,
    event_turn_complete,
};

pub const smithers_action_payload_u = extern union {
    // string payloads (ptr,len)
    chat_send: smithers_string_s,
    workspace_open: smithers_string_s,
    agent_spawn: smithers_string_s,
    search: smithers_string_s,
    jj_commit: smithers_string_s,

    // complex structs
    file_open: extern struct { path: smithers_string_s, line: u32, column: u32 },
    file_save: extern struct { path: smithers_string_s, content: smithers_string_s },
    settings_change: extern struct { key: smithers_string_s, value: smithers_string_s },

    // integral/void-like (pad to avoid zero-size extern structs across ABIs)
    agent_cancel: extern struct { id: u64 },
    workspace_close: extern struct { _pad: u8 = 0 },
    jj_undo: extern struct { _pad: u8 = 0 },
    suggestion_refresh: extern struct { _pad: u8 = 0 },
    status: extern struct { _pad: u8 = 0 },
};

// Keep smithers_action_tag_e in lockstep with internal action.Tag.
comptime {
    const t_internal = @typeInfo(action.Tag).@"enum";
    const t_c = @typeInfo(smithers_action_tag_e).@"enum";
    std.debug.assert(t_internal.fields.len == t_c.fields.len);
    for (t_internal.fields, 0..) |f, i| {
        std.debug.assert(std.mem.eql(u8, f.name, t_c.fields[i].name));
        std.debug.assert(@intFromEnum(@field(action.Tag, f.name)) == @intFromEnum(@field(smithers_action_tag_e, f.name)));
    }
}

// Compile-time discovery
test {
    std.testing.refAllDecls(@This());
}
