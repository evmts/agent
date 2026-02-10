# Design System Implementation

## 13. Design System Implementation

### 13.1 Token definitions

All tokens live in `SmithersDesignSystem/Tokens/`. Implemented as static constants on namespaced enums:

```swift
enum DS {
    enum Color {
        static let base = NSColor(hex: "#0F111A")!
        static let surface1 = NSColor(hex: "#141826")!
        static let surface2 = NSColor(hex: "#1A2030")!
        static let border = NSColor.white.withAlphaComponent(0.08)
        static let accent = NSColor(hex: "#4C8DFF")!
        // ... all tokens from design spec section 2.1
    }
    enum Type {
        static let xs: CGFloat = 10
        static let s: CGFloat = 11
        static let base: CGFloat = 13
        static let l: CGFloat = 15
        static let xl: CGFloat = 20
        static let chatHeading: CGFloat = 28
        // ... all tokens from design spec section 2.5
    }
    enum Space {
        static let _4: CGFloat = 4
        static let _6: CGFloat = 6
        static let _8: CGFloat = 8
        // ... through _32
    }
    enum Radius {
        static let _4: CGFloat = 4
        static let _6: CGFloat = 6
        // ... through _16
    }
}
```

### 13.2 AppTheme

Struct containing all resolved colors for the current appearance (dark/light). Injected into the SwiftUI environment via a custom `EnvironmentKey`.

```swift
struct AppTheme: Equatable {
    let background: NSColor
    let foreground: NSColor
    let mutedForeground: NSColor
    let secondaryBackground: NSColor
    // ... all 24+ color properties

    static let dark = AppTheme(...)   // default dark theme
    static let light = AppTheme(...)  // derived light theme
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = AppTheme.dark
}

extension EnvironmentValues {
    var theme: AppTheme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
```

Views access the theme via `@Environment(\.theme) private var theme`.

### 13.3 Light theme derivation

Per the design spec (section 2.4):

```swift
extension AppTheme {
    static var light: AppTheme {
        AppTheme(
            background: NSColor(hex: "#F6F7FB")!,
            foreground: NSColor.black.withAlphaComponent(0.88),
            mutedForeground: NSColor.black.withAlphaComponent(0.60),
            secondaryBackground: NSColor(hex: "#FFFFFF")!,
            panelBackground: NSColor(hex: "#EEF1F7")!,
            border: NSColor.black.withAlphaComponent(0.10),
            accent: DS.Color.accent,  // same accent in both themes
            // Hover states use black@3-4% instead of white
            // Chat bubbles: assistant → black@4%, user → accent@12%
            // ...
        )
    }
}
```

### 13.4 Neovim theme derivation

`ThemeDerived.fromNvimHighlights()` takes a dictionary of Neovim highlight group colors and maps them to `AppTheme` properties:

- `Normal.bg` → `background`, `Normal.fg` → `foreground`
- `Visual.bg` → `selectionBackground`
- `CursorLine.bg` → `lineHighlight`
- `TabLine*` → tab bar colors
- `Pmenu*` → panel colors
- `LineNr` / `CursorLineNr` → line number colors
- Missing groups: derive via alpha blending from background + foreground.

### 13.5 Shared components

All components in `SmithersDesignSystem/Components/` read the theme from the environment. They are purely presentational — no business logic, no dependencies on models or services.
