const std = @import("std");

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

    // Create Farcaster library module
    const farcaster_mod = b.createModule(.{
        .root_source_file = b.path("src/farcaster.zig"),
        .target = target,
        .optimize = optimize,
    });

    // We will also create a module for our other entry point, 'main.zig'.
    const exe_mod = b.createModule(.{
        // `root_source_file` is the Zig "entry point" of the module. If a module
        // only contains e.g. external object files, you can make this `null`.
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Modules can depend on one another using the `std.Build.Module.addImport` function.
    // This is what allows Zig source code to use `@import("foo")` where 'foo' is not a
    // file path. In this case, we set up `exe_mod` to import `lib_mod`.
    exe_mod.addImport("plue_lib", lib_mod);

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

    // Link required libraries for HTTP and crypto
    farcaster_lib.linkLibC();

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    b.installArtifact(lib);
    b.installArtifact(c_lib);
    b.installArtifact(farcaster_lib);

    const webui = b.dependency("webui", .{
        .target = target,
        .optimize = optimize,
        .dynamic = false,
        .@"enable-tls" = false,
        .verbose = .err,
    });

    // This creates another `std.Build.Step.Compile`, but this one builds an executable
    // rather than a static library.
    const exe = b.addExecutable(.{
        .name = "plue",
        .root_module = exe_mod,
    });
    exe.linkLibrary(webui.artifact("webui"));

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const lib_unit_tests = b.addTest(.{
        .root_module = lib_mod,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

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

    const farcaster_test_mod = b.createModule(.{
        .root_source_file = b.path("test/test_farcaster.zig"),
        .target = target,
        .optimize = optimize,
    });
    farcaster_test_mod.addImport("farcaster", farcaster_mod);
    
    const farcaster_tests = b.addTest(.{
        .root_module = farcaster_test_mod,
    });

    const app_test_mod = b.createModule(.{
        .root_source_file = b.path("test/test_app.zig"),
        .target = target,
        .optimize = optimize,
    });
    app_test_mod.addImport("app_root", lib_mod);
    
    const app_tests = b.addTest(.{
        .root_module = app_test_mod,
    });

    const run_libplue_tests = b.addRunArtifact(libplue_tests);
    const run_farcaster_tests = b.addRunArtifact(farcaster_tests);
    const run_app_tests = b.addRunArtifact(app_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);
    test_step.dependOn(&run_integration_tests.step);
    test_step.dependOn(&run_libplue_tests.step);
    test_step.dependOn(&run_farcaster_tests.step);
    test_step.dependOn(&run_app_tests.step);

    // Individual test steps for granular testing
    const test_integration_step = b.step("test-integration", "Run integration tests");
    test_integration_step.dependOn(&run_integration_tests.step);

    const test_libplue_step = b.step("test-libplue", "Run libplue tests");
    test_libplue_step.dependOn(&run_libplue_tests.step);

    const test_farcaster_step = b.step("test-farcaster", "Run farcaster tests");
    test_farcaster_step.dependOn(&run_farcaster_tests.step);

    const test_app_step = b.step("test-app", "Run app tests");
    test_app_step.dependOn(&run_app_tests.step);

    // Add Swift build step that depends on Zig libraries
    const swift_build_cmd = b.addSystemCommand(&.{
        "swift", "build", "--configuration", "release",
        "-Xlinker", b.fmt("-L{s}", .{b.getInstallPath(.lib, "")}),
    });
    
    // Swift build depends on all Zig libraries being built and installed
    swift_build_cmd.step.dependOn(&lib.step);
    swift_build_cmd.step.dependOn(&c_lib.step);
    swift_build_cmd.step.dependOn(&farcaster_lib.step);
    
    // Create a step for building the complete project (Zig + Swift)
    const build_all_step = b.step("swift", "Build complete project including Swift");
    build_all_step.dependOn(&swift_build_cmd.step);
    
    // Make the default install step also build Swift
    b.getInstallStep().dependOn(&swift_build_cmd.step);
    
    // Add step to run the Swift executable
    const swift_run_cmd = b.addSystemCommand(&.{
        ".build/release/plue"
    });
    swift_run_cmd.step.dependOn(&swift_build_cmd.step);
    
    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the Swift app");
    run_step.dependOn(&swift_run_cmd.step);
    
    const run_swift_step = b.step("run-swift", "Run the Swift application");
    run_swift_step.dependOn(&swift_run_cmd.step);
}
