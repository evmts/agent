//! Action definitions: tags and payloads for smithers lib.
const std = @import("std");

/// Action tags used by the C API boundary.
pub const Tag = enum(u32) {
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

/// Tagged payload union. Each variant corresponds to an action.Tag.
/// Keep fields compact and platform-agnostic.
pub const Payload = union(Tag) {
    chat_send: struct { message: []const u8 },
    workspace_open: struct { path: []const u8 },
    workspace_close: void,
    agent_spawn: struct { task: []const u8 },
    agent_cancel: struct { id: u64 },
    file_save: struct { path: []const u8, content: []const u8 },
    file_open: struct { path: []const u8, line: u32 = 0, column: u32 = 0 },
    search: struct { query: []const u8 },
    jj_commit: struct { description: []const u8 },
    jj_undo: void,
    settings_change: struct { key: []const u8, value: []const u8 },
    suggestion_refresh: void,
    status: void,
    // events
    event_chat_delta: struct { text: []const u8 },
    event_turn_complete: void,
};

// No helper needed: use @tagName(tag) directly at call sites.

// Ensure all decls compile for discovery.
test {
    std.testing.refAllDecls(@This());
}
