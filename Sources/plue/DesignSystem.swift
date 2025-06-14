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
        
        // MARK: - Brand Colors (Used for accents, status, etc.)
        static let primary = Color(red: 0.0, green: 0.478, blue: 1.0)      // #007AFF - iOS Blue
        static let accent = Color(red: 0.345, green: 0.337, blue: 0.839)   // #5856D6 - Indigo
        static let success = Color(red: 0.203, green: 0.780, blue: 0.349)  // #34C759 - Green
        static let warning = Color(red: 1.0, green: 0.584, blue: 0.0)      // #FF9500 - Orange
        static let error = Color(red: 1.0, green: 0.231, blue: 0.188)      // #FF3B30 - Red
        
        // MARK: - Core UI Palette (Ghostty-inspired minimalism)
        // We will enforce these across the entire UI for consistency.
        static let background = Color.black                                      // Pure black for window background
        static let backgroundSecondary = Color(white: 0.05)                      // Slightly off-black for content areas
        static let surface = Color(white: 0.12)                                  // Dark gray for elevated surfaces, inputs
        static let border = Color(white: 0.2)                                    // Subtle borders
        static let borderFocus = Color(red: 0.0, green: 0.478, blue: 1.0)        // Use brand blue for focus rings
        
        static let textPrimary = Color(white: 0.9)                               // Near-white for primary text
        static let textSecondary = Color(white: 0.6)                             // Gray for secondary text
        static let textTertiary = Color(white: 0.4)                              // Darker gray for tertiary/disabled text
        static let textInverse = Color.black                                     // For text on light backgrounds
        
        // MARK: - Legacy compatibility (keeping old names for backward compatibility)
        static let backgroundTertiary = background
        static let surfaceSecondary = surface
        static let surfaceTertiary = surface
        static let borderSecondary = border
        
        // MARK: - Theme-Adaptive Functions (for compatibility with theme system)
        static func background(for theme: Theme) -> Color {
            switch theme {
            case .dark: return background
            case .light: return Color.white
            }
        }
        
        static func surface(for theme: Theme) -> Color {
            switch theme {
            case .dark: return surface
            case .light: return Color(red: 0.95, green: 0.95, blue: 0.95)
            }
        }
        
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
        static let quick = SwiftUI.Animation.easeOut(duration: 0.2)
        static let smooth = SwiftUI.Animation.easeInOut(duration: 0.3)
        static let gentle = SwiftUI.Animation.easeInOut(duration: 0.5)
        static let bouncy = SwiftUI.Animation.spring(response: 0.6, dampingFraction: 0.8)
        static let interactive = SwiftUI.Animation.interactiveSpring(response: 0.3, dampingFraction: 0.8)
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
    @State private var isPressed = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignSystem.Typography.labelMedium)
            .foregroundColor(.white)
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.vertical, DesignSystem.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                    .fill(DesignSystem.Colors.primaryGradient)
            )
            .interactiveScale(pressed: configuration.isPressed)
            .shadow(
                color: DesignSystem.Shadow.medium.color,
                radius: DesignSystem.Shadow.medium.radius,
                x: DesignSystem.Shadow.medium.x,
                y: DesignSystem.Shadow.medium.y
            )
            .hoverEffect()
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignSystem.Typography.labelMedium)
            .foregroundColor(DesignSystem.Colors.textPrimary)
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.vertical, DesignSystem.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                    .fill(DesignSystem.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                            .stroke(DesignSystem.Colors.border, lineWidth: 1)
                    )
            )
            .interactiveScale(pressed: configuration.isPressed)
            .hoverEffect()
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