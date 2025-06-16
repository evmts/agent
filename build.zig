const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Check if we're building within Nix environment
    const in_nix = std.process.getEnvVarOwned(b.allocator, "IN_NIX_SHELL") catch null;
    const nix_check_override = b.option(bool, "skip-nix-check", "Skip the Nix environment check") orelse false;
    
    if (in_nix == null and !nix_check_override) {
        std.log.err("\n" ++
            "╔════════════════════════════════════════════════════════════════════╗\n" ++
            "║                    Nix Environment Required                        ║\n" ++
            "╠════════════════════════════════════════════════════════════════════╣\n" ++
            "║ This project requires Nix to manage dependencies (e.g., Ghostty).  ║\n" ++
            "║                                                                    ║\n" ++
            "║ To install Nix:                                                    ║\n" ++
            "║                                                                    ║\n" ++
            "║ macOS/Linux:                                                       ║\n" ++
            "║   $ sh <(curl -L https://nixos.org/nix/install) --daemon          ║\n" ++
            "║                                                                    ║\n" ++
            "║ After installation:                                                ║\n" ++
            "║   1. Restart your terminal                                         ║\n" ++
            "║   2. Enable flakes by adding to ~/.config/nix/nix.conf:           ║\n" ++
            "║      experimental-features = nix-command flakes                    ║\n" ++
            "║   3. Run: nix develop                                              ║\n" ++
            "║   4. Then: zig build                                               ║\n" ++
            "║                                                                    ║\n" ++
            "║ Platform-specific notes:                                           ║\n" ++
            "║                                                                    ║\n" ++
            "║ macOS:                                                             ║\n" ++
            "║   - You may need to create /nix directory first:                  ║\n" ++
            "║     $ sudo mkdir /nix && sudo chown $USER /nix                    ║\n" ++
            "║   - On Apple Silicon, Rosetta 2 may be needed:                    ║\n" ++
            "║     $ softwareupdate --install-rosetta                             ║\n" ++
            "║                                                                    ║\n" ++
            "║ Linux:                                                             ║\n" ++
            "║   - SELinux users may need additional configuration               ║\n" ++
            "║   - Ubuntu/Debian users should use the --daemon flag              ║\n" ++
            "║                                                                    ║\n" ++
            "║ To bypass this check (not recommended):                            ║\n" ++
            "║   $ zig build -Dskip-nix-check=true                                ║\n" ++
            "║                                                                    ║\n" ++
            "║ Learn more:                                                        ║\n" ++
            "║   - https://nixos.org/download.html                               ║\n" ++
            "║   - https://nixos.wiki/wiki/Flakes                                ║\n" ++
            "╚════════════════════════════════════════════════════════════════════╝\n", .{});
        std.process.exit(1);
    }
    
    if (in_nix) |_| {
        b.allocator.free(in_nix.?);
        std.log.info("✓ Building within Nix environment", .{});
    }

    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // This creates a "module", which represents a collection of source files alongside
    // some compilation options, such as optimization mode and linked system libraries.
    // Every executable or library we compile will be based on one or more modules.
    const lib_mod = b.createModule(.{
        // `root_source_file` is the Zig "entry point" of the module. If a module
        // only contains e.g. external object files, you can make this `null`.
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Create C-compatible library module
    const c_lib_mod = b.createModule(.{
        .root_source_file = b.path("src/libplue.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Create Farcaster library module with dependencies
    const farcaster_mod = b.createModule(.{
        .root_source_file = b.path("src/farcaster/farcaster.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Get Ghostty dependency (for future integration)
    // TODO: Use this once we resolve Ghostty's build dependencies
    // NOTE: Commented out for now as Ghostty's build requires Metal shaders
    // and other resources that aren't available in our context
    // _ = b.dependency("ghostty", .{
    //     .target = target,
    //     .optimize = optimize,
    // });

    // Create Ghostty terminal module that wraps Ghostty's embedded API
    const ghostty_terminal_mod = b.createModule(.{
        .root_source_file = b.path("src/ghostty_terminal.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    // Create Ghostty stubs module for fallback when not using Nix
    const ghostty_stubs_mod = b.createModule(.{
        .root_source_file = b.path("src/ghostty_stubs.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    // Create mini terminal module - our minimal terminal implementation
    const mini_terminal_mod = b.createModule(.{
        .root_source_file = b.path("src/mini_terminal.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    // Create PTY terminal module - proper pseudo-terminal implementation
    const pty_terminal_mod = b.createModule(.{
        .root_source_file = b.path("src/pty_terminal.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    // Create macOS PTY module - minimal working PTY for macOS
    const macos_pty_mod = b.createModule(.{
        .root_source_file = b.path("src/macos_pty.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    // Create simple terminal module - better PTY implementation
    const simple_terminal_mod = b.createModule(.{
        .root_source_file = b.path("src/simple_terminal.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add ghostty terminal module to c_lib_mod so libplue can use it
    c_lib_mod.addImport("ghostty_terminal", ghostty_terminal_mod);
    c_lib_mod.addImport("mini_terminal", mini_terminal_mod);
    c_lib_mod.addImport("pty_terminal", pty_terminal_mod);
    c_lib_mod.addImport("macos_pty", macos_pty_mod);
    // c_lib_mod.addImport("simple_terminal", simple_terminal_mod); // Disabled due to API compatibility issues

    // Now, we will create a static library based on the module we created above.
    // This creates a `std.Build.Step.Compile`, which is the build step responsible
    // for actually invoking the compiler.
    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "plue",
        .root_module = lib_mod,
    });

    // Create C-compatible static library for Swift interop
    const c_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "libplue",
        .root_module = c_lib_mod,
    });

    // Create Farcaster static library for Swift interop
    const farcaster_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "farcaster",
        .root_module = farcaster_mod,
    });

    // Create Ghostty terminal static library for Swift interop
    const ghostty_terminal_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "ghostty_terminal",
        .root_module = ghostty_terminal_mod,
    });
    
    // Create mini terminal static library for Swift interop
    const mini_terminal_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "mini_terminal",
        .root_module = mini_terminal_mod,
    });
    
    // Create PTY terminal static library for Swift interop
    const pty_terminal_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "pty_terminal",
        .root_module = pty_terminal_mod,
    });
    
    // Create macOS PTY static library for Swift interop
    const macos_pty_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "macos_pty",
        .root_module = macos_pty_mod,
    });
    
    // Create simple terminal static library for Swift interop
    const simple_terminal_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "simple_terminal",
        .root_module = simple_terminal_mod,
    });

    // Link required libraries
    farcaster_lib.linkLibC();
    ghostty_terminal_lib.linkLibC();
    mini_terminal_lib.linkLibC();
    pty_terminal_lib.linkLibC();
    macos_pty_lib.linkLibC();
    simple_terminal_lib.linkLibC();
    
    // Link with Ghostty library if available from Nix
    if (b.option([]const u8, "ghostty-lib-path", "Path to Ghostty library directory")) |lib_path| {
        ghostty_terminal_lib.addLibraryPath(.{ .cwd_relative = lib_path });
        ghostty_terminal_lib.linkSystemLibrary2("ghostty", .{ .needed = true });
        
        if (b.option([]const u8, "ghostty-include-path", "Path to Ghostty include directory")) |inc_path| {
            ghostty_terminal_lib.addIncludePath(.{ .cwd_relative = inc_path });
        }
    } else {
        // No Ghostty library available, compile and link stubs
        const ghostty_stubs_lib = b.addStaticLibrary(.{
            .name = "ghostty_stubs",
            .root_module = ghostty_stubs_mod,
        });
        ghostty_terminal_lib.linkLibrary(ghostty_stubs_lib);
        // Also install the stubs library so it can be linked
        b.installArtifact(ghostty_stubs_lib);
    }

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    b.installArtifact(lib);
    b.installArtifact(c_lib);
    b.installArtifact(farcaster_lib);
    b.installArtifact(ghostty_terminal_lib);
    b.installArtifact(mini_terminal_lib);
    b.installArtifact(pty_terminal_lib);
    b.installArtifact(macos_pty_lib);
    // b.installArtifact(simple_terminal_lib); // Disabled due to API compatibility issues

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const lib_unit_tests = b.addTest(.{
        .root_module = lib_mod,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    // Integration tests for our Zig modules
    const integration_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/integration_tests.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_integration_tests = b.addRunArtifact(integration_tests);

    // Individual test modules with proper module imports
    const libplue_test_mod = b.createModule(.{
        .root_source_file = b.path("test/test_libplue.zig"),
        .target = target,
        .optimize = optimize,
    });
    libplue_test_mod.addImport("libplue", c_lib_mod);

    const libplue_tests = b.addTest(.{
        .root_module = libplue_test_mod,
    });

    // macOS PTY test executable
    const macos_pty_test = b.addExecutable(.{
        .name = "test_macos_pty",
        .root_source_file = b.path("test_macos_pty.zig"),
        .target = target,
        .optimize = optimize,
    });
    macos_pty_test.linkLibrary(macos_pty_lib);
    macos_pty_test.linkLibC();
    
    const run_macos_pty_test = b.addRunArtifact(macos_pty_test);
    const macos_pty_test_step = b.step("test-macos-pty", "Run macOS PTY test");
    macos_pty_test_step.dependOn(&run_macos_pty_test.step);

    const farcaster_test_mod = b.createModule(.{
        .root_source_file = b.path("test/test_farcaster.zig"),
        .target = target,
        .optimize = optimize,
    });
    farcaster_test_mod.addImport("farcaster", farcaster_mod);

    const farcaster_tests = b.addTest(.{
        .root_module = farcaster_test_mod,
    });

    const run_libplue_tests = b.addRunArtifact(libplue_tests);
    const run_farcaster_tests = b.addRunArtifact(farcaster_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_integration_tests.step);
    test_step.dependOn(&run_libplue_tests.step);
    test_step.dependOn(&run_farcaster_tests.step);

    // Individual test steps for granular testing
    const test_integration_step = b.step("test-integration", "Run integration tests");
    test_integration_step.dependOn(&run_integration_tests.step);

    const test_libplue_step = b.step("test-libplue", "Run libplue tests");
    test_libplue_step.dependOn(&run_libplue_tests.step);

    const test_farcaster_step = b.step("test-farcaster", "Run farcaster tests");
    test_farcaster_step.dependOn(&run_farcaster_tests.step);

    // Add Swift build step that depends on Zig libraries
    const swift_build_cmd = b.addSystemCommand(&.{
        "swift",    "build",                                       "--configuration", "release",
        "-Xlinker", b.fmt("-L{s}", .{b.getInstallPath(.lib, "")}),
    });

    // Swift build depends on all Zig libraries being built and installed
    swift_build_cmd.step.dependOn(&lib.step);
    swift_build_cmd.step.dependOn(&c_lib.step);
    swift_build_cmd.step.dependOn(&farcaster_lib.step);
    swift_build_cmd.step.dependOn(&ghostty_terminal_lib.step);
    swift_build_cmd.step.dependOn(&mini_terminal_lib.step);

    // Create a step for building the complete project (Zig + Swift)
    const build_all_step = b.step("swift", "Build complete project including Swift");
    build_all_step.dependOn(&swift_build_cmd.step);

    // Make the default install step also build Swift
    // NOTE: Commented out to allow building Zig libraries independently in Nix
    // b.getInstallStep().dependOn(&swift_build_cmd.step);

    // Add step to run the Swift executable
    const swift_run_cmd = b.addSystemCommand(&.{".build/release/plue"});
    swift_run_cmd.step.dependOn(&swift_build_cmd.step);

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the Swift app");
    run_step.dependOn(&swift_run_cmd.step);

    const run_swift_step = b.step("run-swift", "Run the Swift application");
    run_swift_step.dependOn(&swift_run_cmd.step);

    // Development server with file watching
    const dev_step = b.step("dev", "Development server with file watching and smart rebuilds");
    const dev_cmd = b.addSystemCommand(&.{
        "zig", "run", 
        b.pathFromRoot("dev_server.zig"),
        "--", 
        b.build_root.path orelse ".",
    });
    dev_cmd.step.dependOn(&lib.step);
    dev_cmd.step.dependOn(&c_lib.step);
    dev_cmd.step.dependOn(&farcaster_lib.step);
    dev_cmd.step.dependOn(&ghostty_terminal_lib.step);
    dev_cmd.step.dependOn(&mini_terminal_lib.step);
    dev_step.dependOn(&dev_cmd.step);
}
