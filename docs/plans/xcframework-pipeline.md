# Plan: xcframework-pipeline — Add SmithersKit xcframework build step

## Goal

Implement `zig build xcframework` to package libsmithers and headers into `dist/SmithersKit.xcframework` (macOS arm64 + x86_64). This replaces the current manually-built xcframework with a fully automated build pipeline.

## Current State

- **Pre-built xcframework** exists at `dist/SmithersKit.xcframework/` (45MB universal .a, arm64+x86_64)
- **Xcode project** references `../dist/SmithersKit.xcframework` and has "Verify SmithersKit.xcframework" build phase that auto-runs `zig build xcframework` if missing
- **Test scripts** exist at `tests/xcframework_test.sh` (structure validation) and `tests/xcframework_link_test.sh` (link test against both arches)
- **C header** at `include/libsmithers.h` (120 lines, 3 exported functions) + `include/module.modulemap`
- **build.zig** (287 lines): builds single-arch native static lib + SQLite, but has NO `xcframework` step

## Architecture

Pipeline mirrors Ghostty exactly:

```
arm64_module ──► arm64_lib ──► arm64_libtool (libsmithers.a + libsqlite3.a)
                                                                             ──► lipo (universal .a) ──► xcodebuild -create-xcframework
x86_64_module ──► x86_lib ──► x86_libtool  (libsmithers.a + libsqlite3.a)                               ▲
                                                                                                          │
                                                                                       include/ ──────────┘
```

Output structure expected by tests + Xcode:
```
dist/SmithersKit.xcframework/
├── Info.plist
└── macos-arm64_x86_64/
    ├── Headers/
    │   ├── libsmithers.h
    │   └── module.modulemap
    └── libsmithers-universal.a
```

## Implementation Steps

### Step 0: Write plan doc
- **File:** `docs/plans/xcframework-pipeline.md` (this file)
- **Layer:** docs

### Step 1: Add `buildLibSmithersForArch` helper function to build.zig
- **File:** `build.zig`
- **Layer:** zig
- **Details:**
  - Add a helper function `buildLibSmithersForArch(b, cpu_arch, optimize) -> { lib: *Compile, sqlite: *Compile }` that:
    1. Creates a resolved target with `b.resolveTargetQuery(.{ .cpu_arch = cpu_arch, .os_tag = .macos, .os_version_min = .{ .semver = .{ .major = 14, .minor = 0, .patch = 0 } } })`
    2. Creates a `build_options` module with same options as the main module (enable_http_server_tests=false, enable_storage_module=true)
    3. Creates a module with `.root_source_file = b.path("src/lib.zig")`, `.target = resolved_target`, `.optimize = optimize`
    4. Adds `mod.addIncludePath(b.path("pkg/sqlite"))` and `mod.addOptions("build_options", build_opts)`
    5. Creates the libsmithers static library with `.use_llvm = true`, `.bundle_compiler_rt = true`, `.bundle_ubsan_rt = true`, `.linkLibC()`
    6. Creates per-arch SQLite static library with same flags as the existing one, but targeting the cross-compile arch
    7. Links SQLite into libsmithers via `lib.linkLibrary(sqlite_lib)`
    8. Returns both compile artifacts
  - **Gotchas:**
    - `use_llvm = true` is REQUIRED for x86_64 cross-compilation on arm64 Mac
    - `bundle_compiler_rt` and `bundle_ubsan_rt` are `?bool`, set to `true`
    - Each arch module needs its OWN `build_options` attached (can't share the main module's)
    - SQLite must be built per-arch too (same C flags, different target)

### Step 2: Add libtool, lipo, and xcframework steps to build.zig
- **File:** `build.zig`
- **Layer:** zig
- **Details:**
  - Inline the pipeline steps directly in `build.zig` (no separate `src/build/` files — ticket scope)
  - **Per-arch libtool** (combines libsmithers.a + libsqlite3.a into single .a):
    ```
    libtool -static -o libsmithers-merged-<arch>.a libsmithers.a libsqlite3.a
    ```
    Use `b.addSystemCommand` with `addFileArg` for Zig-managed lazy paths
  - **Lipo** (creates universal binary from two arch-specific .a):
    ```
    lipo -create -output libsmithers-universal.a libsmithers-merged-arm64.a libsmithers-merged-x86_64.a
    ```
    Use `addOutputFileArg` for the output so Zig manages the cache path
  - **xcframework creation:**
    1. `rm -rf dist/SmithersKit.xcframework` (xcodebuild fails if output exists)
    2. `xcodebuild -create-xcframework -library <universal.a> -headers include/ -output dist/SmithersKit.xcframework`
    - Both commands use `has_side_effects = true` (writes to source tree)
    - Create step uses `expectExitCode(0)` + captures stdout/stderr
    - Delete step must run BEFORE create step (`run_create.step.dependOn(&run_delete.step)`)
  - Wire as `b.step("xcframework", "Build SmithersKit.xcframework (macOS arm64 + x86_64)")`
  - **Dependency chain:** arm64_build + x86_build → libtool_arm64 + libtool_x86 → lipo → rm -rf → xcodebuild

### Step 3: Wire `dev` step to depend on `xcframework`
- **File:** `build.zig`
- **Layer:** zig
- **Details:**
  - Make the existing `dev_step` depend on the `xcframework` step
  - This ensures Xcode always finds a fresh framework when `zig build dev` is used
  - The Xcode "Verify SmithersKit.xcframework" build phase is a fallback safety net, not the primary path

### Step 4: Verify existing tests pass
- **Layer:** zig (shell)
- **Details:**
  - Run `zig build xcframework` and verify it produces `dist/SmithersKit.xcframework`
  - Run `tests/xcframework_test.sh` — validates structure, Info.plist, Headers, .a files, lipo info, nm symbols
  - Run `tests/xcframework_link_test.sh` — compiles + links a test C program against both arches
  - Run `zig build all` to ensure nothing is broken
  - These tests already exist and cover all acceptance criteria — no new test files needed

### Step 5: Verify Xcode builds
- **Layer:** swift
- **Details:**
  - Run `xcodebuild -project macos/Smithers.xcodeproj -scheme Smithers build` to verify the fresh xcframework works
  - The Xcode project already references `../dist/SmithersKit.xcframework` and Swift files import SmithersKit

## Files

### To Create
- `docs/plans/xcframework-pipeline.md` (this file)

### To Modify
- `build.zig` — add `buildLibSmithersForArch` helper, libtool/lipo/xcframework steps, wire `xcframework` step, wire `dev` dependency

### No New Tests Needed
- `tests/xcframework_test.sh` already exists — validates structure
- `tests/xcframework_link_test.sh` already exists — validates linking
- Both cover all acceptance criteria

## Key Decisions

1. **Inline in build.zig, not src/build/ files** — Ticket says keep in build.zig. Ghostty uses separate files in src/build/ but that's a larger refactor deferred to a future ticket.

2. **`dev` step depends on `xcframework`** — Yes. The Xcode build phase auto-build is a fallback; the primary path should ensure freshness via `zig build dev`.

3. **Shared build_options per arch** — Each arch module gets its own `b.addOptions()` with identical values. Cannot share the main module's options because modules are per-target.

4. **Zap not linked** — Per research, Zap/HTTP is gated behind `enable_http_server_tests` (default false). The xcframework build uses `enable_http_server_tests = false`, so Zap is not compiled/linked. No action needed.

5. **Universal .a, not per-arch slices** — xcodebuild -create-xcframework with a single universal .a produces the `macos-arm64_x86_64` combined slice, matching the existing structure and test expectations.

## Risks

1. **x86_64 cross-compile may fail if LLVM backend unavailable** — Mitigated by `use_llvm = true`. Zig 0.15.2 ships with LLVM backend by default on macOS.

2. **libtool/lipo/xcodebuild availability** — These are macOS system tools, always present. CI uses macOS runners. Not a real risk.

3. **Existing pre-built xcframework must be replaced** — The `rm -rf` step handles this. First build will delete the manually-built one and replace with the automated one.

4. **Build time increase** — Building two architectures + libtool + lipo adds ~30-60s. Acceptable for `zig build xcframework` and `zig build dev`. Does NOT affect `zig build` (default), `zig build test`, or `zig build all`.
