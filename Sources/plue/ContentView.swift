import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            ChatView()
                .tabItem {
                    Image(systemName: "bubble.left.and.bubble.right")
                    Text("Chat")
                }
                .tag(0)
            
            ChatView()
                .tabItem {
                    Image(systemName: "doc.text")
                    Text("Code Editor")
                }
                .tag(1)
        }
        .background(Color(red: 0.05, green: 0.05, blue: 0.06))
    }
}


#Preview {
    ContentView()
        .frame(width: 1200, height: 800)
}
