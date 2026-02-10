import SwiftUI
import Foundation
import SmithersKit
import os


@main
struct SmithersApp: App {
    private static var didValidateLink = false
    init() {
        guard !Self.didValidateLink else { return }
        Self.didValidateLink = true
        let logger = Logger(subsystem: "com.smithers", category: "app")
        var cfg = smithers_config_s(runtime: smithers_runtime_config_s(wakeup: nil, action: nil, userdata: nil))
        if let handle = smithers_app_new(&cfg) {
            smithers_app_free(handle)
            logger.debug("SmithersKit link OK")
        } else {
            logger.error("SmithersKit init failed (nil handle)")
        }
    }

    var body: some Scene {
        Window("Smithers", id: "chat") {
            ChatWindowRootView()
                .frame(minWidth: 800, minHeight: 900)
        }
        .windowStyle(.hiddenTitleBar)

        Window("Smithers IDE", id: "workspace") {
            IDEWindowRootView()
                .frame(minWidth: 1100, minHeight: 900)
        }
        .windowStyle(.hiddenTitleBar)

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
