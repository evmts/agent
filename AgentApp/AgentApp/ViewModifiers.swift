import SwiftUI

// MARK: - Native macOS Card Modifier

struct NativeMacOSCard: ViewModifier {
    let theme: DesignSystem.Theme
    
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(DesignSystem.Materials.regular)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(DesignSystem.Colors.surface(for: theme).opacity(0.5))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(DesignSystem.Colors.border(for: theme), lineWidth: 0.5)
                    )
            )
            .shadow(
                color: DesignSystem.Shadow.subtle.color,
                radius: DesignSystem.Shadow.subtle.radius,
                x: DesignSystem.Shadow.subtle.x,
                y: DesignSystem.Shadow.subtle.y
            )
    }
}

// MARK: - Toolbar Style Modifier

struct ToolbarStyle: ViewModifier {
    let theme: DesignSystem.Theme
    
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                    DesignSystem.Colors.surface(for: theme).opacity(0.3)
                }
                .overlay(
                    Divider()
                        .background(DesignSystem.Colors.border(for: theme)),
                    alignment: .bottom
                )
            )
    }
}

// MARK: - Hover Highlight Modifier

struct HoverHighlight: ViewModifier {
    let theme: DesignSystem.Theme
    @State private var isHovered = false
    
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? 
                        DesignSystem.Colors.primary.opacity(0.1) : 
                        Color.clear
                    )
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
    }
}

// MARK: - Press Effect Modifier

struct PressEffect: ViewModifier {
    let isPressed: Bool
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .opacity(isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
    }
}

// MARK: - Focus Ring Modifier

struct FocusRing: ViewModifier {
    let isFocused: Bool
    let theme: DesignSystem.Theme
    let cornerRadius: CGFloat
    
    init(isFocused: Bool, theme: DesignSystem.Theme, cornerRadius: CGFloat = 6) {
        self.isFocused = isFocused
        self.theme = theme
        self.cornerRadius = cornerRadius
    }
    
    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        isFocused ? DesignSystem.Colors.primary : DesignSystem.Colors.border(for: theme),
                        lineWidth: isFocused ? 2 : 0.5
                    )
            )
            .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

// MARK: - Sidebar Item Modifier

struct SidebarItem: ViewModifier {
    let isSelected: Bool
    let theme: DesignSystem.Theme
    
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isSelected ? 
                        DesignSystem.Colors.primary.opacity(0.1) : 
                        Color.clear
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(
                        isSelected ? DesignSystem.Colors.primary.opacity(0.2) : Color.clear,
                        lineWidth: 0.5
                    )
            )
            .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - View Extensions

extension View {
    func nativeMacOSCard(theme: DesignSystem.Theme) -> some View {
        modifier(NativeMacOSCard(theme: theme))
    }
    
    func toolbarStyle(theme: DesignSystem.Theme) -> some View {
        modifier(ToolbarStyle(theme: theme))
    }
    
    func hoverHighlight(theme: DesignSystem.Theme) -> some View {
        modifier(HoverHighlight(theme: theme))
    }
    
    func pressEffect(isPressed: Bool) -> some View {
        modifier(PressEffect(isPressed: isPressed))
    }
    
    func focusRing(isFocused: Bool, theme: DesignSystem.Theme, cornerRadius: CGFloat = 6) -> some View {
        modifier(FocusRing(isFocused: isFocused, theme: theme, cornerRadius: cornerRadius))
    }
    
    func sidebarItem(isSelected: Bool, theme: DesignSystem.Theme) -> some View {
        modifier(SidebarItem(isSelected: isSelected, theme: theme))
    }
}

// MARK: - Animation Modifiers

struct AnimateOnAppearModifier: ViewModifier {
    let delay: Double
    @State private var isVisible = false
    
    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .onAppear {
                withAnimation(DesignSystem.Animation.plueStandard.delay(delay)) {
                    isVisible = true
                }
            }
    }
}

// MARK: - Animation Extensions

extension View {
    func animateOnAppear(delay: Double = 0) -> some View {
        modifier(AnimateOnAppearModifier(delay: delay))
    }
    
    func shimmer(isActive: Bool = true) -> some View {
        self.overlay(
            GeometryReader { geometry in
                if isActive {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0),
                                    Color.white.opacity(0.1),
                                    Color.white.opacity(0)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .offset(x: -geometry.size.width)
                        .animation(
                            Animation.linear(duration: 1.5)
                                .repeatForever(autoreverses: false),
                            value: isActive
                        )
                }
            }
        )
    }
}

// MARK: - Conditional Modifiers

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
    
    @ViewBuilder
    func ifLet<Value, Content: View>(_ value: Value?, transform: (Self, Value) -> Content) -> some View {
        if let value = value {
            transform(self, value)
        } else {
            self
        }
    }
}

// MARK: - macOS Specific Extensions

extension View {
    func macOSWindowStyle() -> some View {
        self
            .frame(minWidth: 800, minHeight: 600)
            .background(VisualEffectBlur())
    }
    
    func cursorOnHover(_ cursor: NSCursor = .pointingHand) -> some View {
        self.onHover { isHovered in
            if isHovered {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// MARK: - Visual Effect Blur

struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = .sidebar
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}