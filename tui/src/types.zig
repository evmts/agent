const std = @import("std");

/// Connection state for the TUI client
pub const ConnectionState = enum {
    disconnected,
    connecting,
    connected,
    reconnecting,
    err,
};

/// UI mode for the application
pub const UiMode = enum {
    chat, // Normal chat mode
    model_select, // Selecting model
    session_select, // Selecting session
    file_search, // File picker
    approval, // Approval overlay
    help, // Help screen
};

/// Token usage tracking
pub const TokenUsage = struct {
    input: u64 = 0,
    output: u64 = 0,
    cached: u64 = 0,

    /// Calculate total tokens used (input + output)
    pub fn total(self: TokenUsage) u64 {
        return self.input + self.output;
    }
};
