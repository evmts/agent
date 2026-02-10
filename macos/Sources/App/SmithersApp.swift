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
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 800, height: 900)

        Window("Smithers IDE", id: "workspace") {
            IDEWindowRootView()
                .environment(appModel)
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
    var body: some View {
        ZStack {
            Color.black.opacity(0.94)
            Text("Chat Window")
                .foregroundStyle(.white.opacity(0.88))
                .padding(24)
        }
    }
}

struct IDEWindowRootView: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.94)
            Text("IDE Window")
                .foregroundStyle(.white.opacity(0.88))
                .padding(24)
        }
    }
}
