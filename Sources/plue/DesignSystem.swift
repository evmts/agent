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
        
        // MARK: - Brand Colors (Refined, softer palette)
        static let primary = Color(red: 0.2, green: 0.6, blue: 1.0)        // Softer blue
        static let accent = Color(red: 0.345, green: 0.337, blue: 0.839)   // #5856D6 - Indigo
        static let success = Color(red: 0.3, green: 0.8, blue: 0.4)        // Softer green
        static let warning = Color(red: 1.0, green: 0.7, blue: 0.2)        // Softer orange
        static let error = Color(red: 1.0, green: 0.3, blue: 0.3)          // Softer red
        
        // MARK: - Theme-Aware Semantic Colors (Softer, more refined)
        static func background(for theme: Theme) -> Color {
            theme == .dark ? Color(white: 0.04) : Color(white: 0.98) // #0A0A0A instead of pure black
        }
        
        static func backgroundSecondary(for theme: Theme) -> Color {
            theme == .dark ? Color(white: 0.06) : Color.white // #0F0F0F
        }

        static func surface(for theme: Theme) -> Color {
            theme == .dark ? Color(white: 0.08) : Color(white: 0.94) // #141414
        }
        
        static func surfaceSecondary(for theme: Theme) -> Color {
            theme == .dark ? Color(white: 0.06) : Color(white: 0.92) // #0F0F0F
        }
        
        static func border(for theme: Theme) -> Color {
            theme == .dark ? Color.white.opacity(0.1) : Color(white: 0.85) // Much reduced opacity
        }
        
        static func borderSecondary(for theme: Theme) -> Color {
            theme == .dark ? Color.white.opacity(0.05) : Color(white: 0.9) // Very subtle
        }
        
        static func textPrimary(for theme: Theme) -> Color {
            theme == .dark ? Color(white: 0.9) : Color(white: 0.1)
        }
        
        static func textSecondary(for theme: Theme) -> Color {
            theme == .dark ? Color(white: 0.6) : Color(white: 0.4)
        }
        
        static func textTertiary(for theme: Theme) -> Color {
            theme == .dark ? Color(white: 0.4) : Color(white: 0.6)
        }
        
        // MARK: - Legacy compatibility (updated with new values for backward compatibility)
        static let background = Color(white: 0.04)          // Updated to softer black
        static let backgroundSecondary = Color(white: 0.06) // Updated 
        static let backgroundTertiary = Color(white: 0.04)  // Updated
        static let surface = Color(white: 0.08)             // Updated
        static let surfaceSecondary = Color(white: 0.06)    // Updated
        static let surfaceTertiary = Color(white: 0.08)     // Updated
        static let border = Color.white.opacity(0.1)        // Updated to reduced opacity
        static let borderSecondary = Color.white.opacity(0.05) // Updated
        static let borderFocus = Color(red: 0.2, green: 0.6, blue: 1.0) // Updated to softer blue
        static let textPrimary = Color(white: 0.9)
        static let textSecondary = Color(white: 0.6)
        static let textTertiary = Color(white: 0.4)
        static let textInverse = Color.black
        
        // MARK: - Interactive States
        static let interactive = textPrimary
        static let interactiveHover = textPrimary
        static let interactivePressed = textTertiary
        static let interactiveDisabled = textTertiary
        
        // MARK: - Gradients
        static let primaryGradient = LinearGradient(
            colors: [primary, accent],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        static let accentGradient = LinearGradient(
            colors: [accent, Color(red: 0.5, green: 0.5, blue: 1.0)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    // MARK: - Typography System
    
    /// Professional typography scale following Apple's design principles
    struct Typography {
        
        // MARK: - Display Fonts (Large Headers)
        static let displayLarge = Font.system(size: 57, weight: .bold, design: .default)
        static let displayMedium = Font.system(size: 45, weight: .bold, design: .default)
        static let displaySmall = Font.system(size: 36, weight: .bold, design: .default)
        
        // MARK: - Headline Fonts
        static let headlineLarge = Font.system(size: 32, weight: .semibold, design: .default)
        static let headlineMedium = Font.system(size: 28, weight: .semibold, design: .default)
        static let headlineSmall = Font.system(size: 24, weight: .semibold, design: .default)
        
        // MARK: - Title Fonts
        static let titleLarge = Font.system(size: 22, weight: .medium, design: .default)
        static let titleMedium = Font.system(size: 18, weight: .medium, design: .default)
        static let titleSmall = Font.system(size: 16, weight: .medium, design: .default)
        
        // MARK: - Body Fonts
        static let bodyLarge = Font.system(size: 16, weight: .regular, design: .default)
        static let bodyMedium = Font.system(size: 14, weight: .regular, design: .default)
        static let bodySmall = Font.system(size: 12, weight: .regular, design: .default)
        
        // MARK: - Label Fonts
        static let labelLarge = Font.system(size: 14, weight: .medium, design: .default)
        static let labelMedium = Font.system(size: 12, weight: .medium, design: .default)
        static let labelSmall = Font.system(size: 11, weight: .medium, design: .default)
        
        // MARK: - Monospace Fonts (Code/Terminal) - Ghostty-inspired terminal fonts
        static let monoLarge = Font.system(size: 15, weight: .regular, design: .monospaced)
        static let monoMedium = Font.system(size: 13, weight: .regular, design: .monospaced)
        static let monoSmall = Font.system(size: 11, weight: .regular, design: .monospaced)
        
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
        static let subtle = (color: Color.black.opacity(0.1), radius: 2.0, x: 0.0, y: 1.0)
        static let medium = (color: Color.black.opacity(0.15), radius: 8.0, x: 0.0, y: 4.0)
        static let large = (color: Color.black.opacity(0.2), radius: 16.0, x: 0.0, y: 8.0)
        static let focus = (color: Colors.primary.opacity(0.3), radius: 4.0, x: 0.0, y: 0.0)
    }
    
    // MARK: - Animation Curves
    
    struct Animation {
        // Core animations - optimized for responsiveness
        static let plueStandard = SwiftUI.Animation.easeOut(duration: 0.18)
        static let plueSmooth = SwiftUI.Animation.easeInOut(duration: 0.25)
        static let plueBounce = SwiftUI.Animation.spring(response: 0.3, dampingFraction: 0.8)
        static let plueInteractive = SwiftUI.Animation.interactiveSpring(response: 0.25, dampingFraction: 0.8)
        
        // Specialized animations for enhanced UX - optimized for responsiveness
        static let tabSwitch = SwiftUI.Animation.easeInOut(duration: 0.18)
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
}

// MARK: - Component Extensions

extension View {
    
    // MARK: - Surface Styling
    
    func primarySurface() -> some View {
        self
            .background(DesignSystem.Colors.surface)
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
            .background(DesignSystem.Colors.surfaceSecondary)
            .cornerRadius(DesignSystem.CornerRadius.sm)
    }
    
    func elevatedSurface() -> some View {
        self
            .background(DesignSystem.Colors.surfaceTertiary)
            .cornerRadius(DesignSystem.CornerRadius.lg)
            .shadow(
                color: DesignSystem.Shadow.medium.color,
                radius: DesignSystem.Shadow.medium.radius,
                x: DesignSystem.Shadow.medium.x,
                y: DesignSystem.Shadow.medium.y
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
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(DesignSystem.Colors.primary)
                    .opacity(configuration.isPressed ? 0.8 : 1.0)
                    .shadow(
                        color: DesignSystem.Colors.primary.opacity(configuration.isPressed ? 0.4 : 0.2),
                        radius: configuration.isPressed ? 2 : 4,
                        x: 0,
                        y: configuration.isPressed ? 1 : 2
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(DesignSystem.Animation.buttonPress, value: configuration.isPressed)
    }
}

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.white.opacity(configuration.isPressed ? 0.9 : 0.7))
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(configuration.isPressed ? 0.4 : 0.2), lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(configuration.isPressed ? 0.1 : 0))
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(DesignSystem.Animation.buttonPress, value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(DesignSystem.Colors.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(DesignSystem.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(DesignSystem.Colors.border, lineWidth: 1)
                    )
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
            .font(.system(size: size, weight: .medium))
            .foregroundColor(DesignSystem.Colors.textSecondary)
            .frame(width: size + DesignSystem.Spacing.md, height: size + DesignSystem.Spacing.md)
            .background(
                Circle()
                    .fill(DesignSystem.Colors.surface.opacity(configuration.isPressed ? 0.8 : 0.6))
            )
            .interactiveScale(pressed: configuration.isPressed)
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

#Preview("Design System Components") {
    VStack(spacing: DesignSystem.Spacing.xl) {
        // Typography samples
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("Design System")
                .font(DesignSystem.Typography.headlineLarge)
                .foregroundColor(DesignSystem.Colors.textPrimary)
            
            Text("Professional typography and spacing")
                .font(DesignSystem.Typography.bodyMedium)
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
        
        // Button samples
        HStack(spacing: DesignSystem.Spacing.md) {
            Button("Primary") {}
                .buttonStyle(PrimaryButtonStyle())
            
            Button("Secondary") {}
                .buttonStyle(SecondaryButtonStyle())
            
            Button(action: {}) {
                Image(systemName: "gear")
            }
            .buttonStyle(IconButtonStyle())
        }
        
        // Card sample
        ProfessionalCard {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                HStack {
                    Text("Professional Card")
                        .font(DesignSystem.Typography.titleMedium)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    
                    Spacer()
                    
                    StatusIndicator(status: .online, text: "Connected")
                }
                
                Text("This is a professional card component with proper spacing and styling.")
                    .font(DesignSystem.Typography.bodyMedium)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
        }
    }
    .padding(DesignSystem.Spacing.xxl)
    .background(DesignSystem.Colors.background)
    .frame(width: 500, height: 400)
}