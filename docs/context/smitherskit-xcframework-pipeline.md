# Context: smitherskit-xcframework-pipeline

## Summary

Package `libsmithers.a` + `include/libsmithers.h` into a universal `SmithersKit.xcframework` (macOS arm64 + x86_64). Add `zig build xcframework` step.

## Current State

### Build System (`build.zig`)
- Static lib already built at line 26: `b.addLibrary(.{ .name = "smithers", .root_module = mod, .linkage = .static })`
- Header installed at line 32: `b.addInstallHeaderFile(b.path("include/libsmithers.h"), "libsmithers.h")`
- Comment on line 25 already says: `// Static library (xcframework input for Swift)`
- Current build output: `zig-out/lib/libsmithers.a` (arm64-only, ~1.6MB)
- Header output: `zig-out/include/libsmithers.h`
- SQLite linked as dependency from `pkg/sqlite`
- `zig build all` includes: build + tests + fmt-check + prettier-check + typos-check + shellcheck + c_header smoke test
- No `src/build/` directory exists yet (spec says to create one later; for now keep in `build.zig`)
- No `dist/` directory exists yet

### Key Source Files
- `src/lib.zig` — C API exports with force-export comptime block (lines 164-170)
- `src/capi.zig` — C boundary types with comptime sync check (lines 65-73)
- `include/libsmithers.h` — 110-line C header, the Zig↔Swift contract
- `tests/c_header_test.c` — Validates header compiles cleanly (already wired in `all`)

### Dependencies to Bundle
- `libsmithers.a` (from `src/lib.zig`)
- `libsqlite3.a` (from `pkg/sqlite` via `b.dependency("sqlite", ...)`)
- Both must be combined into single .a for xcframework (use `libtool -static`)

## Ghostty Reference Pattern (src/build/)

Ghostty uses a multi-file `src/build/` approach. Smithers currently keeps everything in `build.zig`. The ticket scope is to add the xcframework step — keep it in `build.zig` for now (no `src/build/` refactor needed).

### Key Ghostty Steps (exact pattern to follow):

**1. LipoStep.zig** — Combines two arch-specific .a files into universal:
```zig
const run_step = RunStep.create(b, b.fmt("lipo {s}", .{opts.name}));
run_step.addArgs(&.{ "lipo", "-create", "-output" });
const output = run_step.addOutputFileArg(opts.out_name);
run_step.addFileArg(opts.input_a);
run_step.addFileArg(opts.input_b);
```

**2. LibtoolStep.zig** — Combines multiple .a files into one:
```zig
const run_step = RunStep.create(b, b.fmt("libtool {s}", .{opts.name}));
run_step.addArgs(&.{ "libtool", "-static", "-o" });
const output = run_step.addOutputFileArg(opts.out_name);
for (opts.sources) |source| run_step.addFileArg(source);
```

**3. XCFrameworkStep.zig** — Runs `xcodebuild -create-xcframework`:
```zig
// Delete old
run_delete.addArgs(&.{ "rm", "-rf", opts.out_path });
// Create new
run_create.addArgs(&.{ "xcodebuild", "-create-xcframework" });
for (opts.libraries) |lib| {
    run_create.addArg("-library");
    run_create.addFileArg(lib.library);
    run_create.addArg("-headers");
    run_create.addFileArg(lib.headers);
}
run_create.addArg("-output");
run_create.addArg(opts.out_path);
```

**4. GhosttyLib.initMacOSUniversal** — Builds both arches + lipo:
```zig
const aarch64 = try initStatic(b, &try original_deps.retarget(b, genericMacOSTarget(b, .aarch64)));
const x86_64 = try initStatic(b, &try original_deps.retarget(b, genericMacOSTarget(b, .x86_64)));
const universal = LipoStep.create(b, .{ .name = "ghostty", .out_name = "libghostty.a", .input_a = aarch64.output, .input_b = x86_64.output });
```

**5. GhosttyLib.initStatic** — Key details for static lib:
```zig
lib.linkLibC();
lib.bundle_compiler_rt = true;  // Required for static lib!
lib.bundle_ubsan_rt = true;     // Required for static lib!
// On Darwin: use libtool to combine all deps into one fat .a
```

## Verified Zig 0.15.2 API Signatures

### `b.addLibrary()`
```zig
pub fn addLibrary(b: *Build, options: LibraryOptions) *Step.Compile
pub const LibraryOptions = struct {
    linkage: std.builtin.LinkMode = .static,
    name: []const u8,
    root_module: *Module,
    version: ?std.SemanticVersion = null,
    use_llvm: ?bool = null,
    use_lld: ?bool = null,
    // ...
};
```

### `b.resolveTargetQuery()`
```zig
pub fn resolveTargetQuery(b: *Build, query: Target.Query) ResolvedTarget
// Target.Query fields:
//   cpu_arch: ?Target.Cpu.Arch
//   os_tag: ?Target.Os.Tag
//   os_version_min: ?OsVersion  // OsVersion = union(enum) { none, semver, windows }
```

### `b.createModule()`
```zig
pub fn createModule(b: *Build, options: Module.CreateOptions) *Module
// Module.CreateOptions includes: root_source_file, target, optimize, imports, ...
```

### `Compile` fields
```zig
bundle_compiler_rt: ?bool = null,  // ?bool in 0.15 (not bool)
bundle_ubsan_rt: ?bool = null,
pub fn linkLibC(compile: *Compile) void
pub fn getEmittedBin(compile: *Compile) LazyPath
```

### macOS target creation (from Ghostty):
```zig
b.resolveTargetQuery(.{
    .cpu_arch = .aarch64,  // or .x86_64
    .os_tag = .macos,
    .os_version_min = .{ .semver = .{ .major = 14, .minor = 0, .patch = 0 } },
})
```

## Implementation Plan

### Step-by-step:

1. **Build arm64 libsmithers.a** — Create module + library targeting `aarch64-macos` with macOS 14.0 min
2. **Build x86_64 libsmithers.a** — Same but `x86_64-macos`
3. **Link SQLite into each** — Both arch libs need `sqlite_dep` linked
4. **Bundle compiler_rt + ubsan_rt** — Set `lib.bundle_compiler_rt = true` and `lib.bundle_ubsan_rt = true` on each
5. **Optionally use libtool** — Combine libsmithers.a + libsqlite3.a into single fat .a per arch (Ghostty pattern). This ensures xcframework has ONE .a with all symbols.
6. **Lipo** — Combine arm64 .a + x86_64 .a into universal `libsmithers.a`
7. **XCFramework** — `xcodebuild -create-xcframework -library <universal.a> -headers include/ -output dist/SmithersKit.xcframework`
8. **Wire step** — `b.step("xcframework", "...")` depends on xcframework create step

### Key gotchas:

1. **Must use `use_llvm = true`** — Ghostty does this for cross-compilation. x86_64 builds on arm64 Mac need LLVM backend. Self-hosted fails for macOS x86_64.
2. **Must `bundle_compiler_rt = true`** — Static libs need this or you get undefined symbols at link time.
3. **Must combine deps with libtool** — The xcframework should have ONE .a per platform, not separate libsmithers.a + libsqlite3.a. Use `libtool -static` to combine.
4. **`rm -rf` before `xcodebuild -create-xcframework`** — The command fails if output already exists.
5. **Headers path = directory** — `xcodebuild -create-xcframework -headers` expects a directory path, not a file. Use `b.path("include")` which points to the `include/` directory.
6. **Output path** — Use `dist/SmithersKit.xcframework` (absolute from repo root, or `b.pathJoin(...)`)
7. **`addFileArg` vs `addArg`** — Use `addFileArg` for build-tracked LazyPath inputs (libraries). Use `addArg` for static string paths (output, rm -rf target).
8. **Step dependencies** — xcframework step must depend on the lipo step, which depends on both arch lib steps.

## Reference Files

| File | Relevance |
|------|-----------|
| `build.zig` | THE file to modify — add xcframework step |
| `include/libsmithers.h` | Header to package in xcframework |
| `src/lib.zig` | Force-export block ensures symbols are in .a |
| `tests/c_header_test.c` | Existing smoke test validates header |
| `build.zig.zon` | Package manifest, sqlite dependency |
| `../smithers/ghostty/src/build/XCFrameworkStep.zig` | Exact xcodebuild pattern |
| `../smithers/ghostty/src/build/LipoStep.zig` | Exact lipo pattern |
| `../smithers/ghostty/src/build/LibtoolStep.zig` | Exact libtool pattern |
| `../smithers/ghostty/src/build/GhosttyLib.zig` | Static lib + universal build pattern |
| `../smithers/ghostty/src/build/GhosttyXCFramework.zig` | Orchestration pattern |

## Open Questions

1. **`linkLibC()` needed?** — Ghostty calls `lib.linkLibC()` on static libs. Smithers currently doesn't. May need it for C runtime symbols. Check if xcframework links without it first; add if missing symbols.
2. **libtool vs shipping separate .a files** — Ghostty uses libtool to merge deps into one .a. Smithers could do the same (cleaner xcframework) or list both in xcframework. Recommend: use libtool to combine, matching Ghostty pattern.
3. **`use_llvm = true` required?** — Ghostty forces this. Smithers may need it for x86_64 cross-compilation from arm64. Test without first, but likely required (Ghostty comment: "Fails on self-hosted x86_64 on macOS").
