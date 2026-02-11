import SwiftUI

struct ChatTitleBarZone: View {
    let onOpenEditor: () -> Void
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var appModel

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            Text(appModel.workspaceName)
                .font(.system(size: DS.Typography.s, weight: .medium))
                .foregroundStyle(Color(nsColor: theme.mutedForeground))
            Spacer(minLength: 0)
            IconButton(systemName: "rectangle.split.2x1", size: .small, help: "Open Editor", action: onOpenEditor)
                .accessibilityIdentifier("open_editor")
        }
        .frame(height: 28)
        .padding(.horizontal, DS.Space._8)
        .background(Color(nsColor: theme.panelBackground))
    }
}
