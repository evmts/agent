# Context: fix-xcodeproj-parse-error

## Diagnosis

The Xcode project at `macos/Smithers.xcodeproj/project.pbxproj` fails with:
```
xcodebuild: error: Unable to read project 'Smithers.xcodeproj'
Reason: The project 'Smithers' is damaged and cannot be opened due to a parse error.
```

The `.pbxproj` is an OpenStep-format plist (NOT JSON, NOT XML). Xcode's parser is strict about structure.

## Root Causes (7 issues found)

### CRITICAL Issue 1: Shell script string broken across lines 184-188

The `shellScript` value in the `PBXShellScriptBuildPhase` section (line 184) is split across multiple physical lines. In OpenStep plist, string values MUST be on a single line (with `\n` for embedded newlines). The string starts on line 184 but the closing `"` is on line 188.

**Current (broken):**
```
shellScript = "if [ ! -d ...]\nfi\n
                                    ← line 185: empty
# Emit stamp for incremental builds  ← line 186: raw text OUTSIDE string
/usr/bin/touch "..."                  ← line 187: raw text OUTSIDE string
"; };                                 ← line 188: orphaned closing
```

**Fix:** Merge the stamp-touch commands into the single-line escaped shellScript string. The entire value must be `"...escaped content with \\n..."` on ONE line. Add `\\n# Emit stamp for incremental builds\\n/usr/bin/touch \\"${SRCROOT}/../dist/SmithersKit.stamp\\"\\n` before the closing `"`.

**NOTE:** The `beforefix` backup (line 151-155) has the SAME broken shell script. This bug was introduced when the project was first created by an AI agent.

### CRITICAL Issue 2: PBXGroup entries mixed into PBXFileReference section

Lines 42-55 of the current file contain `PBXGroup` definitions (`isa = PBXGroup`) inside the `/* Begin PBXFileReference section */` ... `/* End PBXFileReference section */` block. Three groups are misplaced:

- Line 42: `D20000000000000000000001 /* Helpers */` — PBXGroup
- Line 46: `D20000000000000000000002 /* Extensions */` — PBXGroup
- Line 51: `D20000000000000000000003 /* DesignSystem */` — PBXGroup

**Fix:** Move these three PBXGroup definitions from the PBXFileReference section into the PBXGroup section (after line 76 `/* Begin PBXGroup section */`). They are duplicated — they already appear correctly in the PBXGroup section (lines 93, 46, 51 in current file map to the same IDs referenced in the Sources group).

Wait — actually looking more carefully, the three PBXGroup entries at lines 42-55 are NOT duplicated in the actual PBXGroup section (lines 76-129). The PBXGroup section references them by ID but they're only defined in the wrong section. So they need to be MOVED, not removed.

### Issue 3: Brace depth imbalance

The file ends with brace depth 1 instead of 0. This is caused by Issue 1 — the broken shell script string creates orphaned content that disrupts the parser's brace tracking.

### Issue 4: Missing Swift files from build phase

4 Swift files exist on disk but are NOT in the Smithers Sources build phase:
- `ChatComposerZone.swift`
- `ChatSidebarView.swift`
- `ChatTitleBarZone.swift`
- `SidebarModeBar.swift`

These need: PBXFileReference entries, PBXBuildFile entries, and inclusion in the Chat/Views PBXGroup and Smithers Sources build phase.

### Issue 5: ComponentsTests.swift missing from Tests PBXGroup

`ComponentsTests.swift` has a PBXBuildFile (line 24) and PBXFileReference (line 50), and is in the test Sources build phase, but is NOT listed in the Tests PBXGroup (lines 103-108). Add `D00000000000000000000007` to the Tests group children.

### Issue 6: DividerLine.swift missing from PBXGroup

`DividerLine.swift` has a PBXFileReference (line 63) and PBXBuildFile (line 28) in the main Sources build phase, but is NOT in any PBXGroup. It belongs in the DesignSystem group (`D20000000000000000000003`).

### Issue 7: Inconsistent indentation

Multiple lines have inconsistent tab/space indentation. While not a parse error, it's messy. Some entries use tabs, some use spaces, some have no leading whitespace (e.g., lines 24, 50, 215, 236).

## Files Inventory

### Swift files on disk (Sources):
```
Sources/App/AppModel.swift
Sources/App/SmithersApp.swift
Sources/Features/Chat/Views/ChatComposerZone.swift
Sources/Features/Chat/Views/ChatSidebarView.swift
Sources/Features/Chat/Views/ChatTitleBarZone.swift
Sources/Features/Chat/Views/ChatWindowRootView.swift
Sources/Features/Chat/Views/SidebarModeBar.swift
Sources/Features/IDE/Views/IDEWindowRootView.swift
Sources/Ghostty/SmithersCore.swift
Sources/Helpers/DesignSystem/AppTheme.swift
Sources/Helpers/DesignSystem/Components.swift
Sources/Helpers/DesignSystem/DividerLine.swift
Sources/Helpers/DesignSystem/Tokens.swift
Sources/Helpers/Extensions/NSColor+Hex.swift
```

### Swift files on disk (Tests):
```
SmithersTests/ChatViewTests.swift
SmithersTests/ComponentsTests.swift
SmithersTests/DesignSystemTests.swift
SmithersTests/SmithersTests.swift
```

### Files in Smithers Sources build phase (current):
- SmithersApp.swift, ChatWindowRootView.swift, IDEWindowRootView.swift, DividerLine.swift, AppModel.swift, SmithersCore.swift, NSColor+Hex.swift, Tokens.swift, AppTheme.swift, Components.swift

### Files MISSING from Smithers Sources build phase:
- ChatComposerZone.swift, ChatSidebarView.swift, ChatTitleBarZone.swift, SidebarModeBar.swift

## Fix Strategy

The cleanest approach is to **rewrite the entire project.pbxproj** rather than patch individual issues. The file is only ~300 lines and hand-crafted (not Xcode-generated), so a clean rewrite with proper structure is safer than surgical edits that might miss edge cases.

### Rewrite checklist:
1. Proper section ordering: PBXBuildFile → PBXContainerItemProxy → PBXFileReference → PBXFrameworksBuildPhase → PBXGroup → PBXNativeTarget → PBXProject → PBXResourcesBuildPhase → PBXShellScriptBuildPhase → PBXSourcesBuildPhase → PBXTargetDependency → XCBuildConfiguration → XCConfigurationList
2. All PBXFileReference entries for ALL 14 Swift source files + 4 test files + plist + entitlements + xcframework + products
3. All PBXBuildFile entries for source compilation + framework linking
4. Test source files also need design system sources compiled into them (Tokens, AppTheme, NSColor+Hex — already done in current file)
5. PBXGroup hierarchy matching actual directory structure
6. Shell script as single-line escaped string
7. Consistent tab indentation throughout
8. Proper brace balancing

### Shell script fix (single-line format):
The `shellScript` value must be entirely on one line with `\n` for newlines:
```
shellScript = "if [ ! -d \"${SRCROOT}/../dist/SmithersKit.xcframework\" ]; then\n  echo \"SmithersKit.xcframework not found at ../dist. Building via 'zig build xcframework'...\"\n  ROOT=\"$(cd \"${SRCROOT}/..\"; pwd)\"\n  cd \"$ROOT\"\n  if ! command -v zig >/dev/null 2>&1; then\n    echo \"zig not found. Install Zig or build xcframework manually.\" >&2\n    exit 1\n  fi\n  zig build xcframework || { echo \"zig build xcframework failed\"; exit 1; }\nfi\n\n# Emit stamp for incremental builds\n/usr/bin/touch \"${SRCROOT}/../dist/SmithersKit.stamp\"\n";
```

### New file IDs needed (for missing files):
Use the same ID pattern as existing entries (long numeric/hex strings). Need PBXFileReference + PBXBuildFile for:
- ChatComposerZone.swift
- ChatSidebarView.swift
- ChatTitleBarZone.swift
- SidebarModeBar.swift

## Key Reference Files

1. `macos/Smithers.xcodeproj/project.pbxproj` — THE file to fix (300 lines)
2. `macos/Smithers.xcodeproj/backup/project.pbxproj.bak` — earliest backup (194 lines, minimal — only SmithersApp.swift)
3. `macos/Smithers.xcodeproj/backup/project.pbxproj.beforefix` — intermediate backup (268 lines, has same bugs)
4. `macos/Smithers.xcodeproj/xcshareddata/xcschemes/Smithers.xcscheme` — scheme file (OK, no changes needed)
5. `scripts/xcode_build_and_open.sh` — build+launch script (uses same xcodebuild command)
6. `dist/SmithersKit.xcframework/` — pre-built xcframework (exists, valid Info.plist)

## Verification Commands

```bash
# 1. Verify zig build still green (MUST not regress)
zig build all

# 2. Build the Xcode project
xcodebuild build -project macos/Smithers.xcodeproj -scheme Smithers

# 3. Run tests
xcodebuild test -project macos/Smithers.xcodeproj -scheme Smithers

# 4. Full build+launch
bash scripts/xcode_build_and_open.sh
```

## Gotchas

1. **OpenStep plist format** — NOT XML, NOT JSON. Uses `{ }` for dicts, `( )` for arrays, `"..."` for strings, `;` as value terminator. Comments are `/* ... */`. LLMs often confuse this with XML plist.

2. **Shell script escaping** — In pbxproj, the shellScript string uses `\"` for quotes inside, `\n` for newlines. Everything must be on ONE physical line. The stamp touch must be part of the same string.

3. **Test target compilation** — The SmithersTests target compiles design system files (Tokens.swift, AppTheme.swift, NSColor+Hex.swift) directly into its Sources build phase. This is necessary because there's no shared framework target — the test target needs these files to run DesignSystemTests and ComponentsTests. Each needs a separate PBXBuildFile ID (can't reuse the app target's).

4. **EXCLUDED_ARCHS = x86_64** — The test target Debug config (line 262) excludes x86_64. This is fine for ARM Macs but may need attention if CI runs on Intel.

5. **xcframework path** — The SmithersKit.xcframework is referenced via relative path `../dist/SmithersKit.xcframework` (relative to the .xcodeproj location). The verify script checks for this path and runs `zig build xcframework` if missing.
