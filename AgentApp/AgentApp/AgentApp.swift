import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct AgentApp: App {
    @StateObject private var appState = AppState()

    init() {
        #if os(macOS)
        // Activate the app so it takes keyboard focus from the launching terminal
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .onAppear {
                    #if os(macOS)
                    // Ensure window is key and frontmost
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.windows.first?.makeKeyAndOrderFront(nil)
                    #endif
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Session") {
                    Task {
                        await appState.createSession()
                    }
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        #if os(macOS)
        Settings {
            SettingsView()
                .environmentObject(appState)
        }
        #endif
    }
}

@MainActor
class AppState: ObservableObject {
    @Published var sessions: [Session] = []
    @Published var currentSessionID: String?
    @Published var isConnected: Bool = false
    @Published var serverURL: String = "http://localhost:8000"

    private var client: AgentClient?

    init() {
        self.client = AgentClient(baseURL: serverURL)
    }

    func updateServerURL(_ url: String) {
        self.serverURL = url
        self.client = AgentClient(baseURL: url)
    }

    func createSession() async {
        guard let client = client else { return }
        do {
            let session = try await client.createSession(title: "New Session")
            sessions.append(session)
            currentSessionID = session.id
        } catch {
            print("Failed to create session: \(error)")
        }
    }

    func loadSessions() async {
        guard let client = client else { return }
        do {
            sessions = try await client.listSessions()
            isConnected = true
        } catch {
            isConnected = false
            print("Failed to load sessions: \(error)")
        }
    }
}
