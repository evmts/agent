import SwiftUI
import AppKit

struct AppTheme: Equatable {
    // Core
    let background: NSColor
    let foreground: NSColor
    let mutedForeground: NSColor
    let secondaryBackground: NSColor
    let panelBackground: NSColor
    let border: NSColor
    let accent: NSColor

    // Editor/aux
    let selectionBackground: NSColor
    let matchingBracket: NSColor
    let lineHighlight: NSColor
    let lineNumberForeground: NSColor
    let lineNumberSelectedForeground: NSColor

    // Chat
    let chatAssistantBubble: NSColor
    let chatUserBubble: NSColor
    let chatCommandBubble: NSColor
    let chatStatusBubble: NSColor
    let chatDiffBubble: NSColor
    let inputFieldBackground: NSColor

    // Derived
    // Threshold chosen to align with derived light theme surface stack; backgrounds above ~0.55 luminance are treated as light.
    var isLight: Bool { background.luminance > 0.55 }
    var colorScheme: ColorScheme { isLight ? .light : .dark }

    // SwiftUI convenience
    var backgroundColor: Color { Color(nsColor: background) }
    var foregroundColor: Color { Color(nsColor: foreground) }
}

extension AppTheme {
    static let dark = AppTheme(
        background: DS.Color.base,
        foreground: DS.Color.textPrimary,
        mutedForeground: DS.Color.textSecondary,
        secondaryBackground: DS.Color.surface1,
        panelBackground: DS.Color.surface2,
        border: DS.Color.border,
        accent: DS.Color.accent,

        selectionBackground: NSColor.white.withAlphaComponent(0.10),
        matchingBracket: NSColor.white.withAlphaComponent(0.16),
        lineHighlight: NSColor.white.withAlphaComponent(0.08),
        lineNumberForeground: DS.Color.textTertiary,
        lineNumberSelectedForeground: DS.Color.textSecondary,

        chatAssistantBubble: DS.Color.chatBubbleAssistant,
        chatUserBubble: DS.Color.chatBubbleUser,
        chatCommandBubble: DS.Color.chatBubbleCommand,
        chatStatusBubble: DS.Color.chatBubbleStatus,
        chatDiffBubble: DS.Color.chatBubbleDiff,
        inputFieldBackground: DS.Color.chatInputBg
    )

    // Light derivation per spec §2.4
    static let light = AppTheme(
        background: NSColor.fromHex("#F6F7FB")!,
        foreground: NSColor.black.withAlphaComponent(0.88),
        mutedForeground: NSColor.black.withAlphaComponent(0.60),
        secondaryBackground: NSColor.fromHex("#FFFFFF")!,
        panelBackground: NSColor.fromHex("#EEF1F7")!,
        border: NSColor.black.withAlphaComponent(0.10),
        accent: DS.Color.accent,

        selectionBackground: NSColor.black.withAlphaComponent(0.08),
        matchingBracket: NSColor.black.withAlphaComponent(0.16),
        lineHighlight: NSColor.black.withAlphaComponent(0.06),
        lineNumberForeground: NSColor.black.withAlphaComponent(0.45),
        lineNumberSelectedForeground: NSColor.black.withAlphaComponent(0.60),

        chatAssistantBubble: NSColor.black.withAlphaComponent(0.04),
        chatUserBubble: DS.Color.accent.withAlphaComponent(0.12),
        chatCommandBubble: NSColor.black.withAlphaComponent(0.04),
        chatStatusBubble: NSColor.black.withAlphaComponent(0.04),
        chatDiffBubble: NSColor.black.withAlphaComponent(0.05),
        inputFieldBackground: NSColor.black.withAlphaComponent(0.06)
    )
}

// Theme EnvironmentKey per spec
private struct ThemeKey: EnvironmentKey {
    static let defaultValue: AppTheme = .dark
}

// Value-based Equatable: compare color values approximately in sRGB
extension AppTheme {
    static func == (lhs: AppTheme, rhs: AppTheme) -> Bool {
        let pairs: [(NSColor, NSColor)] = [
            (lhs.background, rhs.background),
            (lhs.foreground, rhs.foreground),
            (lhs.mutedForeground, rhs.mutedForeground),
            (lhs.secondaryBackground, rhs.secondaryBackground),
            (lhs.panelBackground, rhs.panelBackground),
            (lhs.border, rhs.border),
            (lhs.accent, rhs.accent),
            (lhs.selectionBackground, rhs.selectionBackground),
            (lhs.matchingBracket, rhs.matchingBracket),
            (lhs.lineHighlight, rhs.lineHighlight),
            (lhs.lineNumberForeground, rhs.lineNumberForeground),
            (lhs.lineNumberSelectedForeground, rhs.lineNumberSelectedForeground),
            (lhs.chatAssistantBubble, rhs.chatAssistantBubble),
            (lhs.chatUserBubble, rhs.chatUserBubble),
            (lhs.chatCommandBubble, rhs.chatCommandBubble),
            (lhs.chatStatusBubble, rhs.chatStatusBubble),
            (lhs.chatDiffBubble, rhs.chatDiffBubble),
            (lhs.inputFieldBackground, rhs.inputFieldBackground),
        ]
        for (a, b) in pairs { if !a.isApproximatelyEqual(to: b) { return false } }
        return true
    }
}
extension EnvironmentValues {
    var theme: AppTheme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
