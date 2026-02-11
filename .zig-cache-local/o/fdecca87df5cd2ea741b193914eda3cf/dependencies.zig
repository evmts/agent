pub const packages = struct {
    pub const @"pkg/sqlite" = struct {
        pub const build_root = "/Users/williamcory/agent/pkg/sqlite";
        pub const build_zig = @import("pkg/sqlite");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
        };
    };
};

pub const root_deps: []const struct { []const u8, []const u8 } = &.{
    .{ "sqlite", "pkg/sqlite" },
};
