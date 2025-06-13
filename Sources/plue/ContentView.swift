import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    @State private var loadedTabs: Set<Int> = [0] // Only load tabs when needed
    
    var body: some View {
        TabView(selection: $selectedTab) {
            VimPromptView()
                .tabItem {
                    Image(systemName: "bubble.left.and.bubble.right")
                    Text("Prompt")
                }
                .tag(0)
            
            if loadedTabs.contains(1) {
                ModernChatView()
                    .tabItem {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                        Text("Chat")
                    }
                    .tag(1)
            } else {
                Color.clear
                    .tabItem {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                        Text("Chat")
                    }
                    .tag(1)
            }
            
            if loadedTabs.contains(2) {
                TerminalView()
                    .tabItem {
                        Image(systemName: "terminal")
                        Text("Terminal")
                    }
                    .tag(2)
            } else {
                Color.clear
                    .tabItem {
                        Image(systemName: "terminal")
                        Text("Terminal")
                    }
                    .tag(2)
            }
            
            if loadedTabs.contains(3) {
                WebView()
                    .tabItem {
                        Image(systemName: "globe")
                        Text("Web")
                    }
                    .tag(3)
            } else {
                Color.clear
                    .tabItem {
                        Image(systemName: "globe")
                        Text("Web")
                    }
                    .tag(3)
            }
            
            if loadedTabs.contains(4) {
                ChatView()
                    .tabItem {
                        Image(systemName: "doc.text")
                        Text("Code Editor")
                    }
                    .tag(4)
            } else {
                Color.clear
                    .tabItem {
                        Image(systemName: "doc.text")
                        Text("Code Editor")
                    }
                    .tag(4)
            }
        }
        .background(Color(red: 0.05, green: 0.05, blue: 0.06))
        .onChange(of: selectedTab) { newTab in
            // Lazy load tabs only when selected
            loadedTabs.insert(newTab)
        }
    }
}


#Preview {
    ContentView()
        .frame(width: 1200, height: 800)
}
