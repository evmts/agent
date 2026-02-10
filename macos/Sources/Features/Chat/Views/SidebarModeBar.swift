import SwiftUI

enum SidebarMode: String, CaseIterable, Identifiable {
    case chats, source, agents
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .chats: return "bubble.left.and.bubble.right"
        case .source: return "arrow.triangle.branch"
        case .agents: return "person.3"
        }
    }
    var label: String {
        switch self {
        case .chats: return "Chats"
        case .source: return "Source"
        case .agents: return "Agents"
        }
    }
}

struct SidebarModeBar: View {
    @Binding var mode: SidebarMode
    @Environment(\.theme) private var theme
    @State private var hovered: SidebarMode? = nil

    var body: some View {
        HStack(spacing: DS.Space._8) {
            ForEach(SidebarMode.allCases) { m in
                Button {
                    mode = m
                } label: {
                    HStack(spacing: DS.Space._6) {
                        Image(systemName: m.icon)
                        Text(m.label)
                            .font(.system(size: DS.Typography.s, weight: .medium))
                    }
                    .padding(.horizontal, DS.Space._10)
                    .padding(.vertical, DS.Space._6)
                    .background(
                        Capsule()
                            .fill(Color(nsColor: DS.Color.chatPillBg))
                            .overlay(Capsule().stroke(Color(nsColor: DS.Color.chatPillBorder), lineWidth: 1))
                            .overlay(
                                Capsule().fill(Color(nsColor: DS.Color.chatPillActive))
                                    .opacity(m == mode ? 1.0 : 0.0)
                            )
                            .overlay(
                                Capsule().fill(Color(nsColor: DS.Color.chatSidebarHover))
                                    .opacity(m != mode && hovered == m ? 1.0 : 0.0)
                            )
                    )
                    .foregroundStyle(m == mode ? Color(nsColor: theme.accent) : theme.foregroundColor.opacity(0.6))
                }
                .buttonStyle(.plain)
                .onHover { inside in hovered = inside ? m : (hovered == m ? nil : hovered) }
                .accessibilityIdentifier("modebar_\(m.rawValue)")
            }
            Spacer(minLength: 0)
        }
        .frame(height: 40)
        .padding(.horizontal, DS.Space._8)
        .background(Color(nsColor: DS.Color.chatSidebarBg))
    }
}
