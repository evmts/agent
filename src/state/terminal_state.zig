rows: u32,
cols: u32,
content: []const u8,
is_running: bool,

pub const CTerminalState = extern struct {
    rows: u32,
    cols: u32,
    content: [*:0]const u8,
    is_running: bool,
};
