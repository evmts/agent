/// Wrapper around the webui lib
/// C library for creating native apps using webviews or browsers
/// C library for creating native apps using webviews or browsers
const Webui = @This();

pub extern fn webui_new_window() callconv(.C) usize;

window: usize,

pub fn init() Webui {
    return .{
        .window = webui_new_window(),
    };
}
