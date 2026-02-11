//! Smithers root module — re-exports public Zig API from lib.zig
const lib = @import("lib.zig");

pub const ZigApi = lib.ZigApi;
pub const CAPI = lib.CAPI;

test {
    @import("std").testing.refAllDecls(@This());
}
