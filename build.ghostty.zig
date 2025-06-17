const std = @import("std");
const builtin = @import("builtin");

/// Builds libghostty from the ghostty source in lib/ghostty
/// This calls into Ghostty's build system to properly build the library
pub fn build(b: *std.Build) !void {
    // Import the ghostty build package
    const buildpkg = @import("lib/ghostty/src/build/main.zig");

    // Initialize config similar to how ghostty does it
    const config = try buildpkg.Config.init(b);
    
    // Configure for libghostty mode (app_runtime = .none)
    var lib_config = config;
    lib_config.app_runtime = .none;
    
    // Initialize shared dependencies
    const deps = try buildpkg.SharedDeps.init(b, &lib_config);
    
    // Build libghostty based on the target OS
    if (lib_config.target.result.os.tag.isDarwin()) {
        // On macOS, build the xcframework if requested
        if (lib_config.emit_xcframework) {
            const xcframework = try buildpkg.GhosttyXCFramework.init(b, &deps);
            xcframework.install();
        } else {
            // Otherwise build static library
            const libghostty = try buildpkg.GhosttyLib.initStatic(b, &deps);
            libghostty.installHeader();
            libghostty.install("libghostty.a");
        }
    } else {
        // On other platforms, build both static and shared libraries
        const libghostty_shared = try buildpkg.GhosttyLib.initShared(b, &deps);
        const libghostty_static = try buildpkg.GhosttyLib.initStatic(b, &deps);
        libghostty_shared.installHeader(); // Only need one header
        libghostty_shared.install("libghostty.so");
        libghostty_static.install("libghostty.a");
    }
    
    // Add a custom step to build just libghostty
    const libghostty_step = b.step("libghostty", "Build libghostty");
    libghostty_step.dependOn(b.getInstallStep());
}