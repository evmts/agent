import SwiftUI

struct IDEWindowRootView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.theme) private var theme

    var body: some View {
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
        .accessibilityIdentifier("ide_window_root")
    }
}
