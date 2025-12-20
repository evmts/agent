pub const packages = struct {
    pub const @"webui-2.5.0-beta.4-pxqD5TfeNwBmDX91ECnjWAIQI_IUhqvWBk1yVo37FXLb" = struct {
        pub const build_root = "/Users/williamcory/.cache/zig/p/webui-2.5.0-beta.4-pxqD5TfeNwBmDX91ECnjWAIQI_IUhqvWBk1yVo37FXLb";
        pub const build_zig = @import("webui-2.5.0-beta.4-pxqD5TfeNwBmDX91ECnjWAIQI_IUhqvWBk1yVo37FXLb");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
        };
    };
    pub const @"zig_webui-2.5.0-beta.4-M4z7zexlAQD-drd9H1BqG1goIZQ-S623XbqUWSYDs5wd" = struct {
        pub const build_root = "/Users/williamcory/.cache/zig/p/zig_webui-2.5.0-beta.4-M4z7zexlAQD-drd9H1BqG1goIZQ-S623XbqUWSYDs5wd";
        pub const build_zig = @import("zig_webui-2.5.0-beta.4-M4z7zexlAQD-drd9H1BqG1goIZQ-S623XbqUWSYDs5wd");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
            .{ "webui", "webui-2.5.0-beta.4-pxqD5TfeNwBmDX91ECnjWAIQI_IUhqvWBk1yVo37FXLb" },
        };
    };
};

pub const root_deps: []const struct { []const u8, []const u8 } = &.{
    .{ "zig_webui", "zig_webui-2.5.0-beta.4-M4z7zexlAQD-drd9H1BqG1goIZQ-S623XbqUWSYDs5wd" },
};
