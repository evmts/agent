import Foundation
import libplue

// MARK: - FFI Function Declarations

@_silgen_name("plue_init")
func plue_init() -> Int32

@_silgen_name("plue_deinit")
func plue_deinit()

@_silgen_name("plue_get_state")
func plue_get_state() -> CAppState

@_silgen_name("plue_free_state")
func plue_free_state(_ state: CAppState)

@_silgen_name("plue_process_event")
func plue_process_event(_ eventType: Int32, _ jsonData: UnsafePointer<CChar>?) -> Int32

@_silgen_name("plue_free_string")
func plue_free_string(_ str: UnsafePointer<CChar>)

// Update C function import
@_silgen_name("plue_register_state_callback")
func plue_register_state_callback(_ callback: @convention(c) (UnsafeMutableRawPointer?) -> Void, _ context: UnsafeMutableRawPointer?)

// MARK: - Live FFI Implementation

class LivePlueCore: PlueCoreInterface {
    private var stateCallbacks: [(AppState) -> Void] = []
    private let queue = DispatchQueue(label: "plue.core.live", qos: .userInteractive)
    
    init() {
        // Initialize the Zig core
        let result = plue_init()
        if result != 0 {
            print("LivePlueCore: Failed to initialize Zig core: \(result)")
        } else {
            print("LivePlueCore: Successfully initialized with Zig FFI")
            
            // Get an opaque pointer to this instance of the class
            let context = Unmanaged.passUnretained(self).toOpaque()
            
            // Register the callback, passing the context pointer
            plue_register_state_callback(Self.stateUpdateCallback, context)
        }
    }
    
    deinit {
        plue_deinit()
    }
    
    // The C callback is now a static function that receives the context
    private static let stateUpdateCallback: @convention(c) (UnsafeMutableRawPointer?) -> Void = { context in
        // Ensure context is not nil
        guard let context = context else { return }
        
        // Reconstitute the LivePlueCore instance from the opaque pointer
        let instance = Unmanaged<LivePlueCore>.fromOpaque(context).takeUnretainedValue()
        
        // Call the instance method to notify subscribers
        instance.queue.async {
            instance.notifyStateChange()
        }
    }
    
    func getCurrentState() -> AppState {
        return queue.sync {
            return fetchStateFromZig() ?? AppState.initial
        }
    }
    
    func handleEvent(_ event: AppEvent) {
        queue.async {
            self.sendEventToZig(event)
            // State change notification will be triggered by Zig via callback
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
        plue_deinit()
    }
    
    // MARK: - Private Methods
    
    private func fetchStateFromZig() -> AppState? {
        let cState = plue_get_state()
        defer { plue_free_state(cState) }
        
        // Convert C strings to Swift strings safely
        let errorMessage = cState.error_message != nil && String(cString: cState.error_message).isEmpty == false 
            ? String(cString: cState.error_message) 
            : nil
            
        // Create prompt state
        let promptState = PromptState(
            conversations: PromptState.initial.conversations,
            currentConversationIndex: PromptState.initial.currentConversationIndex,
            currentPromptContent: String(cString: cState.prompt.current_content),
            isProcessing: cState.prompt.processing
        )
        
        // Create terminal state
        let terminalState = TerminalState(
            buffer: Array(repeating: Array(repeating: CoreTerminalCell.empty, count: Int(cState.terminal.cols)), count: Int(cState.terminal.rows)),
            cursor: CursorPosition(row: 0, col: 0),
            dimensions: TerminalDimensions(rows: Int(cState.terminal.rows), cols: Int(cState.terminal.cols)),
            isConnected: cState.terminal.is_running,
            currentCommand: String(cString: cState.terminal.content),
            needsRedraw: false
        )
        
        // Create web state
        let webState = WebState(
            currentURL: String(cString: cState.web.current_url),
            canGoBack: cState.web.can_go_back,
            canGoForward: cState.web.can_go_forward,
            isLoading: cState.web.is_loading,
            isSecure: String(cString: cState.web.current_url).hasPrefix("https://"),
            pageTitle: String(cString: cState.web.page_title)
        )
        
        // Create vim state
        let vimMode: CoreVimMode
        switch cState.vim.mode {
        case VimModeNormal: vimMode = .normal
        case VimModeInsert: vimMode = .insert
        case VimModeVisual: vimMode = .visual
        case VimModeCommand: vimMode = .command
        default: vimMode = .normal
        }
        
        let vimState = VimState(
            mode: vimMode,
            buffer: String(cString: cState.vim.content).components(separatedBy: "\n"),
            cursor: CursorPosition(row: Int(cState.vim.cursor_row), col: Int(cState.vim.cursor_col)),
            statusLine: String(cString: cState.vim.status_line),
            visualSelection: nil
        )
        
        // Create agent state
        var agentState = AgentState.initial
        agentState = AgentState(
            conversations: agentState.conversations,
            currentConversationIndex: agentState.currentConversationIndex,
            isProcessing: cState.agent.processing,
            currentWorkspace: agentState.currentWorkspace,
            availableWorktrees: agentState.availableWorktrees,
            daggerSession: cState.agent.dagger_connected ? agentState.daggerSession : nil,
            workflowQueue: agentState.workflowQueue,
            isExecutingWorkflow: agentState.isExecutingWorkflow
        )
        
        // Map tab type
        let tabType: TabType
        switch cState.current_tab {
        case TabTypePrompt: tabType = .prompt
        case TabTypeFarcaster: tabType = .farcaster
        case TabTypeAgent: tabType = .agent
        case TabTypeTerminal: tabType = .terminal
        case TabTypeWeb: tabType = .web
        case TabTypeEditor: tabType = .editor
        case TabTypeDiff: tabType = .diff
        case TabTypeWorktree: tabType = .worktree
        default: tabType = .prompt
        }
        
        // Map theme
        let theme: DesignSystem.Theme = cState.current_theme == ThemeDark ? .dark : .light
        
        return AppState(
            currentTab: tabType,
            isInitialized: cState.is_initialized,
            errorMessage: errorMessage,
            openAIAvailable: cState.openai_available,
            currentTheme: theme,
            promptState: promptState,
            terminalState: terminalState,
            vimState: vimState,
            webState: webState,
            editorState: EditorState.initial,
            farcasterState: FarcasterState.initial,
            agentState: agentState
        )
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

