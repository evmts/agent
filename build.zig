const std = @import("std");

fn addOptionalShellStep(b: *std.Build, name: []const u8, description: []const u8, script: []const u8) *std.Build.Step {
    const step = b.step(name, description);
    const cmd = b.addSystemCommand(&.{ "sh", "-c", script });
    step.dependOn(&cmd.step);
    return step;
}

fn addLibtoolStep(b: *std.Build, out_name: []const u8, sources: []const std.Build.LazyPath) std.Build.LazyPath {
    const run = b.addSystemCommand(&.{ "libtool", "-static", "-o" });
    const output = run.addOutputFileArg(out_name);
    for (sources) |source| run.addFileArg(source);
    return output;
}

fn addLipoStep(b: *std.Build, out_name: []const u8, input_a: std.Build.LazyPath, input_b: std.Build.LazyPath) std.Build.LazyPath {
    const run = b.addSystemCommand(&.{ "lipo", "-create", "-output" });
    const output = run.addOutputFileArg(out_name);
    run.addFileArg(input_a);
    run.addFileArg(input_b);
    return output;
}

fn addXCFrameworkStep(
    b: *std.Build,
    per_arch_libs: []const std.Build.LazyPath,
    headers_dir: std.Build.LazyPath,
    out_rel: []const u8,
) *std.Build.Step {
    // Resolve output relative to build root to avoid CWD surprises.
    const out_lp = b.path(out_rel);

    // Cleanup any prior output.
    const rm = b.addSystemCommand(&.{ "rm", "-rf" });
    rm.addFileArg(out_lp);

    // Create the xcframework from per-arch libraries (clearer per-arch slices).
    const create = b.addSystemCommand(&.{ "xcodebuild", "-create-xcframework" });
    for (per_arch_libs) |libpath| {
        create.addArg("-library");
        create.addFileArg(libpath);
        create.addArg("-headers");
        create.addFileArg(headers_dir);
    }
    create.addArg("-output");
    create.addFileArg(out_lp);
    create.step.dependOn(&rm.step);
    return &create.step;
}

fn buildStaticLibForTarget(b: *std.Build, resolved_target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) struct { lib_output: std.Build.LazyPath, sqlite_output: std.Build.LazyPath } {
    const sqlite_dep = b.dependency("sqlite", .{ .target = resolved_target, .optimize = optimize });
    const sqlite_lib = sqlite_dep.artifact("sqlite3");

    const mod = b.createModule(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = resolved_target,
        .optimize = optimize,
    });
    mod.addIncludePath(sqlite_dep.path("."));

    const lib = b.addLibrary(.{ .name = "smithers", .root_module = mod, .linkage = .static, .use_llvm = true });
    lib.linkLibrary(sqlite_lib);
    lib.linkLibC();
    lib.bundle_compiler_rt = true;
    lib.bundle_ubsan_rt = true;

    return .{ .lib_output = lib.getEmittedBin(), .sqlite_output = sqlite_lib.getEmittedBin() };
}
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Bring in vendored SQLite (pkg/sqlite) as a static library dependency
    const sqlite_dep = b.dependency("sqlite", .{ .target = target, .optimize = optimize });
    const sqlite_lib = sqlite_dep.artifact("sqlite3");

    // Core module (source of truth for tests & consumers)
    const mod = b.addModule("smithers", .{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Static library (xcframework input for Swift)
    const lib = b.addLibrary(.{ .name = "smithers", .root_module = mod, .linkage = .static, .use_llvm = true });
    mod.addIncludePath(sqlite_dep.path("."));
    lib.linkLibrary(sqlite_lib);
    lib.bundle_compiler_rt = true;
    lib.bundle_ubsan_rt = true;
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
    exe.linkLibrary(sqlite_lib);
    b.installArtifact(exe);

    // Run
    const run_step = b.step("run", "Run the CLI");
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_step.dependOn(&run_cmd.step);
    if (b.args) |args| run_cmd.addArgs(args);

    // Tests
    const mod_tests = b.addTest(.{ .root_module = mod });
    mod_tests.root_module.addIncludePath(sqlite_dep.path("."));
    mod_tests.linkLibrary(sqlite_lib);
    const run_mod_tests = b.addRunArtifact(mod_tests);
    const exe_tests = b.addTest(.{ .root_module = exe.root_module });
    exe_tests.root_module.addIncludePath(sqlite_dep.path("."));
    exe_tests.linkLibrary(sqlite_lib);
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
    const xcode_build = b.addSystemCommand(&.{ "bash", "scripts/xcode_build_and_open.sh" });
    dev_step.dependOn(&xcode_build.step);

    // Format & lint
    const fmt_check = b.addFmt(.{ .paths = &.{"."}, .check = true });
    const fmt_check_step = b.step("fmt-check", "Check Zig code formatting");
    fmt_check_step.dependOn(&fmt_check.step);
    const prettier_check_step = addOptionalShellStep(b, "prettier-check", "Check with prettier (skips if missing)", "if command -v prettier >/dev/null 2>&1; then prettier --check .; else echo 'skipping prettier-check: prettier not installed'; fi");
    const typos_check_step = addOptionalShellStep(b, "typos-check", "Run spell checker (skips if missing)", "if command -v typos >/dev/null 2>&1; then typos; else echo 'skipping typos-check: typos not installed'; fi");
    const shellcheck_step = addOptionalShellStep(b, "shellcheck", "Lint shell scripts (skips if missing)", "if command -v shellcheck >/dev/null 2>&1; then find . -type f -name '*.sh' -exec shellcheck --severity=warning {} +; find . -type f -name '*.bash' -exec shellcheck --severity=warning {} +; else echo 'skipping shellcheck: shellcheck not installed'; fi");

    // All
    const all_step = b.step("all", "Build + tests + fmt + linters (+ web/codex/jj)");
    all_step.dependOn(b.getInstallStep());
    all_step.dependOn(test_step);
    all_step.dependOn(fmt_check_step);
    all_step.dependOn(prettier_check_step);
    all_step.dependOn(typos_check_step);
    all_step.dependOn(shellcheck_step);
    // Also build optional subsystems if present to keep the repo green end-to-end.
    all_step.dependOn(web_step);
    all_step.dependOn(codex_step);
    all_step.dependOn(jj_step);

    // C header compile smoke test (ensures header is valid C)
    const cc = b.addSystemCommand(&.{
        "sh",                                                                           "-c",
        "zig cc -Iinclude -Wall -Wextra -Werror -c tests/c_header_test.c -o /dev/null",
    });
    all_step.dependOn(&cc.step);

    // XCFramework: Build a universal static library and package with headers
    const xcframework_step = b.step("xcframework", "Build dist/SmithersKit.xcframework (universal macOS)");

    const aarch64_target = b.resolveTargetQuery(.{
        .cpu_arch = .aarch64,
        .os_tag = .macos,
        .os_version_min = .{ .semver = .{ .major = 14, .minor = 0, .patch = 0 } },
    });
    const x86_64_target = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .macos,
        .os_version_min = .{ .semver = .{ .major = 14, .minor = 0, .patch = 0 } },
    });

    const arm64_build = buildStaticLibForTarget(b, aarch64_target, optimize);
    const x86_64_build = buildStaticLibForTarget(b, x86_64_target, optimize);

    const arm64_fat = addLibtoolStep(b, "libsmithers-arm64-fat.a", &.{ arm64_build.lib_output, arm64_build.sqlite_output });
    const x86_64_fat = addLibtoolStep(b, "libsmithers-x86_64-fat.a", &.{ x86_64_build.lib_output, x86_64_build.sqlite_output });

    // Produce a universal archive and package as a single macOS slice for maximum compatibility.
    const universal = addLipoStep(b, "libsmithers-universal.a", arm64_fat, x86_64_fat);
    const xcfw_out = "dist/SmithersKit.xcframework"; // Resolved against build root below.
    const xcfw_create = addXCFrameworkStep(b, &.{universal}, b.path("include"), xcfw_out);
    xcframework_step.dependOn(xcfw_create);
    // Ensure `zig build dev` builds the xcframework before invoking Xcode.
    dev_step.dependOn(xcframework_step);
    xcode_build.step.dependOn(xcframework_step);

    // Optional: run xcframework validation scripts
    const xcfw_test = b.step("xcframework-test", "Validate SmithersKit.xcframework (headers, symbols, link)");
    xcfw_test.dependOn(xcfw_create);
    const test_xcfw = b.addSystemCommand(&.{ "bash", "tests/xcframework_test.sh" });
    const link_xcfw = b.addSystemCommand(&.{ "bash", "tests/xcframework_link_test.sh" });
    test_xcfw.step.dependOn(xcfw_create);
    link_xcfw.step.dependOn(&test_xcfw.step);
    xcfw_test.dependOn(&link_xcfw.step);
}
