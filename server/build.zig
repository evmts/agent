const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Dependencies
    const httpz_dep = b.dependency("httpz", .{
        .target = target,
        .optimize = optimize,
    });

    const pg_dep = b.dependency("pg", .{
        .target = target,
        .optimize = optimize,
    });

    // Voltaire dependency (Ethereum primitives with SIWE, secp256k1, keccak)
    const voltaire_dep = b.dependency("voltaire", .{
        .target = target,
        .optimize = optimize,
    });

    // Build jj-ffi Rust library
    const jj_ffi_build = b.addSystemCommand(&.{
        "cargo",
        "build",
        "--release",
        "--manifest-path",
        "jj-ffi/Cargo.toml",
    });

    // Main executable
    const exe = b.addExecutable(.{
        .name = "server-zig",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "httpz", .module = httpz_dep.module("httpz") },
                .{ .name = "pg", .module = pg_dep.module("pg") },
                .{ .name = "primitives", .module = voltaire_dep.module("primitives") },
                .{ .name = "crypto", .module = voltaire_dep.module("crypto") },
            },
        }),
    });

    // Link jj-ffi library
    exe.step.dependOn(&jj_ffi_build.step);
    exe.addIncludePath(b.path("jj-ffi"));
    exe.addLibraryPath(b.path("jj-ffi/target/release"));
    exe.linkSystemLibrary("jj_ffi");
    exe.linkLibC();

    // Link system libraries required by jj-lib
    if (target.result.os.tag == .macos) {
        exe.linkFramework("Security");
        exe.linkFramework("CoreFoundation");
        exe.linkSystemLibrary("resolv");
    }

    b.installArtifact(exe);

    // Run command
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the server");
    run_step.dependOn(&run_cmd.step);

    // Tests
    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "httpz", .module = httpz_dep.module("httpz") },
                .{ .name = "pg", .module = pg_dep.module("pg") },
                .{ .name = "primitives", .module = voltaire_dep.module("primitives") },
                .{ .name = "crypto", .module = voltaire_dep.module("crypto") },
            },
        }),
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
