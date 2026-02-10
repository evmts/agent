const std = @import("std");

fn addOptionalShellStep(b: *std.Build, name: []const u8, description: []const u8, script: []const u8) *std.Build.Step {
    const step = b.step(name, description);
    const cmd = b.addSystemCommand(&.{ "sh", "-c", script });
    step.dependOn(&cmd.step);
    return step;
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Core module (source of truth for tests & consumers)
    const mod = b.addModule("smithers", .{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Static library (xcframework input for Swift)
    const lib = b.addLibrary(.{ .name = "smithers", .root_module = mod, .linkage = .static });
    b.installArtifact(lib);

    // Install public C header alongside the static library
    const header_install = b.addInstallHeaderFile(b.path("include/libsmithers.h"), "libsmithers.h");
    b.getInstallStep().dependOn(&header_install.step);

    // CLI executable (smithers-ctl)
    const exe = b.addExecutable(.{
        .name = "smithers-ctl",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "smithers", .module = mod }},
        }),
    });
    b.installArtifact(exe);

    // Run
    const run_step = b.step("run", "Run the CLI");
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_step.dependOn(&run_cmd.step);
    if (b.args) |args| run_cmd.addArgs(args);

    // Tests
    const mod_tests = b.addTest(.{ .root_module = mod });
    const run_mod_tests = b.addRunArtifact(mod_tests);
    const exe_tests = b.addTest(.{ .root_module = exe.root_module });
    const run_exe_tests = b.addRunArtifact(exe_tests);
    const test_step = b.step("test", "Run Zig tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);

    // Optional integrations
    const web_step = addOptionalShellStep(b, "web", "Build web app (if web/ exists)", "if [ -d web ]; then cd web && pnpm install && pnpm build; else echo 'skipping web: web/ not found'; fi");
    const playwright_step = addOptionalShellStep(b, "playwright", "Run Playwright e2e (if web/ exists)", "if [ -d web ]; then cd web && pnpm install && pnpm exec playwright test; else echo 'skipping playwright: web/ not found'; fi");
    _ = playwright_step;
    const codex_step = addOptionalShellStep(b, "codex", "Build codex submodule (if present)", "if [ -d submodules/codex ]; then cd submodules/codex && zig build; else echo 'skipping codex: submodules/codex not found'; fi");
    const jj_step = addOptionalShellStep(b, "jj", "Build jj submodule (if present)", "if [ -d submodules/jj ]; then cd submodules/jj && zig build; else echo 'skipping jj: submodules/jj not found'; fi");
    const xcode_test_step = addOptionalShellStep(b, "xcode-test", "Run Xcode tests (if macos/ exists)", "if [ -d macos ]; then xcodebuild test -project macos/Smithers.xcodeproj -scheme Smithers; else echo 'skipping xcode-test: macos/ not found'; fi");
    _ = xcode_test_step;
    const ui_test_step = addOptionalShellStep(b, "ui-test", "Run XCUITests (if macos/ exists)", "if [ -d macos ]; then xcodebuild test -project macos/Smithers.xcodeproj -scheme Smithers -only-testing:SmithersUITests; else echo 'skipping ui-test: macos/ not found'; fi");
    _ = ui_test_step;

    // Dev: build everything + launch Xcode app if present
    const dev_step = b.step("dev", "Build everything + launch (if macos/ exists)");
    dev_step.dependOn(b.getInstallStep());
    dev_step.dependOn(web_step);
    dev_step.dependOn(codex_step);
    dev_step.dependOn(jj_step);
    const xcode_build = b.addSystemCommand(&.{
        "sh",                                                                                                                                                                                                                                                                                                                                                         "-c",
        "if [ -d macos ]; then xcodebuild -project macos/Smithers.xcodeproj -scheme Smithers build && if [ -d .build/xcode/Build/Products/Debug/Smithers.app ]; then open .build/xcode/Build/Products/Debug/Smithers.app; else echo 'build ok; app not found at .build/xcode/Build/Products/Debug/Smithers.app'; fi; else echo 'skipping dev: macos/ not found'; fi",
    });
    dev_step.dependOn(&xcode_build.step);

    // Format & lint
    const fmt_check = b.addFmt(.{ .paths = &.{"."}, .check = true });
    const fmt_check_step = b.step("fmt-check", "Check Zig code formatting");
    fmt_check_step.dependOn(&fmt_check.step);
    const prettier_check_step = addOptionalShellStep(b, "prettier-check", "Check with prettier (skips if missing)", "if command -v prettier >/dev/null 2>&1; then prettier --check .; else echo 'skipping prettier-check: prettier not installed'; fi");
    const typos_check_step = addOptionalShellStep(b, "typos-check", "Run spell checker (skips if missing)", "if command -v typos >/dev/null 2>&1; then typos; else echo 'skipping typos-check: typos not installed'; fi");
    const shellcheck_step = addOptionalShellStep(b, "shellcheck", "Lint shell scripts (skips if missing)", "if command -v shellcheck >/dev/null 2>&1; then find . -type f -name '*.sh' -exec shellcheck --severity=warning {} +; find . -type f -name '*.bash' -exec shellcheck --severity=warning {} +; else echo 'skipping shellcheck: shellcheck not installed'; fi");

    // All
    const all_step = b.step("all", "Build + tests + fmt + linters");
    all_step.dependOn(b.getInstallStep());
    all_step.dependOn(test_step);
    all_step.dependOn(fmt_check_step);
    all_step.dependOn(prettier_check_step);
    all_step.dependOn(typos_check_step);
    all_step.dependOn(shellcheck_step);

    // C header compile smoke test (ensures header is valid C)
    const cc = b.addSystemCommand(&.{
        "sh",                                                                           "-c",
        "zig cc -Iinclude -Wall -Wextra -Werror -c tests/c_header_test.c -o /dev/null",
    });
    all_step.dependOn(&cc.step);
}
