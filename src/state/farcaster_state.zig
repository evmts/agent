selected_channel: []const u8 = "home",
is_loading: bool = false,
is_posting: bool = false,

pub const CFarcasterState = extern struct {
    selected_channel: [*:0]const u8,
    is_loading: bool,
    is_posting: bool,
};