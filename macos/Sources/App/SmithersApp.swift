import SwiftUI
import SmithersKit
import os

@main
struct SmithersApp: App {
    @State private var appModel = AppModel()
    // SmithersCore is initialized by AppModel; remove smoke init.

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
