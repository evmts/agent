# Plan: xcode-app-scaffold — Scaffold macOS Xcode Project

## Summary

Create `macos/Smithers.xcodeproj` with a minimal SwiftUI app (macOS 14+, Swift 6 strict), link `dist/SmithersKit.xcframework`, implement two empty Window scenes (Chat + IDE placeholders), wire `zig build dev` to depend on `zig build xcframework`, and validate the full pipeline end-to-end.

## Prerequisites

- `zig build xcframework` already succeeds (verified)
- `dist/SmithersKit.xcframework` contains universal static lib + C header
- `scripts/xcode_build_and_open.sh` exists and handles `macos/` gracefully
- C API symbols verified: `smithers_app_new`, `smithers_app_free`, `smithers_app_action`

## Critical Finding: Missing module.modulemap

The xcframework headers directory contains only `libsmithers.h` — **no `module.modulemap`**. This file is REQUIRED for Swift to `import SmithersKit`. Following the Ghostty pattern (`include/module.modulemap` → copied into xcframework by build step), we must add this first then rebuild the xcframework.

## Implementation Steps

### Step 0: Add module.modulemap to include/ (Zig layer)

**Files:** `include/module.modulemap`

Create `include/module.modulemap` following Ghostty's exact pattern. The `addXCFrameworkStep` in `build.zig` already passes `b.path("include")` as the headers directory — the modulemap will be automatically copied into the xcframework alongside `libsmithers.h`.

```
module SmithersKit {
    umbrella header "libsmithers.h"
    export *
}
```

Then rebuild xcframework so the modulemap is included in `dist/SmithersKit.xcframework/macos-arm64_x86_64/Headers/`.

### Step 1: Wire `zig build dev` to depend on xcframework step (Zig layer)

**Files:** `build.zig`

Add `dev_step.dependOn(xcframework_step)` so that `zig build dev` automatically builds the xcframework before calling `scripts/xcode_build_and_open.sh`. Currently `dev` depends on the install step (native-target lib) but NOT on `xcframework`. The xcode_build_and_open.sh script assumes xcframework exists — this wiring makes it automatic.

Also make the `xcode_build.step` depend on `xcframework_step` for correct ordering (xcframework must be built before xcodebuild runs).

**CRITICAL: Do NOT modify the `all` step.** Per ticket requirements, the canonical `zig build all` step must remain unchanged.

### Step 2: Add .build/ to .gitignore (Config layer)

**Files:** `.gitignore`

Add `.build/` to gitignore. The `scripts/xcode_build_and_open.sh` uses `.build/xcode/` for derived data — this should not be committed.

### Step 3: Create macos/ directory structure (Swift layer)

**Files to create:**

```
macos/
├── Smithers.xcodeproj/
│   └── project.pbxproj
├── Smithers-Info.plist
├── Smithers.entitlements
└── Sources/
    └── App/
        └── SmithersApp.swift
```

#### 3a: Smithers-Info.plist

Minimal macOS app plist. Uses `GENERATE_INFOPLIST_FILE = YES` in Xcode with `INFOPLIST_FILE` pointing to this for overrides (bundle identifier, version, etc.).

Key entries:
- `CFBundleIdentifier`: `$(PRODUCT_BUNDLE_IDENTIFIER)` (resolved from build settings)
- `CFBundleName`: `$(PRODUCT_NAME)`
- `CFBundleVersion`: `1`
- `CFBundleShortVersionString`: `0.1.0`
- `LSMinimumSystemVersion`: `$(MACOSX_DEPLOYMENT_TARGET)`

#### 3b: Smithers.entitlements

Minimal entitlements. App Sandbox disabled for MVP (YOLO mode per spec). Just the standard property list with `com.apple.security.app-sandbox = NO`.

Actually, per spec: "YOLO mode only. No approvals, no sandbox." So we disable sandbox. Simplest: empty entitlements dict (no sandbox key = no sandbox).

#### 3c: SmithersApp.swift

Minimal `@main` SwiftUI app with:
- `import SwiftUI`
- `import SmithersKit` (validates module.modulemap + xcframework linking)
- `@Observable @MainActor final class AppModel` — placeholder with no properties
- Two `Window` scenes: Chat (`id: "chat"`) and IDE (`id: "workspace"`)
- Each window shows a `Text` placeholder with window title
- `.windowStyle(.hiddenTitleBar)` per design spec
- `.defaultSize()` per design spec (chat: 800x900, IDE: 1100x900)
- Smoke test: call `smithers_app_new`/`smithers_app_free` in `.onAppear` or `init` to validate C API linking
- `Settings` scene with placeholder Text

### Step 4: Create project.pbxproj (Swift/Xcode layer)

**Files:** `macos/Smithers.xcodeproj/project.pbxproj`

Hand-crafted minimal pbxproj following Ghostty patterns. Key sections:

**PBXBuildFile:** SmithersKit.xcframework in Frameworks
**PBXFileReference:** SmithersKit.xcframework (`path = ../dist/SmithersKit.xcframework; sourceTree = "<group>"`)
**PBXGroup:** Root group with Sources, Products, Frameworks groups
**PBXNativeTarget:** `Smithers` app target
**PBXSourcesBuildPhase:** (empty — fileSystemSynchronizedGroups handles source discovery)
**PBXFrameworksBuildPhase:** SmithersKit.xcframework
**XCBuildConfiguration (Debug + Release):**

| Setting | Value | Rationale |
|---------|-------|-----------|
| `MACOSX_DEPLOYMENT_TARGET` | `14.0` | Required for @Observable |
| `SWIFT_VERSION` | `6.0` | Swift 6 strict concurrency |
| `SWIFT_STRICT_CONCURRENCY` | `complete` | Per spec |
| `CLANG_ENABLE_MODULES` | `YES` | Required for `import SmithersKit` |
| `OTHER_LDFLAGS` | `"-lstdc++"` | Zig runtime needs C++ stdlib (Ghostty pattern) |
| `PRODUCT_BUNDLE_IDENTIFIER` | `com.smithers.desktop` | App bundle ID |
| `PRODUCT_NAME` | `Smithers` | Display name |
| `INFOPLIST_FILE` | `Smithers-Info.plist` | Plist location |
| `CODE_SIGN_ENTITLEMENTS` | `Smithers.entitlements` | Entitlements |
| `CODE_SIGN_IDENTITY` | `"-"` | Ad-hoc signing (dev) |
| `GENERATE_INFOPLIST_FILE` | `YES` | Auto-gen with overrides |
| `LD_RUNPATH_SEARCH_PATHS` | `@executable_path/../Frameworks` | Framework search |
| `ENABLE_PREVIEWS` | `YES` | SwiftUI previews |

**fileSystemSynchronizedGroups:** Point at `Sources` directory — Xcode auto-discovers Swift files. This is the key Ghostty-pattern simplification (no need to list every .swift file).

**XCConfigurationList:** Debug + Release configurations for project and target.

### Step 5: Validate end-to-end (Verification)

1. `zig build xcframework` — must succeed, `dist/SmithersKit.xcframework/macos-arm64_x86_64/Headers/module.modulemap` must exist
2. `xcodebuild -project macos/Smithers.xcodeproj -scheme Smithers build` — must exit 0
3. `zig build dev` — must build xcframework + xcodebuild + open app
4. App launches to blank Chat window without runtime errors
5. `zig build all` — must still pass (no changes to `all` step)

## Dependency Order

```
Step 0 (module.modulemap) → Step 1 (build.zig wiring)
                          → Step 3 (macos/ files — depends on modulemap for import)
                          → Step 4 (pbxproj — depends on macos/ files existing)
Step 2 (.gitignore) — independent

Step 5 (validation) — depends on all above
```

## Files to Create

1. `include/module.modulemap` — Clang module map for SmithersKit
2. `macos/Smithers-Info.plist` — App Info.plist
3. `macos/Smithers.entitlements` — App entitlements (minimal)
4. `macos/Sources/App/SmithersApp.swift` — @main entry with 2 Window scenes + smoke test
5. `macos/Smithers.xcodeproj/project.pbxproj` — Xcode project definition

## Files to Modify

1. `build.zig` — Add xcframework dependency to dev step
2. `.gitignore` — Add `.build/` entry

## Tests

### Module map validation (extends existing xcframework_test.sh)
Verify `module.modulemap` exists in built xcframework headers directory alongside `libsmithers.h`.

### Xcode build smoke test
`xcodebuild -project macos/Smithers.xcodeproj -scheme Smithers build` exits 0. Already covered by `zig build dev` pipeline.

### C API symbol resolution (runtime)
SmithersApp.swift calls `smithers_app_new` + `smithers_app_free` on launch. If symbols are unresolved, app crashes immediately — caught by manual launch or CI.

## Risks

1. **Hand-crafted pbxproj fragility** — Xcode project files are complex XML-like format with UUID cross-references. A typo breaks the project entirely. Mitigation: Use minimal structure, validate with `xcodebuild` immediately.

2. **Swift 6 strict concurrency warnings** — Even minimal code may trigger warnings with `SWIFT_STRICT_CONCURRENCY = complete`. Mitigation: Use `@MainActor` annotations and `@Observable` pattern from the start.

3. **xcframework module resolution** — If Xcode doesn't find the module.modulemap or the path is wrong, `import SmithersKit` fails. Mitigation: Verify modulemap is copied into xcframework headers, test with `xcodebuild`.

4. **`-lstdc++` may not suffice** — Zig's bundled compiler_rt/ubsan_rt might need additional linker flags on some configurations. Mitigation: The existing `tests/xcframework_link_test.sh` already validates linking; if Xcode needs more flags, add them.

5. **fileSystemSynchronizedGroups compatibility** — Requires Xcode 15+. If CI uses older Xcode, this feature won't work. Mitigation: macOS 14 (Sonoma) ships with Xcode 15, so this is safe for our deployment target.

6. **`zig build all` must remain green** — Adding macos/ directory with Swift files shouldn't affect the `all` step (it doesn't include xcode-test). But any new files touched by `prettier`, `typos`, or `shellcheck` could cause issues. Mitigation: Ensure Swift files aren't matched by prettier config; add domain words to typos.toml if needed.
