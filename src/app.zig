const std = @import("std");

pub const AppEvent = union(enum) {
    chat_message_sent: []const u8,
    tab_switched: TabType,
    farcaster_post_created: struct {
        content: []const u8,
        channel: []const u8,
    },
    window_resized: struct {
        width: u32,
        height: u32,
    },
};

pub const TabType = enum {
    chat,
    terminal,
    farcaster,
    vim,
    metrics,
    settings,
};

pub const AppState = struct {
    current_tab: TabType = .chat,
    
    pub fn processEvent(self: *AppState, event: AppEvent) void {
        switch (event) {
            .tab_switched => |tab| {
                self.current_tab = tab;
            },
            else => {
                // Handle other events as needed
            },
        }
    }
};