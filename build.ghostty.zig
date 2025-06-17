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
            
            // Install the library and header
            const install_lib = b.addInstallFile(libghostty.output, "libghostty.a");
            install_lib.step.dependOn(libghostty.step);
            b.getInstallStep().dependOn(&install_lib.step);
            
            const install_header = b.addInstallHeaderFile(b.path("lib/ghostty/include/ghostty.h"), "ghostty.h");
            b.getInstallStep().dependOn(&install_header.step);
        }
    } else {
        // On other platforms, build both static and shared libraries
        const libghostty_shared = try buildpkg.GhosttyLib.initShared(b, &deps);
        const libghostty_static = try buildpkg.GhosttyLib.initStatic(b, &deps);
        
        // Install shared library
        const install_shared = b.addInstallFile(libghostty_shared.output, "libghostty.so");
        install_shared.step.dependOn(libghostty_shared.step);
        b.getInstallStep().dependOn(&install_shared.step);
        
        // Install static library
        const install_static = b.addInstallFile(libghostty_static.output, "libghostty.a");
        install_static.step.dependOn(libghostty_static.step);
        b.getInstallStep().dependOn(&install_static.step);
        
        // Install header
        const install_header = b.addInstallHeaderFile(b.path("lib/ghostty/include/ghostty.h"), "ghostty.h");
        b.getInstallStep().dependOn(&install_header.step);
    }
    
    // Add a custom step to build just libghostty
    const libghostty_step = b.step("libghostty", "Build libghostty");
    libghostty_step.dependOn(b.getInstallStep());
}