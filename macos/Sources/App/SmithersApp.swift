import SwiftUI
import SmithersKit
import os

@main
struct SmithersApp: App {
    @State private var appModel = AppModel()
    nonisolated(unsafe) static var didValidateLink = false
    init() {
        guard !Self.didValidateLink else { return }
        Self.didValidateLink = true
        SmithersCoreBridge.smokeInitAndFree()
    }

    var body: some Scene {
        Window("Smithers", id: "chat") {
            ChatWindowRootView()
                .environment(appModel)
                .environment(\.theme, appModel.theme)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 800, height: 900)

        Window("Smithers IDE", id: "workspace") {
            IDEWindowRootView()
                .environment(appModel)
                .environment(\.theme, appModel.theme)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 900)

        Settings {
            Text("Settings")
                .padding()
        }
    }
}

struct ChatWindowRootView: View {
    @Environment(\.theme) private var theme
    var body: some View {
        ZStack {
            theme.backgroundColor
            Text("Chat Window")
                .foregroundStyle(theme.foregroundColor)
                .padding(DS.Space._24)
        }
    }
}

struct IDEWindowRootView: View {
    @Environment(\.theme) private var theme
    var body: some View {
        ZStack {
            theme.backgroundColor
            Text("IDE Window")
                .foregroundStyle(theme.foregroundColor)
                .padding(DS.Space._24)
        }
    }
}
