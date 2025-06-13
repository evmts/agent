import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            PromptView()
                .tabItem {
                    Image(systemName: "bubble.left.and.bubble.right")
                    Text("Prompt")
                }
                .tag(0)
            
            ChatView()
                .tabItem {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                    Text("Chat")
                }
                .tag(1)
            
            ChatView()
                .tabItem {
                    Image(systemName: "doc.text")
                    Text("Code Editor")
                }
                .tag(2)
        }
        .background(Color(red: 0.05, green: 0.05, blue: 0.06))
    }
}


#Preview {
    ContentView()
        .frame(width: 1200, height: 800)
}
