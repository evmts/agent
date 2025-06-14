import Foundation

// MARK: - Core State Models (Immutable)

enum TabType: Int, CaseIterable {
    case prompt = 0
    case chat = 1 
    case terminal = 2
    case web = 3
    case editor = 4
    case farcaster = 5
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
    let farcasterState: FarcasterState
    
    static let initial = AppState(
        currentTab: .prompt,
        isInitialized: true,
        errorMessage: nil,
        openAIAvailable: false,
        chatState: ChatState.initial,
        terminalState: TerminalState.initial,
        vimState: VimState.initial,
        webState: WebState.initial,
        editorState: EditorState.initial,
        farcasterState: FarcasterState.initial
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

struct FarcasterState {
    let selectedChannel: String
    let posts: [FarcasterPost]
    let channels: [FarcasterChannel]
    let isLoading: Bool
    
    static let initial = FarcasterState(
        selectedChannel: "dev",
        posts: FarcasterPost.mockPosts,
        channels: FarcasterChannel.mockChannels,
        isLoading: false
    )
}

struct FarcasterPost: Identifiable {
    let id: String
    let author: FarcasterUser
    let content: String
    let timestamp: Date
    let channel: String
    let likes: Int
    let recasts: Int
    let replies: Int
    let isLiked: Bool
    let isRecast: Bool
    
    static let mockPosts: [FarcasterPost] = [
        FarcasterPost(
            id: "1",
            author: FarcasterUser(username: "dwr", displayName: "Dan Romero", avatarURL: ""),
            content: "Building the future of decentralized social on Farcaster. The protocol is designed for developers who want to build without platform risk.",
            timestamp: Date().addingTimeInterval(-3600),
            channel: "dev",
            likes: 42,
            recasts: 15,
            replies: 8,
            isLiked: false,
            isRecast: false
        ),
        FarcasterPost(
            id: "2", 
            author: FarcasterUser(username: "vitalik", displayName: "Vitalik Buterin", avatarURL: ""),
            content: "Interesting developments in decentralized social protocols. The composability potential is huge.",
            timestamp: Date().addingTimeInterval(-7200),
            channel: "dev",
            likes: 128,
            recasts: 34,
            replies: 22,
            isLiked: true,
            isRecast: false
        ),
        FarcasterPost(
            id: "3",
            author: FarcasterUser(username: "jessepollak", displayName: "Jesse Pollak", avatarURL: ""),
            content: "Working on some exciting new features for Base. Can't wait to share what we're building! 🔵",
            timestamp: Date().addingTimeInterval(-10800),
            channel: "dev",
            likes: 89,
            recasts: 21,
            replies: 12,
            isLiked: false,
            isRecast: true
        ),
        FarcasterPost(
            id: "4",
            author: FarcasterUser(username: "balajis", displayName: "Balaji", avatarURL: ""),
            content: "The future is decentralized. Social networks, money, computation - all moving towards peer-to-peer architectures.",
            timestamp: Date().addingTimeInterval(-14400),
            channel: "dev", 
            likes: 203,
            recasts: 67,
            replies: 45,
            isLiked: true,
            isRecast: false
        ),
        FarcasterPost(
            id: "5",
            author: FarcasterUser(username: "farcaster", displayName: "Farcaster", avatarURL: ""),
            content: "Welcome to the decentralized social revolution! Build whatever you want on top of the Farcaster protocol. No ads, no algorithms, just pure social interaction.",
            timestamp: Date().addingTimeInterval(-18000),
            channel: "dev",
            likes: 156,
            recasts: 78,
            replies: 29,
            isLiked: false,
            isRecast: false
        )
    ]
}

struct FarcasterUser {
    let username: String
    let displayName: String
    let avatarURL: String
}

struct FarcasterChannel {
    let id: String
    let name: String
    let description: String
    let memberCount: Int
    
    static let mockChannels: [FarcasterChannel] = [
        FarcasterChannel(id: "dev", name: "Dev", description: "For developers building on Farcaster", memberCount: 1234),
        FarcasterChannel(id: "crypto", name: "Crypto", description: "Cryptocurrency and DeFi discussions", memberCount: 5678),
        FarcasterChannel(id: "art", name: "Art", description: "Digital art and NFT community", memberCount: 2345),
        FarcasterChannel(id: "memes", name: "Memes", description: "The best memes on the internet", memberCount: 9876),
        FarcasterChannel(id: "music", name: "Music", description: "Share and discover music", memberCount: 3456)
    ]
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
    case farcasterSelectChannel(String)
    case farcasterLikePost(String)
    case farcasterRecastPost(String)
    case farcasterReplyToPost(String, String) // postId, replyContent
    case farcasterCreatePost(String)
    case farcasterRefreshFeed
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
    private let farcasterService: FarcasterService?
    
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
        
        // Try to initialize Farcaster service, fall back to mock data if not available
        self.farcasterService = FarcasterService.createTestService()
        if farcasterService != nil {
            print("PlueCore: Farcaster service initialized successfully")
        } else {
            print("PlueCore: Farcaster service not available, using mock data")
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
                editorState: EditorState.initial,
                farcasterState: FarcasterState.initial
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
        editorState: EditorState? = nil,
        farcasterState: FarcasterState? = nil
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
            editorState: editorState ?? self.currentState.editorState,
            farcasterState: farcasterState ?? self.currentState.farcasterState
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
            
        case .farcasterSelectChannel(let channelId):
            selectFarcasterChannel(channelId)
            
        case .farcasterLikePost(let postId):
            likeFarcasterPost(postId)
            
        case .farcasterRecastPost(let postId):
            recastFarcasterPost(postId)
            
        case .farcasterReplyToPost(let postId, let replyContent):
            replyToFarcasterPost(postId, replyContent)
            
        case .farcasterCreatePost(let content):
            createFarcasterPost(content)
            
        case .farcasterRefreshFeed:
            refreshFarcasterFeed()
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
    
    // MARK: - Farcaster Event Handlers
    
    private func selectFarcasterChannel(_ channelId: String) {
        let newFarcasterState = FarcasterState(
            selectedChannel: channelId,
            posts: currentState.farcasterState.posts,
            channels: currentState.farcasterState.channels,
            isLoading: false
        )
        
        currentState = createUpdatedAppState(farcasterState: newFarcasterState)
    }
    
    private func likeFarcasterPost(_ postId: String) {
        if let farcasterService = farcasterService {
            // Use real Farcaster API
            Task { [weak self] in
                do {
                    // First update UI optimistically
                    await self?.updatePostLikeOptimistic(postId, isLiked: true)
                    
                    // Find the post to get the author FID
                    guard let self = self,
                          let post = self.currentState.farcasterState.posts.first(where: { $0.id == postId }),
                          let authorFid = UInt64(post.author.username) else {
                        print("PlueCore: Could not find post or author FID for like")
                        return
                    }
                    
                    let result = try await farcasterService.likeCast(castHash: postId, authorFid: authorFid)
                    print("PlueCore: Liked cast successfully: \(result)")
                } catch {
                    print("PlueCore: Failed to like cast: \(error)")
                    // Revert optimistic update on error
                    await self?.updatePostLikeOptimistic(postId, isLiked: false)
                }
            }
        } else {
            // Use mock behavior
            likeFarcasterPostMock(postId)
        }
    }
    
    private func likeFarcasterPostMock(_ postId: String) {
        var updatedPosts = currentState.farcasterState.posts
        
        if let index = updatedPosts.firstIndex(where: { $0.id == postId }) {
            let post = updatedPosts[index]
            let newPost = FarcasterPost(
                id: post.id,
                author: post.author,
                content: post.content,
                timestamp: post.timestamp,
                channel: post.channel,
                likes: post.isLiked ? post.likes - 1 : post.likes + 1,
                recasts: post.recasts,
                replies: post.replies,
                isLiked: !post.isLiked,
                isRecast: post.isRecast
            )
            updatedPosts[index] = newPost
        }
        
        let newFarcasterState = FarcasterState(
            selectedChannel: currentState.farcasterState.selectedChannel,
            posts: updatedPosts,
            channels: currentState.farcasterState.channels,
            isLoading: false
        )
        
        currentState = createUpdatedAppState(farcasterState: newFarcasterState)
    }
    
    private func updatePostLikeOptimistic(_ postId: String, isLiked: Bool) async {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            var updatedPosts = self.currentState.farcasterState.posts
            
            if let index = updatedPosts.firstIndex(where: { $0.id == postId }) {
                let post = updatedPosts[index]
                let newPost = FarcasterPost(
                    id: post.id,
                    author: post.author,
                    content: post.content,
                    timestamp: post.timestamp,
                    channel: post.channel,
                    likes: isLiked ? post.likes + 1 : post.likes - 1,
                    recasts: post.recasts,
                    replies: post.replies,
                    isLiked: isLiked,
                    isRecast: post.isRecast
                )
                updatedPosts[index] = newPost
            }
            
            let newFarcasterState = FarcasterState(
                selectedChannel: self.currentState.farcasterState.selectedChannel,
                posts: updatedPosts,
                channels: self.currentState.farcasterState.channels,
                isLoading: false
            )
            
            self.currentState = self.createUpdatedAppState(farcasterState: newFarcasterState)
            self.notifyStateChange()
        }
    }
    
    private func recastFarcasterPost(_ postId: String) {
        var updatedPosts = currentState.farcasterState.posts
        
        if let index = updatedPosts.firstIndex(where: { $0.id == postId }) {
            let post = updatedPosts[index]
            let newPost = FarcasterPost(
                id: post.id,
                author: post.author,
                content: post.content,
                timestamp: post.timestamp,
                channel: post.channel,
                likes: post.likes,
                recasts: post.isRecast ? post.recasts - 1 : post.recasts + 1,
                replies: post.replies,
                isLiked: post.isLiked,
                isRecast: !post.isRecast
            )
            updatedPosts[index] = newPost
        }
        
        let newFarcasterState = FarcasterState(
            selectedChannel: currentState.farcasterState.selectedChannel,
            posts: updatedPosts,
            channels: currentState.farcasterState.channels,
            isLoading: false
        )
        
        currentState = createUpdatedAppState(farcasterState: newFarcasterState)
    }
    
    private func replyToFarcasterPost(_ postId: String, _ replyContent: String) {
        var updatedPosts = currentState.farcasterState.posts
        
        // Increment reply count on original post
        if let index = updatedPosts.firstIndex(where: { $0.id == postId }) {
            let post = updatedPosts[index]
            let updatedPost = FarcasterPost(
                id: post.id,
                author: post.author,
                content: post.content,
                timestamp: post.timestamp,
                channel: post.channel,
                likes: post.likes,
                recasts: post.recasts,
                replies: post.replies + 1,
                isLiked: post.isLiked,
                isRecast: post.isRecast
            )
            updatedPosts[index] = updatedPost
        }
        
        // Create reply post
        let replyPost = FarcasterPost(
            id: UUID().uuidString,
            author: FarcasterUser(username: "you", displayName: "You", avatarURL: ""),
            content: replyContent,
            timestamp: Date(),
            channel: currentState.farcasterState.selectedChannel,
            likes: 0,
            recasts: 0,
            replies: 0,
            isLiked: false,
            isRecast: false
        )
        
        updatedPosts.append(replyPost)
        
        let newFarcasterState = FarcasterState(
            selectedChannel: currentState.farcasterState.selectedChannel,
            posts: updatedPosts,
            channels: currentState.farcasterState.channels,
            isLoading: false
        )
        
        currentState = createUpdatedAppState(farcasterState: newFarcasterState)
    }
    
    private func createFarcasterPost(_ content: String) {
        if let farcasterService = farcasterService {
            // Use real Farcaster API
            Task { [weak self] in
                do {
                    let result = try await farcasterService.postCast(text: content)
                    print("PlueCore: Posted cast successfully: \(result)")
                    
                    // Refresh the feed after posting
                    await self?.refreshFarcasterFeedReal()
                } catch {
                    print("PlueCore: Failed to post cast: \(error)")
                    // Fall back to mock behavior
                    self?.createMockFarcasterPost(content)
                }
            }
        } else {
            // Use mock behavior
            createMockFarcasterPost(content)
        }
    }
    
    private func createMockFarcasterPost(_ content: String) {
        let newPost = FarcasterPost(
            id: UUID().uuidString,
            author: FarcasterUser(username: "you", displayName: "You", avatarURL: ""),
            content: content,
            timestamp: Date(),
            channel: currentState.farcasterState.selectedChannel,
            likes: 0,
            recasts: 0,
            replies: 0,
            isLiked: false,
            isRecast: false
        )
        
        let updatedPosts = currentState.farcasterState.posts + [newPost]
        
        let newFarcasterState = FarcasterState(
            selectedChannel: currentState.farcasterState.selectedChannel,
            posts: updatedPosts,
            channels: currentState.farcasterState.channels,
            isLoading: false
        )
        
        currentState = createUpdatedAppState(farcasterState: newFarcasterState)
    }
    
    private func refreshFarcasterFeed() {
        if let farcasterService = farcasterService {
            // Use real Farcaster API
            Task { [weak self] in
                await self?.refreshFarcasterFeedReal()
            }
        } else {
            // Use mock behavior
            refreshFarcasterFeedMock()
        }
    }
    
    private func refreshFarcasterFeedReal() async {
        // Set loading state
        queue.async { [weak self] in
            guard let self = self else { return }
            
            let loadingState = FarcasterState(
                selectedChannel: self.currentState.farcasterState.selectedChannel,
                posts: self.currentState.farcasterState.posts,
                channels: self.currentState.farcasterState.channels,
                isLoading: true
            )
            
            self.currentState = self.createUpdatedAppState(farcasterState: loadingState)
            self.notifyStateChange()
        }
        
        // Fetch real data
        do {
            guard let farcasterService = farcasterService else { return }
            
            let casts = try await farcasterService.getCasts(limit: 25)
            let posts = farcasterService.convertToFarcasterPosts(casts)
            
            queue.async { [weak self] in
                guard let self = self else { return }
                
                let refreshedState = FarcasterState(
                    selectedChannel: self.currentState.farcasterState.selectedChannel,
                    posts: posts,
                    channels: self.currentState.farcasterState.channels,
                    isLoading: false
                )
                
                self.currentState = self.createUpdatedAppState(farcasterState: refreshedState)
                self.notifyStateChange()
            }
            
            print("PlueCore: Refreshed Farcaster feed with \(posts.count) posts")
        } catch {
            print("PlueCore: Failed to refresh Farcaster feed: \(error)")
            
            // Reset loading state on error
            queue.async { [weak self] in
                guard let self = self else { return }
                
                let refreshedState = FarcasterState(
                    selectedChannel: self.currentState.farcasterState.selectedChannel,
                    posts: self.currentState.farcasterState.posts,
                    channels: self.currentState.farcasterState.channels,
                    isLoading: false
                )
                
                self.currentState = self.createUpdatedAppState(farcasterState: refreshedState)
                self.notifyStateChange()
            }
        }
    }
    
    private func refreshFarcasterFeedMock() {
        // Set loading state
        let loadingState = FarcasterState(
            selectedChannel: currentState.farcasterState.selectedChannel,
            posts: currentState.farcasterState.posts,
            channels: currentState.farcasterState.channels,
            isLoading: true
        )
        
        currentState = createUpdatedAppState(farcasterState: loadingState)
        
        // Simulate network delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.queue.async {
                guard let self = self else { return }
                
                // Reset loading state
                let refreshedState = FarcasterState(
                    selectedChannel: self.currentState.farcasterState.selectedChannel,
                    posts: self.currentState.farcasterState.posts,
                    channels: self.currentState.farcasterState.channels,
                    isLoading: false
                )
                
                self.currentState = self.createUpdatedAppState(farcasterState: refreshedState)
                self.notifyStateChange()
            }
        }
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