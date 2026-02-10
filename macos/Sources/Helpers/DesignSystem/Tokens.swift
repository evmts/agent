import AppKit

enum DS {
    enum Color {
        // Core surfaces
        static let base = mustHex("#0F111A")
        static let surface1 = mustHex("#141826")
        static let surface2 = mustHex("#1A2030")
        static let border = NSColor.white.withAlphaComponent(0.08)

        // Accent & semantic
        static let accent = mustHex("#4C8DFF")
        static let success = mustHex("#34D399")
        static let warning = mustHex("#FBBF24")
        static let danger  = mustHex("#F87171")
        static let info    = mustHex("#60A5FA")

        // Chat surfaces
        static let chatSidebarBg = NSColor.fromHex("#0C0E16")!
        static let chatSidebarHover = NSColor.white.withAlphaComponent(0.04)
        static let chatSidebarSelected = accent.withAlphaComponent(0.12)

        static let chatPillBg = NSColor.white.withAlphaComponent(0.06)
        static let chatPillBorder = NSColor.white.withAlphaComponent(0.10)
        static let chatPillActive = accent.withAlphaComponent(0.15)

        static let titlebarBg = surface1
        static let titlebarFg = NSColor.white.withAlphaComponent(0.70)

        // Chat bubbles
        static let chatBubbleAssistant = NSColor.white.withAlphaComponent(0.05)
        static let chatBubbleUser = accent.withAlphaComponent(0.12)
        static let chatBubbleCommand = NSColor.white.withAlphaComponent(0.04)
        static let chatBubbleStatus = NSColor.white.withAlphaComponent(0.04)
        static let chatBubbleDiff = NSColor.white.withAlphaComponent(0.05)
        static let chatInputBg = NSColor.white.withAlphaComponent(0.06)

        // Text opacity tokens
        static let textPrimary = NSColor.white.withAlphaComponent(0.88)
        static let textSecondary = NSColor.white.withAlphaComponent(0.60)
        static let textTertiary = NSColor.white.withAlphaComponent(0.45)

        // Overlay helpers
        static let overlayWhite06 = NSColor.white.withAlphaComponent(0.06)
        static let overlayWhite10 = NSColor.white.withAlphaComponent(0.10)
        // Text on accent background
        static let onAccentText = NSColor.white.withAlphaComponent(0.92)
    }

    // Named `Type` to align with spec (type.xs, type.base). Uppercase avoids keyword collision.
    enum Type {
        static let xs: CGFloat = 10
        static let s: CGFloat = 11
        static let base: CGFloat = 13
        static let l: CGFloat = 15
        static let xl: CGFloat = 20
        static let chatHeading: CGFloat = 28
        static let chatSubheading: CGFloat = 16
        static let chatSidebarTitle: CGFloat = 12
        static let chatTimestamp: CGFloat = 10

        static let lineHeightUI: CGFloat = 1.35
        static let lineHeightChat: CGFloat = 1.5
        static let lineHeightCode: CGFloat = 1.4
    }

    enum Space {
        static let _4: CGFloat = 4
        static let _6: CGFloat = 6
        static let _8: CGFloat = 8
        static let _10: CGFloat = 10
        static let _12: CGFloat = 12
        static let _16: CGFloat = 16
        static let _24: CGFloat = 24
        static let _32: CGFloat = 32
    }

    enum Radius {
        static let _4: CGFloat = 4
        static let _6: CGFloat = 6
        static let _8: CGFloat = 8
        static let _10: CGFloat = 10
        static let _12: CGFloat = 12
        static let _16: CGFloat = 16
    }
}

// Helper to fail fast if a token hex is malformed.
private func mustHex(_ s: String) -> NSColor {
    guard let c = NSColor.fromHex(s) else { preconditionFailure("Invalid design token hex: \(s)") }
    return c
}
