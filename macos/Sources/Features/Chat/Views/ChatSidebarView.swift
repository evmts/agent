import SwiftUI

struct ChatSidebarView: View {
    @State private var sidebarMode: SidebarMode = .chats
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            
            SidebarModeBar(mode: $sidebarMode)
            DividerLine()
            Group {
                switch sidebarMode {
                case .chats:
                    VStack(spacing: 0) {
                        SidebarListRow(title: "Today: Refactor editor", subtitle: "2:14 PM", isSelected: true) {}
                        SidebarListRow(title: "Yesterday: Fix tests", subtitle: "8:03 PM") {}
                        SidebarListRow(title: "Last Week: Add JJ panel", subtitle: "Thu 11:02") {}
                        Spacer()
                    }
                    .padding(.top, DS.Space._8)
                case .source:
                    VStack(alignment: .leading) {
                        Text("Source (JJ)").font(.system(size: DS.Typography.s, weight: .medium))
                            .foregroundStyle(Color(nsColor: theme.mutedForeground))
                        Spacer()
                    }
                    .padding(DS.Space._12)
                    .accessibilityIdentifier("sidebar_content_source")
                case .agents:
                    VStack(alignment: .leading) {
                        Text("Agents").font(.system(size: DS.Typography.s, weight: .medium))
                            .foregroundStyle(Color(nsColor: theme.mutedForeground))
                        Spacer()
                    }
                    .padding(DS.Space._12)
                    .accessibilityIdentifier("sidebar_content_agents")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(nsColor: DS.Color.chatSidebarBg))
        }
    }
}
