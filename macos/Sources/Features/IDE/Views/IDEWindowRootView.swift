import SwiftUI

struct IDEWindowRootView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.theme) private var theme

    var body: some View {
        NavigationSplitView {
            FileTreeSidebar()
        } detail: {
            VStack(spacing: DS.Space._12) {
                Text("Smithers IDE")
                    .font(.system(size: DS.Typography.xl, weight: .semibold))
                    .foregroundStyle(theme.foregroundColor)
                Text(appModel.workspaceName)
                    .font(.system(size: DS.Typography.s))
                    .foregroundStyle(Color(nsColor: theme.mutedForeground))
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.backgroundColor)
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 400)
        .accessibilityIdentifier("ide_window_root")
    }
}
