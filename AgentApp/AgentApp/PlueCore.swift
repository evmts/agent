import Foundation

// MARK: - Core State Models (Immutable)

enum TabType: Int, CaseIterable {
    case prompt = 0
    case farcaster = 1
    case agent = 2
    case terminal = 3
    case web = 4
    case editor = 5
    case diff = 6
    case worktree = 7
}

struct AppState {
    let currentTab: TabType
    let isInitialized: Bool
    let errorMessage: String?
    let openAIAvailable: Bool
    let currentTheme: DesignSystem.Theme
    
    // Tab states
    let promptState: PromptState
    let terminalState: TerminalState
    let vimState: VimState
    let webState: WebState
    let editorState: EditorState
    let farcasterState: FarcasterState
    let agentState: AgentState
    
    static let initial = AppState(
        currentTab: .prompt,
        isInitialized: true,
        errorMessage: nil,
        openAIAvailable: false,
        currentTheme: .dark,
        promptState: PromptState.initial,
        terminalState: TerminalState.initial,
        vimState: VimState.initial,
        webState: WebState.initial,
        editorState: EditorState.initial,
        farcasterState: FarcasterState.initial,
        agentState: AgentState.initial
    )
}

struct PromptState {
    let conversations: [PromptConversation]
    let currentConversationIndex: Int
    let currentPromptContent: String
    let isProcessing: Bool
    
    static let initial = PromptState(
        conversations: [PromptConversation.initial],
        currentConversationIndex: 0,
        currentPromptContent: "# Your Prompt\n\nStart typing your prompt here. The live preview will update on the right.\n\nUse `:w` in the Vim buffer to send this prompt to the Chat tab.",
        isProcessing: false
    )
    
    var currentConversation: PromptConversation? {
        guard currentConversationIndex < conversations.count else { return nil }
        return conversations[currentConversationIndex]
    }
}

struct PromptConversation {
    let id: String
    let messages: [PromptMessage]
    let createdAt: Date
    let updatedAt: Date
    let associatedPromptContent: String?
    
    static let initial = PromptConversation(
        id: UUID().uuidString,
        messages: [
            PromptMessage(
                id: UUID().uuidString,
                content: "Welcome to the Prompt Engineering interface! Use the chat to refine your prompts and see them update in the vim buffer and preview.",
                type: .system,
                timestamp: Date(),
                promptSnapshot: nil
            )
        ],
        createdAt: Date(),
        updatedAt: Date(),
        associatedPromptContent: nil
    )
}

struct PromptMessage: Identifiable {
    let id: String
    let content: String
    let type: PromptMessageType
    let timestamp: Date
    let promptSnapshot: String? // Snapshot of prompt content when message was sent
}

enum PromptMessageType {
    case user
    case assistant
    case system
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
    let automation: WebAutomationState

    static let initial = WebState(
        currentURL: "https://www.apple.com",
        canGoBack: false,
        canGoForward: false,
        isLoading: false,
        isSecure: true,
        pageTitle: "",
        automation: WebAutomationState.initial
    )

    func withAutomation(_ automation: WebAutomationState) -> WebState {
        WebState(
            currentURL: currentURL,
            canGoBack: canGoBack,
            canGoForward: canGoForward,
            isLoading: isLoading,
            isSecure: isSecure,
            pageTitle: pageTitle,
            automation: automation
        )
    }
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

struct AgentState {
    let conversations: [AgentConversation]
    let currentConversationIndex: Int
    let isProcessing: Bool
    let currentWorkspace: GitWorktree?
    let availableWorktrees: [GitWorktree]
    let daggerSession: DaggerSession?
    let workflowQueue: [AgentWorkflow]
    let isExecutingWorkflow: Bool
    
    static let initial = AgentState(
        conversations: [AgentConversation.initial],
        currentConversationIndex: 0,
        isProcessing: false,
        currentWorkspace: nil,
        availableWorktrees: [],
        daggerSession: nil,
        workflowQueue: [],
        isExecutingWorkflow: false
    )
    
    var currentConversation: AgentConversation? {
        guard currentConversationIndex < conversations.count else { return nil }
        return conversations[currentConversationIndex]
    }
}

struct AgentConversation {
    let id: String
    let messages: [AgentMessage]
    let createdAt: Date
    let updatedAt: Date
    let associatedWorktree: String?
    
    static let initial = AgentConversation(
        id: UUID().uuidString,
        messages: [
            AgentMessage(
                id: UUID().uuidString,
                content: "Agent ready! I can help you with git worktrees, code execution in containers, and workflow automation.",
                type: .system,
                timestamp: Date(),
                metadata: nil
            )
        ],
        createdAt: Date(),
        updatedAt: Date(),
        associatedWorktree: nil
    )
}

struct AgentMessage: Identifiable {
    let id: String
    let content: String
    let type: AgentMessageType
    let timestamp: Date
    let metadata: AgentMessageMetadata?
}

enum AgentMessageType {
    case user
    case assistant
    case system
    case workflow
    case error
    case toolInvocation
    case toolResult
}

struct AgentMessageMetadata {
    let worktree: String?
    let workflow: String?
    let containerId: String?
    let exitCode: Int?
    let duration: TimeInterval?
    let browserTool: BrowserToolInvocation?
    let browserSnapshot: AccessibilitySnapshot?

    init(
        worktree: String? = nil,
        workflow: String? = nil,
        containerId: String? = nil,
        exitCode: Int? = nil,
        duration: TimeInterval? = nil,
        browserTool: BrowserToolInvocation? = nil,
        browserSnapshot: AccessibilitySnapshot? = nil
    ) {
        self.worktree = worktree
        self.workflow = workflow
        self.containerId = containerId
        self.exitCode = exitCode
        self.duration = duration
        self.browserTool = browserTool
        self.browserSnapshot = browserSnapshot
    }
}

struct GitWorktree: Identifiable {
    let id: String
    let path: String
    let branch: String
    let isMain: Bool
    let lastModified: Date
    let status: GitWorktreeStatus
    
    static let mockWorktrees: [GitWorktree] = [
        GitWorktree(
            id: "main",
            path: "/Users/user/plue",
            branch: "main",
            isMain: true,
            lastModified: Date().addingTimeInterval(-3600),
            status: .clean
        ),
        GitWorktree(
            id: "feature-branch",
            path: "/Users/user/plue-feature",
            branch: "feature/new-ui",
            isMain: false,
            lastModified: Date().addingTimeInterval(-1800),
            status: .modified
        )
    ]
}

enum GitWorktreeStatus {
    case clean
    case modified
    case untracked
    case conflicts
}

struct DaggerSession {
    let sessionId: String
    let port: Int
    let token: String
    let isConnected: Bool
    let startedAt: Date
}

struct AgentWorkflow {
    let id: String
    let name: String
    let description: String
    let steps: [WorkflowStep]
    let status: WorkflowStatus
    let createdAt: Date
    let startedAt: Date?
    let completedAt: Date?
}

struct WorkflowStep {
    let id: String
    let name: String
    let command: String
    let container: String?
    let dependencies: [String]
    let status: WorkflowStepStatus
}

enum WorkflowStatus {
    case pending
    case running
    case completed
    case failed
    case cancelled
}

enum WorkflowStepStatus {
    case pending
    case running
    case completed
    case failed
    case skipped
}

// MARK: - Events (Commands sent to core)

enum AppEvent {
    case tabSwitched(TabType)
    case themeToggled
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
    
    // Prompt events
    case promptMessageSent(String)
    case promptContentUpdated(String) // from vim buffer or preview
    case promptNewConversation
    case promptSelectConversation(Int)
    
    // Agent events
    case agentMessageSent(String)
    case agentNewConversation
    case agentSelectConversation(Int)
    case agentCreateWorktree(String, String) // branch, path
    case agentSwitchWorktree(String) // worktreeId
    case agentDeleteWorktree(String) // worktreeId
    case agentRefreshWorktrees
    case agentStartDaggerSession
    case agentStopDaggerSession
    case agentExecuteWorkflow(AgentWorkflow)
    case agentCancelWorkflow(String) // workflowId
    
    // AppleScript support events
    case chatMessageSent(String)
    case fileOpened(String)
    case fileSaved

    // Browser automation events
    case browserSnapshot
    case browserClick(ref: String)
    case browserType(ref: String, text: String)
    case browserScroll(direction: ScrollDirection, amount: Int)
    case browserExtract(ref: String)
    case browserScreenshot
    case browserConnect
    case browserDisconnect

    // Browser automation results
    case browserSnapshotComplete(AccessibilitySnapshot)
    case browserActionComplete(BrowserResult)
    case browserActionFailed(String)
}

// MARK: - Core Interface

protocol PlueCoreInterface {
    // State management
    func getCurrentState() -> AppState
    func handleEvent(_ event: AppEvent)
    func subscribe(callback: @escaping (AppState) -> Void)
    
    // Lifecycle
    func initialize() -> Bool
    func initialize(workingDirectory: String) -> Bool
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
        return initialize(workingDirectory: FileManager.default.currentDirectoryPath)
    }
    
    func initialize(workingDirectory: String) -> Bool {
        queue.sync {
            // Change to the specified working directory
            FileManager.default.changeCurrentDirectoryPath(workingDirectory)
            
            // Initialize core state with OpenAI availability
            currentState = AppState(
                currentTab: .prompt,
                isInitialized: true,
                errorMessage: nil,
                openAIAvailable: openAIService != nil,
                currentTheme: .dark,
                promptState: PromptState.initial,
                terminalState: TerminalState.initial,
                vimState: VimState.initial,
                webState: WebState.initial,
                editorState: EditorState.initial,
                farcasterState: FarcasterState.initial,
                agentState: AgentState.initial
            )
            
            print("PlueCore: Initialized with working directory: \(workingDirectory)")
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
        currentTheme: DesignSystem.Theme? = nil,
        errorMessage: String? = nil,
        promptState: PromptState? = nil,
        terminalState: TerminalState? = nil,
        vimState: VimState? = nil,
        webState: WebState? = nil,
        editorState: EditorState? = nil,
        farcasterState: FarcasterState? = nil,
        agentState: AgentState? = nil
    ) -> AppState {
        return AppState(
            currentTab: currentTab ?? self.currentState.currentTab,
            isInitialized: self.currentState.isInitialized,
            errorMessage: errorMessage ?? self.currentState.errorMessage,
            openAIAvailable: self.openAIService != nil,
            currentTheme: currentTheme ?? self.currentState.currentTheme,
            promptState: promptState ?? self.currentState.promptState,
            terminalState: terminalState ?? self.currentState.terminalState,
            vimState: vimState ?? self.currentState.vimState,
            webState: webState ?? self.currentState.webState,
            editorState: editorState ?? self.currentState.editorState,
            farcasterState: farcasterState ?? self.currentState.farcasterState,
            agentState: agentState ?? self.currentState.agentState
        )
    }
    
    // MARK: - Private Event Processing
    
    private func processEvent(_ event: AppEvent) {
        switch event {
        case .tabSwitched(let tab):
            currentState = createUpdatedAppState(currentTab: tab)
            
        case .themeToggled:
            let newTheme: DesignSystem.Theme = currentState.currentTheme == .dark ? .light : .dark
            currentState = createUpdatedAppState(currentTheme: newTheme)
            
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
            
        // Prompt events
        case .promptMessageSent(let message):
            processPromptMessage(message)
            
        case .promptContentUpdated(let content):
            updatePromptContent(content)
            
        case .promptNewConversation:
            createNewPromptConversation()
            
        case .promptSelectConversation(let index):
            selectPromptConversation(index)
            
        // Agent events
        case .agentMessageSent(let message):
            processAgentMessage(message)
            
        case .agentNewConversation:
            createNewAgentConversation()
            
        case .agentSelectConversation(let index):
            selectAgentConversation(index)
            
        case .agentCreateWorktree(let branch, let path):
            createWorktree(branch: branch, path: path)
            
        case .agentSwitchWorktree(let worktreeId):
            switchWorktree(worktreeId)
            
        case .agentDeleteWorktree(let worktreeId):
            deleteWorktree(worktreeId)
            
        case .agentRefreshWorktrees:
            refreshWorktrees()
            
        case .agentStartDaggerSession:
            startDaggerSession()
            
        case .agentStopDaggerSession:
            stopDaggerSession()
            
        case .agentExecuteWorkflow(let workflow):
            executeWorkflow(workflow)
            
        case .agentCancelWorkflow(let workflowId):
            cancelWorkflow(workflowId)
            
        // AppleScript support events
        case .chatMessageSent(let message):
            processPromptMessage(message) // Route to prompt messages

        case .fileOpened(let path):
            // For now, just log - could integrate with editor state later
            print("File opened: \(path)")

        case .fileSaved:
            // For now, just log - could integrate with editor state later
            print("File saved")

        // Browser automation events
        case .browserSnapshot:
            Task {
                await BrowserAutomationManager.shared.captureSnapshot()
            }

        case .browserClick(let ref):
            Task {
                do {
                    try await BrowserAutomationManager.shared.automation.click(ref: ref)
                } catch {
                    print("[PlueCore] Browser click failed: \(error)")
                }
            }

        case .browserType(let ref, let text):
            Task {
                do {
                    try await BrowserAutomationManager.shared.automation.type(ref: ref, text: text)
                } catch {
                    print("[PlueCore] Browser type failed: \(error)")
                }
            }

        case .browserScroll(let direction, let amount):
            Task {
                do {
                    try await BrowserAutomationManager.shared.automation.scroll(direction: direction, amount: amount)
                } catch {
                    print("[PlueCore] Browser scroll failed: \(error)")
                }
            }

        case .browserExtract(let ref):
            Task {
                do {
                    let text = try await BrowserAutomationManager.shared.automation.extractText(ref: ref)
                    print("[PlueCore] Extracted text: \(text)")
                } catch {
                    print("[PlueCore] Browser extract failed: \(error)")
                }
            }

        case .browserScreenshot:
            Task {
                do {
                    let data = try await BrowserAutomationManager.shared.automation.screenshot()
                    print("[PlueCore] Screenshot captured: \(data.count) bytes")
                } catch {
                    print("[PlueCore] Browser screenshot failed: \(error)")
                }
            }

        case .browserConnect:
            // Handled by WebView directly
            break

        case .browserDisconnect:
            // Handled by WebView directly
            break

        case .browserSnapshotComplete(let snapshot):
            let newAutomation = currentState.webState.automation.withSnapshot(snapshot)
            let newWebState = currentState.webState.withAutomation(newAutomation)
            currentState = createUpdatedAppState(webState: newWebState)

        case .browserActionComplete:
            // Log action completion
            break

        case .browserActionFailed(let error):
            print("[PlueCore] Browser action failed: \(error)")
        }
    }
    
    private func processChatMessage(_ message: String) {
        // Add user message
        let userMessage = PromptMessage(
            id: UUID().uuidString,
            content: message,
            type: .user,
            timestamp: Date(),
            promptSnapshot: nil
        )
        
        var conversations = currentState.promptState.conversations
        var currentConv = conversations[currentState.promptState.currentConversationIndex]
        currentConv = PromptConversation(
            id: currentConv.id,
            messages: currentConv.messages + [userMessage],
            createdAt: currentConv.createdAt,
            updatedAt: Date(),
            associatedPromptContent: currentConv.associatedPromptContent
        )
        conversations[currentState.promptState.currentConversationIndex] = currentConv
        
        // Update state with generation started
        let newPromptState = PromptState(
            conversations: conversations,
            currentConversationIndex: currentState.promptState.currentConversationIndex,
            currentPromptContent: currentState.promptState.currentPromptContent,
            isProcessing: true
        )
        
        currentState = createUpdatedAppState(promptState: newPromptState)
        
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
                return currentState.promptState.currentConversation 
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
            
            let aiMessage = PromptMessage(
                id: UUID().uuidString,
                content: content,
                type: .assistant,
                timestamp: Date(),
                promptSnapshot: nil
            )
            
            var conversations = self.currentState.promptState.conversations
            var currentConv = conversations[self.currentState.promptState.currentConversationIndex]
            currentConv = PromptConversation(
                id: currentConv.id,
                messages: currentConv.messages + [aiMessage],
                createdAt: currentConv.createdAt,
                updatedAt: Date(),
                associatedPromptContent: currentConv.associatedPromptContent
            )
            conversations[self.currentState.promptState.currentConversationIndex] = currentConv
            
            let newPromptState = PromptState(
                conversations: conversations,
                currentConversationIndex: self.currentState.promptState.currentConversationIndex,
                currentPromptContent: self.currentState.promptState.currentPromptContent,
                isProcessing: false
            )
            
            self.currentState = self.createUpdatedAppState(promptState: newPromptState)
            
            self.notifyStateChange()
        }
    }
    
    private func createNewConversation() {
        let newConv = PromptConversation(
            id: UUID().uuidString,
            messages: [
                PromptMessage(
                    id: UUID().uuidString,
                    content: "New conversation started. How can I help you?",
                    type: .assistant,
                    timestamp: Date(),
                    promptSnapshot: nil
                )
            ],
            createdAt: Date(),
            updatedAt: Date(),
            associatedPromptContent: nil
        )
        
        let conversations = currentState.promptState.conversations + [newConv]
        let newPromptState = PromptState(
            conversations: conversations,
            currentConversationIndex: conversations.count - 1,
            currentPromptContent: currentState.promptState.currentPromptContent,
            isProcessing: false
        )
        
        currentState = createUpdatedAppState(promptState: newPromptState)
    }
    
    private func selectConversation(_ index: Int) {
        guard index < currentState.promptState.conversations.count else { return }
        
        let newPromptState = PromptState(
            conversations: currentState.promptState.conversations,
            currentConversationIndex: index,
            currentPromptContent: currentState.promptState.currentPromptContent,
            isProcessing: false
        )
        
        currentState = createUpdatedAppState(promptState: newPromptState)
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
        let newBuffer = currentState.vimState.buffer
        let newCursor = currentState.vimState.cursor
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
            pageTitle: "Loading...",
            automation: currentState.webState.automation
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
                    pageTitle: "Loaded Page",
                    automation: self.currentState.webState.automation
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
            pageTitle: "Previous Page",
            automation: currentState.webState.automation
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
            pageTitle: "Next Page",
            automation: currentState.webState.automation
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
            pageTitle: "Reloading...",
            automation: currentState.webState.automation
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
        if farcasterService != nil {
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
    
    // MARK: - Prompt Event Handlers
    
    private func processPromptMessage(_ message: String) {
        // Add user message to conversation
        let userMessage = PromptMessage(
            id: UUID().uuidString,
            content: message,
            type: .user,
            timestamp: Date(),
            promptSnapshot: currentState.promptState.currentPromptContent
        )
        
        var conversations = currentState.promptState.conversations
        var currentConv = conversations[currentState.promptState.currentConversationIndex]
        currentConv = PromptConversation(
            id: currentConv.id,
            messages: currentConv.messages + [userMessage],
            createdAt: currentConv.createdAt,
            updatedAt: Date(),
            associatedPromptContent: currentConv.associatedPromptContent
        )
        conversations[currentState.promptState.currentConversationIndex] = currentConv
        
        // Update state with processing started
        let newPromptState = PromptState(
            conversations: conversations,
            currentConversationIndex: currentState.promptState.currentConversationIndex,
            currentPromptContent: currentState.promptState.currentPromptContent,
            isProcessing: true
        )
        
        currentState = createUpdatedAppState(promptState: newPromptState)
        
        // Generate prompt response
        Task { [weak self] in
            await self?.generatePromptResponse(for: message)
        }
    }
    
    private func generatePromptResponse(for input: String) async {
        // Simulate processing delay
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        let responseContent = generatePromptResponseContent(for: input)
        
        // Update state with response
        await updateStateWithPromptResponse(content: responseContent)
    }
    
    private func generatePromptResponseContent(for input: String) -> String {
        let lowercaseInput = input.lowercased()
        
        if lowercaseInput.contains("help") || lowercaseInput.contains("how") {
            return "I can help you refine your prompts! Try asking me to:\n• Make your prompt more specific\n• Add context or examples\n• Improve clarity or structure\n• Switch to Farcaster tab to post the prompt"
        } else if lowercaseInput.contains("improve") || lowercaseInput.contains("better") {
            return "To improve your prompt, consider:\n• Being more specific about desired output\n• Adding examples of what you want\n• Specifying the format or style\n• Including relevant context"
        } else if lowercaseInput.contains("update") || lowercaseInput.contains("change") {
            return "I can help update your prompt content. The vim buffer and preview will sync automatically. What changes would you like to make?"
        } else {
            return "I'm here to help you craft better prompts! The current prompt in the vim buffer will be used when you switch to other tabs or use the 'chat' button. How can I help you improve it?"
        }
    }
    
    private func updateStateWithPromptResponse(content: String) async {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            let promptMessage = PromptMessage(
                id: UUID().uuidString,
                content: content,
                type: .assistant,
                timestamp: Date(),
                promptSnapshot: self.currentState.promptState.currentPromptContent
            )
            
            var conversations = self.currentState.promptState.conversations
            var currentConv = conversations[self.currentState.promptState.currentConversationIndex]
            currentConv = PromptConversation(
                id: currentConv.id,
                messages: currentConv.messages + [promptMessage],
                createdAt: currentConv.createdAt,
                updatedAt: Date(),
                associatedPromptContent: currentConv.associatedPromptContent
            )
            conversations[self.currentState.promptState.currentConversationIndex] = currentConv
            
            let newPromptState = PromptState(
                conversations: conversations,
                currentConversationIndex: self.currentState.promptState.currentConversationIndex,
                currentPromptContent: self.currentState.promptState.currentPromptContent,
                isProcessing: false
            )
            
            self.currentState = self.createUpdatedAppState(promptState: newPromptState)
            
            self.notifyStateChange()
        }
    }
    
    private func updatePromptContent(_ content: String) {
        let newPromptState = PromptState(
            conversations: currentState.promptState.conversations,
            currentConversationIndex: currentState.promptState.currentConversationIndex,
            currentPromptContent: content,
            isProcessing: currentState.promptState.isProcessing
        )
        
        currentState = createUpdatedAppState(promptState: newPromptState)
    }
    
    private func createNewPromptConversation() {
        let newConv = PromptConversation(
            id: UUID().uuidString,
            messages: [
                PromptMessage(
                    id: UUID().uuidString,
                    content: "New prompt session started. How can I help you refine your prompt?",
                    type: .system,
                    timestamp: Date(),
                    promptSnapshot: nil
                )
            ],
            createdAt: Date(),
            updatedAt: Date(),
            associatedPromptContent: currentState.promptState.currentPromptContent
        )
        
        let conversations = currentState.promptState.conversations + [newConv]
        let newPromptState = PromptState(
            conversations: conversations,
            currentConversationIndex: conversations.count - 1,
            currentPromptContent: currentState.promptState.currentPromptContent,
            isProcessing: false
        )
        
        currentState = createUpdatedAppState(promptState: newPromptState)
    }
    
    private func selectPromptConversation(_ index: Int) {
        guard index < currentState.promptState.conversations.count else { return }
        
        let newPromptState = PromptState(
            conversations: currentState.promptState.conversations,
            currentConversationIndex: index,
            currentPromptContent: currentState.promptState.currentPromptContent,
            isProcessing: false
        )
        
        currentState = createUpdatedAppState(promptState: newPromptState)
    }
    
    // MARK: - Agent Event Handlers
    
    private func processAgentMessage(_ message: String) {
        // Add user message
        let userMessage = AgentMessage(
            id: UUID().uuidString,
            content: message,
            type: .user,
            timestamp: Date(),
            metadata: AgentMessageMetadata(
                worktree: currentState.agentState.currentWorkspace?.id,
                workflow: nil,
                containerId: nil,
                exitCode: nil,
                duration: nil
            )
        )
        
        var conversations = currentState.agentState.conversations
        var currentConv = conversations[currentState.agentState.currentConversationIndex]
        currentConv = AgentConversation(
            id: currentConv.id,
            messages: currentConv.messages + [userMessage],
            createdAt: currentConv.createdAt,
            updatedAt: Date(),
            associatedWorktree: currentConv.associatedWorktree
        )
        conversations[currentState.agentState.currentConversationIndex] = currentConv
        
        // Update state with processing started
        let newAgentState = AgentState(
            conversations: conversations,
            currentConversationIndex: currentState.agentState.currentConversationIndex,
            isProcessing: true,
            currentWorkspace: currentState.agentState.currentWorkspace,
            availableWorktrees: currentState.agentState.availableWorktrees,
            daggerSession: currentState.agentState.daggerSession,
            workflowQueue: currentState.agentState.workflowQueue,
            isExecutingWorkflow: currentState.agentState.isExecutingWorkflow
        )
        
        currentState = createUpdatedAppState(agentState: newAgentState)
        
        // Generate agent response
        Task { [weak self] in
            await self?.generateAgentResponse(for: message)
        }
    }
    
    private func generateAgentResponse(for input: String) async {
        // Simulate processing delay
        try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
        
        let responseContent = generateAgentResponseContent(for: input)
        
        // Update state with agent response
        await updateStateWithAgentResponse(content: responseContent, type: .assistant)
    }
    
    private func generateAgentResponseContent(for input: String) -> String {
        let lowercaseInput = input.lowercased()
        
        if lowercaseInput.contains("worktree") {
            return "I can help you with git worktrees! Use commands like 'create worktree <branch>' or 'list worktrees' to manage your parallel development environments."
        } else if lowercaseInput.contains("dagger") {
            return "Dagger integration allows me to execute workflows in containers. I can start a Dagger session and run isolated build/test processes for you."
        } else if lowercaseInput.contains("workflow") {
            return "I can create and execute custom workflows using Dagger. These run in containers for safety and reproducibility. What workflow would you like to create?"
        } else {
            return "I'm your development agent. I can help with git worktrees, container-based workflows via Dagger, and automating development tasks. What would you like me to help you with?"
        }
    }
    
    private func updateStateWithAgentResponse(content: String, type: AgentMessageType) async {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            let agentMessage = AgentMessage(
                id: UUID().uuidString,
                content: content,
                type: type,
                timestamp: Date(),
                metadata: AgentMessageMetadata(
                    worktree: self.currentState.agentState.currentWorkspace?.id,
                    workflow: nil,
                    containerId: nil,
                    exitCode: nil,
                    duration: nil
                )
            )
            
            var conversations = self.currentState.agentState.conversations
            var currentConv = conversations[self.currentState.agentState.currentConversationIndex]
            currentConv = AgentConversation(
                id: currentConv.id,
                messages: currentConv.messages + [agentMessage],
                createdAt: currentConv.createdAt,
                updatedAt: Date(),
                associatedWorktree: currentConv.associatedWorktree
            )
            conversations[self.currentState.agentState.currentConversationIndex] = currentConv
            
            let newAgentState = AgentState(
                conversations: conversations,
                currentConversationIndex: self.currentState.agentState.currentConversationIndex,
                isProcessing: false,
                currentWorkspace: self.currentState.agentState.currentWorkspace,
                availableWorktrees: self.currentState.agentState.availableWorktrees,
                daggerSession: self.currentState.agentState.daggerSession,
                workflowQueue: self.currentState.agentState.workflowQueue,
                isExecutingWorkflow: self.currentState.agentState.isExecutingWorkflow
            )
            
            self.currentState = self.createUpdatedAppState(agentState: newAgentState)
            
            self.notifyStateChange()
        }
    }
    
    private func createNewAgentConversation() {
        let newConv = AgentConversation(
            id: UUID().uuidString,
            messages: [
                AgentMessage(
                    id: UUID().uuidString,
                    content: "New agent session started. How can I help you with development workflows?",
                    type: .system,
                    timestamp: Date(),
                    metadata: nil
                )
            ],
            createdAt: Date(),
            updatedAt: Date(),
            associatedWorktree: currentState.agentState.currentWorkspace?.id
        )
        
        let conversations = currentState.agentState.conversations + [newConv]
        let newAgentState = AgentState(
            conversations: conversations,
            currentConversationIndex: conversations.count - 1,
            isProcessing: false,
            currentWorkspace: currentState.agentState.currentWorkspace,
            availableWorktrees: currentState.agentState.availableWorktrees,
            daggerSession: currentState.agentState.daggerSession,
            workflowQueue: currentState.agentState.workflowQueue,
            isExecutingWorkflow: currentState.agentState.isExecutingWorkflow
        )
        
        currentState = createUpdatedAppState(agentState: newAgentState)
    }
    
    private func selectAgentConversation(_ index: Int) {
        guard index < currentState.agentState.conversations.count else { return }
        
        let newAgentState = AgentState(
            conversations: currentState.agentState.conversations,
            currentConversationIndex: index,
            isProcessing: false,
            currentWorkspace: currentState.agentState.currentWorkspace,
            availableWorktrees: currentState.agentState.availableWorktrees,
            daggerSession: currentState.agentState.daggerSession,
            workflowQueue: currentState.agentState.workflowQueue,
            isExecutingWorkflow: currentState.agentState.isExecutingWorkflow
        )
        
        currentState = createUpdatedAppState(agentState: newAgentState)
    }
    
    private func createWorktree(branch: String, path: String) {
        // Mock implementation - in real app would call git worktree add
        let newWorktree = GitWorktree(
            id: UUID().uuidString,
            path: path,
            branch: branch,
            isMain: false,
            lastModified: Date(),
            status: .clean
        )
        
        let updatedWorktrees = currentState.agentState.availableWorktrees + [newWorktree]
        
        let newAgentState = AgentState(
            conversations: currentState.agentState.conversations,
            currentConversationIndex: currentState.agentState.currentConversationIndex,
            isProcessing: false,
            currentWorkspace: newWorktree,
            availableWorktrees: updatedWorktrees,
            daggerSession: currentState.agentState.daggerSession,
            workflowQueue: currentState.agentState.workflowQueue,
            isExecutingWorkflow: currentState.agentState.isExecutingWorkflow
        )
        
        currentState = createUpdatedAppState(agentState: newAgentState)
        
        // Add system message about worktree creation
        Task { [weak self] in
            await self?.updateStateWithAgentResponse(
                content: "Created new worktree '\\(branch)' at \\(path)",
                type: .system
            )
        }
    }
    
    private func switchWorktree(_ worktreeId: String) {
        guard let worktree = currentState.agentState.availableWorktrees.first(where: { $0.id == worktreeId }) else {
            return
        }
        
        let newAgentState = AgentState(
            conversations: currentState.agentState.conversations,
            currentConversationIndex: currentState.agentState.currentConversationIndex,
            isProcessing: false,
            currentWorkspace: worktree,
            availableWorktrees: currentState.agentState.availableWorktrees,
            daggerSession: currentState.agentState.daggerSession,
            workflowQueue: currentState.agentState.workflowQueue,
            isExecutingWorkflow: currentState.agentState.isExecutingWorkflow
        )
        
        currentState = createUpdatedAppState(agentState: newAgentState)
        
        // Add system message about worktree switch
        Task { [weak self] in
            await self?.updateStateWithAgentResponse(
                content: "Switched to worktree '\\(worktree.branch)' at \\(worktree.path)",
                type: .system
            )
        }
    }
    
    private func deleteWorktree(_ worktreeId: String) {
        let updatedWorktrees = currentState.agentState.availableWorktrees.filter { $0.id != worktreeId }
        let currentWorkspace = currentState.agentState.currentWorkspace?.id == worktreeId ? nil : currentState.agentState.currentWorkspace
        
        let newAgentState = AgentState(
            conversations: currentState.agentState.conversations,
            currentConversationIndex: currentState.agentState.currentConversationIndex,
            isProcessing: false,
            currentWorkspace: currentWorkspace,
            availableWorktrees: updatedWorktrees,
            daggerSession: currentState.agentState.daggerSession,
            workflowQueue: currentState.agentState.workflowQueue,
            isExecutingWorkflow: currentState.agentState.isExecutingWorkflow
        )
        
        currentState = createUpdatedAppState(agentState: newAgentState)
        
        // Add system message about worktree deletion
        Task { [weak self] in
            await self?.updateStateWithAgentResponse(
                content: "Deleted worktree with ID: \\(worktreeId)",
                type: .system
            )
        }
    }
    
    private func refreshWorktrees() {
        // Mock implementation - would scan git worktrees in real app
        let mockWorktrees = GitWorktree.mockWorktrees
        
        let newAgentState = AgentState(
            conversations: currentState.agentState.conversations,
            currentConversationIndex: currentState.agentState.currentConversationIndex,
            isProcessing: false,
            currentWorkspace: currentState.agentState.currentWorkspace,
            availableWorktrees: mockWorktrees,
            daggerSession: currentState.agentState.daggerSession,
            workflowQueue: currentState.agentState.workflowQueue,
            isExecutingWorkflow: currentState.agentState.isExecutingWorkflow
        )
        
        currentState = createUpdatedAppState(agentState: newAgentState)
    }
    
    private func startDaggerSession() {
        // Mock Dagger session - in real app would call `dagger engine` and capture port/token
        let session = DaggerSession(
            sessionId: UUID().uuidString,
            port: 8080,
            token: "mock-token-\(UUID().uuidString)",
            isConnected: true,
            startedAt: Date()
        )
        
        let newAgentState = AgentState(
            conversations: currentState.agentState.conversations,
            currentConversationIndex: currentState.agentState.currentConversationIndex,
            isProcessing: false,
            currentWorkspace: currentState.agentState.currentWorkspace,
            availableWorktrees: currentState.agentState.availableWorktrees,
            daggerSession: session,
            workflowQueue: currentState.agentState.workflowQueue,
            isExecutingWorkflow: currentState.agentState.isExecutingWorkflow
        )
        
        currentState = createUpdatedAppState(agentState: newAgentState)
        
        // Add system message about Dagger session
        Task { [weak self] in
            await self?.updateStateWithAgentResponse(
                content: "Started Dagger session on port \\(session.port). Ready for container workflows.",
                type: .system
            )
        }
    }
    
    private func stopDaggerSession() {
        let newAgentState = AgentState(
            conversations: currentState.agentState.conversations,
            currentConversationIndex: currentState.agentState.currentConversationIndex,
            isProcessing: false,
            currentWorkspace: currentState.agentState.currentWorkspace,
            availableWorktrees: currentState.agentState.availableWorktrees,
            daggerSession: nil,
            workflowQueue: currentState.agentState.workflowQueue,
            isExecutingWorkflow: currentState.agentState.isExecutingWorkflow
        )
        
        currentState = createUpdatedAppState(agentState: newAgentState)
        
        // Add system message about Dagger session stop
        Task { [weak self] in
            await self?.updateStateWithAgentResponse(
                content: "Stopped Dagger session. Container workflows disabled.",
                type: .system
            )
        }
    }
    
    private func executeWorkflow(_ workflow: AgentWorkflow) {
        // Mock workflow execution
        let updatedWorkflow = AgentWorkflow(
            id: workflow.id,
            name: workflow.name,
            description: workflow.description,
            steps: workflow.steps,
            status: .running,
            createdAt: workflow.createdAt,
            startedAt: Date(),
            completedAt: nil
        )
        
        let newAgentState = AgentState(
            conversations: currentState.agentState.conversations,
            currentConversationIndex: currentState.agentState.currentConversationIndex,
            isProcessing: false,
            currentWorkspace: currentState.agentState.currentWorkspace,
            availableWorktrees: currentState.agentState.availableWorktrees,
            daggerSession: currentState.agentState.daggerSession,
            workflowQueue: [updatedWorkflow],
            isExecutingWorkflow: true
        )
        
        currentState = createUpdatedAppState(agentState: newAgentState)
        
        // Simulate workflow execution
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            await self?.completeWorkflow(workflow.id)
        }
    }
    
    private func completeWorkflow(_ workflowId: String) async {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            let newAgentState = AgentState(
                conversations: self.currentState.agentState.conversations,
                currentConversationIndex: self.currentState.agentState.currentConversationIndex,
                isProcessing: false,
                currentWorkspace: self.currentState.agentState.currentWorkspace,
                availableWorktrees: self.currentState.agentState.availableWorktrees,
                daggerSession: self.currentState.agentState.daggerSession,
                workflowQueue: [],
                isExecutingWorkflow: false
            )
            
            self.currentState = self.createUpdatedAppState(agentState: newAgentState)
            self.notifyStateChange()
        }
        
        // Add completion message
        await updateStateWithAgentResponse(
            content: "Workflow completed successfully! All steps executed in container environment.",
            type: .workflow
        )
    }
    
    private func cancelWorkflow(_ workflowId: String) {
        let newAgentState = AgentState(
            conversations: currentState.agentState.conversations,
            currentConversationIndex: currentState.agentState.currentConversationIndex,
            isProcessing: false,
            currentWorkspace: currentState.agentState.currentWorkspace,
            availableWorktrees: currentState.agentState.availableWorktrees,
            daggerSession: currentState.agentState.daggerSession,
            workflowQueue: [],
            isExecutingWorkflow: false
        )
        
        currentState = createUpdatedAppState(agentState: newAgentState)
        
        // Add cancellation message
        Task { [weak self] in
            await self?.updateStateWithAgentResponse(
                content: "Workflow cancelled by user request.",
                type: .system
            )
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
    static let shared: PlueCoreInterface = LivePlueCore()
    
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