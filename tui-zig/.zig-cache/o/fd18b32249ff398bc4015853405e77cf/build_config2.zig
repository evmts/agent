const config = @import("config.zig");
const d = config.default;

pub const tables = [_]config.Table{
    .{
        .fields = &.{
            d.field("east_asian_width"),
            d.field("grapheme_break"),
            d.field("general_category"),
            d.field("is_emoji_presentation"),
         },
     },
};
