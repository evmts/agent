import SwiftUI
import AppKit

// IconButton per spec §3.1
struct IconButton: View {
    enum Size { case small, medium, large }
    let systemName: String
    let size: Size
    let help: String?
    let action: () -> Void
    @Environment(\.theme) private var theme
    @State private var hovering = false
    @State private var pressing = false

    private var dim: CGFloat {
        switch size { case .small: return 24; case .medium: return 28; case .large: return 32 }
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .regular))
                .frame(width: dim, height: dim)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    Color(nsColor: hovering ? (pressing ? NSColor.white.withAlphaComponent(0.10) : NSColor.white.withAlphaComponent(0.06)) : .clear)
                )
        )
        .foregroundStyle(Color(nsColor: theme.foreground))
        .onHover { hovering = $0 }
        .pressAction { pressing = $0 }
        .help(help ?? "")
    }
}

// PrimaryButton per spec §3.2
struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: DS.Typography.base, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.92))
                .frame(height: 32)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: theme.accent).opacity(0.90))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(hovering ? 0.06 : 0))
                        )
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// PillButton per spec §3.3
struct PillButton: View {
    let title: String
    var systemName: String? = nil
    let action: () -> Void
    @Environment(\.theme) private var theme
    @State private var hovering = false
    @State private var pressing = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let name = systemName { Image(systemName: name) }
                Text(title).font(.system(size: DS.Typography.s, weight: .medium))
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .background(
                Capsule()
                    .strokeBorder(Color(nsColor: DS.Color.chatPillBorder), lineWidth: 1)
                    .background(
                        Capsule().fill(Color(nsColor: DS.Color.chatPillBg))
                    )
                    .overlay(
                        Capsule().fill(Color(nsColor: DS.Color.chatPillActive).opacity(hovering || pressing ? 1.0 : 0.0))
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .pressAction { pressing = $0 }
    }
}

// SidebarListRow per spec §3.5
struct SidebarListRow: View {
    let title: String
    var subtitle: String? = nil
    var isSelected: Bool = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: DS.Typography.chatSidebarTitle, weight: .semibold))
                    if let s = subtitle { Text(s).font(.system(size: 10)).foregroundStyle(Color(nsColor: DS.Color.textTertiary)) }
                }
                Spacer(minLength: 0)
            }
            .frame(height: 44)
            .padding(.horizontal, 12)
            .background(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: DS.Color.accent.withAlphaComponent(0.12)))
                    } else if hovering {
                        RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.04))
                    }
                }
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// Small helper to detect press state for hover/active visuals
private struct PressAction: ViewModifier {
    let onChange: (Bool) -> Void
    func body(content: Content) -> some View {
        content
            .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in onChange(true) }.onEnded { _ in onChange(false) })
    }
}

private extension View {
    func pressAction(_ onChange: @escaping (Bool) -> Void) -> some View {
        modifier(PressAction(onChange: onChange))
    }
}

