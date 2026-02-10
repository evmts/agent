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
    @GestureState private var pressing = false

    private var dim: CGFloat {
        switch size { case .small: return 24; case .medium: return 28; case .large: return 32 }
    }
    private var iconPointSize: CGFloat {
        switch size { case .small: return 14; case .medium, .large: return 16 }
    }

    var body: some View {
        let base = Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: iconPointSize, weight: .regular))
                .frame(width: dim, height: dim)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color(nsColor: theme.foreground))
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    Color(nsColor: hovering ? (pressing ? DS.Color.overlayWhite10 : DS.Color.overlayWhite06) : .clear)
                )
        )
        .onHover { hovering = $0 }
        .gesture(
            LongPressGesture(minimumDuration: 0)
                .updating($pressing) { current, state, _ in state = current }
        )
        .accessibilityLabel(Text(help ?? systemName.replacingOccurrences(of: ".", with: " ")))
        .accessibilityIdentifier("iconbutton_\(systemName)")

        if let help = help { base.help(help) } else { base }
    }
}

// PrimaryButton per spec §3.2
struct PrimaryButton: View {
    let title: String
    var isDisabled: Bool = false
    let action: () -> Void
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: DS.Type.base, weight: .semibold))
                .foregroundStyle(Color(nsColor: DS.Color.onAccentText))
                .frame(height: 32)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: theme.accent).opacity(0.90))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(nsColor: DS.Color.overlayWhite06).opacity(hovering ? 1.0 : 0))
                        )
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .opacity(isDisabled ? 0.45 : 1.0)
        .disabled(isDisabled)
        .accessibilityLabel(Text(title))
        .accessibilityIdentifier("primarybutton_\(title.replacingOccurrences(of: " ", with: "_"))")
    }
}

// PillButton per spec §3.3
struct PillButton: View {
    let title: String
    var systemName: String? = nil
    let action: () -> Void
    @Environment(\.theme) private var theme
    @State private var hovering = false
    @GestureState private var pressing = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let name = systemName { Image(systemName: name) }
                Text(title)
                    .font(.system(size: DS.Type.s, weight: .medium))
                    .foregroundStyle(Color(nsColor: theme.foreground))
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
                        Capsule().fill(Color(nsColor: DS.Color.chatPillActive).opacity((hovering || pressing) ? 1.0 : 0.0))
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .gesture(
            LongPressGesture(minimumDuration: 0).updating($pressing) { current, state, _ in state = current }
        )
        .accessibilityLabel(Text(title))
        .accessibilityIdentifier("pillbutton_\(title.replacingOccurrences(of: " ", with: "_"))")
    }
}

// SidebarListRow per spec §3.5
struct SidebarListRow: View {
    let title: String
    var subtitle: String? = nil
    var isSelected: Bool = false
    let action: () -> Void
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: DS.Type.chatSidebarTitle, weight: .semibold))
                    if let s = subtitle {
                        Text(s)
                            .font(.system(size: 10))
                            .foregroundStyle(Color(nsColor: DS.Color.textTertiary))
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(height: 44)
            .padding(.horizontal, 12)
            .background(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: DS.Color.chatSidebarSelected))
                    } else if hovering {
                        RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: DS.Color.chatSidebarHover))
                    }
                }
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(Text(title))
        .accessibilityIdentifier("sidebarrow_\(title.replacingOccurrences(of: " ", with: "_"))")
    }
}

// (Removed dead PressAction modifier; LongPressGesture with @GestureState handles press state.)
