mode: VimMode,
content: []const u8,
cursor_row: u32,
cursor_col: u32,
status_line: []const u8,

pub const VimMode = enum(c_int) {
    normal = 0,
    insert = 1,
    visual = 2,
    command = 3,
};

pub const CVimState = extern struct {
    mode: VimMode,
    content: [*:0]const u8,
    cursor_row: u32,
    cursor_col: u32,
    status_line: [*:0]const u8,
};
