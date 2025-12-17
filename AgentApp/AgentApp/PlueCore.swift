import Foundation
import SwiftUI

// MARK: - Tab Types

enum TabType: Int, CaseIterable {
    case agent = 0
    case terminal = 1
    case editor = 2

    var title: String {
        switch self {
        case .agent: return "Agent"
        case .terminal: return "Terminal"
        case .editor: return "Editor"
        }
    }

    var icon: String {
        switch self {
        case .agent: return "brain"
        case .terminal: return "terminal"
        case .editor: return "doc.text"
        }
    }
}

// MARK: - App State

struct PlueAppState {
    var currentTab: TabType
    var currentTheme: DesignSystem.Theme
    var agentState: AgentState
    var editorState: EditorState

    static let initial = PlueAppState(
        currentTab: .agent,
        currentTheme: .dark,
        agentState: AgentState.initial,
        editorState: EditorState.initial
    )
}

// MARK: - Agent State

struct AgentState {
    var conversations: [AgentConversation]
    var currentConversationIndex: Int
    var isProcessing: Bool

    static let initial = AgentState(
        conversations: [AgentConversation.initial],
        currentConversationIndex: 0,
        isProcessing: false
    )

    var currentConversation: AgentConversation? {
        guard currentConversationIndex < conversations.count else { return nil }
        return conversations[currentConversationIndex]
    }
}

struct AgentConversation: Identifiable {
    let id: String
    var messages: [AgentMessage]
    let createdAt: Date
    var updatedAt: Date

    static let initial = AgentConversation(
        id: UUID().uuidString,
        messages: [
            AgentMessage(
                id: UUID().uuidString,
                content: "Welcome! I'm your AI agent. How can I help you today?",
                type: .system,
                timestamp: Date()
            )
        ],
        createdAt: Date(),
        updatedAt: Date()
    )
}

struct AgentMessage: Identifiable {
    let id: String
    let content: String
    let type: AgentMessageType
    let timestamp: Date
}

enum AgentMessageType {
    case user
    case assistant
    case system
}

// MARK: - Editor State

struct EditorState {
    var content: String
    var language: String
    var hasUnsavedChanges: Bool

    static let initial = EditorState(
        content: "// Welcome to the Editor\n// Start coding here...\n",
        language: "swift",
        hasUnsavedChanges: false
    )
}

// MARK: - App Events

enum PlueEvent {
    case tabSwitched(TabType)
    case themeToggled
    case agentMessageSent(String)
    case agentNewConversation
    case editorContentChanged(String)
}

// MARK: - Core Protocol

protocol PlueCoreInterface {
    func getCurrentState() -> PlueAppState
    func handleEvent(_ event: PlueEvent)
    func subscribe(callback: @escaping (PlueAppState) -> Void)
}

// MARK: - Mock Core Implementation

class MockPlueCore: PlueCoreInterface {
    private var currentState: PlueAppState = PlueAppState.initial
    private var stateCallbacks: [(PlueAppState) -> Void] = []
    private let queue = DispatchQueue(label: "plue.core", qos: .userInteractive)

    func getCurrentState() -> PlueAppState {
        return queue.sync { currentState }
    }

    func handleEvent(_ event: PlueEvent) {
        queue.async {
            self.processEvent(event)
            self.notifyStateChange()
        }
    }

    func subscribe(callback: @escaping (PlueAppState) -> Void) {
        queue.async {
            self.stateCallbacks.append(callback)
            DispatchQueue.main.async {
                callback(self.currentState)
            }
        }
    }

    private func processEvent(_ event: PlueEvent) {
        switch event {
        case .tabSwitched(let tab):
            currentState.currentTab = tab

        case .themeToggled:
            currentState.currentTheme = currentState.currentTheme == .dark ? .light : .dark

        case .agentMessageSent(let message):
            processAgentMessage(message)

        case .agentNewConversation:
            createNewConversation()

        case .editorContentChanged(let content):
            currentState.editorState.content = content
            currentState.editorState.hasUnsavedChanges = true
        }
    }

    private func processAgentMessage(_ message: String) {
        // Add user message
        let userMessage = AgentMessage(
            id: UUID().uuidString,
            content: message,
            type: .user,
            timestamp: Date()
        )

        currentState.agentState.conversations[currentState.agentState.currentConversationIndex].messages.append(userMessage)
        currentState.agentState.conversations[currentState.agentState.currentConversationIndex].updatedAt = Date()
        currentState.agentState.isProcessing = true
        notifyStateChange()

        // Simulate AI response
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await self?.addAgentResponse(for: message)
        }
    }

    @MainActor
    private func addAgentResponse(for input: String) {
        queue.async { [weak self] in
            guard let self = self else { return }

            let response = self.generateMockResponse(for: input)
            let assistantMessage = AgentMessage(
                id: UUID().uuidString,
                content: response,
                type: .assistant,
                timestamp: Date()
            )

            self.currentState.agentState.conversations[self.currentState.agentState.currentConversationIndex].messages.append(assistantMessage)
            self.currentState.agentState.conversations[self.currentState.agentState.currentConversationIndex].updatedAt = Date()
            self.currentState.agentState.isProcessing = false
            self.notifyStateChange()
        }
    }

    private func generateMockResponse(for input: String) -> String {
        let lowercaseInput = input.lowercased()

        if lowercaseInput.contains("help") {
            return "I can help you with:\n- Code generation and review\n- Debugging assistance\n- Documentation\n- General programming questions\n\nJust ask me anything!"
        } else if lowercaseInput.contains("code") || lowercaseInput.contains("write") {
            return "I'd be happy to help you write code! Please describe what you'd like to create, and I'll provide an implementation."
        } else if lowercaseInput.contains("explain") {
            return "I can explain code, concepts, or architectural decisions. What would you like me to clarify?"
        } else {
            return "I understand you're asking about '\(input)'. This is a mock response - in production, this would connect to your agent backend for real AI-powered responses."
        }
    }

    private func createNewConversation() {
        let newConv = AgentConversation(
            id: UUID().uuidString,
            messages: [
                AgentMessage(
                    id: UUID().uuidString,
                    content: "New conversation started. How can I help you?",
                    type: .system,
                    timestamp: Date()
                )
            ],
            createdAt: Date(),
            updatedAt: Date()
        )

        currentState.agentState.conversations.append(newConv)
        currentState.agentState.currentConversationIndex = currentState.agentState.conversations.count - 1
    }

    private func notifyStateChange() {
        let state = currentState
        DispatchQueue.main.async {
            for callback in self.stateCallbacks {
                callback(state)
            }
        }
    }
}

// MARK: - Singleton

class PlueCore {
    static let shared: PlueCoreInterface = MockPlueCore()
    private init() {}
}
