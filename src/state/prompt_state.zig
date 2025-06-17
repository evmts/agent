processing: bool,
current_content: []const u8,
last_message: []const u8 = "",
conversation_count: u32 = 1,
current_conversation_index: u32 = 0,

pub const CPromptState = extern struct {
    processing: bool,
    current_content: [*:0]const u8,
};
