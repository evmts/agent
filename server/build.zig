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

    // Link libgcc_s for unwinding symbols required by Rust std library (voltaire crypto)
    if (target.result.os.tag == .linux) {
        exe.linkSystemLibrary("gcc_s");
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

    // Link jj-ffi library for tests
    unit_tests.step.dependOn(&jj_ffi_build.step);
    unit_tests.addIncludePath(b.path("jj-ffi"));
    unit_tests.addLibraryPath(b.path("jj-ffi/target/release"));
    unit_tests.linkSystemLibrary("jj_ffi");
    unit_tests.linkLibC();

    // Link system libraries required by jj-lib for tests
    if (target.result.os.tag == .macos) {
        unit_tests.linkFramework("Security");
        unit_tests.linkFramework("CoreFoundation");
        unit_tests.linkSystemLibrary("resolv");
    }

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // Integration tests
    const integration_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests/integration/mod.zig"),
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

    // Link jj-ffi library for integration tests
    integration_tests.step.dependOn(&jj_ffi_build.step);
    integration_tests.addIncludePath(b.path("jj-ffi"));
    integration_tests.addLibraryPath(b.path("jj-ffi/target/release"));
    integration_tests.linkSystemLibrary("jj_ffi");
    integration_tests.linkLibC();

    // Link system libraries required by jj-lib for integration tests
    if (target.result.os.tag == .macos) {
        integration_tests.linkFramework("Security");
        integration_tests.linkFramework("CoreFoundation");
        integration_tests.linkSystemLibrary("resolv");
    }

    const run_integration_tests = b.addRunArtifact(integration_tests);
    const integration_test_step = b.step("test:integration", "Run integration tests (requires TEST_DATABASE_URL)");
    integration_test_step.dependOn(&run_integration_tests.step);

    // All tests (unit + integration)
    const all_tests_step = b.step("test:all", "Run all tests (unit + integration)");
    all_tests_step.dependOn(&run_unit_tests.step);
    all_tests_step.dependOn(&run_integration_tests.step);

    // Agent test (LLM integration test)
    const agent_tests = b.addTest(.{
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

    agent_tests.step.dependOn(&jj_ffi_build.step);
    agent_tests.addIncludePath(b.path("jj-ffi"));
    agent_tests.addLibraryPath(b.path("jj-ffi/target/release"));
    agent_tests.linkSystemLibrary("jj_ffi");
    agent_tests.linkLibC();

    if (target.result.os.tag == .macos) {
        agent_tests.linkFramework("Security");
        agent_tests.linkFramework("CoreFoundation");
        agent_tests.linkSystemLibrary("resolv");
    }

    agent_tests.filters = &.{"agent reads file"};
    const run_agent_tests = b.addRunArtifact(agent_tests);
    const agent_test_step = b.step("test:agent", "Run agent LLM integration test");
    agent_test_step.dependOn(&run_agent_tests.step);
}
