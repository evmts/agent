processing: bool,
current_content: []const u8,

pub const CPromptState = extern struct {
    processing: bool,
    current_content: [*:0]const u8,
};
