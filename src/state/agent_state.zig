processing: bool,
dagger_connected: bool,
last_message: []const u8 = "",
conversation_count: u32 = 1,
current_conversation_index: u32 = 0,

pub const CAgentState = extern struct {
    processing: bool,
    dagger_connected: bool,
};
