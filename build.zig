const std = @import("std");

// Shared SQLite compile flags (DRY across per-arch and root builds)
const sqlite_flags = [_][]const u8{
    "-DSQLITE_THREADSAFE=1",
    "-DSQLITE_OMIT_LOAD_EXTENSION",
    "-DSQLITE_DEFAULT_SYNCHRONOUS=1",
    "-DSQLITE_ENABLE_FTS5",
    "-DSQLITE_ENABLE_JSON1",
    "-DSQLITE_DQS=0",
};

fn addOptionalShellStep(
    b: *std.Build,
    name: []const u8,
    description: []const u8,
    script: []const u8,
) *std.Build.Step {
    const step = b.step(name, description);
    const cmd = b.addSystemCommand(&.{ "sh", "-c", script });
    step.dependOn(&cmd.step);
    return step;
}

// Build libsmithers (static) for a specific macOS CPU arch and return both the
// smithers library and the per-arch sqlite static library artifacts. Used by
// the xcframework packaging pipeline.
fn buildLibSmithersForArch(
    b: *std.Build,
    cpu_arch: std.Target.Cpu.Arch,
    optimize: std.builtin.OptimizeMode,
) struct { lib: *std.Build.Step.Compile, sqlite: *std.Build.Step.Compile } {
    const resolved = b.resolveTargetQuery(.{
        .cpu_arch = cpu_arch,
        .os_tag = .macos,
        .os_version_min = .{ .semver = .{ .major = 14, .minor = 0, .patch = 0 } },
    });

    // Per-arch build options (match root module defaults)
    const arch_build_opts = b.addOptions();
    arch_build_opts.addOption(bool, "enable_http_server_tests", false);
    arch_build_opts.addOption(bool, "enable_storage_module", false);

    // smithers module (per-arch) — unique name per arch to avoid collisions
    const arch_name = switch (cpu_arch) {
        .aarch64 => "smithers-arch-aarch64",
        .x86_64 => "smithers-arch-x86_64",
        else => "smithers-arch",
    };
    const arch_mod = b.addModule(arch_name, .{
        .root_source_file = b.path("src/lib.zig"),
        .target = resolved,
        .optimize = optimize,
    });
    arch_mod.addOptions("build_options", arch_build_opts);
    arch_mod.addIncludePath(b.path("pkg/sqlite"));

    // Optional zap dependency for http_server when enabled
    const zap_dep = b.dependency("zap", .{ .target = resolved, .optimize = optimize });
    arch_mod.addImport("zap", zap_dep.module("zap"));

    // Per-arch sqlite static library
    const sqlite_lib = b.addLibrary(.{
        .name = "sqlite3",
        .root_module = b.createModule(.{ .target = resolved, .optimize = optimize }),
        .linkage = .static,
    });
    sqlite_lib.addIncludePath(b.path("pkg/sqlite"));
    sqlite_lib.addCSourceFile(.{ .file = b.path("pkg/sqlite/sqlite3.c"), .flags = &sqlite_flags });
    sqlite_lib.linkLibC();

    // smithers static lib (per-arch). Root module = arch_mod (no redundant self-import).
    const lib = b.addLibrary(.{ .name = "smithers", .root_module = arch_mod, .linkage = .static });
    lib.addIncludePath(b.path("pkg/sqlite"));
    lib.linkLibC();
    lib.linkLibrary(sqlite_lib);

    return .{ .lib = lib, .sqlite = sqlite_lib };
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Build options consumed by src/lib.zig
    const build_opts = b.addOptions();
    build_opts.addOption(bool, "enable_http_server_tests", false);
    build_opts.addOption(bool, "enable_storage_module", false);

    // Root smithers module
    const mod = b.addModule("smithers", .{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
    });
    mod.addOptions("build_options", build_opts);
    mod.addIncludePath(b.path("pkg/sqlite"));

    // Wire zap dependency for modules that need it (http_server). Gated by
    // build option in src/lib.zig, so simply exposing the import is safe.
    const zap_dep_root = b.dependency("zap", .{ .target = target, .optimize = optimize });
    mod.addImport("zap", zap_dep_root.module("zap"));

    // CLI executable
    const exe = b.addExecutable(.{
        .name = "smithers-ctl",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "smithers", .module = mod }},
        }),
    });
    exe.root_module.addImport("zap", zap_dep_root.module("zap"));

    // Vendored SQLite amalgamation (native) as static library
    const sqlite_lib = b.addLibrary(.{
        .name = "sqlite3",
        .root_module = b.createModule(.{ .target = target, .optimize = optimize }),
        .linkage = .static,
    });
    sqlite_lib.addIncludePath(b.path("pkg/sqlite"));
    sqlite_lib.addCSourceFile(.{ .file = b.path("pkg/sqlite/sqlite3.c"), .flags = &sqlite_flags });
    sqlite_lib.linkLibC();

    exe.addIncludePath(b.path("pkg/sqlite"));
    exe.linkLibrary(sqlite_lib);
    b.installArtifact(exe);

    // Run step
    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    // Tests for root module and CLI module
    const mod_tests = b.addTest(.{ .root_module = mod });
    mod_tests.addIncludePath(b.path("pkg/sqlite"));
    mod_tests.linkLibrary(sqlite_lib);
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{ .root_module = exe.root_module });
    exe_tests.addIncludePath(b.path("pkg/sqlite"));
    exe_tests.linkLibrary(sqlite_lib);
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);

    // Optional integration steps (no-ops if directories are missing)
    const web_step = addOptionalShellStep(
        b,
        "web",
        "Build web app (if web/ + pnpm)",
        "if [ ! -d web ]; then echo 'skipping web: web/ not found'; elif ! command -v pnpm >/dev/null 2>&1; then echo 'skipping web: pnpm not installed'; else cd web && pnpm install && pnpm build; fi",
    );

    const playwright_step = addOptionalShellStep(
        b,
        "playwright",
        "Run Playwright e2e (if web/ + pnpm)",
        "if [ ! -d web ]; then echo 'skipping playwright: web/ not found'; elif ! command -v pnpm >/dev/null 2>&1; then echo 'skipping playwright: pnpm not installed'; else cd web && pnpm install && pnpm exec playwright test; fi",
    );
    _ = playwright_step;

    const codex_step = addOptionalShellStep(
        b,
        "codex",
        "Build codex submodule (if present)",
        "if [ -d submodules/codex ]; then cd submodules/codex && zig build; else echo \"skipping codex: submodules/codex not found\"; fi",
    );

    const jj_step = addOptionalShellStep(
        b,
        "jj",
        "Build jj submodule (if present)",
        "if [ -d submodules/jj ]; then cd submodules/jj && zig build; else echo \"skipping jj: submodules/jj not found\"; fi",
    );

    const xcode_test_step = addOptionalShellStep(
        b,
        "xcode-test",
        "Run Xcode tests (if macos/ exists)",
        "if [ -d macos ]; then xcodebuild test -project macos/Smithers.xcodeproj -scheme Smithers; else echo \"skipping xcode-test: macos/ not found\"; fi",
    );
    _ = xcode_test_step;

    const ui_test_step = addOptionalShellStep(
        b,
        "ui-test",
        "Run XCUITests (if macos/ exists)",
        "if [ -d macos ]; then xcodebuild test -project macos/Smithers.xcodeproj -scheme Smithers -only-testing:SmithersUITests; else echo \"skipping ui-test: macos/ not found\"; fi",
    );
    _ = ui_test_step;

    // Top-level xcframework step (wired later to concrete commands)
    const xc_step = b.step("xcframework", "Build SmithersKit.xcframework (macOS arm64 + x86_64)");

    // Dev step: ensure xcframework exists before launching Xcode
    const dev_step = b.step("dev", "Build everything + launch (if macos/ exists)");
    dev_step.dependOn(b.getInstallStep());
    dev_step.dependOn(web_step);
    dev_step.dependOn(codex_step);
    dev_step.dependOn(jj_step);
    dev_step.dependOn(xc_step);
    const xcode_build = b.addSystemCommand(&.{
        "sh",
        "-c",
        "if [ -d macos ]; then xcodebuild -project macos/Smithers.xcodeproj -scheme Smithers build && if [ -d .build/xcode/Build/Products/Debug/Smithers.app ]; then open .build/xcode/Build/Products/Debug/Smithers.app; else echo \"build succeeded; app not found at .build/xcode/Build/Products/Debug/Smithers.app\"; fi; else echo \"skipping dev: macos/ not found\"; fi",
    });
    dev_step.dependOn(&xcode_build.step);

    // Format & lint steps
    const fmt_check = b.addFmt(.{ .paths = &.{"."}, .check = true });
    const fmt_check_step = b.step("fmt-check", "Check Zig code formatting");
    fmt_check_step.dependOn(&fmt_check.step);

    const prettier_check_step = addOptionalShellStep(b, "prettier-check", "Check formatting with prettier (skips if missing)", "if command -v prettier >/dev/null 2>&1; then prettier --check .; else echo 'skipping prettier-check: prettier not installed'; fi");
    const typos_check_step = addOptionalShellStep(b, "typos-check", "Run spell checker (skips if missing)", "if command -v typos >/dev/null 2>&1; then typos; else echo 'skipping typos-check: typos not installed'; fi");
    const shellcheck_step = addOptionalShellStep(b, "shellcheck", "Lint shell scripts (skips if missing)", "if command -v shellcheck >/dev/null 2>&1; then find . -type f -name '*.sh' -exec shellcheck --severity=warning {} +; find . -type f -name '*.bash' -exec shellcheck --severity=warning {} +; else echo 'skipping shellcheck: shellcheck not installed'; fi");

    const all_step = b.step("all", "Run ALL checks (build + test + format + lint)");
    all_step.dependOn(b.getInstallStep());
    all_step.dependOn(test_step);
    all_step.dependOn(fmt_check_step);
    all_step.dependOn(prettier_check_step);
    all_step.dependOn(typos_check_step);
    all_step.dependOn(shellcheck_step);
    all_step.dependOn(web_step);

    // --- xcframework pipeline ---
    // Build per-arch static libraries, merge with libtool, create universal .a, then package.
    const arm = buildLibSmithersForArch(b, .aarch64, optimize);
    const x86 = buildLibSmithersForArch(b, .x86_64, optimize);

    // Ensure required Apple toolchain commands exist
    const xc_tools_check = b.addSystemCommand(&.{
        "sh",
        "-c",
        "for t in libtool lipo xcodebuild; do if ! command -v $t >/dev/null 2>&1; then echo 'xcframework: missing' $t >&2; exit 1; fi; done",
    });

    const lt_arm = b.addSystemCommand(&.{ "libtool", "-static", "-o" });
    const arm_merged = lt_arm.addOutputFileArg("libsmithers-merged-arm64.a");
    lt_arm.addFileArg(arm.lib.getEmittedBin());
    lt_arm.addFileArg(arm.sqlite.getEmittedBin());
    lt_arm.step.dependOn(&xc_tools_check.step);

    const lt_x86 = b.addSystemCommand(&.{ "libtool", "-static", "-o" });
    const x86_merged = lt_x86.addOutputFileArg("libsmithers-merged-x86_64.a");
    lt_x86.addFileArg(x86.lib.getEmittedBin());
    lt_x86.addFileArg(x86.sqlite.getEmittedBin());
    lt_x86.step.dependOn(&xc_tools_check.step);

    const lipo_cmd = b.addSystemCommand(&.{ "lipo", "-create", "-output" });
    const universal_out = lipo_cmd.addOutputFileArg("libsmithers.a");
    lipo_cmd.addFileArg(arm_merged);
    lipo_cmd.addFileArg(x86_merged);
    lipo_cmd.step.dependOn(&lt_arm.step);
    lipo_cmd.step.dependOn(&lt_x86.step);
    lipo_cmd.step.dependOn(&xc_tools_check.step);

    const xcfw_output_path = "dist/SmithersKit.xcframework";
    const mkdist_cmd = b.addSystemCommand(&.{ "mkdir", "-p", "dist" });
    const rm_cmd = b.addSystemCommand(&.{ "rm", "-rf", xcfw_output_path });
    rm_cmd.has_side_effects = true;

    const xcf_cmd = b.addSystemCommand(&.{ "xcodebuild", "-create-xcframework", "-library" });
    xcf_cmd.addFileArg(universal_out);
    xcf_cmd.addArgs(&.{ "-headers", "include", "-output", xcfw_output_path });
    xcf_cmd.has_side_effects = true;
    xcf_cmd.step.dependOn(&lipo_cmd.step);
    xcf_cmd.step.dependOn(&mkdist_cmd.step);
    xcf_cmd.step.dependOn(&rm_cmd.step);
    xcf_cmd.step.dependOn(&xc_tools_check.step);

    // Wire pipeline to the top-level step
    xc_step.dependOn(&xcf_cmd.step);
}
