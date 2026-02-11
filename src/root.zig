//! Smithers root module — re-exports public Zig API from lib.zig
const std = @import("std");
const lib = @import("lib.zig");
const build_options = @import("build_options");

// Gate heavy modules (e.g., storage/sqlite, http_server) out of the default
// test build unless explicitly enabled via build options. Keeps `zig build all`
// green on hosts without native deps wired.
pub const ZigApi = lib.ZigApi;
pub const CAPI = lib.CAPI;

comptime {
    if (build_options.enable_storage_module) {
        @import("storage.zig");
    }
}

test {
    std.testing.refAllDecls(@This());
}
