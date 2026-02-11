# Context: xcode-app-scaffold

## Current State

### Build System (build.zig)
- `zig build xcframework` step already exists and works — produces `dist/SmithersKit.xcframework`
- xcframework is universal (arm64 + x86_64), contains `libsmithers.a` + `Headers/libsmithers.h`
- Verified symbols: `_smithers_app_new`, `_smithers_app_free`, `_smithers_app_action` are exported
- `zig build dev` step exists at line 143-149 — calls `bash scripts/xcode_build_and_open.sh`
- `zig build all` does NOT include xcframework or dev — only build+test+format+lint (line 160-173)
- `zig build` produces native-target lib + header install

### Scripts
- `scripts/xcode_build_and_open.sh` exists — runs `xcodebuild -project macos/Smithers.xcodeproj -scheme Smithers` with derived data at `.build/xcode/`, then `open` the app
- Script exits 0 if `macos/` doesn't exist (graceful skip)

### C API (include/libsmithers.h)
- Complete header with opaque types, action enums, callbacks, config structs, lifecycle functions
- `smithers_app_new(config)` → `smithers_app_t`, `smithers_app_free(app)`, `smithers_app_action(app, tag, payload)`
- Runtime config: `wakeup` callback, `action` callback, `userdata` opaque pointer

### Zig Source (src/)
- `lib.zig`: CAPI struct with exported functions, ZigApi struct, force-export comptime block
- `App.zig`: Full lifecycle (create/init/deinit/destroy), arena allocator, performAction stub
- `capi.zig`, `action.zig`, `config.zig`, `host.zig`, `storage.zig`, `memory.zig`, `main.zig` all exist

### Missing
- `macos/` directory does not exist — needs to be created entirely
- No `.xcodeproj`, no Swift source files, no Info.plist, no entitlements, no bridging header

## Ghostty Reference Patterns

### Project Structure
```
ghostty/macos/
├── Ghostty.xcodeproj/project.pbxproj  (1203 lines, real Xcode project)
├── Sources/
│   ├── App/macOS/
│   │   ├── main.swift              (uses NSApplicationMain, NOT @main/@App)
│   │   ├── AppDelegate.swift       (57K lines, main app logic)
│   │   ├── ghostty-bridging-header.h  (imports C headers for Swift)
│   │   └── MainMenu.xib
│   ├── Features/                   (feature-based dirs)
│   ├── Ghostty/                    (C FFI wrappers)
│   └── Helpers/
├── Ghostty-Info.plist
├── Ghostty.entitlements
├── GhosttyDebug.entitlements
├── GhosttyKit.xcframework/         (pre-built, referenced by project)
├── Assets.xcassets/
└── Tests/
```

### Key Xcode Build Settings (Ghostty macOS target)
- `MACOSX_DEPLOYMENT_TARGET = 13.0`
- `SWIFT_VERSION = 5.0` (NOT Swift 6 — Ghostty uses 5 + upcoming features)
- `SWIFT_OBJC_BRIDGING_HEADER = "Sources/App/macOS/ghostty-bridging-header.h"`
- `"OTHER_LDFLAGS[arch=*]" = "-lstdc++"` (needed for Zig runtime)
- `CODE_SIGN_IDENTITY[sdk=macosx*] = "-"` (ad-hoc signing)
- `ENABLE_PREVIEWS = YES`
- `EXECUTABLE_NAME = ghostty`
- `GENERATE_INFOPLIST_FILE = YES` (with INFOPLIST_FILE override)
- `LD_RUNPATH_SEARCH_PATHS = ("$(inherited)", "@executable_path/../Frameworks")`
- Uses `fileSystemSynchronizedGroups` for Sources dir (Xcode auto-discovers .swift files)

### XCFramework Linking in Ghostty
- `GhosttyKit.xcframework` at `macos/GhosttyKit.xcframework/` (same level as .xcodeproj)
- Referenced as `PBXFileReference` with `lastKnownFileType = wrapper.xcframework`
- Added to Frameworks group + PBXFrameworksBuildPhase
- No explicit FRAMEWORK_SEARCH_PATHS — Xcode handles it from the reference

### Ghostty Does NOT Use SwiftUI App Protocol
- Uses `NSApplicationMain` in `main.swift`, NOT `@main struct App: App`
- Has `AppDelegate` (NSApplicationDelegate), MainMenu.xib
- This is because Ghostty is a terminal — more AppKit-heavy

## Smithers v2 Design: SwiftUI @main

Per engineering spec, Smithers uses SwiftUI App protocol (NOT NSApplicationMain):

```swift
@main
struct SmithersApp: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        Window("Smithers", id: "chat") {
            ChatWindowRootView().environment(appModel)
        }
        .windowStyle(.hiddenTitleBar)

        Window("Smithers IDE", id: "workspace") {
            IDEWindowRootView().environment(appModel)
        }
        .windowStyle(.hiddenTitleBar)

        Settings { SettingsView().environment(appModel) }
    }
}
```

For this scaffold ticket, we need **minimal** versions — placeholders, not full implementations.

## v1 Reference (prototype0/)

v1 uses `@main struct SmithersApp: App` with:
- `@StateObject` (old pattern, v2 uses `@State` + `@Observable`)
- `WindowGroup` (single window, v2 uses two `Window` scenes)
- `@NSApplicationDelegateAdaptor(SmithersAppDelegate.self)`
- `.windowStyle(.hiddenTitleBar)`
- `.commands { }` for keyboard shortcuts

## Critical Implementation Details

### XCFramework Path
Ticket says `dist/SmithersKit.xcframework` — this is at repo root, NOT inside `macos/`.
Ghostty puts its xcframework at `macos/GhosttyKit.xcframework/`.

**Decision needed:** Reference `../dist/SmithersKit.xcframework` from the .xcodeproj, or copy it into `macos/` during build? The `zig build xcframework` already outputs to `dist/`. For the Xcode project, we can reference it with `path = "../dist/SmithersKit.xcframework"; sourceTree = "<group>";`.

### Bridging Header vs. Module Map (Updated)
Ghostty uses a bridging header, but SmithersKit ships as an xcframework with a `module.modulemap` (placed in `include/` and copied into the xcframework). With the module map in place, Swift can `import SmithersKit` directly and no bridging header is required. This scaffold intentionally omits any bridging header and relies solely on the module map.

### Generating project.pbxproj
The `.xcodeproj` format is a proprietary Apple format. Options:
1. **Hand-craft the pbxproj** — tedious but fully controlled (Ghostty approach)
2. **Use `xcodebuild` to create** — no such command exists
3. **Create via Xcode GUI** — requires interactive Xcode session
4. **Use xcodegen** — spec says NO xcodegen

Best approach: Hand-craft a minimal pbxproj based on Ghostty's structure. The format is well-understood: PBXFileReference, PBXGroup, PBXNativeTarget, PBXSourcesBuildPhase, PBXFrameworksBuildPhase, XCBuildConfiguration sections.

### Swift 6 Strict Concurrency
Spec says "Swift 6 strict. NEVER ignore warnings." Set:
- `SWIFT_VERSION = 6.0`
- `SWIFT_STRICT_CONCURRENCY = complete`

### Deployment Target
Spec: macOS 14+ (Sonoma). Set `MACOSX_DEPLOYMENT_TARGET = 14.0`.

### fileSystemSynchronizedGroups
Xcode 15+ feature that auto-discovers source files from a directory. Used by Ghostty. This means we create `macos/Sources/` with Swift files and the project just picks them up — no need to list each file in pbxproj. HUGE simplification.

## Gotchas / Pitfalls

1. **Static lib linking with Zig runtime**: Ghostty uses `OTHER_LDFLAGS = "-lstdc++"`. The Zig-compiled static lib includes compiler_rt and ubsan_rt (see build.zig `bundle_compiler_rt = true`). May need additional linker flags. The existing `tests/xcframework_link_test.sh` links successfully with just `clang -arch ... -I ... .c .a`, but Swift/Xcode linking may need `libc` explicitly.

2. **xcframework path from Xcode project**: The project.pbxproj uses relative paths. Since xcframework is at `../dist/SmithersKit.xcframework` from `macos/`, the `sourceTree` must be `"<group>"` with the right relative path, or `SOURCE_ROOT` with appropriate path. Ghostty uses `path = GhosttyKit.xcframework; sourceTree = "<group>";` because the framework is IN the `macos/` directory.

3. **SwiftUI Window vs WindowGroup**: The spec uses `Window("Smithers", id: "chat")` (single instance) not `WindowGroup` (multiple instances). `Window` was introduced in macOS 13 but behaves differently for single-instance semantics.

4. **Smoke link test**: Ticket asks for "tiny Swift call to smithers_app_new/smithers_app_free". This requires the bridging header to work. Quick test: call from `SmithersApp.init()` or an `onAppear`.

5. **zig build dev dependency**: The dev step depends on `zig build` (install step) but NOT on `zig build xcframework`. The xcode_build_and_open.sh script assumes the xcframework already exists. Either: (a) make dev depend on xcframework step, or (b) document that xcframework must be built first. Option (a) is better for developer experience.

## Minimal File Set Needed

```
macos/
├── Smithers.xcodeproj/
│   ├── project.pbxproj
│   └── project.xcworkspace/
│       └── contents.xcworkspacedata
├── Sources/
│   └── App/
│       └── SmithersApp.swift          (minimal @main with 2 Window scenes)
├── Smithers-Bridging-Header.h         (imports libsmithers.h)
├── Smithers-Info.plist                (minimal)
└── Smithers.entitlements              (minimal)
```

The `SmithersKit.xcframework` stays at `dist/` — referenced from project.

## Key Symbols for Smoke Test

```swift
// In SmithersApp.swift or a helper
import Foundation

// These come through the bridging header
func smokeTest() {
    var config = smithers_config_s()
    config.runtime = smithers_runtime_config_s()
    let app = smithers_app_new(&config)
    if let app = app {
        smithers_app_free(app)
        print("SmithersKit link OK")
    }
}
```
