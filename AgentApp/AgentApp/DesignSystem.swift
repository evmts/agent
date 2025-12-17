import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Design System for Agent App (Based on Plue)

struct DesignSystem {

    // MARK: - Theme Management

    enum Theme: String, CaseIterable {
        case dark = "dark"
        case light = "light"

        var displayName: String {
            switch self {
            case .dark: return "Dark"
            case .light: return "Light"
            }
        }
    }

    // MARK: - Color Palette

    struct Colors {
        // Brand Colors
        static let primary = Color(red: 0.0, green: 0.478, blue: 1.0)
        static let accent = Color(red: 0.345, green: 0.337, blue: 0.839)
        static let success = Color(red: 0.204, green: 0.780, blue: 0.349)
        static let warning = Color(red: 1.0, green: 0.800, blue: 0.0)
        static let error = Color(red: 1.0, green: 0.231, blue: 0.188)

        #if os(macOS)
        // Theme-Aware Semantic Colors (Native macOS palette)
        static func background(for theme: Theme) -> Color {
            Color(NSColor.windowBackgroundColor)
        }

        static func surface(for theme: Theme) -> Color {
            Color(NSColor.controlBackgroundColor)
        }

        static func border(for theme: Theme) -> Color {
            Color(NSColor.separatorColor)
        }

        static func textPrimary(for theme: Theme) -> Color {
            Color(NSColor.labelColor)
        }

        static func textSecondary(for theme: Theme) -> Color {
            Color(NSColor.secondaryLabelColor)
        }

        // Legacy compatibility
        static let background = Color(NSColor.windowBackgroundColor)
        static let surface = Color(NSColor.controlBackgroundColor)
        static let border = Color(NSColor.separatorColor)
        static let textPrimary = Color(NSColor.labelColor)
        static let textSecondary = Color(NSColor.secondaryLabelColor)
        static let textTertiary = Color(NSColor.tertiaryLabelColor)
        #else
        static func background(for theme: Theme) -> Color {
            theme == .dark ? Color(white: 0.1) : Color(white: 0.95)
        }

        static func surface(for theme: Theme) -> Color {
            theme == .dark ? Color(white: 0.15) : Color.white
        }

        static func border(for theme: Theme) -> Color {
            theme == .dark ? Color(white: 0.3) : Color(white: 0.8)
        }

        static func textPrimary(for theme: Theme) -> Color {
            theme == .dark ? Color.white : Color.black
        }

        static func textSecondary(for theme: Theme) -> Color {
            theme == .dark ? Color(white: 0.7) : Color(white: 0.4)
        }

        static let background = Color(white: 0.1)
        static let surface = Color(white: 0.15)
        static let border = Color(white: 0.3)
        static let textPrimary = Color.white
        static let textSecondary = Color(white: 0.7)
        static let textTertiary = Color(white: 0.5)
        #endif
    }

    // MARK: - Typography

    struct Typography {
        static let headlineLarge = Font.system(size: 28, weight: .semibold, design: .default)
        static let headlineMedium = Font.system(size: 22, weight: .semibold, design: .default)
        static let headlineSmall = Font.system(size: 18, weight: .semibold, design: .default)

        static let titleLarge = Font.system(size: 17, weight: .medium, design: .default)
        static let titleMedium = Font.system(size: 15, weight: .medium, design: .default)
        static let titleSmall = Font.system(size: 13, weight: .medium, design: .default)

        static let bodyLarge = Font.system(size: 15, weight: .regular, design: .default)
        static let bodyMedium = Font.system(size: 13, weight: .regular, design: .default)
        static let bodySmall = Font.system(size: 11, weight: .regular, design: .default)

        static let labelLarge = Font.system(size: 13, weight: .medium, design: .default)
        static let labelMedium = Font.system(size: 11, weight: .medium, design: .default)
        static let labelSmall = Font.system(size: 10, weight: .medium, design: .default)

        static let monoMedium = Font.system(size: 12, weight: .regular, design: .monospaced)
        static let monoSmall = Font.system(size: 10, weight: .regular, design: .monospaced)
    }

    // MARK: - Spacing

    struct Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
    }

    // MARK: - Corner Radius

    struct CornerRadius {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
        static let xl: CGFloat = 16
    }

    // MARK: - Animation

    struct Animation {
        static let quick = SwiftUI.Animation.easeOut(duration: 0.18)
        static let smooth = SwiftUI.Animation.easeInOut(duration: 0.25)
        static let tabSwitch = SwiftUI.Animation.easeInOut(duration: 0.12)
        static let messageAppear = SwiftUI.Animation.spring(response: 0.3, dampingFraction: 0.75)
        static let buttonPress = SwiftUI.Animation.easeOut(duration: 0.12)
    }

    // MARK: - Icon Sizes

    struct IconSize {
        static let small: CGFloat = 12
        static let medium: CGFloat = 16
        static let large: CGFloat = 20
        static let xl: CGFloat = 24
    }

    // MARK: - Materials

    struct Materials {
        static let thin = Material.thin
        static let regular = Material.regular
        static let thick = Material.thick

        static func adaptive(for theme: Theme) -> Material {
            theme == .dark ? .ultraThick : .regular
        }
    }
}

// MARK: - View Extensions

extension View {
    func primarySurface() -> some View {
        self
            .background(DesignSystem.Materials.regular)
            .background(DesignSystem.Colors.surface.opacity(0.5))
            .cornerRadius(DesignSystem.CornerRadius.md)
    }

    func elevatedSurface() -> some View {
        self
            .background(DesignSystem.Materials.thick)
            .cornerRadius(DesignSystem.CornerRadius.lg)
            .shadow(color: Color.black.opacity(0.2), radius: 5, x: 0, y: 2)
    }
}

// MARK: - Button Styles

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(DesignSystem.Colors.primary)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(DesignSystem.Animation.buttonPress, value: configuration.isPressed)
    }
}

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(DesignSystem.Colors.textPrimary.opacity(0.85))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(DesignSystem.Colors.surface.opacity(configuration.isPressed ? 0.8 : 0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(DesignSystem.Colors.border, lineWidth: 0.5)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(DesignSystem.Animation.buttonPress, value: configuration.isPressed)
    }
}
