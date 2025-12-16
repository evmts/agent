// There is currently no zig in this project
// We just use build.zig because it's essentially a better version of a MAKEFILE
// Run zig build --help to see all the available commands
const std = @import("std");

pub fn build(b: *std.Build) void {
    // ==========================================================
    // PyInstaller: Build Python server
    // ==========================================================
    const pyinstaller_step = b.step("pyinstaller", "Build Python server with PyInstaller");

    const pyinstaller_cmd = b.addSystemCommand(&.{
        ".venv/bin/pyinstaller",
        "--onefile",
        "--distpath",
        "tui/internal/embedded/bin",
        "--name",
        "agent-server",
        "--add-data",
        "agent:agent",
        "--add-data",
        "snapshot:snapshot",
        "--hidden-import",
        "uvicorn",
        "--hidden-import",
        "uvicorn.logging",
        "--hidden-import",
        "uvicorn.loops.auto",
        "--hidden-import",
        "uvicorn.protocols.http.auto",
        "--hidden-import",
        "uvicorn.protocols.websockets.auto",
        "--hidden-import",
        "uvicorn.lifespan.on",
        "--hidden-import",
        "fastapi",
        "--hidden-import",
        "starlette",
        "--hidden-import",
        "sse_starlette",
        "--hidden-import",
        "pydantic",
        "--hidden-import",
        "pydantic_ai",
        "--hidden-import",
        "anthropic",
        "--hidden-import",
        "httpx",
        "--hidden-import",
        "gitpython",
        "--hidden-import",
        "git",
        "--exclude-module",
        "logfire",
        "--copy-metadata",
        "genai_prices",
        "--copy-metadata",
        "pydantic_ai_slim",
        "--copy-metadata",
        "pydantic_ai",
        "main.py",
    });
    pyinstaller_step.dependOn(&pyinstaller_cmd.step);

    // ==========================================================
    // Go: Build TUI binary only (no PyInstaller)
    // ==========================================================
    const build_go_step = b.step("build-go", "Build Go TUI binary only");
    const build_go_cmd = b.addSystemCommand(&.{ "go", "build", "-C", "tui", "-o", "../agent-tui", "." });
    build_go_step.dependOn(&build_go_cmd.step);

    // ==========================================================
    // Full build: PyInstaller + Go (unified binary)
    // ==========================================================
    const build_step = b.step("build", "Build unified binary (PyInstaller + Go)");
    const full_go_cmd = b.addSystemCommand(&.{ "go", "build", "-C", "tui", "-o", "../agent-tui", "." });
    full_go_cmd.step.dependOn(&pyinstaller_cmd.step);
    build_step.dependOn(&full_go_cmd.step);

    // ==========================================================
    // Run: Build and run unified binary
    // ==========================================================
    const run_step = b.step("run", "Build and run the unified TUI");
    const run_cmd = b.addSystemCommand(&.{"./agent-tui"});
    run_cmd.step.dependOn(&full_go_cmd.step);
    run_step.dependOn(&run_cmd.step);

    // ==========================================================
    // Run dev: Run with external backend (no embedded server)
    // ==========================================================
    const run_dev_step = b.step("run-dev", "Run TUI with external backend");
    const run_dev_cmd = b.addSystemCommand(&.{ "./agent-tui", "--embedded=false" });
    run_dev_cmd.setEnvironmentVariable("BACKEND_URL", "http://localhost:8000");
    const build_go_for_dev = b.addSystemCommand(&.{ "go", "build", "-C", "tui", "-o", "../agent-tui", "." });
    run_dev_cmd.step.dependOn(&build_go_for_dev.step);
    run_dev_step.dependOn(&run_dev_cmd.step);

    // ==========================================================
    // Test: Run Go tests
    // ==========================================================
    const test_step = b.step("test", "Run Go tests");
    const test_cmd = b.addSystemCommand(&.{ "go", "test", "-C", "tui", "./..." });
    test_step.dependOn(&test_cmd.step);

    // ==========================================================
    // Clean: Remove all build artifacts
    // ==========================================================
    const clean_step = b.step("clean", "Remove all build artifacts");
    const clean_cmd = b.addSystemCommand(&.{
        "rm",
        "-rf",
        "agent-tui",
        "tui/internal/embedded/bin/agent-server",
        "build",
        "dist",
        "agent-server.spec",
    });
    clean_step.dependOn(&clean_cmd.step);

    // ==========================================================
    // Format: Format Go code
    // ==========================================================
    const fmt_step = b.step("fmt", "Format Go code");
    const fmt_cmd = b.addSystemCommand(&.{ "go", "fmt", "-C", "tui", "./..." });
    fmt_step.dependOn(&fmt_cmd.step);

    // ==========================================================
    // Lint: Run golangci-lint
    // ==========================================================
    const lint_step = b.step("lint", "Run golangci-lint");
    const lint_cmd = b.addSystemCommand(&.{ "golangci-lint", "run", "tui/..." });
    lint_step.dependOn(&lint_cmd.step);

    // ==========================================================
    // Deps: Install/update all dependencies
    // ==========================================================
    const deps_step = b.step("deps", "Install/update all dependencies");
    const go_deps_cmd = b.addSystemCommand(&.{ "go", "mod", "-C", "tui", "tidy" });
    const pip_deps_cmd = b.addSystemCommand(&.{ "uv", "pip", "install", "pyinstaller" });
    deps_step.dependOn(&go_deps_cmd.step);
    deps_step.dependOn(&pip_deps_cmd.step);

    // Default step is full build
    b.default_step = build_step;
}
