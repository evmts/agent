const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Match upstream naming convention (sqlite3) and ship as a static lib.
    const lib = b.addLibrary(.{
        .name = "sqlite3",
        .root_module = b.createModule(.{ .target = target, .optimize = optimize }),
        .linkage = .static,
    });

    // Compile the amalgamation with hardened, feature-complete flags.
    lib.addCSourceFile(.{
        .file = b.path("sqlite3.c"),
        .flags = &.{
            "-DSQLITE_THREADSAFE=1",
            "-DSQLITE_OMIT_LOAD_EXTENSION",
            "-DSQLITE_DEFAULT_SYNCHRONOUS=1",
            "-DSQLITE_ENABLE_FTS5",
            "-DSQLITE_ENABLE_JSON1",
            "-DSQLITE_DQS=0",
            // Avoid UBSan symbol requirements when linking into Xcode-built targets.
            "-fno-sanitize=undefined",
            "-fno-sanitize=integer",
        },
    });
    lib.addIncludePath(b.path("."));
    lib.linkLibC();

    b.installArtifact(lib);
}
