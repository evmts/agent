# Research Context: macos-xcode-scaffold

## Summary

Scaffold the `macos/Smithers.xcodeproj` Xcode project with a minimal SwiftUI app targeting macOS 14+, linking `dist/SmithersKit.xcframework`. The xcframework already exists and contains a universal static lib + C header. Critical missing piece: `include/module.modulemap` (required for Swift `import SmithersKit`).

## What Exists Today

### xcframework (DONE)
- `dist/SmithersKit.xcframework/` — fully built, contains:
  - `Info.plist` — declares `macos-arm64_x86_64` slice
  - `macos-arm64_x86_64/libsmithers-universal.a` (45MB universal binary)
  - `macos-arm64_x86_64/Headers/libsmithers.h` (C API header)
- Built by `zig build xcframework` (build.zig lines 176-199)
- Validated by `tests/xcframework_test.sh` and `tests/xcframework_link_test.sh`

### C API (DONE)
- `include/libsmithers.h` — 110 lines, exports:
  - `smithers_app_new(config)`, `smithers_app_free(app)`, `smithers_app_action(app, tag, payload)`
  - Opaque types: `smithers_app_t`, `smithers_surface_t`
  - 13 action tags, payload union, callback function pointers

### Build System (DONE, needs wiring)
- `build.zig` line 143-149: `dev` step runs `scripts/xcode_build_and_open.sh`
- `scripts/xcode_build_and_open.sh`: checks `macos/` exists, runs `xcodebuild -project macos/Smithers.xcodeproj -scheme Smithers`, opens `.app`
- Already gracefully skips: `if [[ ! -d macos ]]; then echo "skipping: macos/ not found"; exit 0; fi`

### macos/ Directory (DOES NOT EXIST)
- This is what needs to be created.

## Critical Missing Piece: module.modulemap

The xcframework headers directory does NOT contain a `module.modulemap`. This is REQUIRED for Swift to `import SmithersKit`. Without it, Xcode won't recognize the C API as a Swift-importable module.

### Ghostty Pattern (FOLLOW THIS)
File: `../smithers/ghostty/include/module.modulemap`
```
module GhosttyKit {
    umbrella header "ghostty.h"
    export *
}
```

For Smithers, create `include/module.modulemap`:
```
module SmithersKit {
    umbrella header "libsmithers.h"
    export *
}
```

This file must be in `include/` alongside `libsmithers.h`, so the xcframework build copies it into `Headers/`. The `addXCFrameworkStep` in build.zig passes `b.path("include")` as the headers dir — it will automatically pick up the modulemap.

After adding this, re-run `zig build xcframework` so the modulemap gets copied into `dist/SmithersKit.xcframework/macos-arm64_x86_64/Headers/`.

## Xcode Project Structure (What to Create)

### File Layout
```
macos/
├── Smithers.xcodeproj/
│   └── project.pbxproj          # Xcode project definition
├── Smithers-Info.plist           # App Info.plist (macOS 14+)
├── Smithers.entitlements         # App Sandbox entitlements
└── Sources/
    ├── App/
    │   └── SmithersApp.swift     # @main, @Observable AppModel, Window scenes
    └── Ghostty/
        └── SmithersCore.swift    # Placeholder for C FFI bridge
```

### Key Build Settings for pbxproj
From Ghostty reference (`../smithers/ghostty/macos/Ghostty.xcodeproj/project.pbxproj`):

| Setting | Value | Why |
|---------|-------|-----|
| `MACOSX_DEPLOYMENT_TARGET` | `14.0` | Required for @Observable macro |
| `SWIFT_VERSION` | `6.0` | Swift 6 strict concurrency (spec requirement) |
| `CLANG_ENABLE_MODULES` | `YES` | Required to `import SmithersKit` |
| `OTHER_LDFLAGS[arch=*]` | `-lstdc++` | Zig links C++ runtime (Ghostty pattern) |
| `PRODUCT_BUNDLE_IDENTIFIER` | `com.smithers.desktop` | From v1 Info.plist URL scheme |

### xcframework Linking
In pbxproj, the xcframework reference follows this Ghostty pattern:
1. `PBXFileReference` entry: `lastKnownFileType = wrapper.xcframework; path = ../dist/SmithersKit.xcframework`
2. `PBXBuildFile` entry: adds to Frameworks build phase
3. Frameworks group contains the reference
4. Note: path is RELATIVE to the xcodeproj location — `../dist/SmithersKit.xcframework`

## SwiftUI App Entry Point

### v2 Pattern (from spec — @Observable, NOT v1's ObservableObject)
```swift
import SwiftUI
import SmithersKit

@Observable @MainActor
final class AppModel {
    var workspace: WorkspaceModel? = nil
    var hasWorkspace: Bool { workspace != nil }
    var workspaceName: String { workspace?.rootDirectory.lastPathComponent ?? "Smithers" }
}

@main
struct SmithersApp: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        Window("Smithers", id: "chat") {
            Text("Chat Window — Smithers v2")
                .environment(appModel)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 800, height: 900)

        Window("Smithers IDE", id: "workspace") {
            Text("IDE Window — Smithers v2")
                .environment(appModel)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 900)

        Settings {
            Text("Settings Placeholder")
        }
    }
}
```

Key differences from v1:
- `@Observable` (NOT `ObservableObject` + `@Published`)
- `@State` (NOT `@StateObject`)
- `.environment(appModel)` (NOT `@EnvironmentObject`)
- Two `Window` scenes (NOT single `WindowGroup`)
- macOS 14+ required for `@Observable` macro

### v1 Reference (DO NOT copy pattern, just reference structure)
- `/Users/williamcory/smithers/apps/desktop/Smithers/SmithersApp.swift` — 167 lines, uses old `@StateObject`/`ObservableObject`

## Ghostty Xcode Patterns (Reference)

### Entry point
Ghostty uses raw `NSApplicationMain()` + `AppDelegate` (AppKit-heavy). Smithers v2 uses `@main struct SmithersApp: App` (SwiftUI-first). Different pattern — don't follow Ghostty's entry point.

### Framework linking (FOLLOW THIS)
- xcframework at `macos/GhosttyKit.xcframework` (relative to project root)
- Referenced in pbxproj via `PBXFileReference` with `lastKnownFileType = wrapper.xcframework`
- `CLANG_ENABLE_MODULES = YES` + `module.modulemap` = Swift module import
- `OTHER_LDFLAGS[arch=*] = "-lstdc++"` — needed for Zig's C++ runtime dependency
- No bridging header needed for C framework access — module.modulemap handles it

### Test target
- `GhosttyTests` target exists with `PRODUCT_BUNDLE_IDENTIFIER = com.mitchellh.GhosttyTests`
- For Smithers: create `SmithersTests` target with one no-op test

## Gotchas / Pitfalls

1. **module.modulemap MUST be added to `include/` BEFORE building xcframework.** Without it, Swift can't import SmithersKit. After adding, re-run `zig build xcframework`.

2. **xcframework path in pbxproj must be relative to macos/ dir.** Since xcframework is at `dist/SmithersKit.xcframework` and project is at `macos/Smithers.xcodeproj`, the relative path is `../dist/SmithersKit.xcframework`.

3. **`-lstdc++` linker flag required.** Zig-compiled static libs that bundle compiler_rt need C++ standard library linked. Ghostty does this for all architectures.

4. **`zig build all` must keep passing.** The `all` step does NOT depend on `dev` or `xcode-test` — it only runs Zig build, tests, fmt, lint, and C header smoke test. Adding `macos/` should not break it.

5. **Creating pbxproj by hand is fragile.** Xcode project files are complex XML with UUIDs. Best approach: use `xcodebuild` or create via Xcode GUI, then commit. Alternative: use a minimal hand-crafted pbxproj (Ghostty's is hand-maintained). If generating programmatically, ensure all UUID cross-references are consistent.

## Open Questions

1. **Should `zig build dev` depend on `zig build xcframework`?** Currently `dev` depends on `installStep` (native target build) but NOT on `xcframework`. The xcode_build_and_open.sh script assumes xcframework already exists at `dist/`. Either: (a) make `dev` depend on `xcframework` step, or (b) document that user must run `zig build xcframework` first. Recommendation: (a) add dependency.

2. **Swift 6 strict concurrency in Xcode.** The spec says "Swift 6 strict. NEVER ignore warnings." This means `SWIFT_STRICT_CONCURRENCY = complete` in build settings. However, this may cause issues with older patterns. For scaffold, enable it from the start — easier than retrofitting.

3. **pbxproj creation method.** Hand-write minimal pbxproj following Ghostty's pattern, or generate via Xcode? For reproducibility and version control, hand-writing a minimal one is preferred (Ghostty approach). The scaffold only needs: 1 app target, 1 test target, minimal sources.
