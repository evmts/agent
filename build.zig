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
        
        // Set paths to built ghostty
        ghostty_paths = .{
            .lib_path = b.getInstallPath(.lib, ""),
            .include_path = b.getInstallPath(.header, ""),
        };
    } else {
        // Use provided paths or defaults
        ghostty_paths = .{
            .lib_path = ghostty_lib_path orelse b.pathFromRoot("lib/ghostty/.zig-cache/o/b11a20ce4aa45da884bb124cfc1c77eb"),
            .include_path = ghostty_include_path orelse b.pathFromRoot("lib/ghostty/include"),
        };
    }

    // Step 2: Build all Zig modules and libraries
    buildZigLibraries(b, target, optimize, ghostty_paths);

    // Step 3: Create Swift build step
    const swift_step = buildSwift(b, target, optimize, ghostty_paths);
    
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

    // Dev step with file watching
    const dev_step = b.step("dev", "Run in development mode with hot reload");
    const dev_server = b.addExecutable(.{
        .name = "dev_server",
        .root_source_file = b.path("dev_server.zig"),
        .target = target,
        .optimize = .Debug,
    });
    const run_dev_server = b.addRunArtifact(dev_server);
    run_dev_server.addArg(b.build_root.path orelse ".");
    dev_step.dependOn(&run_dev_server.step);

    // Swift-only step
    const swift_only_step = b.step("swift", "Build only the Swift application");
    swift_only_step.dependOn(&swift_step.step);

    // Tests
    buildTests(b, target, optimize);

    // MCP servers - disabled for now due to JSON API incompatibility
    // buildMCPServers(b, target, optimize);
}

fn buildGhostty(b: *std.Build, _: std.Build.ResolvedTarget, _: std.builtin.OptimizeMode) *std.Build.Step {
    const ghostty_step = b.step("ghostty", "Build Ghostty library");
    
    // First, let's find where libghostty.a actually ends up
    const find_lib_cmd = b.addSystemCommand(&.{
        "sh", "-c",
        "cd lib/ghostty && zig build -Doptimize=ReleaseFast -Dapp-runtime=none -Demit-xcframework=false 2>&1 >/dev/null && find .zig-cache -name 'libghostty*.a' -type f | head -1 | xargs -I {} cp {} ../../zig-out/lib/libghostty.a && echo '✅ Built and copied libghostty.a'"
    });
    
    // Ensure output directory exists
    const mkdir_cmd = b.addSystemCommand(&.{ "mkdir", "-p", b.pathJoin(&.{b.install_path, "lib"}) });
    find_lib_cmd.step.dependOn(&mkdir_cmd.step);
    
    // Install the header
    const install_header = b.addInstallFile(
        b.path("lib/ghostty/include/ghostty.h"),
        "ghostty.h"
    );
    
    ghostty_step.dependOn(&find_lib_cmd.step);
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

    const farcaster_mod = b.createModule(.{
        .root_source_file = b.path("src/farcaster/farcaster.zig"),
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

    // Add imports
    c_lib_mod.addImport("ghostty_terminal", ghostty_terminal_mod);
    c_lib_mod.addImport("terminal", terminal_mod);
    c_lib_mod.addImport("app", app_mod);
    c_lib_mod.addImport("state", state_mod);

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
    b.installArtifact(c_lib);

    const farcaster_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "farcaster",
        .root_module = farcaster_mod,
    });
    farcaster_lib.linkLibC();
    b.installArtifact(farcaster_lib);

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
        "-Xlinker", "-lfarcaster",
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

fn buildTests(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
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