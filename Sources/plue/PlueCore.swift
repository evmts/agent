import Foundation

// MARK: - Core State Models (Immutable)

enum TabType: Int, CaseIterable {
    case prompt = 0
    case chat = 1 
    case terminal = 2
    case web = 3
    case editor = 4
}

struct AppState {
    let currentTab: TabType
    let isInitialized: Bool
    let errorMessage: String?
    let openAIAvailable: Bool
    
    // Tab states
    let chatState: ChatState
    let terminalState: TerminalState
    let vimState: VimState
    let webState: WebState
    let editorState: EditorState
    
    static let initial = AppState(
        currentTab: .prompt,
        isInitialized: true,
        errorMessage: nil,
        openAIAvailable: false,
        chatState: ChatState.initial,
        terminalState: TerminalState.initial,
        vimState: VimState.initial,
        webState: WebState.initial,
        editorState: EditorState.initial
    )
}

struct ChatState {
    let conversations: [Conversation]
    let currentConversationIndex: Int
    let isGenerating: Bool
    let generationProgress: Float
    
    static let initial = ChatState(
        conversations: [Conversation.initial],
        currentConversationIndex: 0,
        isGenerating: false,
        generationProgress: 0.0
    )
    
    var currentConversation: Conversation? {
        guard currentConversationIndex < conversations.count else { return nil }
        return conversations[currentConversationIndex]
    }
}

struct Conversation {
    let id: String
    let messages: [CoreMessage]
    let createdAt: Date
    let updatedAt: Date
    
    static let initial = Conversation(
        id: UUID().uuidString,
        messages: [
            CoreMessage(
                id: UUID().uuidString,
                content: "Welcome to Plue! How can I help you today?",
                isUser: false,
                timestamp: Date()
            )
        ],
        createdAt: Date(),
        updatedAt: Date()
    )
}

struct CoreMessage: Identifiable {
    let id: String
    let content: String
    let isUser: Bool
    let timestamp: Date
}

struct TerminalState {
    let buffer: [[CoreTerminalCell]]
    let cursor: CursorPosition
    let dimensions: TerminalDimensions
    let isConnected: Bool
    let currentCommand: String
    let needsRedraw: Bool
    
    static let initial = TerminalState(
        buffer: Array(repeating: Array(repeating: CoreTerminalCell.empty, count: 80), count: 25),
        cursor: CursorPosition(row: 0, col: 0),
        dimensions: TerminalDimensions(rows: 25, cols: 80),
        isConnected: false,
        currentCommand: "",
        needsRedraw: false
    )
}

struct CoreTerminalCell {
    let character: Character
    let foregroundColor: UInt32
    let backgroundColor: UInt32
    let attributes: UInt32
    
    static let empty = CoreTerminalCell(
        character: " ",
        foregroundColor: 0xFFFFFFFF, // White
        backgroundColor: 0x00000000, // Transparent
        attributes: 0
    )
}

struct CursorPosition {
    let row: Int
    let col: Int
}

struct TerminalDimensions {
    let rows: Int
    let cols: Int
}

struct VimState {
    let mode: CoreVimMode
    let buffer: [String]
    let cursor: CursorPosition
    let statusLine: String
    let visualSelection: CoreVisualSelection?
    
    static let initial = VimState(
        mode: .normal,
        buffer: [""],
        cursor: CursorPosition(row: 0, col: 0),
        statusLine: "",
        visualSelection: nil
    )
}

enum CoreVimMode {
    case normal
    case insert
    case command
    case visual
}

struct CoreVisualSelection {
    let startRow: Int
    let startCol: Int
    let endRow: Int
    let endCol: Int
    let type: CoreVisualType
}

enum CoreVisualType {
    case characterwise
    case linewise
    case blockwise
}

struct WebState {
    let currentURL: String
    let canGoBack: Bool
    let canGoForward: Bool
    let isLoading: Bool
    let isSecure: Bool
    let pageTitle: String
    
    static let initial = WebState(
        currentURL: "https://www.apple.com",
        canGoBack: false,
        canGoForward: false,
        isLoading: false,
        isSecure: true,
        pageTitle: ""
    )
}

struct EditorState {
    let content: String
    let language: String
    let cursor: CursorPosition
    let hasUnsavedChanges: Bool
    
    static let initial = EditorState(
        content: "// Welcome to Plue Code Editor\n// Start coding here...",
        language: "swift",
        cursor: CursorPosition(row: 0, col: 0),
        hasUnsavedChanges: false
    )
}

// MARK: - Events (Commands sent to core)

enum AppEvent {
    case tabSwitched(TabType)
    case chatMessageSent(String)
    case chatNewConversation
    case chatSelectConversation(Int)
    case terminalInput(String)
    case terminalResize(rows: Int, cols: Int)
    case vimKeypress(key: String, modifiers: UInt32)
    case vimSetContent(String)
    case webNavigate(String)
    case webGoBack
    case webGoForward
    case webReload
    case editorContentChanged(String)
    case editorSave
}

// MARK: - Core Interface

protocol PlueCoreInterface {
    // State management
    func getCurrentState() -> AppState
    func handleEvent(_ event: AppEvent)
    func subscribe(callback: @escaping (AppState) -> Void)
    
    // Lifecycle
    func initialize() -> Bool
    func shutdown()
}

// MARK: - Mock Implementation (will be replaced with Zig FFI)

class MockPlueCore: PlueCoreInterface {
    private var currentState: AppState = AppState.initial
    private var stateCallbacks: [(AppState) -> Void] = []
    private let openAIService: OpenAIService?
    
    // Thread-safe access using serial queue
    private let queue = DispatchQueue(label: "plue.core", qos: .userInteractive)
    
    init() {
        // Try to initialize OpenAI service, fall back to mock responses if not available
        do {
            self.openAIService = try OpenAIService()
            print("PlueCore: OpenAI service initialized successfully")
        } catch {
            self.openAIService = nil
            print("PlueCore: OpenAI service not available (\(error.localizedDescription)), using mock responses")
        }
    }
    
    func getCurrentState() -> AppState {
        return queue.sync {
            return currentState
        }
    }
    
    func handleEvent(_ event: AppEvent) {
        queue.async {
            self.processEvent(event)
            self.notifyStateChange()
        }
    }
    
    func subscribe(callback: @escaping (AppState) -> Void) {
        queue.async {
            self.stateCallbacks.append(callback)
            // Send current state immediately
            DispatchQueue.main.async {
                callback(self.currentState)
            }
        }
    }
    
    func initialize() -> Bool {
        queue.sync {
            // Initialize core state with OpenAI availability
            currentState = AppState(
                currentTab: .prompt,
                isInitialized: true,
                errorMessage: nil,
                openAIAvailable: openAIService != nil,
                chatState: ChatState.initial,
                terminalState: TerminalState.initial,
                vimState: VimState.initial,
                webState: WebState.initial,
                editorState: EditorState.initial
            )
            return true
        }
    }
    
    func shutdown() {
        queue.sync {
            stateCallbacks.removeAll()
        }
    }
    
    // MARK: - Helper Methods
    
    private func createUpdatedAppState(
        currentTab: TabType? = nil,
        errorMessage: String? = nil,
        chatState: ChatState? = nil,
        terminalState: TerminalState? = nil,
        vimState: VimState? = nil,
        webState: WebState? = nil,
        editorState: EditorState? = nil
    ) -> AppState {
        return AppState(
            currentTab: currentTab ?? self.currentState.currentTab,
            isInitialized: self.currentState.isInitialized,
            errorMessage: errorMessage ?? self.currentState.errorMessage,
            openAIAvailable: self.openAIService != nil,
            chatState: chatState ?? self.currentState.chatState,
            terminalState: terminalState ?? self.currentState.terminalState,
            vimState: vimState ?? self.currentState.vimState,
            webState: webState ?? self.currentState.webState,
            editorState: editorState ?? self.currentState.editorState
        )
    }
    
    // MARK: - Private Event Processing
    
    private func processEvent(_ event: AppEvent) {
        switch event {
        case .tabSwitched(let tab):
            currentState = createUpdatedAppState(currentTab: tab)
            
        case .chatMessageSent(let message):
            processChatMessage(message)
            
        case .chatNewConversation:
            createNewConversation()
            
        case .chatSelectConversation(let index):
            selectConversation(index)
            
        case .terminalInput(let input):
            processTerminalInput(input)
            
        case .terminalResize(let rows, let cols):
            resizeTerminal(rows: rows, cols: cols)
            
        case .vimKeypress(let key, let modifiers):
            processVimKeypress(key: key, modifiers: modifiers)
            
        case .vimSetContent(let content):
            setVimContent(content)
            
        case .webNavigate(let url):
            navigateWeb(to: url)
            
        case .webGoBack:
            webGoBack()
            
        case .webGoForward:
            webGoForward()
            
        case .webReload:
            webReload()
            
        case .editorContentChanged(let content):
            updateEditorContent(content)
            
        case .editorSave:
            saveEditor()
        }
    }
    
    private func processChatMessage(_ message: String) {
        // Add user message
        let userMessage = CoreMessage(
            id: UUID().uuidString,
            content: message,
            isUser: true,
            timestamp: Date()
        )
        
        var conversations = currentState.chatState.conversations
        var currentConv = conversations[currentState.chatState.currentConversationIndex]
        currentConv = Conversation(
            id: currentConv.id,
            messages: currentConv.messages + [userMessage],
            createdAt: currentConv.createdAt,
            updatedAt: Date()
        )
        conversations[currentState.chatState.currentConversationIndex] = currentConv
        
        // Update state with generation started
        let newChatState = ChatState(
            conversations: conversations,
            currentConversationIndex: currentState.chatState.currentConversationIndex,
            isGenerating: true,
            generationProgress: 0.0
        )
        
        currentState = createUpdatedAppState(chatState: newChatState)
        
        // Generate AI response using OpenAI API
        Task { [weak self] in
            await self?.generateAIResponse(for: message)
        }
    }
    
    private func generateAIResponse(for input: String) async {
        guard let openAIService = openAIService else {
            // Fallback to mock response if OpenAI service not available
            await generateMockAIResponse(for: input)
            return
        }
        
        let responseContent: String
        
        do {
            // Get conversation history for context
            let currentConversation = queue.sync { 
                return currentState.chatState.currentConversation 
            }
            
            let conversationMessages = currentConversation?.messages ?? []
            let openAIMessages = openAIService.convertToOpenAIMessages(conversationMessages)
            
            // Add the new user message
            let allMessages = openAIMessages + [OpenAIMessage(role: "user", content: input)]
            
            print("PlueCore: Sending request to OpenAI API...")
            responseContent = try await openAIService.sendChatMessage(
                messages: allMessages,
                model: "gpt-4",
                temperature: 0.7
            )
            print("PlueCore: Received response from OpenAI API")
            
        } catch {
            print("PlueCore: OpenAI API error: \(error.localizedDescription)")
            responseContent = "I apologize, but I'm having trouble connecting to the AI service right now. Error: \(error.localizedDescription)"
        }
        
        // Update state with AI response
        await updateStateWithAIResponse(content: responseContent)
    }
    
    private func generateMockAIResponse(for input: String) async {
        // Simulate API delay
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        let mockResponse = "Mock Response: I understand you're asking about '\(input)'. This is a placeholder response since the OpenAI API key is not configured. Please set the OPENAI_API_KEY environment variable to enable real AI responses."
        
        await updateStateWithAIResponse(content: mockResponse)
    }
    
    private func updateStateWithAIResponse(content: String) async {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            let aiMessage = CoreMessage(
                id: UUID().uuidString,
                content: content,
                isUser: false,
                timestamp: Date()
            )
            
            var conversations = self.currentState.chatState.conversations
            var currentConv = conversations[self.currentState.chatState.currentConversationIndex]
            currentConv = Conversation(
                id: currentConv.id,
                messages: currentConv.messages + [aiMessage],
                createdAt: currentConv.createdAt,
                updatedAt: Date()
            )
            conversations[self.currentState.chatState.currentConversationIndex] = currentConv
            
            let newChatState = ChatState(
                conversations: conversations,
                currentConversationIndex: self.currentState.chatState.currentConversationIndex,
                isGenerating: false,
                generationProgress: 1.0
            )
            
            self.currentState = self.createUpdatedAppState(chatState: newChatState)
            
            self.notifyStateChange()
        }
    }
    
    private func createNewConversation() {
        let newConv = Conversation(
            id: UUID().uuidString,
            messages: [
                CoreMessage(
                    id: UUID().uuidString,
                    content: "New conversation started. How can I help you?",
                    isUser: false,
                    timestamp: Date()
                )
            ],
            createdAt: Date(),
            updatedAt: Date()
        )
        
        let conversations = currentState.chatState.conversations + [newConv]
        let newChatState = ChatState(
            conversations: conversations,
            currentConversationIndex: conversations.count - 1,
            isGenerating: false,
            generationProgress: 0.0
        )
        
        currentState = createUpdatedAppState(chatState: newChatState)
    }
    
    private func selectConversation(_ index: Int) {
        guard index < currentState.chatState.conversations.count else { return }
        
        let newChatState = ChatState(
            conversations: currentState.chatState.conversations,
            currentConversationIndex: index,
            isGenerating: false,
            generationProgress: 0.0
        )
        
        currentState = createUpdatedAppState(chatState: newChatState)
    }
    
    private func processTerminalInput(_ input: String) {
        // Simple command processing (will be real PTY in Zig)
        let output = executeCommand(input.trimmingCharacters(in: .whitespacesAndNewlines))
        
        // Update terminal state with new output
        // For now, just toggle needsRedraw
        let newTerminalState = TerminalState(
            buffer: currentState.terminalState.buffer,
            cursor: currentState.terminalState.cursor,
            dimensions: currentState.terminalState.dimensions,
            isConnected: true,
            currentCommand: output,
            needsRedraw: true
        )
        
        currentState = createUpdatedAppState(terminalState: newTerminalState)
    }
    
    private func executeCommand(_ command: String) -> String {
        switch command {
        case "ls":
            return "file1.txt  file2.swift  directory/  .hidden"
        case "pwd":
            return "/Users/user/plue"
        case "clear":
            return ""
        case "":
            return ""
        default:
            return "\(command): command processed by Zig core"
        }
    }
    
    private func resizeTerminal(rows: Int, cols: Int) {
        let newDimensions = TerminalDimensions(rows: rows, cols: cols)
        let newBuffer = Array(repeating: Array(repeating: CoreTerminalCell.empty, count: cols), count: rows)
        
        let newTerminalState = TerminalState(
            buffer: newBuffer,
            cursor: CursorPosition(row: 0, col: 0),
            dimensions: newDimensions,
            isConnected: currentState.terminalState.isConnected,
            currentCommand: currentState.terminalState.currentCommand,
            needsRedraw: true
        )
        
        currentState = createUpdatedAppState(terminalState: newTerminalState)
    }
    
    private func processVimKeypress(key: String, modifiers: UInt32) {
        // Simple vim simulation (will be real vim in Zig)
        var newMode = currentState.vimState.mode
        var newBuffer = currentState.vimState.buffer
        var newCursor = currentState.vimState.cursor
        var newStatusLine = currentState.vimState.statusLine
        
        switch (currentState.vimState.mode, key) {
        case (.normal, "i"):
            newMode = .insert
            newStatusLine = "-- INSERT --"
        case (.insert, _) where key == "Escape":
            newMode = .normal
            newStatusLine = ""
        case (.normal, ":"):
            newMode = .command
            newStatusLine = ":"
        default:
            break
        }
        
        let newVimState = VimState(
            mode: newMode,
            buffer: newBuffer,
            cursor: newCursor,
            statusLine: newStatusLine,
            visualSelection: currentState.vimState.visualSelection
        )
        
        currentState = createUpdatedAppState(vimState: newVimState)
    }
    
    private func setVimContent(_ content: String) {
        let lines = content.components(separatedBy: .newlines)
        
        let newVimState = VimState(
            mode: currentState.vimState.mode,
            buffer: lines.isEmpty ? [""] : lines,
            cursor: CursorPosition(row: 0, col: 0),
            statusLine: currentState.vimState.statusLine,
            visualSelection: nil
        )
        
        currentState = createUpdatedAppState(vimState: newVimState)
    }
    
    private func navigateWeb(to url: String) {
        let newWebState = WebState(
            currentURL: url,
            canGoBack: true,
            canGoForward: currentState.webState.canGoForward,
            isLoading: true,
            isSecure: url.hasPrefix("https://"),
            pageTitle: "Loading..."
        )
        
        currentState = createUpdatedAppState(webState: newWebState)
        
        // Simulate loading completion
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.queue.async {
                guard let self = self else { return }
                let completedWebState = WebState(
                    currentURL: url,
                    canGoBack: true,
                    canGoForward: self.currentState.webState.canGoForward,
                    isLoading: false,
                    isSecure: url.hasPrefix("https://"),
                    pageTitle: "Loaded Page"
                )
                
                self.currentState = self.createUpdatedAppState(webState: completedWebState)
                
                self.notifyStateChange()
            }
        }
    }
    
    private func webGoBack() {
        let newWebState = WebState(
            currentURL: "https://previous-page.com",
            canGoBack: false,
            canGoForward: true,
            isLoading: false,
            isSecure: true,
            pageTitle: "Previous Page"
        )
        
        currentState = createUpdatedAppState(webState: newWebState)
    }
    
    private func webGoForward() {
        let newWebState = WebState(
            currentURL: "https://next-page.com",
            canGoBack: true,
            canGoForward: false,
            isLoading: false,
            isSecure: true,
            pageTitle: "Next Page"
        )
        
        currentState = createUpdatedAppState(webState: newWebState)
    }
    
    private func webReload() {
        let newWebState = WebState(
            currentURL: currentState.webState.currentURL,
            canGoBack: currentState.webState.canGoBack,
            canGoForward: currentState.webState.canGoForward,
            isLoading: true,
            isSecure: currentState.webState.isSecure,
            pageTitle: "Reloading..."
        )
        
        currentState = createUpdatedAppState(webState: newWebState)
    }
    
    private func updateEditorContent(_ content: String) {
        let newEditorState = EditorState(
            content: content,
            language: currentState.editorState.language,
            cursor: currentState.editorState.cursor,
            hasUnsavedChanges: true
        )
        
        currentState = createUpdatedAppState(editorState: newEditorState)
    }
    
    private func saveEditor() {
        let newEditorState = EditorState(
            content: currentState.editorState.content,
            language: currentState.editorState.language,
            cursor: currentState.editorState.cursor,
            hasUnsavedChanges: false
        )
        
        currentState = createUpdatedAppState(editorState: newEditorState)
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

// MARK: - Singleton Instance

public class PlueCore {
    static let shared: PlueCoreInterface = MockPlueCore()
    
    private init() {}
}

/// Errors that can occur when working with PlueCore
public enum PlueError: Error {
    case initializationFailed
    
    public var localizedDescription: String {
        switch self {
        case .initializationFailed:
            return "Failed to initialize Plue core library"
        }
    }
}