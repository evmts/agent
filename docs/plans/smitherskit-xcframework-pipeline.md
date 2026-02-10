# Plan: SmithersKit XCFramework Pipeline

**Ticket:** smitherskit-xcframework-pipeline
**Layer:** Zig (build system only)
**Goal:** Add `zig build xcframework` step that produces `dist/SmithersKit.xcframework` with arm64 + x86_64 slices

## Context

The existing `build.zig` already builds a single-arch `libsmithers.a` (arm64-only on Apple Silicon) and installs `include/libsmithers.h`. We need to:

1. Build `libsmithers.a` for **both** `aarch64-macos` and `x86_64-macos`
2. For each arch, combine `libsmithers.a` + `libsqlite3.a` into a single fat `.a` via `libtool -static`
3. Combine both fat `.a` files into a universal binary via `lipo -create`
4. Run `xcodebuild -create-xcframework` to produce `dist/SmithersKit.xcframework`

Pattern follows Ghostty's `src/build/{LipoStep,LibtoolStep,XCFrameworkStep,GhosttyLib,GhosttyXCFramework}.zig` exactly.

## Architecture Decisions

- **Keep in `build.zig`** — No `src/build/` refactor. The ticket scope is narrow; extract to `src/build/` in a future refactor ticket.
- **Use `libtool -static`** — Combine `libsmithers.a` + `libsqlite3.a` into ONE `.a` per arch. Xcframework should ship a single library with all symbols. Ghostty pattern.
- **`use_llvm = true`** — Required for x86_64 cross-compilation on arm64 Mac. Ghostty confirms self-hosted fails.
- **`bundle_compiler_rt = true`, `bundle_ubsan_rt = true`** — Required for static libs or undefined symbols at link time.
- **`linkLibC()`** — Required for static lib (C runtime symbols). Ghostty does this.
- **macOS 14.0 minimum** — Per spec constraint (Sonoma).
- **Output path: `dist/SmithersKit.xcframework`** — Convention from ticket. `dist/` created if missing, gitignored.
- **No dSYM** — Static libraries don't support dsymutil (Ghostty returns null for static dsym).

## Implementation Steps

### Step 0: Add `dist/` to `.gitignore`

**File:** `.gitignore`

Add `dist/` to prevent the xcframework from being committed. It's a build artifact.

### Step 1: Add helper functions for libtool, lipo, xcodebuild

**File:** `build.zig`

Add three helper functions inline in `build.zig` (no separate files). Each returns a `std.Build.LazyPath` output:

```zig
/// Combines multiple .a files into one using `libtool -static`.
fn addLibtoolStep(b: *std.Build, name: []const u8, out_name: []const u8, sources: []const std.Build.LazyPath) std.Build.LazyPath {
    const run = b.addSystemCommand(&.{ "libtool", "-static", "-o" });
    const output = run.addOutputFileArg(out_name);
    for (sources) |source| run.addFileArg(source);
    return output;
}

/// Combines two arch-specific .a files into a universal binary using `lipo -create`.
fn addLipoStep(b: *std.Build, name: []const u8, out_name: []const u8, input_a: std.Build.LazyPath, input_b: std.Build.LazyPath) std.Build.LazyPath {
    const run = b.addSystemCommand(&.{ "lipo", "-create", "-output" });
    const output = run.addOutputFileArg(out_name);
    run.addFileArg(input_a);
    run.addFileArg(input_b);
    return output;
}

/// Runs `xcodebuild -create-xcframework` with a universal .a + headers dir.
fn addXCFrameworkStep(b: *std.Build, universal_lib: std.Build.LazyPath, headers_dir: std.Build.LazyPath, out_path: []const u8) *std.Build.Step {
    // Must delete old xcframework first (xcodebuild fails if it exists)
    const rm = b.addSystemCommand(&.{ "rm", "-rf", out_path });
    // Ensure dist/ directory exists
    const mkdir = b.addSystemCommand(&.{ "mkdir", "-p", std.fs.path.dirname(out_path) orelse "dist" });
    mkdir.step.dependOn(&rm.step);
    // Create xcframework
    const create = b.addSystemCommand(&.{ "xcodebuild", "-create-xcframework" });
    create.addArg("-library");
    create.addFileArg(universal_lib);
    create.addArg("-headers");
    create.addFileArg(headers_dir);
    create.addArg("-output");
    create.addArg(out_path);
    create.step.dependOn(&mkdir.step);
    return &create.step;
}
```

### Step 2: Build static lib per architecture with bundled deps

**File:** `build.zig`

Add a helper function that creates a static lib targeting a specific architecture:

```zig
fn buildStaticLibForTarget(b: *std.Build, resolved_target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) struct { lib_output: std.Build.LazyPath, sqlite_output: std.Build.LazyPath } {
    // SQLite for this target
    const sqlite_dep = b.dependency("sqlite", .{ .target = resolved_target, .optimize = optimize });
    const sqlite_lib = sqlite_dep.artifact("sqlite3");

    // Smithers module for this target
    const mod = b.createModule(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = resolved_target,
        .optimize = optimize,
    });
    mod.addIncludePath(sqlite_dep.path("."));

    // Static library with LLVM, compiler_rt, ubsan_rt, libc
    const lib = b.addLibrary(.{
        .name = "smithers",
        .root_module = mod,
        .linkage = .static,
        .use_llvm = true,
    });
    lib.linkLibrary(sqlite_lib);
    lib.linkLibC();
    lib.bundle_compiler_rt = true;
    lib.bundle_ubsan_rt = true;

    return .{
        .lib_output = lib.getEmittedBin(),
        .sqlite_output = sqlite_lib.getEmittedBin(),
    };
}
```

### Step 3: Wire `xcframework` build step

**File:** `build.zig`

In the `build()` function, add the `xcframework` step that orchestrates:

1. Build aarch64-macos static lib + SQLite
2. Build x86_64-macos static lib + SQLite
3. `libtool -static` to combine smithers.a + sqlite3.a for each arch
4. `lipo -create` to combine both fat .a files into universal
5. `xcodebuild -create-xcframework` with universal lib + `include/` headers

```zig
// XCFramework step
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

// libtool: combine smithers + sqlite per arch
const arm64_fat = addLibtoolStep(b, "arm64", "libsmithers-fat.a", &.{ arm64_build.lib_output, arm64_build.sqlite_output });
const x86_64_fat = addLibtoolStep(b, "x86_64", "libsmithers-fat.a", &.{ x86_64_build.lib_output, x86_64_build.sqlite_output });

// lipo: combine both arches
const universal = addLipoStep(b, "universal", "libsmithers.a", arm64_fat, x86_64_fat);

// xcodebuild: create xcframework
const xcfw_step = addXCFrameworkStep(b, universal, b.path("include"), "dist/SmithersKit.xcframework");
xcframework_step.dependOn(xcfw_step);
```

### Step 4: Add xcframework validation test

**File:** `tests/xcframework_test.sh`

Shell script that validates the produced xcframework:

1. Check `dist/SmithersKit.xcframework` exists
2. Check `Info.plist` is present
3. Check `Headers/libsmithers.h` is present
4. Check `libsmithers.a` has both arm64 and x86_64 slices (`lipo -info`)
5. Check key symbols exist (`nm -g | grep smithers_app_new`)

This test is NOT wired into `zig build all` (xcframework is opt-in) but can be run after `zig build xcframework`.

### Step 5: Verify `zig build all` remains green

Run `zig build all` to confirm the xcframework step doesn't break existing build steps. The `xcframework` step is independent — it's NOT wired into `all` or `install` (it's opt-in via `zig build xcframework`).

## Dependency Graph

```
zig build xcframework
├── xcodebuild -create-xcframework
│   ├── rm -rf dist/SmithersKit.xcframework
│   ├── mkdir -p dist
│   └── depends on: universal lib + include/ headers
│
├── lipo -create (universal libsmithers.a)
│   ├── libtool -static (arm64 fat)
│   │   ├── libsmithers.a (aarch64-macos)
│   │   └── libsqlite3.a (aarch64-macos)
│   └── libtool -static (x86_64 fat)
│       ├── libsmithers.a (x86_64-macos)
│       └── libsqlite3.a (x86_64-macos)
```

## Risks

1. **x86_64 cross-compilation may fail without LLVM** — Mitigated by `use_llvm = true` (Ghostty pattern). If Zig self-hosted can't target x86_64-macos from arm64, LLVM backend is the fallback.
2. **`bundle_compiler_rt`/`bundle_ubsan_rt` are `?bool` in Zig 0.15** — Must set to `true` explicitly, not just truthy. Verified against stdlib source.
3. **`xcodebuild` may not be available in all CI environments** — Only macOS runners have it. Step will fail gracefully on Linux.
4. **libtool output file naming collision** — Both arches produce `libsmithers-fat.a` but in different Zig cache dirs (LazyPath handles this automatically).
5. **SQLite dep must be re-created per target** — Can't reuse the default-target SQLite for cross-arch builds. Each arch gets its own `b.dependency("sqlite", ...)` call with the specific target.

## Files Summary

### Create
- `tests/xcframework_test.sh` — Post-build validation script

### Modify
- `build.zig` — Add helper functions + `xcframework` step
- `.gitignore` — Add `dist/`

### Docs
- (None required beyond this plan; README note about consuming xcframework is in acceptance criteria — add as inline comment or section)
