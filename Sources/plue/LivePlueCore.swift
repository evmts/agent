import Foundation

// MARK: - FFI Function Declarations

@_silgen_name("plue_init")
func plue_init() -> Int32

@_silgen_name("plue_deinit")
func plue_deinit()

@_silgen_name("plue_get_state")
func plue_get_state() -> UnsafePointer<CChar>?

@_silgen_name("plue_process_event")
func plue_process_event(_ eventType: Int32, _ jsonData: UnsafePointer<CChar>?) -> Int32

@_silgen_name("plue_free_string")
func plue_free_string(_ str: UnsafePointer<CChar>)

// MARK: - Live FFI Implementation

class LivePlueCore: PlueCoreInterface {
    private var stateCallbacks: [(AppState) -> Void] = []
    private let queue = DispatchQueue(label: "plue.core.live", qos: .userInteractive)
    private var pollTimer: Timer?
    
    init() {
        // Initialize the Zig core
        let result = plue_init()
        if result != 0 {
            print("LivePlueCore: Failed to initialize Zig core: \(result)")
        } else {
            print("LivePlueCore: Successfully initialized with Zig FFI")
        }
        
        // Start polling for state changes
        startStatePolling()
    }
    
    deinit {
        stopStatePolling()
        plue_deinit()
    }
    
    func getCurrentState() -> AppState {
        return queue.sync {
            return fetchStateFromZig() ?? AppState.initial
        }
    }
    
    func handleEvent(_ event: AppEvent) {
        queue.async {
            self.sendEventToZig(event)
            self.notifyStateChange()
        }
    }
    
    func subscribe(callback: @escaping (AppState) -> Void) {
        queue.async {
            self.stateCallbacks.append(callback)
            // Send current state immediately
            if let state = self.fetchStateFromZig() {
                DispatchQueue.main.async {
                    callback(state)
                }
            }
        }
    }
    
    func initialize() -> Bool {
        return initialize(workingDirectory: FileManager.default.currentDirectoryPath)
    }
    
    func initialize(workingDirectory: String) -> Bool {
        // Already initialized in init
        return true
    }
    
    func shutdown() {
        stopStatePolling()
        plue_deinit()
    }
    
    // MARK: - Private Methods
    
    private func startStatePolling() {
        // Poll for state changes every 100ms
        // In a real implementation, we'd use a more efficient notification system
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            self.queue.async {
                self.notifyStateChange()
            }
        }
    }
    
    private func stopStatePolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
    
    private func fetchStateFromZig() -> AppState? {
        guard let statePtr = plue_get_state() else {
            print("LivePlueCore: Failed to get state from Zig")
            return nil
        }
        
        defer { plue_free_string(statePtr) }
        
        let stateJson = String(cString: statePtr)
        
        guard let data = stateJson.data(using: .utf8) else {
            print("LivePlueCore: Failed to convert state JSON to data")
            return nil
        }
        
        do {
            let zigState = try JSONDecoder().decode(ZigAppState.self, from: data)
            return zigState.toAppState()
        } catch {
            print("LivePlueCore: Failed to decode state JSON: \(error)")
            print("LivePlueCore: JSON was: \(stateJson)")
            return nil
        }
    }
    
    private func sendEventToZig(_ event: AppEvent) {
        let eventType = eventTypeFromAppEvent(event)
        let eventData = eventDataFromAppEvent(event)
        
        var result: Int32 = 0
        if let data = eventData {
            data.withCString { cString in
                result = plue_process_event(eventType, cString)
            }
        } else {
            result = plue_process_event(eventType, nil)
        }
        
        if result != 0 {
            print("LivePlueCore: Failed to process event: \(event)")
        }
    }
    
    private func notifyStateChange() {
        guard let state = fetchStateFromZig() else { return }
        
        DispatchQueue.main.async {
            for callback in self.stateCallbacks {
                callback(state)
            }
        }
    }
    
    private func eventTypeFromAppEvent(_ event: AppEvent) -> Int32 {
        switch event {
        case .tabSwitched: return 0
        case .themeToggled: return 1
        case .terminalInput: return 2
        case .terminalResize: return 3
        case .vimKeypress: return 4
        case .vimSetContent: return 5
        case .webNavigate: return 6
        case .webGoBack: return 7
        case .webGoForward: return 8
        case .webReload: return 9
        case .editorContentChanged: return 10
        case .editorSave: return 11
        case .farcasterSelectChannel: return 12
        case .farcasterLikePost: return 13
        case .farcasterRecastPost: return 14
        case .farcasterReplyToPost: return 15
        case .farcasterCreatePost: return 16
        case .farcasterRefreshFeed: return 17
        case .promptMessageSent: return 18
        case .promptContentUpdated: return 19
        case .promptNewConversation: return 20
        case .promptSelectConversation: return 21
        case .agentMessageSent: return 22
        case .agentNewConversation: return 23
        case .agentSelectConversation: return 24
        case .agentCreateWorktree: return 25
        case .agentSwitchWorktree: return 26
        case .agentDeleteWorktree: return 27
        case .agentRefreshWorktrees: return 28
        case .agentStartDaggerSession: return 29
        case .agentStopDaggerSession: return 30
        case .agentExecuteWorkflow: return 31
        case .agentCancelWorkflow: return 32
        case .chatMessageSent: return 33
        case .fileOpened: return 34
        case .fileSaved: return 35
        }
    }
    
    private func eventDataFromAppEvent(_ event: AppEvent) -> String? {
        switch event {
        case .tabSwitched(let tab):
            return "\(tab.rawValue)"
        case .terminalInput(let input):
            return input
        case .terminalResize(let rows, let cols):
            return "{\"rows\":\(rows),\"cols\":\(cols)}"
        case .vimKeypress(let key, let modifiers):
            return "{\"key\":\"\(key)\",\"modifiers\":\(modifiers)}"
        case .vimSetContent(let content):
            return content
        case .webNavigate(let url):
            return url
        case .editorContentChanged(let content):
            return content
        case .farcasterSelectChannel(let channel):
            return channel
        case .farcasterLikePost(let postId):
            return postId
        case .farcasterRecastPost(let postId):
            return postId
        case .farcasterReplyToPost(let postId, let reply):
            return "{\"postId\":\"\(postId)\",\"reply\":\"\(reply)\"}"
        case .farcasterCreatePost(let content):
            return content
        case .promptMessageSent(let message):
            return message
        case .promptContentUpdated(let content):
            return content
        case .promptSelectConversation(let index):
            return "\(index)"
        case .agentMessageSent(let message):
            return message
        case .agentSelectConversation(let index):
            return "\(index)"
        case .agentCreateWorktree(let branch, let path):
            return "{\"branch\":\"\(branch)\",\"path\":\"\(path)\"}"
        case .agentSwitchWorktree(let id):
            return id
        case .agentDeleteWorktree(let id):
            return id
        case .agentExecuteWorkflow(let workflow):
            // For now, just return the workflow ID
            return workflow.id
        case .agentCancelWorkflow(let id):
            return id
        case .chatMessageSent(let message):
            return message
        case .fileOpened(let path):
            return path
        default:
            return nil
        }
    }
}

// MARK: - Zig State Decoding

private struct ZigAppState: Decodable {
    let current_tab: Int
    let is_initialized: Bool
    let error_message: String?
    let openai_available: Bool
    let current_theme: Int
    let prompt_processing: Bool
    let prompt_current_content: String
    let terminal_rows: Int
    let terminal_cols: Int
    let terminal_content: String
    let agent_processing: Bool
    let agent_dagger_connected: Bool
    
    func toAppState() -> AppState {
        // For now, create a minimal state with the core values
        // In a full implementation, we'd map all the nested states
        var promptState = PromptState.initial
        promptState = PromptState(
            conversations: promptState.conversations,
            currentConversationIndex: promptState.currentConversationIndex,
            currentPromptContent: prompt_current_content,
            isProcessing: prompt_processing
        )
        
        let terminalState = TerminalState(
            buffer: Array(repeating: Array(repeating: CoreTerminalCell.empty, count: terminal_cols), count: terminal_rows),
            cursor: CursorPosition(row: 0, col: 0),
            dimensions: TerminalDimensions(rows: terminal_rows, cols: terminal_cols),
            isConnected: true,
            currentCommand: "",
            needsRedraw: false
        )
        
        var agentState = AgentState.initial
        agentState = AgentState(
            conversations: agentState.conversations,
            currentConversationIndex: agentState.currentConversationIndex,
            isProcessing: agent_processing,
            currentWorkspace: agentState.currentWorkspace,
            availableWorktrees: agentState.availableWorktrees,
            daggerSession: agent_dagger_connected ? agentState.daggerSession : nil,
            workflowQueue: agentState.workflowQueue,
            isExecutingWorkflow: agentState.isExecutingWorkflow
        )
        
        return AppState(
            currentTab: TabType(rawValue: current_tab) ?? .prompt,
            isInitialized: is_initialized,
            errorMessage: error_message,
            openAIAvailable: openai_available,
            currentTheme: current_theme == 0 ? .dark : .light,
            promptState: promptState,
            terminalState: terminalState,
            vimState: VimState.initial,
            webState: WebState.initial,
            editorState: EditorState.initial,
            farcasterState: FarcasterState.initial,
            agentState: agentState
        )
    }
}