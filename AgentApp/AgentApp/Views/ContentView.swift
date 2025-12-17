import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var showingSidebar = true
    @State private var inputText = ""

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            MainContentView()
        }
        .task {
            await appState.loadSessions()
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        List(selection: $appState.currentSessionID) {
            Section("Sessions") {
                ForEach(appState.sessions) { session in
                    NavigationLink(value: session.id) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.title)
                                .font(.headline)
                            Text(session.formattedDate)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Agent")
        .toolbar {
            ToolbarItem {
                Button {
                    Task {
                        await appState.createSession()
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .overlay {
            if appState.sessions.isEmpty {
                ContentUnavailableView {
                    Label("No Sessions", systemImage: "terminal")
                } description: {
                    Text("Create a new session to get started")
                } actions: {
                    Button("New Session") {
                        Task {
                            await appState.createSession()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}

struct MainContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var showingTerminal = true

    var body: some View {
        Group {
            if appState.currentSessionID != nil {
                VSplitView {
                    ChatView()

                    if showingTerminal {
                        #if os(macOS)
                        TerminalView(workingDirectory: nil)
                            .frame(minHeight: 200)
                        #else
                        Text("Terminal not available on iOS")
                            .frame(minHeight: 200)
                        #endif
                    }
                }
                .toolbar {
                    ToolbarItem {
                        Button {
                            showingTerminal.toggle()
                        } label: {
                            Image(systemName: showingTerminal ? "terminal.fill" : "terminal")
                        }
                        .help(showingTerminal ? "Hide Terminal" : "Show Terminal")
                    }
                }
            } else {
                ContentUnavailableView {
                    Label("Select a Session", systemImage: "sidebar.left")
                } description: {
                    Text("Choose a session from the sidebar or create a new one")
                }
            }
        }
    }
}

struct ChatView: View {
    @EnvironmentObject var appState: AppState
    @State private var messages: [MessageWithParts] = []
    @State private var inputText = ""
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(messages) { message in
                            MessageView(message: message)
                                .id(message.info.id)
                        }

                        if isLoading {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Thinking...")
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                            .id("loading")
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _, _ in
                    withAnimation {
                        proxy.scrollTo(messages.last?.info.id ?? "loading", anchor: .bottom)
                    }
                }
            }

            Divider()

            HStack(spacing: 12) {
                TextField("Message...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .onSubmit {
                        sendMessage()
                    }

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
            }
            .padding()
            .background(.bar)
        }
    }

    private func sendMessage() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let text = inputText
        inputText = ""
        isLoading = true

        Task {
            // TODO: Send message via AgentClient
            // For now, just add a mock response
            let userMessage = MessageWithParts(
                info: Message(
                    id: UUID().uuidString,
                    sessionID: appState.currentSessionID ?? "",
                    role: "user",
                    time: MessageTime(created: Date().timeIntervalSince1970, updated: Date().timeIntervalSince1970)
                ),
                parts: [Part(id: UUID().uuidString, sessionID: appState.currentSessionID ?? "", messageID: "", type: "text", text: text)]
            )
            messages.append(userMessage)
            isLoading = false
        }
    }
}

struct MessageView: View {
    let message: MessageWithParts

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: message.info.role == "user" ? "person.fill" : "cpu")
                .font(.title3)
                .foregroundStyle(message.info.role == "user" ? .blue : .purple)
                .frame(width: 32, height: 32)
                .background(message.info.role == "user" ? Color.blue.opacity(0.1) : Color.purple.opacity(0.1))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 8) {
                Text(message.info.role == "user" ? "You" : "Agent")
                    .font(.headline)

                ForEach(message.parts) { part in
                    PartView(part: part)
                }
            }

            Spacer()
        }
        .padding()
        .background(message.info.role == "user" ? Color.clear : Color.secondary.opacity(0.05))
        .cornerRadius(12)
    }
}

struct PartView: View {
    let part: Part

    var body: some View {
        switch part.type {
        case "text":
            Text(part.text ?? "")
                .textSelection(.enabled)
        case "tool":
            ToolPartView(part: part)
        case "reasoning":
            DisclosureGroup {
                Text(part.text ?? "")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } label: {
                Label("Thinking", systemImage: "brain")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        default:
            Text(part.text ?? "Unknown part type: \(part.type)")
                .foregroundStyle(.secondary)
        }
    }
}

struct ToolPartView: View {
    let part: Part

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "hammer.fill")
                    .foregroundStyle(.orange)
                Text(part.tool ?? "Tool")
                    .font(.callout.bold())

                Spacer()

                if let state = part.state {
                    StatusBadge(status: state.status)
                }
            }

            if let state = part.state, let output = state.output, !output.isEmpty {
                Text(output)
                    .font(.system(.caption, design: .monospaced))
                    .padding(8)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(6)
            }
        }
        .padding()
        .background(Color.orange.opacity(0.05))
        .cornerRadius(8)
    }
}

struct StatusBadge: View {
    let status: String

    var color: Color {
        switch status {
        case "completed": return .green
        case "running": return .blue
        case "pending": return .orange
        default: return .gray
        }
    }

    var body: some View {
        Text(status.capitalized)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .cornerRadius(4)
    }
}

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var serverURL: String = ""

    var body: some View {
        Form {
            Section("Server") {
                TextField("Server URL", text: $serverURL)
                    .onAppear {
                        serverURL = appState.serverURL
                    }

                HStack {
                    Circle()
                        .fill(appState.isConnected ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text(appState.isConnected ? "Connected" : "Disconnected")
                        .foregroundStyle(.secondary)
                }

                Button("Connect") {
                    appState.updateServerURL(serverURL)
                    Task {
                        await appState.loadSessions()
                    }
                }
            }
        }
        .padding()
        .frame(width: 400, height: 200)
    }
}

// Preview in Xcode:
// ContentView()
//     .environmentObject(AppState())
