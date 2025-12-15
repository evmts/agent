const std = @import("std");

pub fn build(b: *std.Build) void {
    // Build the Go binary
    const build_step = b.step("build", "Build the TUI binary");
    const build_cmd = b.addSystemCommand(&.{ "go", "build", "-o", "tui", "." });
    build_step.dependOn(&build_cmd.step);

    // Run the TUI (depends on build)
    const run_step = b.step("run", "Build and run the TUI");
    const run_cmd = b.addSystemCommand(&.{"./tui"});
    run_cmd.step.dependOn(&build_cmd.step);
    run_step.dependOn(&run_cmd.step);

    // Run with dev backend
    const run_dev_step = b.step("run-dev", "Build and run with local backend");
    const run_dev_cmd = b.addSystemCommand(&.{"./tui"});
    run_dev_cmd.setEnvironmentVariable("BACKEND_URL", "http://localhost:8000");
    run_dev_cmd.step.dependOn(&build_cmd.step);
    run_dev_step.dependOn(&run_dev_cmd.step);

    // Run tests
    const test_step = b.step("test", "Run Go tests");
    const test_cmd = b.addSystemCommand(&.{ "go", "test", "./..." });
    test_step.dependOn(&test_cmd.step);

    // Clean build artifacts
    const clean_step = b.step("clean", "Remove build artifacts");
    const clean_cmd = b.addSystemCommand(&.{ "rm", "-f", "tui" });
    clean_step.dependOn(&clean_cmd.step);

    // Format code
    const fmt_step = b.step("fmt", "Format Go code");
    const fmt_cmd = b.addSystemCommand(&.{ "go", "fmt", "./..." });
    fmt_step.dependOn(&fmt_cmd.step);

    // Run linter
    const lint_step = b.step("lint", "Run golangci-lint");
    const lint_cmd = b.addSystemCommand(&.{ "golangci-lint", "run" });
    lint_step.dependOn(&lint_cmd.step);

    // Install/update dependencies
    const deps_step = b.step("deps", "Install/update Go dependencies");
    const deps_cmd = b.addSystemCommand(&.{ "go", "mod", "tidy" });
    deps_step.dependOn(&deps_cmd.step);

    // Default step is build
    b.default_step = build_step;
}
