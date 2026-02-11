# Plan: fix-xcodeproj-parse-error

## Summary

Rewrite `macos/Smithers.xcodeproj/project.pbxproj` to fix 7 issues (2 critical parse-breaking) that prevent Xcode from opening/building the project. The file is ~300 lines of OpenStep plist, AI-generated with structural errors from inception.

## Root Cause Analysis

The `.pbxproj` has two critical parse-breaking bugs plus five structural issues:

1. **CRITICAL: Shell script string split across lines 184-188.** The `shellScript` value in `PBXShellScriptBuildPhase` has its closing `"` on line 188 with raw text (comment + touch command) on lines 185-187 outside the string literal. OpenStep plist requires strings on a single line.

2. **CRITICAL: PBXGroup entries in PBXFileReference section.** Three `PBXGroup` definitions (Helpers, Extensions, DesignSystem) at lines 42-55 are inside `/* Begin PBXFileReference section */` instead of `/* Begin PBXGroup section */`.

3. Brace depth imbalance (consequence of issue 1).

4. Four Swift files on disk missing from build phase: `ChatComposerZone.swift`, `ChatSidebarView.swift`, `ChatTitleBarZone.swift`, `SidebarModeBar.swift`.

5. `ComponentsTests.swift` missing from Tests PBXGroup children.

6. `DividerLine.swift` missing from DesignSystem PBXGroup children.

7. Inconsistent indentation throughout.

Both backup files (`project.pbxproj.bak`, `project.pbxproj.beforefix`) have the same critical bugs — they were introduced when the project was first AI-generated.

## Strategy

**Full rewrite** of the ~300-line `project.pbxproj`. Patching individual issues risks missing edge cases in an already-corrupted file. A clean rewrite with proper section ordering, all 18 Swift files registered, single-line shell script, and consistent indentation is safer and more maintainable.

### What stays the same:
- All existing object IDs (referenced by scheme file `Smithers.xcscheme`)
- Target structure (Smithers app + SmithersTests unit test bundle)
- Build configurations (Debug/Release for project, app target, test target)
- Shell script build phase logic (verify xcframework, emit stamp)
- SmithersKit.xcframework linkage from `../dist/`
- Test target compiling design system sources directly (no shared framework)
- Scheme file — no changes needed (IDs match)

### What changes:
- Proper section ordering per Apple convention
- PBXGroup entries moved to correct section
- Shell script merged to single escaped line
- 4 missing Swift files get PBXFileReference + PBXBuildFile + PBXGroup entries
- ComponentsTests.swift added to Tests PBXGroup
- DividerLine.swift added to DesignSystem PBXGroup
- Consistent tab indentation throughout
- Proper brace balancing

## Implementation Steps

### Step 0: Back up current file
Copy current `project.pbxproj` to `backup/project.pbxproj.pre-rewrite` for safety. This is a non-destructive safety measure.

**File:** `macos/Smithers.xcodeproj/backup/project.pbxproj.pre-rewrite`

### Step 1: Rewrite project.pbxproj
Write the complete new `project.pbxproj` with:

**New IDs needed** (for 4 missing files — PBXFileReference + PBXBuildFile each = 8 new entries):
- `F00000000000000000000001` — ChatComposerZone.swift PBXFileReference
- `F00000000000000000000002` — ChatSidebarView.swift PBXFileReference
- `F00000000000000000000003` — ChatTitleBarZone.swift PBXFileReference
- `F00000000000000000000004` — SidebarModeBar.swift PBXFileReference
- `F00000000000000000000011` — ChatComposerZone.swift PBXBuildFile
- `F00000000000000000000012` — ChatSidebarView.swift PBXBuildFile
- `F00000000000000000000013` — ChatTitleBarZone.swift PBXBuildFile
- `F00000000000000000000014` — SidebarModeBar.swift PBXBuildFile

**Section ordering** (Apple convention):
1. PBXBuildFile
2. PBXContainerItemProxy
3. PBXFileReference
4. PBXFrameworksBuildPhase
5. PBXGroup
6. PBXNativeTarget
7. PBXProject
8. PBXResourcesBuildPhase
9. PBXShellScriptBuildPhase
10. PBXSourcesBuildPhase
11. PBXTargetDependency
12. XCBuildConfiguration
13. XCConfigurationList

**PBXGroup hierarchy** (must match disk):
```
Root (A00000000000000000000002)
├── Tests (B1111111111111111111111B) → SmithersTests/
│   ├── SmithersTests.swift
│   ├── ChatViewTests.swift
│   ├── ComponentsTests.swift        ← ADD
│   └── DesignSystemTests.swift
├── Smithers-Info.plist
├── Smithers.entitlements
├── Sources (A00000000000000000000004)
│   ├── App (A00000000000000000000018)
│   │   ├── SmithersApp.swift
│   │   └── AppModel.swift
│   ├── Ghostty (C11111111111111111111123)
│   │   └── SmithersCore.swift
│   ├── Helpers (D20000000000000000000001)
│   │   ├── Extensions (D20000000000000000000002)
│   │   │   └── NSColor+Hex.swift
│   │   └── DesignSystem (D20000000000000000000003)
│   │       ├── Tokens.swift
│   │       ├── AppTheme.swift
│   │       ├── Components.swift
│   │       └── DividerLine.swift    ← ADD
│   └── Features (E43022596692747107705011)
│       ├── Chat (E67917935509812531650863)
│       │   └── Views (E41187255318532219734785)
│       │       ├── ChatWindowRootView.swift
│       │       ├── ChatComposerZone.swift    ← ADD
│       │       ├── ChatSidebarView.swift     ← ADD
│       │       ├── ChatTitleBarZone.swift     ← ADD
│       │       └── SidebarModeBar.swift      ← ADD
│       └── IDE (E54142318959259192779124)
│           └── Views (E82581908906109446756056)
│               └── IDEWindowRootView.swift
├── Frameworks (A00000000000000000000005)
│   └── SmithersKit.xcframework
└── Products (A00000000000000000000003)
    ├── Smithers.app
    └── SmithersTests.xctest
```

**Shell script** (single line with `\n` escapes):
```
shellScript = "if [ ! -d \"${SRCROOT}/../dist/SmithersKit.xcframework\" ]; then\n  echo \"SmithersKit.xcframework not found at ../dist. Building via 'zig build xcframework'...\"\n  ROOT=\"$(cd \"${SRCROOT}/..\"; pwd)\"\n  cd \"$ROOT\"\n  if ! command -v zig >/dev/null 2>&1; then\n    echo \"zig not found. Install Zig or build xcframework manually.\" >&2\n    exit 1\n  fi\n  zig build xcframework || { echo \"zig build xcframework failed\"; exit 1; }\nfi\n\n# Emit stamp for incremental builds\n/usr/bin/touch \"${SRCROOT}/../dist/SmithersKit.stamp\"\n";
```

**Smithers Sources build phase** — all 14 source files:
SmithersApp.swift, AppModel.swift, SmithersCore.swift, NSColor+Hex.swift, Tokens.swift, AppTheme.swift, Components.swift, DividerLine.swift, ChatWindowRootView.swift, ChatComposerZone.swift, ChatSidebarView.swift, ChatTitleBarZone.swift, SidebarModeBar.swift, IDEWindowRootView.swift

**SmithersTests Sources build phase** — 4 test files + 3 design system files:
SmithersTests.swift, ChatViewTests.swift, ComponentsTests.swift, DesignSystemTests.swift, NSColor+Hex.swift, Tokens.swift, AppTheme.swift

**File:** `macos/Smithers.xcodeproj/project.pbxproj`

### Step 2: Validate — zig build all
Run `zig build all` to ensure no regression. This step only touches pbxproj, so Zig build is unaffected — but we verify per always-green policy.

### Step 3: Validate — xcodebuild build
Run `xcodebuild build -project macos/Smithers.xcodeproj -scheme Smithers` to verify the project parses and builds. This is the primary acceptance criterion.

### Step 4: Validate — xcodebuild test
Run `xcodebuild test -project macos/Smithers.xcodeproj -scheme Smithers` to verify SmithersTests execute without project-parse errors. Tests may have their own failures — this step validates the project structure, not test correctness.

### Step 5: Validate shell script phase
Verify the "Verify SmithersKit.xcframework" run script phase works correctly:
- With `dist/SmithersKit.xcframework` present (should touch stamp, not rebuild)
- Confirm no infinite rebuild loop (outputPaths stamp file prevents re-execution)

## Files Inventory

### Files to modify:
- `macos/Smithers.xcodeproj/project.pbxproj` — full rewrite

### Files to create:
- `macos/Smithers.xcodeproj/backup/project.pbxproj.pre-rewrite` — safety backup
- `docs/plans/fix-xcodeproj-parse-error.md` — this plan

### Files NOT modified:
- `macos/Smithers.xcodeproj/xcshareddata/xcschemes/Smithers.xcscheme` — scheme is valid, references correct IDs
- All Swift source files — no changes
- `build.zig` — no changes
- Any Zig source — no changes

## Risks

1. **ID mismatch with scheme.** The scheme references `A00000000000000000000006` (Smithers target) and `B11111111111111111111116` (SmithersTests target). These IDs must be preserved exactly. Mitigated by using same IDs from current file.

2. **Shell script escaping.** OpenStep plist shell script escaping is notoriously tricky. A single misplaced `\"` or missing `\n` breaks the parse. Mitigated by testing with xcodebuild immediately after write.

3. **Swift compilation errors.** The 4 newly-added files may have compilation errors unrelated to the project structure fix. This ticket's scope is project parse/build — Swift compilation issues in those files would be separate tickets. However, since these files were already on disk from a prior implementation step, they should be valid.

4. **Test target may fail tests** (not compilation). The acceptance criteria says "executes SmithersTests without project-parse errors" — test failures are separate from project structure validity.

5. **xcframework may not have all needed symbols.** The current `dist/SmithersKit.xcframework` is a stub. If Swift files reference symbols not yet in the xcframework, linking will fail. This would indicate the xcframework needs updating (separate ticket), not a pbxproj issue.

## No Tests to Write

This ticket is purely a project file fix — no new code, no new logic. The validation IS the test:
- `xcodebuild build` = parse + compile test
- `xcodebuild test` = test infrastructure validation
- `zig build all` = regression check

No Zig unit tests, Playwright tests, or XCUITests are applicable. The pbxproj file is a build system artifact, not executable code.
