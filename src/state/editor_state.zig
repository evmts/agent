file_path: []const u8 = "",
content: []const u8 = "",
is_modified: bool = false,

pub const CEditorState = extern struct {
    file_path: [*:0]const u8,
    content: [*:0]const u8,
    is_modified: bool,
};