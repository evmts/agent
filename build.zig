const std = @import("std");

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

pub fn build(b: *std.Build) void {
    // Standard target options allow the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});
    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});
    // Build options for conditional compilation
    const build_opts = b.addOptions();
    build_opts.addOption(bool, "enable_http_server_tests", false);

    // It's also possible to define more custom flags to toggle optional features
    // of this build script using `b.option()`. All defined flags (including
    // target and optimize options) will be listed when running `zig build --help`
    // in this directory.

    // This creates a module, which represents a collection of source files alongside
    // some compilation options, such as optimization mode and linked system libraries.
    // Zig modules are the preferred way of making Zig code available to consumers.
    // addModule defines a module that we intend to make available for importing
    // to our consumers. We must give it a name because a Zig package can expose
    // multiple modules and consumers will need to be able to specify which
    // module they want to access.
    const mod = b.addModule("smithers", .{
        // The root source file is the "entry point" of this module. Users of
        // this module will only be able to access public declarations contained
        // in this file, which means that if you have declarations that you
        // intend to expose to consumers that were defined in other files part
        // of this module, you will have to make sure to re-export them from
        // the root file.
        .root_source_file = b.path("src/root.zig"),
        // Later on we'll use this module as the root module of a test executable
        // which requires us to specify a target.
        .target = target,
    });

    // Attach build options module for conditional compilation
    mod.addOptions("build_options", build_opts);

    // Here we define an executable. An executable needs to have a root module
    // which needs to expose a `main` function. While we could add a main function
    // to the module defined above, it's sometimes preferable to split business
    // logic and the CLI into two separate modules.
    //
    // If your goal is to create a Zig library for others to use, consider if
    // it might benefit from also exposing a CLI tool. A parser library for a
    // data serialization format could also bundle a CLI syntax checker, for example.
    //
    // If instead your goal is to create an executable, consider if users might
    // be interested in also being able to embed the core functionality of your
    // program in their own executable in order to avoid the overhead involved in
    // subprocessing your CLI tool.
    //
    // If neither case applies to you, feel free to delete the declaration you
    // don't need and to put everything under a single module.
    const exe = b.addExecutable(.{
        .name = "agent",
        .root_module = b.createModule(.{
            // b.createModule defines a new module just like b.addModule but,
            // unlike b.addModule, it does not expose the module to consumers of
            // this package, which is why in this case we don't have to give it a name.
            .root_source_file = b.path("src/main.zig"),
            // Target and optimization levels must be explicitly wired in when
            // defining an executable or library (in the root module), and you
            // can also hardcode a specific target for an executable or library
            // definition if desireable (e.g. firmware for embedded devices).
            .target = target,
            .optimize = optimize,
            // List of modules available for import in source files part of the
            // root module.
            .imports = &.{
                // Here "agent" is the name you will use in your source code to
                // import this module (e.g. `@import("agent")`). The name is
                // repeated because you are allowed to rename your imports, which
                // can be extremely useful in case of collisions (which can happen
                // importing modules from different packages).
                .{ .name = "smithers", .module = mod },
            },
        }),
    });

    // This declares intent for the executable to be installed into the
    // install prefix when running `zig build` (i.e. when executing the default
    // step). By default the install prefix is `zig-out/` but can be overridden
    // by passing `--prefix` or `-p`.
    b.installArtifact(exe);

    // This creates a top level step. Top level steps have a name and can be
    // invoked by name when running `zig build` (e.g. `zig build run`).
    // This will evaluate the `run` step rather than the default step.
    // For a top level step to actually do something, it must depend on other
    // steps (e.g. a Run step, as we will see in a moment).
    const run_step = b.step("run", "Run the app");

    // This creates a RunArtifact step in the build graph. A RunArtifact step
    // invokes an executable compiled by Zig. Steps will only be executed by the
    // runner if invoked directly by the user (in the case of top level steps)
    // or if another step depends on it, so it's up to you to define when and
    // how this Run step will be executed. In our case we want to run it when
    // the user runs `zig build run`, so we create a dependency link.
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    // By making the run step depend on the default step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Creates an executable that will run `test` blocks from the provided module.
    // Here `mod` needs to define a target, which is why earlier we made sure to
    // set the releative field.
    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    // A run step that will run the test executable.
    const run_mod_tests = b.addRunArtifact(mod_tests);

    // Creates an executable that will run `test` blocks from the executable's
    // root module. Note that test executables only test one module at a time,
    // hence why we have to create two separate ones.
    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    // A run step that will run the second test executable.
    const run_exe_tests = b.addRunArtifact(exe_tests);

    // A top level step for running all tests. dependOn can be called multiple
    // times and since the two run steps do not depend on one another, this will
    // make the two of them run in parallel.
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);

    // Optional integration steps (no-ops if directories are missing).
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
        "if [ ! -d web ]; then echo 'skipping playwright: web/ not found'; elif ! command -v pnpm >/dev/null 2>&1; then echo 'skipping playwright: pnpm not installed'; else cd web && pnpm install && pnpm exec playwright --version >/dev/null 2>&1 && pnpm exec playwright test; fi",
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

    const dev_step = b.step("dev", "Build everything + launch (if macos/ exists)");
    dev_step.dependOn(b.getInstallStep());
    dev_step.dependOn(web_step);
    dev_step.dependOn(codex_step);
    dev_step.dependOn(jj_step);
    const xcode_build = b.addSystemCommand(&.{
        "sh",
        "-c",
        "if [ -d macos ]; then xcodebuild -project macos/Smithers.xcodeproj -scheme Smithers build && if [ -d .build/xcode/Build/Products/Debug/Smithers.app ]; then open .build/xcode/Build/Products/Debug/Smithers.app; else echo \"build succeeded; app not found at .build/xcode/Build/Products/Debug/Smithers.app\"; fi; else echo \"skipping dev: macos/ not found\"; fi",
    });
    dev_step.dependOn(&xcode_build.step);

    // Format check step (zig fmt --check .)
    const fmt_check = b.addFmt(.{
        .paths = &.{"."},
        .check = true,
    });
    const fmt_check_step = b.step("fmt-check", "Check Zig code formatting");
    fmt_check_step.dependOn(&fmt_check.step);

    // Replaced: Prettier/Typos/Shellcheck checks
    const prettier_check_step = addOptionalShellStep(b, "prettier-check", "Check formatting with prettier (skips if missing)", "if command -v prettier >/dev/null 2>&1; then prettier --check .; else echo 'skipping prettier-check: prettier not installed'; fi");

    const typos_check_step = addOptionalShellStep(b, "typos-check", "Run spell checker (skips if missing)", "if command -v typos >/dev/null 2>&1; then typos; else echo 'skipping typos-check: typos not installed'; fi");

    const shellcheck_step = addOptionalShellStep(b, "shellcheck", "Lint shell scripts (skips if missing)", "if command -v shellcheck >/dev/null 2>&1; then find . -type f -name '*.sh' -exec shellcheck --severity=warning {} +; find . -type f -name '*.bash' -exec shellcheck --severity=warning {} +; else echo 'skipping shellcheck: shellcheck not installed'; fi");

    // ALL checks step - runs EVERYTHING
    const all_step = b.step("all", "Run ALL checks (build + test + format + lint)");
    all_step.dependOn(b.getInstallStep()); // Build
    all_step.dependOn(test_step); // Tests
    all_step.dependOn(fmt_check_step); // Zig fmt check
    all_step.dependOn(prettier_check_step); // Prettier check
    all_step.dependOn(typos_check_step); // Spell check
    all_step.dependOn(shellcheck_step); // Shell lint
    all_step.dependOn(web_step);

    // Just like flags, top level steps are also listed in the `--help` menu.
    //
    // The Zig build system is entirely implemented in userland, which means
    // that it cannot hook into private compiler APIs. All compilation work
    // orchestrated by the build system will result in other Zig compiler
    // subcommands being invoked with the right flags defined. You can observe
    // these invocations when one fails (or you pass a flag to increase
    // verbosity) to validate assumptions and diagnose problems.
    //
    // Lastly, the Zig build system is relatively simple and self-contained,
    // and reading its source code will allow you to master it.
}
