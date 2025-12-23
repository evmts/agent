const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Dependencies
    const pg_dep = b.dependency("pg", .{
        .target = target,
        .optimize = optimize,
    });

    // DB module
    const db_mod = b.addModule("db", .{
        .root_source_file = b.path("root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Tests
    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("root.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "pg", .module = pg_dep.module("pg") },
            },
        }),
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // Workflow integration tests
    const workflow_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test-workflows.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "pg", .module = pg_dep.module("pg") },
            },
        }),
    });

    const run_workflow_tests = b.addRunArtifact(workflow_tests);
    const workflow_test_step = b.step("test:workflows", "Run workflow DAO integration tests");
    workflow_test_step.dependOn(&run_workflow_tests.step);

    // Connection test (simpler, for debugging)
    const connection_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test-connection.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "pg", .module = pg_dep.module("pg") },
            },
        }),
    });

    const run_connection_test = b.addRunArtifact(connection_test);
    const connection_test_step = b.step("test:connection", "Run simple connection test");
    connection_test_step.dependOn(&run_connection_test.step);

    _ = db_mod;
}
