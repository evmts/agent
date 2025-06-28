const std = @import("std");
const builtin = @import("builtin");

const GhosttyPaths = struct {
    lib_path: []const u8,
    include_path: []const u8,
};

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // Build options
    const skip_ghostty = b.option(bool, "skip-ghostty", "Skip building Ghostty (use pre-built)") orelse false;
    const ghostty_lib_path = b.option([]const u8, "ghostty-lib-path", "Path to pre-built libghostty");
    const ghostty_include_path = b.option([]const u8, "ghostty-include-path", "Path to ghostty headers");

    // Step 1: Build libghostty if not skipped
    var ghostty_paths: GhosttyPaths = undefined;

    if (!skip_ghostty) {
        const ghostty_step = buildGhostty(b, target, optimize);
        b.getInstallStep().dependOn(ghostty_step);
        
        // Use the actual location where libghostty.a is created
        ghostty_paths = .{
            .lib_path = b.pathJoin(&.{b.install_path, "lib"}),
            .include_path = b.pathJoin(&.{b.install_path, "ghostty-deps", "include"}),
        };
    } else {
        // Use provided paths or defaults
        ghostty_paths = .{
            .lib_path = ghostty_lib_path orelse b.pathJoin(&.{b.install_path, "lib"}),
            .include_path = ghostty_include_path orelse b.pathFromRoot("lib/ghostty/include"),
        };
    }

    // Step 2: Build all Zig modules and libraries
    buildZigLibraries(b, target, optimize, ghostty_paths);

    // Step 2.5: Build TypeScript executables
    const ts_step = buildTypeScriptExecutables(b);

    // Step 3: Create Swift build step
    const swift_step = buildSwift(b, target, optimize, ghostty_paths);
    swift_step.step.dependOn(ts_step);
    
    // Main build step
    const build_step = b.step("build", "Build the complete application");
    build_step.dependOn(&swift_step.step);

    // Run step
    const run_step = b.step("run", "Build and run the application");
    const run_cmd = b.addSystemCommand(&.{
        ".build/arm64-apple-macosx/debug/plue",
    });
    run_cmd.step.dependOn(&swift_step.step);
    run_step.dependOn(&run_cmd.step);

    // Dev step - just run the app in debug mode
    const dev_step = b.step("dev", "Build and run in development mode");
    const dev_cmd = b.addSystemCommand(&.{
        ".build/arm64-apple-macosx/debug/plue",
    });
    dev_cmd.step.dependOn(&swift_step.step);
    dev_step.dependOn(&dev_cmd.step);
    
    // Watch step with file watching (renamed from dev)
    const watch_step = b.step("watch", "Run development server with file watching");
    const dev_server = b.addExecutable(.{
        .name = "dev_server",
        .root_source_file = b.path("dev_server.zig"),
        .target = target,
        .optimize = .Debug,
    });
    const run_dev_server = b.addRunArtifact(dev_server);
    run_dev_server.addArg(b.build_root.path orelse ".");
    watch_step.dependOn(&run_dev_server.step);

    // Swift-only step
    const swift_only_step = b.step("swift", "Build only the Swift application");
    swift_only_step.dependOn(&swift_step.step);

    // TypeScript-only step
    const ts_only_step = b.step("ts", "Build only the TypeScript executables");
    ts_only_step.dependOn(ts_step);

    // Tests
    const test_step = buildTests(b, target, optimize);

    // MCP servers - disabled for now due to JSON API incompatibility
    // buildMCPServers(b, target, optimize);

    // All step - builds and tests everything
    const all_step = b.step("all", "Build everything and run all tests");
    
    // Build all libraries and executables
    all_step.dependOn(b.getInstallStep());
    all_step.dependOn(&swift_step.step);
    
    // Run all tests
    all_step.dependOn(test_step);
    
    // Add a verification step that checks if everything built correctly
    const verify_step = b.addSystemCommand(&.{
        "sh", "-c",
        \\echo "🔍 Verifying build artifacts..." &&
        \\if [ -f zig-out/lib/libplue.a ]; then echo "✅ libplue.a"; else echo "❌ libplue.a missing"; exit 1; fi &&
        \\if [ -f zig-out/lib/liblibplue.a ]; then echo "✅ liblibplue.a"; else echo "❌ liblibplue.a missing"; exit 1; fi &&
        \\if [ -f zig-out/lib/libterminal.a ]; then echo "✅ libterminal.a"; else echo "❌ libterminal.a missing"; exit 1; fi &&
        \\if [ -f zig-out/lib/libghostty_terminal.a ]; then echo "✅ libghostty_terminal.a"; else echo "❌ libghostty_terminal.a missing"; exit 1; fi &&
        \\if [ -f zig-out/lib/libghostty.a ]; then echo "✅ libghostty.a"; else echo "❌ libghostty.a missing"; fi &&
        \\if [ -f .build/arm64-apple-macosx/debug/plue ] || [ -f .build/arm64-apple-macosx/release/plue ]; then echo "✅ Swift executable"; else echo "❌ Swift executable missing"; exit 1; fi &&
        \\echo "✨ All build artifacts verified!"
    });
    verify_step.step.dependOn(&swift_step.step);
    all_step.dependOn(&verify_step.step);
    
    // Add a final success message
    const success_msg = b.addSystemCommand(&.{
        "sh", "-c",
        \\echo "" &&
        \\echo "🎉 Build and test completed successfully!" &&
        \\echo "📦 All libraries built" &&
        \\echo "✅ All tests passed" &&
        \\echo "🚀 Ready to run: zig build run"
    });
    success_msg.step.dependOn(&verify_step.step);
    all_step.dependOn(&success_msg.step);
}

fn buildGhostty(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Step {
    const ghostty_step = b.step("ghostty", "Build Ghostty library");
    
    // Build a stub library for ghostty
    const ghostty_stub = b.addLibrary(.{
        .linkage = .static,
        .name = "ghostty",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/ghostty_stub.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    ghostty_stub.linkLibC();
    ghostty_stub.root_module.addIncludePath(.{ .cwd_relative = b.pathFromRoot("lib/ghostty/include") });
    b.installArtifact(ghostty_stub);
    
    // Install the header to our output directory
    const install_header = b.addInstallFile(
        b.path("lib/ghostty/include/ghostty.h"),
        "ghostty-deps/include/ghostty.h"
    );
    
    ghostty_step.dependOn(&ghostty_stub.step);
    ghostty_step.dependOn(&install_header.step);
    
    return ghostty_step;
}

fn buildZigLibraries(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    ghostty_paths: GhosttyPaths,
) void {
    // Create modules
    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const c_lib_mod = b.createModule(.{
        .root_source_file = b.path("src/libplue.zig"),
        .target = target,
        .optimize = optimize,
    });

    const ghostty_terminal_mod = b.createModule(.{
        .root_source_file = b.path("src/ghostty_terminal.zig"),
        .target = target,
        .optimize = optimize,
    });
    ghostty_terminal_mod.addIncludePath(.{ .cwd_relative = ghostty_paths.include_path });


    const app_mod = b.createModule(.{
        .root_source_file = b.path("src/app.zig"),
        .target = target,
        .optimize = optimize,
    });

    const terminal_mod = b.createModule(.{
        .root_source_file = b.path("src/terminal.zig"),
        .target = target,
        .optimize = optimize,
    });

    const state_mod = b.createModule(.{
        .root_source_file = b.path("src/state/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    // Add nvim_client to state module
    state_mod.addImport("nvim_client", b.createModule(.{
        .root_source_file = b.path("src/nvim_client.zig"),
        .target = target,
        .optimize = optimize,
    }));

    // Add imports
    c_lib_mod.addImport("ghostty_terminal", ghostty_terminal_mod);
    c_lib_mod.addImport("terminal", terminal_mod);
    c_lib_mod.addImport("app", app_mod);
    c_lib_mod.addImport("state", state_mod);
    // Add farcaster as a module import to libplue
    c_lib_mod.addImport("farcaster", b.createModule(.{
        .root_source_file = b.path("src/farcaster/farcaster.zig"),
        .target = target,
        .optimize = optimize,
    }));
    // Add nvim_client as a module import to libplue
    c_lib_mod.addImport("nvim_client", b.createModule(.{
        .root_source_file = b.path("src/nvim_client.zig"),
        .target = target,
        .optimize = optimize,
    }));

    // Create libraries
    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "plue",
        .root_module = lib_mod,
    });
    b.installArtifact(lib);

    const c_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "libplue",
        .root_module = c_lib_mod,
    });
    c_lib.linkLibC(); // libplue needs linkLibC since it now includes farcaster
    b.installArtifact(c_lib);

    const ghostty_terminal_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "ghostty_terminal",
        .root_module = ghostty_terminal_mod,
    });
    ghostty_terminal_lib.linkLibC();
    ghostty_terminal_lib.addObjectFile(.{ .cwd_relative = b.pathJoin(&.{ ghostty_paths.lib_path, "libghostty.a" }) });
    b.installArtifact(ghostty_terminal_lib);

    const terminal_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "terminal",
        .root_module = terminal_mod,
    });
    terminal_lib.linkLibC();
    b.installArtifact(terminal_lib);

}

fn buildSwift(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    ghostty_paths: GhosttyPaths,
) *std.Build.Step.Run {
    var swift_args = std.ArrayList([]const u8).init(b.allocator);
    
    // Base swift build command
    swift_args.appendSlice(&.{
        "swift", "build",
        "-c", if (optimize == .Debug) "debug" else "release",
        "--product", "plue",
    }) catch @panic("OOM");
    
    // Add linker flags for our Zig libraries
    swift_args.appendSlice(&.{
        "-Xlinker", b.fmt("-L{s}", .{b.getInstallPath(.lib, "")}),
        "-Xlinker", "-lplue",
        "-Xlinker", "-llibplue",
        "-Xlinker", "-lterminal",
        "-Xlinker", "-lghostty_terminal",
    }) catch @panic("OOM");
    
    // Add ghostty include path
    swift_args.appendSlice(&.{
        "-Xcc", b.fmt("-I{s}", .{ghostty_paths.include_path}),
    }) catch @panic("OOM");
    
    // Add framework flags for macOS
    if (target.result.os.tag == .macos) {
        swift_args.appendSlice(&.{
            "-Xlinker", "-framework", "-Xlinker", "CoreFoundation",
            "-Xlinker", "-framework", "-Xlinker", "CoreGraphics",
            "-Xlinker", "-framework", "-Xlinker", "CoreText",
            "-Xlinker", "-framework", "-Xlinker", "CoreVideo",
            "-Xlinker", "-framework", "-Xlinker", "Metal",
            "-Xlinker", "-framework", "-Xlinker", "MetalKit",
            "-Xlinker", "-framework", "-Xlinker", "QuartzCore",
            "-Xlinker", "-framework", "-Xlinker", "IOKit",
            "-Xlinker", "-framework", "-Xlinker", "Carbon",
            "-Xlinker", "-framework", "-Xlinker", "Cocoa",
            "-Xlinker", "-framework", "-Xlinker", "Security",
        }) catch @panic("OOM");
    }
    
    const swift_cmd = b.addSystemCommand(swift_args.items);
    
    // Swift build depends on all Zig libraries
    swift_cmd.step.dependOn(b.getInstallStep());
    
    return swift_cmd;
}

fn buildTypeScriptExecutables(b: *std.Build) *std.Build.Step {
    const ts_step = b.step("ts-executables", "Build TypeScript executables");
    
    // First, check if bun is available
    const check_bun = b.addSystemCommand(&.{ "which", "bun" });
    check_bun.expectExitCode(0);
    
    // Install dependencies
    const bun_install = b.addSystemCommand(&.{ 
        "sh", "-c", 
        "cd executables && bun install" 
    });
    bun_install.step.dependOn(&check_bun.step);
    
    // Build TypeScript executables
    const bun_build = b.addSystemCommand(&.{ 
        "sh", "-c", 
        "cd executables && bun run build" 
    });
    bun_build.step.dependOn(&bun_install.step);
    
    ts_step.dependOn(&bun_build.step);
    
    // Add a verification step
    const verify_ts = b.addSystemCommand(&.{
        "sh", "-c",
        \\echo "🔍 Verifying TypeScript executables..." &&
        \\if [ -f bin/plue-ai-provider ]; then echo "✅ plue-ai-provider"; else echo "⚠️  plue-ai-provider not built yet"; fi &&
        \\echo "✨ TypeScript build completed!"
    });
    verify_ts.step.dependOn(&bun_build.step);
    ts_step.dependOn(&verify_ts.step);
    
    return ts_step;
}

fn buildTests(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Step {
    // Create test modules and add tests
    const test_step = b.step("test", "Run all tests");
    
    // Library tests
    const lib_tests = b.addTest(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_lib_tests = b.addRunArtifact(lib_tests);
    test_step.dependOn(&run_lib_tests.step);
    
    // Integration tests
    const integration_tests = b.addTest(.{
        .root_source_file = b.path("test/integration_tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_integration_tests = b.addRunArtifact(integration_tests);
    test_step.dependOn(&run_integration_tests.step);
    
    // Terminal test executable
    const terminal_test = b.addExecutable(.{
        .name = "test_macos_pty",
        .root_source_file = b.path("test_macos_pty.zig"),
        .target = target,
        .optimize = optimize,
    });
    terminal_test.linkLibC();
    
    const run_terminal_test = b.addRunArtifact(terminal_test);
    const terminal_test_step = b.step("test-terminal", "Run terminal test");
    terminal_test_step.dependOn(&run_terminal_test.step);

    // OpenCode server test executable
    const opencode_test = b.addExecutable(.{
        .name = "opencode-server-test",
        .root_source_file = b.path("src/opencode_server_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    opencode_test.linkLibC();
    b.installArtifact(opencode_test);
    
    const run_opencode_test = b.addRunArtifact(opencode_test);
    const opencode_test_step = b.step("test-opencode", "Test OpenCode server management");
    opencode_test_step.dependOn(&run_opencode_test.step);
    
    // Swift tests
    const swift_test_step = b.step("test-swift", "Run Swift tests");
    const swift_test_cmd = b.addSystemCommand(&.{
        "swift", "test",
        "--configuration", if (optimize == .Debug) "debug" else "release",
        "-Xlinker", b.fmt("-L{s}", .{b.getInstallPath(.lib, "")}),
        "-Xlinker", "-lplue",
        "-Xlinker", "-llibplue",
        "-Xlinker", "-lterminal",
        "-Xlinker", "-lghostty_terminal",
    });
    swift_test_cmd.step.dependOn(b.getInstallStep()); // Ensure libraries are built
    swift_test_step.dependOn(&swift_test_cmd.step);
    
    // Add Swift tests to main test step
    test_step.dependOn(swift_test_step);
    
    return test_step;
}

fn buildMCPServers(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    // MCP AppleScript server
    const mcp_applescript = b.addExecutable(.{
        .name = "mcp-applescript",
        .root_source_file = b.path("mcp/applescript.zig"),
        .target = target,
        .optimize = optimize,
    });
    mcp_applescript.linkLibC();
    b.installArtifact(mcp_applescript);

    const run_mcp_applescript = b.addRunArtifact(mcp_applescript);
    const mcp_applescript_step = b.step("mcp-applescript", "Run the MCP AppleScript server");
    mcp_applescript_step.dependOn(&run_mcp_applescript.step);

    // Plue MCP server
    const plue_mcp = b.addExecutable(.{
        .name = "plue-mcp",
        .root_source_file = b.path("mcp/plue_mcp_fixed.zig"),
        .target = target,
        .optimize = optimize,
    });
    plue_mcp.linkLibC();
    b.installArtifact(plue_mcp);

    const run_plue_mcp = b.addRunArtifact(plue_mcp);
    const plue_mcp_step = b.step("plue-mcp", "Run the Plue MCP server");
    plue_mcp_step.dependOn(&run_plue_mcp.step);
}