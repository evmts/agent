//! libsmithers root module (C API exports + public Zig API).
const std = @import("std");
const Allocator = std.mem.Allocator;
const App = @import("App.zig");
const configpkg = @import("config.zig");
const action = @import("action.zig");
const capi = @import("capi.zig");
const hostpkg = @import("host.zig");
const storagepkg = @import("storage.zig");

pub const ZigApi = struct {
    /// Preferred initializer: explicit allocator per zig-rules.md.
    pub fn createWith(alloc: Allocator, runtime: configpkg.RuntimeConfig) !*App {
        return App.create(alloc, runtime);
    }

    pub fn destroy(app: *App) void {
        app.destroy();
    }
    pub fn perform(app: *App, payload: action.Payload) void {
        app.performAction(payload);
    }
};

/// C-compatible API exports. Follow libghostty pattern (force-export block).
pub const CAPI = struct {
    pub export fn smithers_app_new(c_config: ?*const capi.smithers_config_s) callconv(.c) ?*App {
        var runtime_cfg: configpkg.RuntimeConfig = .{};
        if (c_config) |c| {
            const r = c.runtime;
            runtime_cfg = .{ .wakeup = r.wakeup, .action = r.action, .userdata = r.userdata };
        }
        return App.create(std.heap.page_allocator, runtime_cfg) catch null;
    }

    pub export fn smithers_app_free(app: ?*App) callconv(.c) void {
        if (app) |a| a.destroy();
    }

    pub export fn smithers_app_action(app: *App, tag: capi.smithers_action_tag_e, payload: capi.smithers_action_payload_u) callconv(.c) void {
        const zig_tag: action.Tag = @enumFromInt(@intFromEnum(tag));
        const pl = payloadFromC(zig_tag, payload);
        app.performAction(pl);
    }
};

/// Convert C API payload to Zig action payload based on the tag.
fn cStringToSlice(c: capi.smithers_string_s) []const u8 {
    if (c.len == 0) return &[_]u8{};
    if (c.ptr) |p| return p[0..c.len];
    return &[_]u8{};
}

fn payloadFromC(tag: action.Tag, payload: capi.smithers_action_payload_u) action.Payload {
    return switch (tag) {
        .chat_send => .{ .chat_send = .{ .message = cStringToSlice(payload.chat_send) } },
        .workspace_open => .{ .workspace_open = .{ .path = cStringToSlice(payload.workspace_open) } },
        .workspace_close => .{ .workspace_close = {} },
        .agent_spawn => .{ .agent_spawn = .{ .task = cStringToSlice(payload.agent_spawn) } },
        .agent_cancel => .{ .agent_cancel = .{ .id = payload.agent_cancel.id } },
        .file_save => .{ .file_save = .{ .path = cStringToSlice(payload.file_save.path), .content = cStringToSlice(payload.file_save.content) } },
        .file_open => .{ .file_open = .{ .path = cStringToSlice(payload.file_open.path), .line = payload.file_open.line, .column = payload.file_open.column } },
        .search => .{ .search = .{ .query = cStringToSlice(payload.search) } },
        .jj_commit => .{ .jj_commit = .{ .description = cStringToSlice(payload.jj_commit) } },
        .jj_undo => .{ .jj_undo = {} },
        .settings_change => .{ .settings_change = .{ .key = cStringToSlice(payload.settings_change.key), .value = cStringToSlice(payload.settings_change.value) } },
        .suggestion_refresh => .{ .suggestion_refresh = {} },
        .status => .{ .status = {} },
        // Events are not expected over C->Zig dispatch; map to empty payloads to satisfy exhaustiveness.
        .event_chat_delta => .{ .event_chat_delta = .{ .text = &[_]u8{} } },
        .event_turn_complete => .{ .event_turn_complete = {} },
    };
}

test "cStringToSlice edge cases" {
    const testing = std.testing;
    // non-null ptr with zero len — should return empty slice
    const one = "x";
    const zero_len = capi.smithers_string_s{ .ptr = one.ptr, .len = 0 };
    try testing.expectEqual(@as(usize, 0), cStringToSlice(zero_len).len);
}

test "payloadFromC chat_send maps correctly" {
    const msg = "hi";
    var p: capi.smithers_action_payload_u = undefined;
    p.chat_send = .{ .ptr = msg.ptr, .len = msg.len };
    const out = payloadFromC(.chat_send, p);
    switch (out) {
        .chat_send => |cs| try std.testing.expectEqualStrings(msg, cs.message),
        else => return error.UnexpectedTag,
    }
}

test "payloadFromC all variants mapping" {
    // workspace_open
    var p1: capi.smithers_action_payload_u = undefined;
    const w = "/tmp";
    p1.workspace_open = .{ .ptr = w.ptr, .len = w.len };
    _ = payloadFromC(.workspace_open, p1);
    // workspace_close
    var p2: capi.smithers_action_payload_u = undefined;
    p2.workspace_close = .{ ._pad = 0 };
    _ = payloadFromC(.workspace_close, p2);
    // agent_spawn
    var p3: capi.smithers_action_payload_u = undefined;
    const task = "do it";
    p3.agent_spawn = .{ .ptr = task.ptr, .len = task.len };
    _ = payloadFromC(.agent_spawn, p3);
    // agent_cancel
    var p4: capi.smithers_action_payload_u = undefined;
    p4.agent_cancel = .{ .id = 42 };
    _ = payloadFromC(.agent_cancel, p4);
    // file_open
    var p5: capi.smithers_action_payload_u = undefined;
    const path = "a.zig";
    p5.file_open = .{ .path = .{ .ptr = path.ptr, .len = path.len }, .line = 10, .column = 2 };
    _ = payloadFromC(.file_open, p5);
    // file_save
    var p6: capi.smithers_action_payload_u = undefined;
    const body = "x";
    p6.file_save = .{ .path = .{ .ptr = path.ptr, .len = path.len }, .content = .{ .ptr = body.ptr, .len = body.len } };
    _ = payloadFromC(.file_save, p6);
    // search
    var p7: capi.smithers_action_payload_u = undefined;
    const q = "hello";
    p7.search = .{ .ptr = q.ptr, .len = q.len };
    _ = payloadFromC(.search, p7);
    // jj_commit
    var p8: capi.smithers_action_payload_u = undefined;
    const d = "fix: x";
    p8.jj_commit = .{ .ptr = d.ptr, .len = d.len };
    _ = payloadFromC(.jj_commit, p8);
    // jj_undo
    var p9: capi.smithers_action_payload_u = undefined;
    p9.jj_undo = .{ ._pad = 0 };
    _ = payloadFromC(.jj_undo, p9);
    // settings_change
    var p10: capi.smithers_action_payload_u = undefined;
    const k = "theme";
    const v = "dark";
    p10.settings_change = .{ .key = .{ .ptr = k.ptr, .len = k.len }, .value = .{ .ptr = v.ptr, .len = v.len } };
    _ = payloadFromC(.settings_change, p10);
    // suggestion_refresh
    var p11: capi.smithers_action_payload_u = undefined;
    p11.suggestion_refresh = .{ ._pad = 0 };
    _ = payloadFromC(.suggestion_refresh, p11);
    // status
    var p12: capi.smithers_action_payload_u = undefined;
    p12.status = .{ ._pad = 0 };
    _ = payloadFromC(.status, p12);
}

test {
    std.testing.refAllDecls(@This());
}

// Ensure host module is compiled as part of this build (avoids unreachable
// code masking errors). We reference all decls for coverage.
test "host module is reachable" {
    std.testing.refAllDecls(hostpkg);
}

test "storage module is reachable" {
    std.testing.refAllDecls(storagepkg);
}

// Force-export all CAPI functions to prevent dead code elimination when
// building a static library (libghostty pattern).
comptime {
    for (@typeInfo(CAPI).@"struct".decls) |decl| {
        _ = &@field(CAPI, decl.name);
    }
}
