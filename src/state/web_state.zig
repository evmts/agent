can_go_back: bool,
can_go_forward: bool,
is_loading: bool,
current_url: []const u8,
page_title: []const u8,

pub const CWebState = extern struct {
    can_go_back: bool,
    can_go_forward: bool,
    is_loading: bool,
    current_url: [*:0]const u8,
    page_title: [*:0]const u8,
};
