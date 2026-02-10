# Plan: swift-design-system-tokens

## Summary

Implement the Swift DesignSystem module: DS token enums, AppTheme struct (dark default + light derivation stub), SwiftUI Environment injection, and 4 shared components. Replace hardcoded colors in placeholder windows. Add unit tests verifying token values.

## Current State

- **3 Swift files in build:** SmithersApp.swift (inline placeholder views with hardcoded `Color.black.opacity(0.94)` and `.white.opacity(0.88)`), AppModel.swift (empty), SmithersCore.swift
- **1 test file:** SmithersTests.swift (Swift Testing framework, `@Suite`/`@Test`/`#expect`)
- **No DesignSystem directory** — must create `macos/Sources/Helpers/DesignSystem/`
- **Corrupted file:** `macos/Sources/Features/Chat/Views/ChatWindowRootView.swift` (128 bytes, truncated, NOT in pbxproj) — must delete
- **pbxproj:** Every new `.swift` file needs 4 manual entries (PBXFileReference, PBXBuildFile, PBXGroup children, PBXSourcesBuildPhase)
- **Build config:** macOS 14.0, Swift 6.0, `SWIFT_STRICT_CONCURRENCY = complete`, ad-hoc signing

## Reference Patterns (v1)

- `AppTheme` struct with `NSColor` properties + SwiftUI `Color` computed extensions
- `NSColor.fromHex(_:)` with Scanner-based parsing (6/8 digit)
- `NSColor.toHexString(includeAlpha:)`, `.luminance`, `.isApproximatelyEqual(to:tolerance:)`
- Typography enum with static `CGFloat` constants
- Custom `EnvironmentKey` for theme injection (`@Environment(\.theme)`)

## v1→v2 Spec Change

- `chat.bubble.user`: v1 `white@8%` → **v2 `accent@12%`** (per design spec §2.1)

---

## Implementation Steps

### Step 0: Delete corrupted file

Delete `macos/Sources/Features/Chat/Views/ChatWindowRootView.swift` — 128-byte truncated file, not in Xcode project, safe to remove. Prevents confusion.

**Files affected:**
- DELETE: `macos/Sources/Features/Chat/Views/ChatWindowRootView.swift`

### Step 1: Create NSColor+Hex extension

Foundation for all token definitions. Hex parsing, luminance, comparison utilities.

**File:** `macos/Sources/Helpers/Extensions/NSColor+Hex.swift`

Content:
- `NSColor.fromHex(_:)` — supports `#RRGGBB`, `0xRRGGBB`, 6/8 digit hex strings
- `NSColor.toHexString(includeAlpha:)` — sRGB hex output
- `NSColor.luminance` — perceptual luminance (0.2126R + 0.7152G + 0.0722B)
- `NSColor.blended(with:fraction:)` — color blending via sRGB space
- `NSColor.isApproximatelyEqual(to:tolerance:)` — component-wise comparison

Adapted from v1 `AppTheme.swift` NSColor extension (lines 238-289), extracted to own file per v2 org.

### Step 2: Create DS token enums

Static design token constants per spec §2.1-§2.7.

**File:** `macos/Sources/Helpers/DesignSystem/Tokens.swift`

Content — single `DS` enum namespace:
- `DS.Color` — all surface, accent, semantic, chat, text tokens as `static let` NSColor values
  - `base`, `surface1`, `surface2`, `border`, `accent`, `success`, `warning`, `danger`, `info`
  - `chatSidebarBg`, `chatSidebarHover`, `chatSidebarSelected`
  - `chatPillBg`, `chatPillBorder`, `chatPillActive`
  - `titlebarBg`, `titlebarFg`
  - `chatBubbleAssistant`, `chatBubbleUser` (accent@12%, NOT white@8%), `chatBubbleCommand`, `chatBubbleStatus`, `chatBubbleDiff`
  - `chatInputBg`
  - `textPrimary`, `textSecondary`, `textTertiary`
- `DS.Typography` — `xs`(10), `s`(11), `base`(13), `l`(15), `xl`(20), `chatHeading`(28), `chatSubheading`(16), `chatSidebarTitle`(12), `chatTimestamp`(10); line height multipliers; icon sizes
- `DS.Space` — 4pt grid: `_4`, `_6`, `_8`, `_10`, `_12`, `_16`, `_24`, `_32`
- `DS.Radius` — `_4`, `_6`, `_8`, `_10`, `_12`, `_16`

### Step 3: Create AppTheme struct + EnvironmentKey

Resolved theme struct injected via SwiftUI environment.

**File:** `macos/Sources/Helpers/DesignSystem/AppTheme.swift`

Content:
- `struct AppTheme: Equatable, Sendable` — NSColor properties for all resolved colors:
  - background, foreground, mutedForeground, secondaryBackground, panelBackground
  - panelBorder, divider, tabBarBackground, tabSelectedBackground, tabSelectedForeground
  - tabForeground, tabBorder, selectionBackground, matchingBracket, accent
  - lineNumberForeground, lineNumberSelectedForeground, lineNumberBackground, lineHighlight
  - chatAssistantBubble, chatUserBubble, chatCommandBubble, chatStatusBubble, chatDiffBubble
  - inputFieldBackground
- `static let dark = AppTheme(...)` — populated from `DS.Color` tokens
- `static let light = AppTheme(...)` — stub per spec §2.4 derivation (base→#F6F7FB, surface1→#FFFFFF, etc.)
- `isLight` computed via `background.luminance > 0.55`
- `colorScheme` computed returning `.light`/`.dark`
- `fromNvimHighlights(_:)` — stub returning `.dark` (impl in Phase 6)
- SwiftUI `Color` computed extension properties (e.g., `var backgroundColor: Color { Color(nsColor: background) }`)
- Custom `EnvironmentKey`:
  ```swift
  private struct ThemeKey: EnvironmentKey {
      static let defaultValue = AppTheme.dark
  }
  extension EnvironmentValues {
      var theme: AppTheme { get { self[ThemeKey.self] } set { self[ThemeKey.self] = newValue } }
  }
  ```
- Equatable via `comparisonColors` array + `isApproximatelyEqual` (v1 pattern)

### Step 4: Create shared components

4 reusable SwiftUI components per spec §3.

**File:** `macos/Sources/Helpers/DesignSystem/Components.swift`

Content:
- **`IconButton`** — Sizes enum (.small 24, .medium 28, .large 32), SF Symbol name, action closure. Default no bg, hover `white@6%`, active `white@10%`. Tooltip via `.help()`. `@Environment(\.theme)` for colors.
- **`PrimaryButton`** — 32pt height, 12pt h-padding, radius 8, accent@90% bg, white@92% text. Hover brightens. Disabled 45% opacity. Takes label string + action.
- **`PillButton`** — Capsule shape, 14pt h / 8pt v padding, `chatPillBg` bg, 1px `chatPillBorder` border. Hover/active `chatPillActive`. Takes label + optional SF Symbol + action.
- **`SidebarListRow`** — 44pt height (36pt dense variant). Hover `white@4%`, selected `accent@12%`. Title 12pt primary, secondary 10pt tertiary. Takes title, subtitle, isSelected, action.

All components use `@Environment(\.theme)` — no hardcoded colors.

### Step 5: Write unit tests (TDD — tests before wiring)

**File:** `macos/SmithersTests/DesignSystemTests.swift`

Tests using Swift Testing framework:
- `@Test func accentIsCorrect()` — verify `DS.Color.accent.toHexString(includeAlpha: false) == "4C8DFF"`
- `@Test func baseIsCorrect()` — verify `DS.Color.base.toHexString(includeAlpha: false) == "0F111A"`
- `@Test func darkThemeUsesSpecTokens()` — verify `AppTheme.dark.accent.isApproximatelyEqual(to: DS.Color.accent)`
- `@Test func lightThemeInvertsBase()` — verify `AppTheme.light.background.luminance > 0.55`
- `@Test func typographyBaseIs13()` — verify `DS.Typography.base == 13`
- `@Test func spacingGridIs4pt()` — verify `DS.Space._4 == 4`, `DS.Space._8 == 8`, etc.
- `@Test func radiusValues()` — verify radius constants
- `@Test func hexParsingRoundTrip()` — create NSColor from hex, convert back, verify
- `@Test func chatBubbleUserIsAccentTinted()` — verify v2 spec: user bubble uses accent@12% not white@8%

### Step 6: Update SmithersApp.swift — replace hardcoded colors with theme

Replace inline placeholder views with theme-driven versions. Inject theme via `.environment(\.theme, appModel.theme)`.

**File:** `macos/Sources/App/SmithersApp.swift`

Changes:
- Add `import AppKit` (for NSColor used by theme)
- Inject theme: `.environment(\.theme, AppTheme.dark)` on both window scenes
  (Later: AppModel will own theme; for now, static `.dark`)
- `ChatWindowRootView`: replace `Color.black.opacity(0.94)` → `theme.backgroundColor`, `.white.opacity(0.88)` → `theme.foregroundColor`
- `IDEWindowRootView`: same replacements
- Both views: `@Environment(\.theme) private var theme`

### Step 7: Update AppModel.swift — add theme property

**File:** `macos/Sources/App/AppModel.swift`

Changes:
- Add `var theme: AppTheme = .dark` property
- Future phases wire preferences/Neovim override; for now default dark

### Step 8: Register all new files in project.pbxproj

**File:** `macos/Smithers.xcodeproj/project.pbxproj`

Must add for each new file:
1. **PBXFileReference** entry with unique ID
2. **PBXBuildFile** entry linking to Sources build phase
3. **PBXGroup** entries for new directory groups (Helpers, DesignSystem, Extensions)
4. File refs added to correct **PBXSourcesBuildPhase**

New files for **Smithers app target** (5 files):
- `NSColor+Hex.swift` → Helpers/Extensions/
- `Tokens.swift` → Helpers/DesignSystem/
- `AppTheme.swift` → Helpers/DesignSystem/
- `Components.swift` → Helpers/DesignSystem/

New file for **SmithersTests target** (1 file):
- `DesignSystemTests.swift` → SmithersTests/

New PBXGroup entries:
- `Helpers` (child of Sources)
  - `Extensions` (child of Helpers)
  - `DesignSystem` (child of Helpers)

UUID pattern (following existing convention of zero-padded hex):
- `D` prefix for new DesignSystem files
- File refs: `D00000000000000000000001` through `D00000000000000000000005`
- Build files: `D10000000000000000000001` through `D10000000000000000000005`
- Groups: `D20000000000000000000001` (Helpers), `D20000000000000000000002` (Extensions), `D20000000000000000000003` (DesignSystem)
- Test build file: `D10000000000000000000006`
- Test file ref: `D00000000000000000000006`

### Step 9: Verify green build

Run `zig build all` to verify:
- `xcodebuild build` succeeds (app compiles with new files)
- `xcodebuild test` succeeds (all tests pass including new DesignSystemTests)
- `zig fmt --check .` passes
- No new warnings under `SWIFT_STRICT_CONCURRENCY = complete`

---

## Files to Create

1. `macos/Sources/Helpers/Extensions/NSColor+Hex.swift` — hex parsing + color utilities
2. `macos/Sources/Helpers/DesignSystem/Tokens.swift` — DS.Color, DS.Typography, DS.Space, DS.Radius
3. `macos/Sources/Helpers/DesignSystem/AppTheme.swift` — theme struct + EnvironmentKey + Color extensions
4. `macos/Sources/Helpers/DesignSystem/Components.swift` — IconButton, PrimaryButton, PillButton, SidebarListRow
5. `macos/SmithersTests/DesignSystemTests.swift` — token value assertions

## Files to Modify

1. `macos/Sources/App/SmithersApp.swift` — replace hardcoded colors, inject theme
2. `macos/Sources/App/AppModel.swift` — add theme property
3. `macos/Smithers.xcodeproj/project.pbxproj` — register all new files + groups

## Files to Delete

1. `macos/Sources/Features/Chat/Views/ChatWindowRootView.swift` — corrupted, not in project

## Risks

1. **pbxproj corruption** — Manual edits to Xcode project file are fragile. Unique IDs must not collide. Mitigated: use systematic D-prefix pattern, verify build immediately.
2. **Swift 6 strict concurrency** — `AppTheme` struct is value-type so auto-Sendable. `DS` enum with static lets is safe. Components using `@Environment` are MainActor-isolated by SwiftUI. Low risk.
3. **NSColor color space** — `fromHex` must use `sRGB` color space for consistent round-trip. `toHexString` must convert via `usingColorSpace(.sRGB)`. Pattern proven in v1.
4. **Test target linking** — `DesignSystemTests.swift` must be added to SmithersTests target (not Smithers app target). Tests import types via `@testable import Smithers` or direct access since unit test target depends on app.
5. **v2 chat.bubble.user spec change** — Must use `accent@12%` (not v1 `white@8%`). Explicit in tokens + test assertion.

## Dependency Order

```
Step 0 (delete corrupted)
  → Step 1 (NSColor+Hex) — no deps
    → Step 2 (Tokens) — depends on NSColor+Hex for fromHex
      → Step 3 (AppTheme) — depends on Tokens
        → Step 4 (Components) — depends on AppTheme/theme EnvironmentKey
          → Step 5 (Tests) — depends on all above
            → Step 6 (SmithersApp update) — depends on AppTheme
              → Step 7 (AppModel update) — depends on AppTheme
                → Step 8 (pbxproj) — depends on all files existing
                  → Step 9 (verify green)
```

Note: Steps 5-7 could be done in parallel with 8, but 8 must include all files before build verification.

## Implementation Note: pbxproj Registration

The critical part is getting the pbxproj right. Every file needs entries in 4 sections. The test file goes to the SmithersTests sources build phase, everything else to Smithers sources build phase. New group hierarchy:

```
Sources (A00000000000000000000004)
├── App (existing)
├── Ghostty (existing)
└── Helpers (NEW: D20000000000000000000001)
    ├── Extensions (NEW: D20000000000000000000002)
    │   └── NSColor+Hex.swift
    └── DesignSystem (NEW: D20000000000000000000003)
        ├── Tokens.swift
        ├── AppTheme.swift
        └── Components.swift
```
