const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Shared library for Bun FFI
    const lib = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "plue_ssh",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/lib.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    // Link libssh from homebrew
    lib.root_module.addSystemIncludePath(.{ .cwd_relative = "/opt/homebrew/include" });
    lib.root_module.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/lib" });
    lib.root_module.linkSystemLibrary("ssh", .{});

    b.installArtifact(lib);

    // CLI executable for testing
    const exe = b.addExecutable(.{
        .name = "plue-ssh",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    // Link libssh for CLI
    exe.root_module.addSystemIncludePath(.{ .cwd_relative = "/opt/homebrew/include" });
    exe.root_module.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/lib" });
    exe.root_module.linkSystemLibrary("ssh", .{});

    b.installArtifact(exe);

    // Run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the CLI");
    run_step.dependOn(&run_cmd.step);

    // Tests
    const lib_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/lib.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    lib_tests.root_module.addSystemIncludePath(.{ .cwd_relative = "/opt/homebrew/include" });
    lib_tests.root_module.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/lib" });
    lib_tests.root_module.linkSystemLibrary("ssh", .{});

    const run_lib_tests = b.addRunArtifact(lib_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_tests.step);
}
