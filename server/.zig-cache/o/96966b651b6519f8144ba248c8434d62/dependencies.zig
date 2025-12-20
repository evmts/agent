pub const packages = struct {
    pub const @"../core-zig" = struct {
        pub const build_root = "/Users/williamcory/agent/server-zig/../core-zig";
        pub const build_zig = @import("../core-zig");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
        };
    };
    pub const @"N-V-__8AAEGLAAB4JS8S1rWwdvXUTwnt7gRNthhJanWx4AvP" = struct {
        pub const build_root = "/Users/williamcory/.cache/zig/p/N-V-__8AAEGLAAB4JS8S1rWwdvXUTwnt7gRNthhJanWx4AvP";
        pub const build_zig = @import("N-V-__8AAEGLAAB4JS8S1rWwdvXUTwnt7gRNthhJanWx4AvP");
        pub const deps: []const struct { []const u8, []const u8 } = &.{};
    };
    pub const ai = struct {
        pub const build_root = "/Users/williamcory/agent/server-zig/ai";
        pub const build_zig = @import("ai");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
        };
    };
    pub const @"clap-0.11.0-oBajB-TnAQC7yPLnZRT5WzHZ_4Ly4dX2OILskli74b9H" = struct {
        pub const build_root = "/Users/williamcory/.cache/zig/p/clap-0.11.0-oBajB-TnAQC7yPLnZRT5WzHZ_4Ly4dX2OILskli74b9H";
        pub const build_zig = @import("clap-0.11.0-oBajB-TnAQC7yPLnZRT5WzHZ_4Ly4dX2OILskli74b9H");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
        };
    };
    pub const @"httpz-0.0.0-PNVzrEktBwCzPoiua-S8LAYo2tILqczm3tSpneEzLQ9L" = struct {
        pub const build_root = "/Users/williamcory/.cache/zig/p/httpz-0.0.0-PNVzrEktBwCzPoiua-S8LAYo2tILqczm3tSpneEzLQ9L";
        pub const build_zig = @import("httpz-0.0.0-PNVzrEktBwCzPoiua-S8LAYo2tILqczm3tSpneEzLQ9L");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
            .{ "metrics", "metrics-0.0.0-W7G4eP2_AQAdJGKMonHeZFaY4oU4ZXPFFTqFCFXItX3O" },
            .{ "websocket", "websocket-0.1.0-ZPISdZJxAwAt6Ys_JpoHQQV3NpWCof_N9Jg-Ul2g7OoV" },
        };
    };
    pub const @"metrics-0.0.0-W7G4eP2_AQAdJGKMonHeZFaY4oU4ZXPFFTqFCFXItX3O" = struct {
        pub const build_root = "/Users/williamcory/.cache/zig/p/metrics-0.0.0-W7G4eP2_AQAdJGKMonHeZFaY4oU4ZXPFFTqFCFXItX3O";
        pub const build_zig = @import("metrics-0.0.0-W7G4eP2_AQAdJGKMonHeZFaY4oU4ZXPFFTqFCFXItX3O");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
        };
    };
    pub const @"metrics-0.0.0-W7G4eP2_AQBKsaql3dhLJ-pkf-RdP-zV3vflJy4N34jC" = struct {
        pub const build_root = "/Users/williamcory/.cache/zig/p/metrics-0.0.0-W7G4eP2_AQBKsaql3dhLJ-pkf-RdP-zV3vflJy4N34jC";
        pub const build_zig = @import("metrics-0.0.0-W7G4eP2_AQBKsaql3dhLJ-pkf-RdP-zV3vflJy4N34jC");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
        };
    };
    pub const @"pg-0.0.0-Wp_7gag6BgD_QAZrPhNNEGpnUZR_LEkKT40Ura3p-4yX" = struct {
        pub const build_root = "/Users/williamcory/.cache/zig/p/pg-0.0.0-Wp_7gag6BgD_QAZrPhNNEGpnUZR_LEkKT40Ura3p-4yX";
        pub const build_zig = @import("pg-0.0.0-Wp_7gag6BgD_QAZrPhNNEGpnUZR_LEkKT40Ura3p-4yX");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
            .{ "buffer", "N-V-__8AAEGLAAB4JS8S1rWwdvXUTwnt7gRNthhJanWx4AvP" },
            .{ "metrics", "metrics-0.0.0-W7G4eP2_AQBKsaql3dhLJ-pkf-RdP-zV3vflJy4N34jC" },
        };
    };
    pub const voltaire = struct {
        pub const build_root = "/Users/williamcory/agent/server-zig/voltaire";
        pub const build_zig = @import("voltaire");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
            .{ "zbench", "zbench-0.11.2-YTdc7zolAQDlBF9i0ywXIvDjafL3Kg27S-aFUq6dU5zy" },
            .{ "clap", "clap-0.11.0-oBajB-TnAQC7yPLnZRT5WzHZ_4Ly4dX2OILskli74b9H" },
            .{ "z_ens_normalize", "z_ens_normalize-0.0.0-Iv6nMI2_AgCrLtEnZZnoeP87kZtP-36iIWzj3cD3v-vd" },
            .{ "libwally_core", "voltaire/lib/libwally-core" },
        };
    };
    pub const @"voltaire/lib/libwally-core" = struct {
        pub const build_root = "/Users/williamcory/agent/server-zig/voltaire/lib/libwally-core";
        pub const deps: []const struct { []const u8, []const u8 } = &.{};
    };
    pub const @"websocket-0.1.0-ZPISdZJxAwAt6Ys_JpoHQQV3NpWCof_N9Jg-Ul2g7OoV" = struct {
        pub const build_root = "/Users/williamcory/.cache/zig/p/websocket-0.1.0-ZPISdZJxAwAt6Ys_JpoHQQV3NpWCof_N9Jg-Ul2g7OoV";
        pub const build_zig = @import("websocket-0.1.0-ZPISdZJxAwAt6Ys_JpoHQQV3NpWCof_N9Jg-Ul2g7OoV");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
        };
    };
    pub const @"z_ens_normalize-0.0.0-Iv6nMI2_AgCrLtEnZZnoeP87kZtP-36iIWzj3cD3v-vd" = struct {
        pub const build_root = "/Users/williamcory/.cache/zig/p/z_ens_normalize-0.0.0-Iv6nMI2_AgCrLtEnZZnoeP87kZtP-36iIWzj3cD3v-vd";
        pub const build_zig = @import("z_ens_normalize-0.0.0-Iv6nMI2_AgCrLtEnZZnoeP87kZtP-36iIWzj3cD3v-vd");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
        };
    };
    pub const @"zbench-0.11.2-YTdc7zolAQDlBF9i0ywXIvDjafL3Kg27S-aFUq6dU5zy" = struct {
        pub const build_root = "/Users/williamcory/.cache/zig/p/zbench-0.11.2-YTdc7zolAQDlBF9i0ywXIvDjafL3Kg27S-aFUq6dU5zy";
        pub const build_zig = @import("zbench-0.11.2-YTdc7zolAQDlBF9i0ywXIvDjafL3Kg27S-aFUq6dU5zy");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
        };
    };
};

pub const root_deps: []const struct { []const u8, []const u8 } = &.{
    .{ "httpz", "httpz-0.0.0-PNVzrEktBwCzPoiua-S8LAYo2tILqczm3tSpneEzLQ9L" },
    .{ "pg", "pg-0.0.0-Wp_7gag6BgD_QAZrPhNNEGpnUZR_LEkKT40Ura3p-4yX" },
    .{ "voltaire", "voltaire" },
    .{ "zig-ai-sdk", "ai" },
    .{ "core", "../core-zig" },
};
