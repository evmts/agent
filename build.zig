// There is currently no zig in this project
// We just use build.zig because it's essentially a better version of a MAKEFILE
// Run zig build --help to see all the available commands
const std = @import("std");

pub fn build(b: *std.Build) void {
    // ==========================================================
    // Go: Build TUI binary
    // ==========================================================
    const build_tui_step = b.step("tui", "Build Go TUI binary");
    const build_tui_cmd = b.addSystemCommand(&.{ "go", "build", "-C", "tui", "-o", "../agent-tui", "." });
    build_tui_step.dependOn(&build_tui_cmd.step);

    // ==========================================================
    // Run TUI: Build and run the TUI (connects to external server)
    // ==========================================================
    const run_tui_step = b.step("run-tui", "Build and run TUI (connects to localhost:8000)");
    const run_tui_build = b.addSystemCommand(&.{ "go", "build", "-C", "tui", "-o", "../agent-tui", "." });
    // Use exec to replace shell process, ensuring proper TTY passthrough
    const run_tui_cmd = b.addSystemCommand(&.{ "sh", "-c", "exec ./agent-tui --embedded=false" });
    run_tui_cmd.step.dependOn(&run_tui_build.step);
    run_tui_step.dependOn(&run_tui_cmd.step);

    // ==========================================================
    // Run: Build and run TUI with embedded Python server (default)
    // ==========================================================
    const run_step = b.step("run", "Build and run TUI with embedded server");
    const run_tui_build_default = b.addSystemCommand(&.{ "go", "build", "-C", "tui", "-o", "../agent-tui", "." });
    // Use exec to replace shell process, ensuring proper TTY passthrough
    const run_cmd = b.addSystemCommand(&.{ "sh", "-c", "exec ./agent-tui --embedded" });
    run_cmd.step.dependOn(&run_tui_build_default.step);
    run_step.dependOn(&run_cmd.step);

    // ==========================================================
    // Run Server: Start just the Python server
    // ==========================================================
    const run_server_step = b.step("run-server", "Start just the Python server");
    const run_server_cmd = b.addSystemCommand(&.{ ".venv/bin/python", "main.py" });
    run_server_step.dependOn(&run_server_cmd.step);

    // ==========================================================
    // Test: Run Python tests
    // ==========================================================
    const test_step = b.step("test", "Run Python tests");
    const test_cmd = b.addSystemCommand(&.{ ".venv/bin/pytest" });
    test_step.dependOn(&test_cmd.step);

    // ==========================================================
    // Test Go: Run Go SDK tests
    // ==========================================================
    const test_go_step = b.step("test-go", "Run Go SDK tests");
    const test_go_cmd = b.addSystemCommand(&.{ "go", "test", "-C", "sdk/agent", "./..." });
    test_go_step.dependOn(&test_go_cmd.step);

    // ==========================================================
    // Clean: Remove all build artifacts
    // ==========================================================
    const clean_step = b.step("clean", "Remove all build artifacts");
    const clean_cmd = b.addSystemCommand(&.{
        "rm",
        "-rf",
        "build",
        "dist",
        "agent-tui",
        "*.spec",
    });
    clean_step.dependOn(&clean_cmd.step);

    // ==========================================================
    // Deps: Install/update all dependencies
    // ==========================================================
    const deps_step = b.step("deps", "Install/update all dependencies");
    const pip_deps_cmd = b.addSystemCommand(&.{ "uv", "pip", "install", "-e", "." });
    const go_deps_cmd = b.addSystemCommand(&.{ "go", "mod", "-C", "tui", "tidy" });
    deps_step.dependOn(&pip_deps_cmd.step);
    deps_step.dependOn(&go_deps_cmd.step);

    // ==========================================================
    // Format: Format Go code
    // ==========================================================
    const fmt_step = b.step("fmt", "Format Go code");
    const fmt_cmd = b.addSystemCommand(&.{ "go", "fmt", "-C", "tui", "./..." });
    fmt_step.dependOn(&fmt_cmd.step);

    // Default step is run
    b.default_step = run_step;
}
