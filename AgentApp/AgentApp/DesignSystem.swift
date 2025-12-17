import SwiftUI
import AppKit

// MARK: - Professional Design System for Plue

/// A comprehensive design system that defines the visual language of Plue
/// Follows Apple's Human Interface Guidelines while establishing a unique, professional identity
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
    
    /// Primary color palette with semantic naming
    struct Colors {
        
        // MARK: - Brand Colors (Native macOS-inspired palette)
        static let primary = Color(red: 0.0, green: 0.478, blue: 1.0)      // macOS blue
        static let accent = Color(red: 0.345, green: 0.337, blue: 0.839)   // #5856D6 - Indigo
        static let success = Color(red: 0.204, green: 0.780, blue: 0.349)  // macOS green
        static let warning = Color(red: 1.0, green: 0.800, blue: 0.0)      // macOS yellow
        static let error = Color(red: 1.0, green: 0.231, blue: 0.188)      // macOS red
        
        // MARK: - Theme-Aware Semantic Colors (Native macOS palette)
        static func background(for theme: Theme) -> Color {
            theme == .dark ? Color(NSColor.windowBackgroundColor) : Color(NSColor.windowBackgroundColor)
        }
        
        static func backgroundSecondary(for theme: Theme) -> Color {
            theme == .dark ? Color(NSColor.controlBackgroundColor) : Color(NSColor.controlBackgroundColor)
        }

        static func surface(for theme: Theme) -> Color {
            theme == .dark ? Color(NSColor.underPageBackgroundColor) : Color(NSColor.underPageBackgroundColor)
        }
        
        static func surfaceSecondary(for theme: Theme) -> Color {
            theme == .dark ? Color(NSColor.unemphasizedSelectedContentBackgroundColor) : Color(NSColor.unemphasizedSelectedContentBackgroundColor)
        }
        
        static func border(for theme: Theme) -> Color {
            Color(NSColor.separatorColor)
        }
        
        static func borderSecondary(for theme: Theme) -> Color {
            Color(NSColor.separatorColor).opacity(0.5)
        }
        
        static func textPrimary(for theme: Theme) -> Color {
            Color(NSColor.labelColor)
        }
        
        static func textSecondary(for theme: Theme) -> Color {
            Color(NSColor.secondaryLabelColor)
        }
        
        static func textTertiary(for theme: Theme) -> Color {
            Color(NSColor.tertiaryLabelColor)
        }
        
        // MARK: - Legacy compatibility (using native macOS colors)
        static let background = Color(NSColor.windowBackgroundColor)
        static let backgroundSecondary = Color(NSColor.controlBackgroundColor)
        static let backgroundTertiary = Color(NSColor.underPageBackgroundColor)
        static let surface = Color(NSColor.controlBackgroundColor)
        static let surfaceSecondary = Color(NSColor.unemphasizedSelectedContentBackgroundColor)
        static let surfaceTertiary = Color(NSColor.controlBackgroundColor)
        static let border = Color(NSColor.separatorColor)
        static let borderSecondary = Color(NSColor.separatorColor).opacity(0.5)
        static let borderFocus = Color(red: 0.0, green: 0.478, blue: 1.0) // macOS blue
        static let textPrimary = Color(NSColor.labelColor)
        static let textSecondary = Color(NSColor.secondaryLabelColor)
        static let textTertiary = Color(NSColor.tertiaryLabelColor)
        static let textInverse = Color(NSColor.selectedTextBackgroundColor)
        
        // MARK: - Interactive States
        static let interactive = textPrimary
        static let interactiveHover = textPrimary
        static let interactivePressed = textTertiary
        static let interactiveDisabled = textTertiary
        
        // MARK: - Gradients
        static let primaryGradient = LinearGradient(
            colors: [primary, primary.opacity(0.8)],
            startPoint: .top,
            endPoint: .bottom
        )
        
        static let accentGradient = LinearGradient(
            colors: [accent, accent.opacity(0.8)],
            startPoint: .top,
            endPoint: .bottom
        )
        
        // Native macOS-style subtle gradient for surfaces
        static func surfaceGradient(for theme: Theme) -> LinearGradient {
            LinearGradient(
                colors: [
                    surface(for: theme),
                    surface(for: theme).opacity(0.95)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
    
    // MARK: - Typography System
    
    /// Professional typography scale following Apple's design principles
    struct Typography {
        
        // MARK: - Display Fonts (Large Headers)
        static let displayLarge = Font.system(size: 57, weight: .bold, design: .rounded)
        static let displayMedium = Font.system(size: 45, weight: .bold, design: .rounded)
        static let displaySmall = Font.system(size: 36, weight: .bold, design: .rounded)
        
        // MARK: - Headline Fonts
        static let headlineLarge = Font.system(size: 28, weight: .semibold, design: .default)
        static let headlineMedium = Font.system(size: 22, weight: .semibold, design: .default)
        static let headlineSmall = Font.system(size: 18, weight: .semibold, design: .default)
        
        // MARK: - Title Fonts
        static let titleLarge = Font.system(size: 17, weight: .medium, design: .default)
        static let titleMedium = Font.system(size: 15, weight: .medium, design: .default)
        static let titleSmall = Font.system(size: 13, weight: .medium, design: .default)
        
        // MARK: - Body Fonts
        static let bodyLarge = Font.system(size: 15, weight: .regular, design: .default)
        static let bodyMedium = Font.system(size: 13, weight: .regular, design: .default)
        static let bodySmall = Font.system(size: 11, weight: .regular, design: .default)
        
        // MARK: - Label Fonts
        static let labelLarge = Font.system(size: 13, weight: .medium, design: .default)
        static let labelMedium = Font.system(size: 11, weight: .medium, design: .default)
        static let labelSmall = Font.system(size: 10, weight: .medium, design: .default)
        
        // MARK: - Monospace Fonts (Code/Terminal)
        static let monoLarge = Font.custom("SF Mono", size: 14).weight(.regular)
        static let monoMedium = Font.custom("SF Mono", size: 12).weight(.regular)
        static let monoSmall = Font.custom("SF Mono", size: 10).weight(.regular)
        
        // Fallback to system monospace if SF Mono not available
        static let monoLargeFallback = Font.system(size: 14, weight: .regular, design: .monospaced)
        static let monoMediumFallback = Font.system(size: 12, weight: .regular, design: .monospaced)
        static let monoSmallFallback = Font.system(size: 10, weight: .regular, design: .monospaced)
        
        // MARK: - Caption Fonts
        static let caption = Font.system(size: 10, weight: .regular, design: .default)
        static let captionMedium = Font.system(size: 10, weight: .medium, design: .default)
    }
    
    // MARK: - Spacing System
    
    /// Consistent spacing scale using 4px base unit
    struct Spacing {
        static let xs: CGFloat = 4      // Extra small
        static let sm: CGFloat = 8      // Small
        static let md: CGFloat = 12     // Medium
        static let lg: CGFloat = 16     // Large
        static let xl: CGFloat = 20     // Extra large
        static let xxl: CGFloat = 24    // 2x Extra large
        static let xxxl: CGFloat = 32   // 3x Extra large
        static let huge: CGFloat = 48   // Huge spacing
        static let massive: CGFloat = 64 // Massive spacing
    }
    
    // MARK: - Corner Radius
    
    struct CornerRadius {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
        static let xl: CGFloat = 16
        static let xxl: CGFloat = 20
        static let xxxl: CGFloat = 24
        static let circular: CGFloat = 50
    }
    
    // MARK: - Shadows
    
    struct Shadow {
        static let subtle = (color: Color(NSColor.shadowColor).opacity(0.15), radius: 2.0, x: 0.0, y: 1.0)
        static let medium = (color: Color(NSColor.shadowColor).opacity(0.2), radius: 5.0, x: 0.0, y: 2.0)
        static let large = (color: Color(NSColor.shadowColor).opacity(0.25), radius: 10.0, x: 0.0, y: 5.0)
        static let focus = (color: Colors.primary.opacity(0.4), radius: 3.0, x: 0.0, y: 0.0)
        
        // Native macOS window shadow
        static let window = (color: Color.black.opacity(0.3), radius: 20.0, x: 0.0, y: 10.0)
    }
    
    // MARK: - Animation Curves
    
    struct Animation {
        // Core animations - optimized for responsiveness
        static let plueStandard = SwiftUI.Animation.easeOut(duration: 0.18)
        static let plueSmooth = SwiftUI.Animation.easeInOut(duration: 0.25)
        static let plueBounce = SwiftUI.Animation.spring(response: 0.3, dampingFraction: 0.8)
        static let plueInteractive = SwiftUI.Animation.interactiveSpring(response: 0.25, dampingFraction: 0.8)
        
        // Specialized animations for enhanced UX - optimized for responsiveness
        static let tabSwitch = SwiftUI.Animation.easeInOut(duration: 0.12)
        static let messageAppear = SwiftUI.Animation.spring(response: 0.3, dampingFraction: 0.75)
        static let buttonPress = SwiftUI.Animation.easeOut(duration: 0.12)
        static let socialInteraction = SwiftUI.Animation.spring(response: 0.25, dampingFraction: 0.7)
        static let heartBeat = SwiftUI.Animation.spring(response: 0.15, dampingFraction: 0.6)
        static let slideTransition = SwiftUI.Animation.easeInOut(duration: 0.22)
        static let scaleIn = SwiftUI.Animation.spring(response: 0.3, dampingFraction: 0.8)
        static let staggerDelay = 0.03 // For staggered animations - faster
        
        // Legacy names for compatibility - updated for speed
        static let quick = plueStandard
        static let smooth = plueSmooth
        static let gentle = SwiftUI.Animation.easeInOut(duration: 0.25) // Much faster
        static let bouncy = plueBounce
        static let interactive = plueInteractive
    }
    
    // MARK: - Icon Sizes
    
    struct IconSize {
        static let small: CGFloat = 12
        static let medium: CGFloat = 16
        static let large: CGFloat = 20
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }
    
    // MARK: - Visual Effects
    
    struct Materials {
        static let thin = Material.thin
        static let regular = Material.regular
        static let thick = Material.thick
        static let chrome = Material.ultraThin
        // Use regular material for these macOS-specific materials
        static let sidebar = Material.regular
        static let titleBar = Material.ultraThin
        static let hudWindow = Material.ultraThick
        static let popover = Material.regular
        static let menu = Material.thin
        static let sheet = Material.thick
        
        static func adaptive(for theme: Theme) -> Material {
            theme == .dark ? .ultraThick : .regular
        }
    }
    
    // MARK: - macOS Native Effects
    
    struct Effects {
        static let vibrancy = NSVisualEffectView.Material.sidebar
        static let hudVibrancy = NSVisualEffectView.Material.hudWindow
        static let contentBackground = NSVisualEffectView.Material.contentBackground
        static let behindWindow = NSVisualEffectView.Material.sidebar // behindWindow is not available
    }
}

// MARK: - Component Extensions

extension View {
    
    // MARK: - Surface Styling
    
    func primarySurface() -> some View {
        self
            .background(DesignSystem.Materials.regular)
            .background(DesignSystem.Colors.surface.opacity(0.5))
            .cornerRadius(DesignSystem.CornerRadius.md)
            .shadow(
                color: DesignSystem.Shadow.subtle.color,
                radius: DesignSystem.Shadow.subtle.radius,
                x: DesignSystem.Shadow.subtle.x,
                y: DesignSystem.Shadow.subtle.y
            )
    }
    
    func secondarySurface() -> some View {
        self
            .background(DesignSystem.Materials.thin)
            .background(DesignSystem.Colors.surfaceSecondary.opacity(0.3))
            .cornerRadius(DesignSystem.CornerRadius.sm)
    }
    
    func elevatedSurface() -> some View {
        self
            .background(DesignSystem.Materials.thick)
            .background(DesignSystem.Colors.surfaceTertiary.opacity(0.5))
            .cornerRadius(DesignSystem.CornerRadius.lg)
            .shadow(
                color: DesignSystem.Shadow.medium.color,
                radius: DesignSystem.Shadow.medium.radius,
                x: DesignSystem.Shadow.medium.x,
                y: DesignSystem.Shadow.medium.y
            )
    }
    
    // MARK: - Native macOS Effects
    
    func glassEffect() -> some View {
        self
            .background(DesignSystem.Materials.chrome)
            .cornerRadius(DesignSystem.CornerRadius.md)
    }
    
    func sidebarStyle() -> some View {
        self
            .background(DesignSystem.Materials.sidebar)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }
    
    func hudStyle() -> some View {
        self
            .background(DesignSystem.Materials.hudWindow)
            .cornerRadius(DesignSystem.CornerRadius.lg)
            .shadow(
                color: DesignSystem.Shadow.large.color,
                radius: DesignSystem.Shadow.large.radius,
                x: DesignSystem.Shadow.large.x,
                y: DesignSystem.Shadow.large.y
            )
    }
    
    // MARK: - Border Styling
    
    func primaryBorder() -> some View {
        self
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                    .stroke(DesignSystem.Colors.border, lineWidth: 1)
            )
    }
    
    func focusBorder(_ isFocused: Bool) -> some View {
        self
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                    .stroke(
                        isFocused ? DesignSystem.Colors.borderFocus : DesignSystem.Colors.border,
                        lineWidth: isFocused ? 2 : 1
                    )
                    .animation(DesignSystem.Animation.quick, value: isFocused)
            )
    }
    
    // MARK: - Interactive States
    
    func interactiveScale(pressed: Bool) -> some View {
        self
            .scaleEffect(pressed ? 0.96 : 1.0)
            .animation(DesignSystem.Animation.interactive, value: pressed)
    }
    
    func hoverEffect() -> some View {
        self
            .onHover { isHovered in
                if isHovered {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
    
    // MARK: - Content Transitions
    
    func contentTransition() -> some View {
        self
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .move(edge: .trailing)),
                removal: .opacity.combined(with: .move(edge: .leading))
            ))
    }
}

// MARK: - Professional Button Styles

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(
                ZStack {
                    // Base layer
                    RoundedRectangle(cornerRadius: 5)
                        .fill(DesignSystem.Colors.primary)
                    
                    // Gradient overlay for depth
                    RoundedRectangle(cornerRadius: 5)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(configuration.isPressed ? 0 : 0.1),
                                    Color.black.opacity(configuration.isPressed ? 0.1 : 0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Color.black.opacity(0.2), lineWidth: 0.5)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(DesignSystem.Animation.buttonPress, value: configuration.isPressed)
    }
}

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(DesignSystem.Colors.textPrimary.opacity(configuration.isPressed ? 0.9 : 0.85))
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(configuration.isPressed ? 0.8 : 0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(DesignSystem.Colors.border, lineWidth: 0.5)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(DesignSystem.Animation.buttonPress, value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .regular))
            .foregroundColor(DesignSystem.Colors.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(
                ZStack {
                    // Material background
                    RoundedRectangle(cornerRadius: 5)
                        .fill(DesignSystem.Materials.regular)
                    
                    // Color overlay
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(NSColor.controlBackgroundColor).opacity(0.3))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(DesignSystem.Colors.border, lineWidth: 0.5)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(DesignSystem.Animation.plueStandard, value: configuration.isPressed)
    }
}

struct IconButtonStyle: ButtonStyle {
    let size: CGFloat
    
    init(size: CGFloat = DesignSystem.IconSize.medium) {
        self.size = size
    }
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.8, weight: .regular))
            .foregroundColor(DesignSystem.Colors.textSecondary)
            .frame(width: size + DesignSystem.Spacing.sm, height: size + DesignSystem.Spacing.sm)
            .background(
                Circle()
                    .fill(Color(NSColor.controlBackgroundColor).opacity(configuration.isPressed ? 0.8 : 0.5))
            )
            .overlay(
                Circle()
                    .strokeBorder(DesignSystem.Colors.border.opacity(0.3), lineWidth: 0.5)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(DesignSystem.Animation.buttonPress, value: configuration.isPressed)
            .hoverEffect()
    }
}

// MARK: - Professional Card Component

struct ProfessionalCard<Content: View>: View {
    let content: Content
    let padding: CGFloat
    
    init(padding: CGFloat = DesignSystem.Spacing.lg, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.padding = padding
    }
    
    var body: some View {
        content
            .padding(padding)
            .elevatedSurface()
    }
}

// MARK: - Status Indicator Component

struct StatusIndicator: View {
    let status: StatusType
    let text: String
    
    enum StatusType {
        case online, offline, warning, error
        
        var color: Color {
            switch self {
            case .online: return DesignSystem.Colors.success
            case .offline: return DesignSystem.Colors.textTertiary
            case .warning: return DesignSystem.Colors.warning
            case .error: return DesignSystem.Colors.error
            }
        }
    }
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            Circle()
                .fill(status.color)
                .frame(width: 8, height: 8)
            
            Text(text)
                .font(DesignSystem.Typography.labelSmall)
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
    }
}

// Preview removed to fix build error