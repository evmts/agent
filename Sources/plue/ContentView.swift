import SwiftUI

struct ContentView: View {
    @State private var appState = AppState.initial
    private let core = PlueCore.shared
    
    var body: some View {
        TabView(selection: Binding(
            get: { TabType(rawValue: appState.currentTab.rawValue) ?? .prompt },
            set: { newTab in
                core.handleEvent(.tabSwitched(newTab))
            }
        )) {
            // Remove all lazy loading - no more race conditions!
            VimPromptView(appState: appState, core: core)
                .tabItem {
                    Image(systemName: "bubble.left.and.bubble.right")
                    Text("Prompt")
                }
                .tag(TabType.prompt)
            
            // Temporarily use old views until we refactor them
            ModernChatView(appState: appState, core: core)
                .tabItem {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                    Text("Chat")
                }
                .tag(TabType.chat)
            
            TerminalView(appState: appState, core: core)
                .tabItem {
                    Image(systemName: "terminal")
                    Text("Terminal")
                }
                .tag(TabType.terminal)
            
            WebView(appState: appState, core: core)
                .tabItem {
                    Image(systemName: "globe")
                    Text("Web")
                }
                .tag(TabType.web)
            
            ChatView(appState: appState, core: core)
                .tabItem {
                    Image(systemName: "doc.text")
                    Text("Code Editor")
                }
                .tag(TabType.editor)
        }
        .background(Color(red: 0.05, green: 0.05, blue: 0.06))
        .onAppear {
            // Initialize core and subscribe to state changes
            _ = core.initialize()
            core.subscribe { newState in
                appState = newState
            }
        }
    }
}


#Preview {
    ContentView()
        .frame(width: 1200, height: 800)
}
