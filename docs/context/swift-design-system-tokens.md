# Research Context: swift-design-system-tokens

## Summary

Implement `DS` token enums, `AppTheme` struct with dark/light, SwiftUI Environment injection, and 4 shared components (`IconButton`, `PrimaryButton`, `PillButton`, `SidebarListRow`). Replace hardcoded colors in placeholder views. Add unit test verifying tokens.

## Current State

### Existing Swift Files (5 total + 1 test)
All in `macos/Sources/`:
- `App/SmithersApp.swift` — `@main`, two `Window` scenes, **inline placeholder** `ChatWindowRootView` and `IDEWindowRootView` with hardcoded `Color.black.opacity(0.94)` and `.white.opacity(0.88)`
- `App/AppModel.swift` — empty `@Observable @MainActor final class AppModel {}`
- `Ghostty/SmithersCore.swift` — C FFI bridge, `smokeInitAndFree()`
- `Features/Chat/Views/ChatWindowRootView.swift` — **CORRUPTED** (128 bytes, truncated mid-expression). Duplicate of inline def in SmithersApp.swift. **Must delete or fix.**
- `SmithersTests/SmithersTests.swift` — single test using Swift Testing (`@Suite`, `@Test`, `#expect`)

### Xcode Project (`project.pbxproj`)
- **Only 3 Swift files registered in build**: SmithersApp.swift, AppModel.swift, SmithersCore.swift
- Features/ directory files are **NOT in the Xcode project** — the ChatWindowRootView.swift there is unreferenced
- **Targets**: Smithers (app), SmithersTests (unit test bundle)
- **Settings**: macOS 14.0, Swift 6.0, `SWIFT_STRICT_CONCURRENCY = complete`, ad-hoc code signing
- **Framework**: SmithersKit.xcframework at `../dist/SmithersKit.xcframework`
- `OTHER_LDFLAGS = "-lstdc++"`

### Critical: Adding New Files Requires project.pbxproj Updates
Every new `.swift` file needs:
1. `PBXFileReference` entry (unique ID, path)
2. `PBXBuildFile` entry (linking file ref to Sources build phase)
3. `PBXGroup` entry (parent group must list the file ref)
4. The file ref ID added to the correct `PBXSourcesBuildPhase` (Smithers target or SmithersTests target)

### Build System
- `zig build all` is canonical green check — currently passes
- `xcodebuild test -project macos/Smithers.xcodeproj -scheme Smithers` — currently passes (1 test)
- `zig build xcode-test` runs the same xcodebuild command
- Xcode project does NOT auto-discover files — must be manually registered in pbxproj

### No DesignSystem Directory Exists
- No `macos/Sources/Helpers/` directory
- No `macos/Sources/DesignSystem/` directory
- Spec says `DesignSystem/` under `macos/Sources/Helpers/DesignSystem/` — but engineering spec also says `SmithersDesignSystem/Tokens/` and `SmithersDesignSystem/Components/`
- **Decision**: Use `macos/Sources/Helpers/DesignSystem/` per engineering spec §3 code org

## Reference Implementations

### v1 AppTheme (prototype0/Smithers/AppTheme.swift) — 290 lines
**Key patterns to follow:**
- `struct AppTheme: Equatable` with `NSColor` properties (not SwiftUI `Color`)
- SwiftUI convenience via extension: `var backgroundColor: Color { Color(nsColor: background) }`
- `NSColor.fromHex(_:)` — supports `#RRGGBB`, `0xRRGGBB`, 6/8 digit
- `NSColor.toHexString(includeAlpha:)`, `.luminance`, `.blended(with:fraction:)`, `.isApproximatelyEqual(to:tolerance:)`
- `static let default = AppTheme(...)` with all dark theme values
- `fromNvimHighlights(_:)` for dynamic theming (stub for now)
- `isLight` computed from `background.luminance > 0.55`
- `colorScheme` computed property for SwiftUI `.preferredColorScheme()`

### v1 Typography (prototype0/Smithers/Typography.swift) — 25 lines
```swift
enum Typography {
    static let xs: CGFloat = 10
    static let s: CGFloat = 11
    static let base: CGFloat = 13
    static let l: CGFloat = 15
    static let xl: CGFloat = 20
    static let iconS: CGFloat = 16
    static let iconM: CGFloat = 24
    static let iconL: CGFloat = 36
    static let lineHeightUI: CGFloat = 1.35
    static let lineHeightChat: CGFloat = 1.5
    static let lineHeightCode: CGFloat = 1.4
    static let textPrimary: Double = 0.88
    static let textMuted: Double = 0.60
    static let textFaint: Double = 0.45
}
```

### Ghostty NSColor Extension Pattern
- Uses `OSColor` typealias for cross-platform (NSColor on macOS, UIColor on iOS)
- `convenience init?(hex:)` — same Scanner-based hex parsing
- `.luminance` — perceptual formula
- `.darken(by:)` — HSB manipulation
- File: `ghostty/macos/Sources/Helpers/Extensions/OSColor+Extension.swift`

### Web Tokens (web/src/styles/tokens.css) — Canonical values
All token values defined in CSS custom properties. v2 design spec §2.1 is the canonical source, web tokens match.

Key values for Swift:
```
base: #0F111A
surface1: #141826
surface2: #1A2030
border: white@8%
sidebar.bg: #0C0E16
accent: #4C8DFF (rgb: 76, 141, 255)
success: #34D399
warning: #FBBF24
danger: #F87171
info: #60A5FA
text.primary: white@88%
text.secondary: white@60%
text.tertiary: white@45%
chat.bubble.user: accent@12%  (NOTE: v1 used white@8% — v2 spec says accent@12%)
```

## Design Spec Token Values (from system prompt §2)

### DS.Color (§2.1)
| Token | Value |
|-------|-------|
| `color.base` | `#0F111A` |
| `color.surface1` | `#141826` |
| `color.surface2` | `#1A2030` |
| `color.border` | `white@8%` |
| `color.accent` | `#4C8DFF` |
| `color.success` | `#34D399` |
| `color.warning` | `#FBBF24` |
| `color.danger` | `#F87171` |
| `color.info` | `#60A5FA` |
| `chat.sidebar.bg` | `#0C0E16` |
| `chat.sidebar.hover` | `white@4%` |
| `chat.sidebar.selected` | `accent@12%` |
| `chat.pill.bg` | `white@6%` |
| `chat.pill.border` | `white@10%` |
| `chat.pill.active` | `accent@15%` |
| `titlebar.bg` | `#141826` |
| `titlebar.fg` | `white@70%` |
| `chat.bubble.assistant` | `white@5%` |
| `chat.bubble.user` | `accent@12%` |
| `chat.bubble.command` | `white@4%` |
| `chat.bubble.status` | `white@4%` |
| `chat.bubble.diff` | `white@5%` |
| `chat.input.bg` | `white@6%` |

### DS.Type (§2.5)
| Token | Size |
|-------|------|
| `type.xs` | 10 |
| `type.s` | 11 |
| `type.base` | 13 |
| `type.l` | 15 |
| `type.xl` | 20 |
| `type.chatHeading` | 28 |
| `type.chatSubheading` | 16 |
| `type.chatSidebarTitle` | 12 |
| `type.chatTimestamp` | 10 |

### DS.Space (§2.6)
4pt grid: 4, 6, 8, 10, 12, 16, 24, 32

### DS.Radius (§2.7)
4, 6, 8, 10, 12, 16

### Text opacity (§2.2)
primary: 88%, secondary: 60%, tertiary: 45%

### Light theme derivation (§2.4)
- Keep accent identical
- base → #F6F7FB, surface1 → #FFFFFF, surface2 → #EEF1F7, border → black@10%
- Text: black@same-opacities
- Chat bubbles: assistant → black@4%, user → accent@12%
- Hover: black@3-4%

## Component Specs (from system prompt §3)

### IconButton (§3.1)
- Sizes: Small 24x24, Medium 28x28, Large 32x32
- Default: no bg; Hover: white@6%; Active: white@10%
- Icon: 14-16pt
- Tooltip via `.help()`

### PrimaryButton (§3.2)
- 32pt height, 12pt h-padding, radius 8
- accent@90% bg, white 92% text
- Hover: brighten +6% (white@6% overlay)
- Disabled: 45% opacity

### PillButton (§3.3)
- Radius 999 (capsule), padding 14pt h / 8pt v
- chat.pill.bg bg, 1px chat.pill.border border
- Hover/active: chat.pill.active

### SidebarListRow (§3.5)
- 44pt (or 36pt dense)
- Hover: white@4%; Selected: accent@12%
- Title: type.chatSidebarTitle 12pt primary; Secondary: 10pt tertiary

## Gotchas / Pitfalls

1. **Corrupted file**: `macos/Sources/Features/Chat/Views/ChatWindowRootView.swift` is truncated. SmithersApp.swift has duplicate inline definitions. Must reconcile — either delete the corrupted file or fix it and remove inline defs from SmithersApp.swift. The corrupted file is NOT in the Xcode project, so it's safe to delete.

2. **pbxproj manual edits**: Every new Swift file must be added to `project.pbxproj` with unique IDs. Use the existing ID pattern (A0/B1/C1/C4 prefixes + zero-padded). New files need: PBXFileReference, PBXBuildFile, added to PBXGroup children, added to PBXSourcesBuildPhase files array.

3. **Swift 6 strict concurrency**: `SWIFT_STRICT_CONCURRENCY = complete`. All mutable shared state must be `@MainActor` or use `actor`. Static token constants are fine (immutable). `AppTheme` as a struct is `Sendable` by default.

4. **v1 chat.bubble.user = white@8% vs v2 spec = accent@12%**: The design spec explicitly changed user bubble from white-tinted to accent-tinted. Use spec value (`accent@12%`), not v1 value.

5. **Environment injection pattern**: Use custom `EnvironmentKey` per v1 pattern. The v2 spec says `@Environment(\.theme)` — implement this. Don't use `@Environment(AppTheme.self)` (that's for `@Observable` classes, not structs).

## Implementation Plan Sketch

### New Files to Create
1. `macos/Sources/Helpers/DesignSystem/Tokens.swift` — `DS.Color`, `DS.Type`, `DS.Space`, `DS.Radius` enums with static constants
2. `macos/Sources/Helpers/DesignSystem/AppTheme.swift` — `AppTheme` struct (dark default, light stub), `EnvironmentKey`, SwiftUI Color convenience
3. `macos/Sources/Helpers/DesignSystem/NSColor+Hex.swift` — `fromHex`, `toHexString`, `luminance`, `isApproximatelyEqual`
4. `macos/Sources/Helpers/DesignSystem/Components.swift` — `IconButton`, `PrimaryButton`, `PillButton`, `SidebarListRow`
5. `macos/SmithersTests/DesignSystemTests.swift` — token value assertions

### Files to Modify
1. `macos/Sources/App/SmithersApp.swift` — replace hardcoded colors with theme, inject via `.environment(\.theme, ...)`
2. `macos/Smithers.xcodeproj/project.pbxproj` — register all new files

### Files to Delete/Fix
1. `macos/Sources/Features/Chat/Views/ChatWindowRootView.swift` — delete corrupted file (not in Xcode project anyway)

### Test Assertions
```swift
@Test func accentIsCorrect() {
    let hex = DS.Color.accent.toHexString(includeAlpha: false)
    #expect(hex == "4C8DFF")
}
```
