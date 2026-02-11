# Context: xcframework-pipeline

## Summary

Add `zig build xcframework` step that builds libsmithers for arm64 + x86_64, merges with SQLite via libtool, creates universal binary via lipo, and packages into `dist/SmithersKit.xcframework` with headers + modulemap. Follows Ghostty's exact build patterns.

## Current State

### What Exists Already
- **Pre-built xcframework** at `dist/SmithersKit.xcframework/` with universal `libsmithers.a` (arm64+x86_64)
- **Xcode project** references `../dist/SmithersKit.xcframework` and has "Verify SmithersKit.xcframework" build phase that auto-runs `zig build xcframework` if missing
- **Test scripts** at `tests/xcframework_test.sh` (structure validation) and `tests/xcframework_link_test.sh` (link test against both arches)
- **C header** at `include/libsmithers.h` (120 lines, 3 exported functions)
- **Module map** at `include/module.modulemap` (SmithersKit module)
- **Context doc** at `docs/context/smitherskit-xcframework-pipeline.md` (prior research)

### What's Missing
- **No `zig build xcframework` step in build.zig** — the step name is referenced by Xcode but doesn't exist yet
- Current build.zig only builds single-arch (native) static lib via `b.addLibrary()`

### build.zig Structure (287 lines)
- Lines 108-127: SQLite static lib build (`sqlite_lib`)
- Lines 80-104: CLI executable (`smithers-ctl`) that links SQLite
- Lines 164-188: Test steps that link SQLite
- Lines 239-249: `dev` step (build + xcodebuild + launch)
- Lines 266-273: `all` step (build + test + fmt + lint)

## Ghostty Reference — Exact Patterns to Follow

### Pipeline: lib(arm64) + lib(x86_64) → libtool(per-arch) → lipo → xcodebuild -create-xcframework

### 1. LibtoolStep.zig (`../smithers/ghostty/src/build/LibtoolStep.zig`, 45 lines)
Combines multiple .a files into one:
```zig
const run_step = RunStep.create(b, b.fmt("libtool {s}", .{opts.name}));
run_step.addArgs(&.{ "libtool", "-static", "-o" });
const output = run_step.addOutputFileArg(opts.out_name);
for (opts.sources) |source| run_step.addFileArg(source);
```

### 2. LipoStep.zig (`../smithers/ghostty/src/build/LipoStep.zig`, 43 lines)
Combines two arch-specific .a into universal:
```zig
const run_step = RunStep.create(b, b.fmt("lipo {s}", .{opts.name}));
run_step.addArgs(&.{ "lipo", "-create", "-output" });
const output = run_step.addOutputFileArg(opts.out_name);
run_step.addFileArg(opts.input_a);
run_step.addFileArg(opts.input_b);
```

### 3. XCFrameworkStep.zig (`../smithers/ghostty/src/build/XCFrameworkStep.zig`, 78 lines)
Runs xcodebuild -create-xcframework:
```zig
// Delete old (required — xcodebuild fails if output exists)
const run_delete = RunStep.create(b, ...);
run_delete.has_side_effects = true;
run_delete.addArgs(&.{ "rm", "-rf", opts.out_path });

// Create new
const run_create = RunStep.create(b, ...);
run_create.has_side_effects = true;
run_create.addArgs(&.{ "xcodebuild", "-create-xcframework" });
for (opts.libraries) |lib| {
    run_create.addArg("-library");
    run_create.addFileArg(lib.library);
    run_create.addArg("-headers");
    run_create.addFileArg(lib.headers);  // directory, not file
}
run_create.addArg("-output");
run_create.addArg(opts.out_path);
run_create.expectExitCode(0);
_ = run_create.captureStdOut();
_ = run_create.captureStdErr();
run_create.step.dependOn(&run_delete.step);
```

### 4. GhosttyLib.initStatic — Critical static lib settings
```zig
const lib = b.addLibrary(.{
    .name = "ghostty",
    .root_module = b.createModule(.{
        .root_source_file = b.path("src/main_c.zig"),
        .target = deps.config.target,
        .optimize = deps.config.optimize,
    }),
    .use_llvm = true,  // Required for x86_64 cross-compile on arm64 Mac
});
lib.linkLibC();
lib.bundle_compiler_rt = true;   // Required for static lib symbols
lib.bundle_ubsan_rt = true;      // Required for static lib symbols
```

### 5. GhosttyLib.initMacOSUniversal — Arch targeting
```zig
const aarch64 = try initStatic(b, &try deps.retarget(b, genericMacOSTarget(b, .aarch64)));
const x86_64  = try initStatic(b, &try deps.retarget(b, genericMacOSTarget(b, .x86_64)));
const universal = LipoStep.create(b, .{
    .name = "ghostty",
    .out_name = "libghostty.a",
    .input_a = aarch64.output,
    .input_b = x86_64.output,
});
```

## Verified Zig 0.15.2 API Signatures

All verified against `/Users/williamcory/.zvm/0.15.2/lib/std/`:

### Build.resolveTargetQuery (Build.zig:2649)
```zig
pub fn resolveTargetQuery(b: *Build, query: Target.Query) ResolvedTarget
```

### Target.Query.os_version_min (Target/Query.zig:31)
```zig
os_version_min: ?OsVersion = null,
// OsVersion = union(enum) { none: void, semver: SemanticVersion, windows: ... }
```

### SemanticVersion (SemanticVersion.zig:8-11)
```zig
major: usize, minor: usize, patch: usize,
pre: ?[]const u8 = null, build: ?[]const u8 = null,
```

### Build.addLibrary (Build.zig:841)
```zig
pub fn addLibrary(b: *Build, options: LibraryOptions) *Step.Compile
```

### LibraryOptions (Build.zig:824-839)
```zig
pub const LibraryOptions = struct {
    linkage: std.builtin.LinkMode = .static,
    name: []const u8,
    root_module: *Module,
    version: ?std.SemanticVersion = null,
    max_rss: usize = 0,
    use_llvm: ?bool = null,
    use_lld: ?bool = null,
    zig_lib_dir: ?LazyPath = null,
    win32_manifest: ?LazyPath = null,
};
```

### Compile fields (Step/Compile.zig:41-42)
```zig
bundle_compiler_rt: ?bool = null,  // ?bool (not bool)
bundle_ubsan_rt: ?bool = null,     // ?bool (not bool)
```

### Compile.getEmittedBin (Step/Compile.zig:883)
```zig
pub fn getEmittedBin(compile: *Compile) LazyPath
```

## Xcode Integration

### project.pbxproj References
- `SmithersKit.xcframework` file ref points to `../dist/SmithersKit.xcframework` (line 53)
- Linked in Frameworks build phase for both app and test targets (lines 98, 102)
- "Verify SmithersKit.xcframework" shell script build phase (line 248):
  - Input: `${SRCROOT}/../dist/SmithersKit.xcframework/Info.plist`
  - Output: `${SRCROOT}/../dist/SmithersKit.stamp`
  - Auto-runs `zig build xcframework` if missing
- Swift files importing SmithersKit: `SmithersCore.swift`, `SmithersApp.swift`, `SmithersTests.swift`
- Build settings: `MACOSX_DEPLOYMENT_TARGET = 14.0`

## Zap/HTTP Server Status

`src/http_server.zig` imports Zap (`@import("zap")`) but is gated behind `enable_http_server_tests` build option (default false). The http_server module is only compiled when explicitly enabled. For the xcframework build, Zap does NOT need to be linked unless `enable_http_server_tests = true`. The current build.zig doesn't wire Zap as a dependency at all — it's declared in build.zig.zon but not imported via `b.dependency()`.

## Key Implementation Details

### Dependency Graph
```
arm64_mod ──► arm64_lib ──► arm64_libtool (libsmithers.a + libsqlite3.a)  ──► lipo ──► xcodebuild -create-xcframework
                                                                             ▲
x86_mod  ──► x86_lib   ──► x86_libtool  (libsmithers.a + libsqlite3.a)  ───┘          ▲
                                                                                       │
                                                                          include/ ─────┘
```

### Per-Arch Build Function Pattern
For each arch (aarch64, x86_64):
1. `b.resolveTargetQuery(.{ .cpu_arch = .aarch64, .os_tag = .macos, .os_version_min = .{ .semver = .{ .major = 14, .minor = 0, .patch = 0 } } })`
2. `b.createModule(.{ .root_source_file = b.path("src/lib.zig"), .target = resolved_target, .optimize = optimize })`
3. Add SQLite include path: `arch_mod.addIncludePath(b.path("pkg/sqlite"))`
4. Add build_options to module
5. `b.addLibrary(.{ .name = "smithers", .root_module = arch_mod, .use_llvm = true })`
6. Set `lib.bundle_compiler_rt = true` and `lib.bundle_ubsan_rt = true`
7. `lib.linkLibC()`
8. Build per-arch SQLite: same flags, same source, arch-specific target
9. `lib.linkLibrary(sqlite_arch_lib)` — links SQLite symbols into libsmithers
10. Use libtool to combine `lib.getEmittedBin()` + `sqlite_lib.getEmittedBin()` into single .a

### Critical Gotchas
1. **`use_llvm = true`** — Required for x86_64 cross-compilation on arm64 Mac. Ghostty: "Fails on self-hosted x86_64 on macOS"
2. **`bundle_compiler_rt = true`** — Required for static libs or undefined symbols at link
3. **`bundle_ubsan_rt = true`** — Same reason
4. **`rm -rf` before xcodebuild** — xcodebuild -create-xcframework fails if output path already exists
5. **`-headers` expects directory** — Pass `b.path("include")`, not a file path. The include/ dir contains both libsmithers.h and module.modulemap — both will be copied into Headers/

### Output Structure Expected by Tests
```
dist/SmithersKit.xcframework/
├── Info.plist
    └── macos-arm64_x86_64/
        ├── Headers/
        │   ├── libsmithers.h
        │   └── module.modulemap
        └── libsmithers.a
```

### Acceptance Criteria Checklist
1. `zig build xcframework` produces `dist/SmithersKit.xcframework`
2. xcframework contains `Headers/libsmithers.h` and `Headers/module.modulemap`
3. `tests/xcframework_test.sh` passes (structure + lipo -info + nm symbol check)
4. `tests/xcframework_link_test.sh` passes (compile + link test C program against both arches)
5. `xcodebuild -project macos/Smithers.xcodeproj -scheme Smithers build` succeeds

## Open Questions

1. **Keep inline or refactor to src/build/?** — Ticket says keep in build.zig. The Ghostty pattern uses separate files in src/build/ but that's a larger refactor. Recommend: inline helper functions in build.zig for now, refactor to src/build/ in a future ticket.
2. **Should `dev` step depend on `xcframework`?** — Ticket says "optionally". Recommend yes — the Xcode build phase already auto-builds if missing, but having dev depend on xcframework ensures it's always fresh.
3. **build_options for xcframework modules** — The arch-specific modules need the same `build_options` as the main module (enable_http_server_tests, enable_storage_module). Must create and attach build_options to each arch module.
