import SwiftUI

struct ChatWindowRootView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.theme) private var theme
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationSplitView {
            ChatSidebarView()
        } detail: {
            VStack(spacing: 0) {
                ChatTitleBarZone(onOpenEditor: {
                    appModel.windowCoordinator.showWorkspacePanel(openWindow)
                })
                DividerLine()
                MessagesZone()
                DividerLine()
                ChatComposerZone(onSend: { text in
                    appModel.sendChatMessage(text)
                })
            }
            .background(theme.backgroundColor)
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 360)
    }
}

private struct MessagesZone: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.theme) private var theme
    var body: some View {
        ScrollView {
            LazyVStack(spacing: DS.Space._10) {
                ForEach(appModel.chat.messages) { m in
                    HStack {
                        switch m.role {
                        case .user:
                            Spacer(minLength: 0)
                            UserBubble(text: m.text)
                        case .assistant:
                            AssistantBubble(text: m.text)
                            Spacer(minLength: 0)
                        }
                    }
                }
                if appModel.chat.isStreaming && !appModel.chat.messages.contains(where: { $0.role == .assistant }) {
                    HStack {
                        AssistantBubble(text: "Thinking…")
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.horizontal, DS.Space._16)
            .padding(.top, DS.Space._16)
            .padding(.bottom, DS.Space._12)
        }
        .accessibilityIdentifier("messages_scroll")
    }
}

private struct UserBubble: View {
    let text: String
    @Environment(\.theme) private var theme
    var body: some View {
        Text(text)
            .font(.system(size: DS.Typography.base))
            .foregroundStyle(theme.foregroundColor)
            .padding(DS.Space._12)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: DS.Radius._12,
                    bottomLeadingRadius: DS.Radius._12,
                    bottomTrailingRadius: DS.Radius._4,
                    topTrailingRadius: DS.Radius._12
                ).fill(Color(nsColor: theme.chatUserBubble))
            )
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityIdentifier("bubble_user")
    }
}

private struct AssistantBubble: View {
    let text: String
    @Environment(\.theme) private var theme
    var body: some View {
        Text(text)
            .font(.system(size: DS.Typography.base))
            .foregroundStyle(theme.foregroundColor)
            .padding(DS.Space._12)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: DS.Radius._12,
                    bottomLeadingRadius: DS.Radius._4,
                    bottomTrailingRadius: DS.Radius._12,
                    topTrailingRadius: DS.Radius._12
                ).fill(Color(nsColor: theme.chatAssistantBubble))
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("bubble_assistant")
    }
}
