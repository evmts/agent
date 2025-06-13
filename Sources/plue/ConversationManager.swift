import Foundation
import SwiftUI

// MARK: - Conversation Manager
class ConversationManager: ObservableObject {
    @Published var currentChatIndex: Int = 0
    @Published var currentResponseIndex: Int = -1
    @Published var chats: [Chat] = []
    @Published var isViewingResponse: Bool = false
    @Published var chatSlideOffset: CGFloat = 0
    @Published var isAnimatingSlide: Bool = false
    
    private let conversationFolder: String
    private let fileManager = FileManager.default
    
    init() {
        let tempDir = NSTemporaryDirectory()
        conversationFolder = tempDir + "plue_conversations_\(UUID().uuidString)/"
        createConversationFolder()
        createInitialChat()
    }
    
    private func createInitialChat() {
        let initialChat = Chat(id: UUID().uuidString, title: "Chat 1", responses: [])
        chats.append(initialChat)
    }
    
    private func createConversationFolder() {
        try? fileManager.createDirectory(atPath: conversationFolder, withIntermediateDirectories: true)
    }
    
    // MARK: - Message Management
    func addUserMessage(_ content: String) {
        guard currentChatIndex < chats.count else { return }
        
        let messageId = UUID().uuidString
        let chatId = chats[currentChatIndex].id
        let filePath = conversationFolder + "\(chatId)_user_\(messageId).md"
        
        // Save user message to file
        try? content.write(toFile: filePath, atomically: true, encoding: .utf8)
        
        // Don't add to responses array - user messages are persisted but not displayed
    }
    
    func addAIResponse(_ content: String) {
        guard currentChatIndex < chats.count else { return }
        
        let messageId = UUID().uuidString
        let chatId = chats[currentChatIndex].id
        let filePath = conversationFolder + "\(chatId)_ai_\(messageId).md"
        
        // Save AI response to file
        try? content.write(toFile: filePath, atomically: true, encoding: .utf8)
        
        // Create response object
        let response = ConversationResponse(
            id: messageId,
            content: content,
            filePath: filePath,
            timestamp: Date()
        )
        
        chats[currentChatIndex].responses.append(response)
        currentResponseIndex = chats[currentChatIndex].responses.count - 1
    }
    
    // MARK: - Navigation
    func navigateUp() -> Bool {
        guard currentChatIndex < chats.count else { return false }
        let responses = chats[currentChatIndex].responses
        guard !responses.isEmpty else { return false }
        
        if !isViewingResponse {
            // First time navigating up - go to latest response
            currentResponseIndex = responses.count - 1
            isViewingResponse = true
            return true
        } else if currentResponseIndex > 0 {
            // Navigate to previous response
            currentResponseIndex -= 1
            return true
        }
        return false
    }
    
    func navigateDown() -> Bool {
        guard currentChatIndex < chats.count else { return false }
        let responses = chats[currentChatIndex].responses
        guard !responses.isEmpty else { return false }
        
        if !isViewingResponse {
            // First time navigating - go to first response
            currentResponseIndex = 0
            isViewingResponse = true
            return true
        } else if currentResponseIndex < responses.count - 1 {
            // Navigate to next response
            currentResponseIndex += 1
            return true
        }
        return false
    }
    
    func navigateToPreviousChat() {
        guard currentChatIndex > 0 else { return }
        slideToChat(newIndex: currentChatIndex - 1, direction: .left)
    }
    
    func navigateToNextChat() {
        if currentChatIndex < chats.count - 1 {
            slideToChat(newIndex: currentChatIndex + 1, direction: .right)
        } else {
            // Create new chat
            createNewChat()
            slideToChat(newIndex: chats.count - 1, direction: .right)
        }
    }
    
    private func slideToChat(newIndex: Int, direction: SlideDirection) {
        guard !isAnimatingSlide else { return }
        
        isAnimatingSlide = true
        let slideDistance: CGFloat = direction == .left ? 800 : -800
        
        withAnimation(.easeInOut(duration: 0.3)) {
            chatSlideOffset = slideDistance
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.currentChatIndex = newIndex
            self.chatSlideOffset = -slideDistance
            self.updateCurrentResponseIndex()
            
            withAnimation(.easeInOut(duration: 0.15)) {
                self.chatSlideOffset = 0
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.isAnimatingSlide = false
            }
        }
    }
    
    private func createNewChat() {
        let newChat = Chat(id: UUID().uuidString, title: "Chat \(chats.count + 1)", responses: [])
        chats.append(newChat)
    }
    
    private func updateCurrentResponseIndex() {
        guard currentChatIndex < chats.count else { return }
        let responses = chats[currentChatIndex].responses
        currentResponseIndex = responses.isEmpty ? -1 : responses.count - 1
        isViewingResponse = false
    }
    
    func exitResponseView() {
        isViewingResponse = false
        updateCurrentResponseIndex()
    }
    
    // MARK: - Current Response
    var currentResponse: ConversationResponse? {
        guard currentChatIndex < chats.count else { return nil }
        let responses = chats[currentChatIndex].responses
        guard currentResponseIndex >= 0 && currentResponseIndex < responses.count else { return nil }
        return responses[currentResponseIndex]
    }
    
    var currentChat: Chat? {
        guard currentChatIndex < chats.count else { return nil }
        return chats[currentChatIndex]
    }
    
    // MARK: - File Operations
    func updateCurrentResponse(_ newContent: String) {
        guard let response = currentResponse, currentChatIndex < chats.count else { return }
        
        // Update file
        try? newContent.write(toFile: response.filePath, atomically: true, encoding: .utf8)
        
        // Update in-memory content
        chats[currentChatIndex].responses[currentResponseIndex].content = newContent
    }
    
    func updateLastUserMessage(_ newContent: String) {
        guard currentChatIndex < chats.count else { return }
        
        let chatId = chats[currentChatIndex].id
        let files = getAllConversationFiles()
        
        // Find the most recent user message file for this chat
        let userFiles = files.filter { $0.contains("\(chatId)_user_") }
            .sorted(by: >)  // Sort by filename (most recent first)
        
        if let latestUserFile = userFiles.first {
            let filePath = conversationFolder + latestUserFile
            try? newContent.write(toFile: filePath, atomically: true, encoding: .utf8)
        }
    }
    
    func getAllConversationFiles() -> [String] {
        let files = (try? fileManager.contentsOfDirectory(atPath: conversationFolder)) ?? []
        return files.sorted()
    }
    
    deinit {
        // Clean up conversation folder
        try? fileManager.removeItem(atPath: conversationFolder)
    }
}

// MARK: - Chat Model
struct Chat: Identifiable {
    let id: String
    let title: String
    var responses: [ConversationResponse]
}

// MARK: - Conversation Response Model
struct ConversationResponse: Identifiable {
    let id: String
    var content: String
    let filePath: String
    let timestamp: Date
}

// MARK: - Slide Direction
enum SlideDirection {
    case left
    case right
}

// MARK: - Vim Response Buffer View
struct VimResponseBufferView: View {
    @ObservedObject var conversationManager: ConversationManager
    @StateObject private var vimTerminal = VimResponseTerminal()
    @FocusState private var isTerminalFocused: Bool
    
    let onExit: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with navigation info
            responseHeader
            
            // Terminal display area for response
            VimResponseTerminalDisplayView(vimTerminal: vimTerminal)
                .focused($isTerminalFocused)
                .background(Color.black)
                .frame(minHeight: 200, maxHeight: 400)
                .padding(.horizontal, 8)
                .padding(.top, 8)
            
            // Status line
            responseStatusLine
        }
        .background(Color.black)
        .overlay(
            Rectangle()
                .stroke(isTerminalFocused ? Color.blue.opacity(0.5) : Color.gray.opacity(0.3), lineWidth: 1)
        )
        .onAppear {
            setupTerminal()
            isTerminalFocused = true
        }
        .onChange(of: conversationManager.currentResponseIndex) { _ in
            updateTerminalContent()
        }
    }
    
    private var responseHeader: some View {
        HStack {
            Text("Response \(conversationManager.currentResponseIndex + 1) of \(conversationManager.currentChat?.responses.count ?? 0)")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
            
            Spacer()
            
            Text("^J/^K navigate • :q exit")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.8))
    }
    
    private var responseStatusLine: some View {
        HStack {
            Text(vimTerminal.statusLine.isEmpty ? " " : vimTerminal.statusLine)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white)
            
            Spacer()
            
            Text("RESPONSE")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.yellow)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.8))
    }
    
    private func setupTerminal() {
        vimTerminal.onNavigateUp = {
            _ = conversationManager.navigateUp()
        }
        
        vimTerminal.onNavigateDown = {
            _ = conversationManager.navigateDown()
        }
        
        vimTerminal.onExit = onExit
        
        updateTerminalContent()
    }
    
    private func updateTerminalContent() {
        guard let response = conversationManager.currentResponse else { return }
        vimTerminal.loadContent(response.content)
    }
}

// MARK: - Vim Response Terminal
class VimResponseTerminal: ObservableObject {
    @Published var statusLine: String = ""
    @Published var currentMode: VimMode = .normal
    
    private var bufferLines: [String] = [""]
    private var cursorRow = 0
    private var cursorCol = 0
    
    var onNavigateUp: (() -> Void)?
    var onNavigateDown: (() -> Void)?
    var onExit: (() -> Void)?
    
    func loadContent(_ content: String) {
        bufferLines = content.components(separatedBy: .newlines)
        if bufferLines.isEmpty {
            bufferLines = [""]
        }
        cursorRow = 0
        cursorCol = 0
        currentMode = .normal
        statusLine = ""
        updateDisplay()
    }
    
    func handleKeyPress(_ event: NSEvent) {
        let characters = event.characters ?? ""
        let keyCode = event.keyCode
        let modifiers = event.modifierFlags
        
        switch currentMode {
        case .normal:
            handleNormalModeKey(characters: characters, keyCode: keyCode, modifiers: modifiers)
        case .insert:
            handleInsertModeKey(characters: characters, keyCode: keyCode, modifiers: modifiers)
        case .command:
            handleCommandModeKey(characters: characters, keyCode: keyCode, modifiers: modifiers)
        case .visual:
            handleNormalModeKey(characters: characters, keyCode: keyCode, modifiers: modifiers) // Same as normal for responses
        }
        
        updateDisplay()
    }
    
    private func handleNormalModeKey(characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        // Handle Control key navigation
        if modifiers.contains(.control) {
            switch characters.lowercased() {
            case "j":
                onNavigateDown?()
                return
            case "k":
                onNavigateUp?()
                return
            case "h":
                onNavigateUp?()  // In response view, H also goes up
                return
            case "l":
                onNavigateDown?()  // In response view, L also goes down
                return
            default:
                break
            }
        }
        
        switch characters {
        case "i":
            enterInsertMode()
        case "a":
            enterInsertMode()
            cursorCol += 1
        case "A":
            cursorCol = bufferLines[cursorRow].count
            enterInsertMode()
        case "o":
            bufferLines.insert("", at: cursorRow + 1)
            cursorRow += 1
            cursorCol = 0
            enterInsertMode()
        case "O":
            bufferLines.insert("", at: cursorRow)
            cursorCol = 0
            enterInsertMode()
        case ":":
            enterCommandMode()
        case "h":
            moveCursorLeft()
        case "j":
            moveCursorDown()
        case "k":
            moveCursorUp()
        case "l":
            moveCursorRight()
        case "w":
            moveWordForward()
        case "b":
            moveWordBackward()
        case "0":
            cursorCol = 0
        case "$":
            cursorCol = max(0, bufferLines[cursorRow].count - 1)
        case "x":
            deleteCharacterAtCursor()
        case "dd":
            deleteLine()
        case "g":
            if statusLine.hasSuffix("g") {
                // gg - go to top
                cursorRow = 0
                cursorCol = 0
                statusLine = ""
            } else {
                statusLine = "g"
            }
        case "G":
            // Go to bottom
            cursorRow = bufferLines.count - 1
            cursorCol = 0
        default:
            statusLine = ""
        }
    }
    
    private func handleCommandModeKey(characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        switch keyCode {
        case 53: // Escape
            currentMode = .normal
            statusLine = ""
        case 36: // Return
            executeCommand()
        default:
            if !characters.isEmpty {
                statusLine += characters
            }
        }
    }
    
    private func handleInsertModeKey(characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        // Handle Control key navigation in insert mode
        if modifiers.contains(.control) {
            switch characters.lowercased() {
            case "j":
                onNavigateDown?()
                return
            case "k":
                onNavigateUp?()
                return
            default:
                break
            }
        }
        
        switch keyCode {
        case 53: // Escape
            exitInsertMode()
        case 36: // Return
            insertNewline()
        case 51: // Delete/Backspace
            handleBackspace()
        default:
            if !characters.isEmpty {
                insertText(characters)
            }
        }
    }
    
    private func executeCommand() {
        let command = statusLine.dropFirst() // Remove ':'
        
        switch command {
        case "q", "quit":
            onExit?()
        default:
            break
        }
        
        currentMode = .normal
        statusLine = ""
    }
    
    // MARK: - Vim Editing Methods
    private func enterInsertMode() {
        currentMode = .insert
        statusLine = "-- INSERT --"
    }
    
    private func exitInsertMode() {
        currentMode = .normal
        statusLine = ""
    }
    
    private func enterCommandMode() {
        currentMode = .command
        statusLine = ":"
    }
    
    private func insertText(_ text: String) {
        var line = bufferLines[cursorRow]
        let insertIndex = line.index(line.startIndex, offsetBy: cursorCol)
        line.insert(contentsOf: text, at: insertIndex)
        bufferLines[cursorRow] = line
        cursorCol += text.count
    }
    
    private func insertNewline() {
        let currentLine = bufferLines[cursorRow]
        let leftPart = String(currentLine.prefix(cursorCol))
        let rightPart = String(currentLine.suffix(currentLine.count - cursorCol))
        
        bufferLines[cursorRow] = leftPart
        bufferLines.insert(rightPart, at: cursorRow + 1)
        cursorRow += 1
        cursorCol = 0
    }
    
    private func handleBackspace() {
        if cursorCol > 0 {
            var line = bufferLines[cursorRow]
            let removeIndex = line.index(line.startIndex, offsetBy: cursorCol - 1)
            line.remove(at: removeIndex)
            bufferLines[cursorRow] = line
            cursorCol -= 1
        } else if cursorRow > 0 {
            // Join with previous line
            let currentLine = bufferLines.remove(at: cursorRow)
            cursorRow -= 1
            cursorCol = bufferLines[cursorRow].count
            bufferLines[cursorRow] += currentLine
        }
    }
    
    private func deleteCharacterAtCursor() {
        guard cursorCol < bufferLines[cursorRow].count else { return }
        
        var line = bufferLines[cursorRow]
        let removeIndex = line.index(line.startIndex, offsetBy: cursorCol)
        line.remove(at: removeIndex)
        bufferLines[cursorRow] = line
    }
    
    private func deleteLine() {
        if bufferLines.count > 1 {
            bufferLines.remove(at: cursorRow)
            if cursorRow >= bufferLines.count {
                cursorRow = bufferLines.count - 1
            }
        } else {
            bufferLines[0] = ""
        }
        cursorCol = 0
    }
    
    private func moveWordForward() {
        let line = bufferLines[cursorRow]
        let startIndex = line.index(line.startIndex, offsetBy: cursorCol)
        
        if let spaceRange = line[startIndex...].firstIndex(of: " ") {
            cursorCol = line.distance(from: line.startIndex, to: spaceRange) + 1
        } else {
            cursorCol = line.count
        }
    }
    
    private func moveWordBackward() {
        let line = bufferLines[cursorRow]
        guard cursorCol > 0 else { return }
        
        let endIndex = line.index(line.startIndex, offsetBy: cursorCol - 1)
        
        if let spaceRange = line[..<endIndex].lastIndex(of: " ") {
            cursorCol = line.distance(from: line.startIndex, to: spaceRange) + 1
        } else {
            cursorCol = 0
        }
    }
    
    // MARK: - Cursor Movement
    private func moveCursorLeft() {
        if cursorCol > 0 {
            cursorCol -= 1
        }
    }
    
    private func moveCursorRight() {
        if cursorCol < bufferLines[cursorRow].count {
            cursorCol += 1
        }
    }
    
    private func moveCursorUp() {
        if cursorRow > 0 {
            cursorRow -= 1
            cursorCol = min(cursorCol, bufferLines[cursorRow].count)
        }
    }
    
    private func moveCursorDown() {
        if cursorRow < bufferLines.count - 1 {
            cursorRow += 1
            cursorCol = min(cursorCol, bufferLines[cursorRow].count)
        }
    }
    
    private func updateDisplay() {
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
    
    // MARK: - Public Interface
    func getDisplayLines() -> [String] {
        return bufferLines
    }
    
    func getCursorPosition() -> (row: Int, col: Int) {
        return (cursorRow, cursorCol)
    }
}

// MARK: - Vim Response Terminal Display View
struct VimResponseTerminalDisplayView: NSViewRepresentable {
    let vimTerminal: VimResponseTerminal
    
    func makeNSView(context: Context) -> VimResponseTerminalNSView {
        let view = VimResponseTerminalNSView(vimTerminal: vimTerminal)
        return view
    }
    
    func updateNSView(_ nsView: VimResponseTerminalNSView, context: Context) {
        nsView.updateDisplay()
    }
}

class VimResponseTerminalNSView: NSView {
    private let vimTerminal: VimResponseTerminal
    private let cellWidth: CGFloat = 8.0
    private let cellHeight: CGFloat = 16.0
    private var cursorTimer: Timer?
    private var showCursor = true
    
    init(vimTerminal: VimResponseTerminal) {
        self.vimTerminal = vimTerminal
        super.init(frame: .zero)
        
        setupView()
        startCursorBlink()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }
    
    private func startCursorBlink() {
        cursorTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            self.showCursor.toggle()
            self.needsDisplay = true
        }
    }
    
    override var acceptsFirstResponder: Bool {
        return true
    }
    
    override func becomeFirstResponder() -> Bool {
        return true
    }
    
    override func keyDown(with event: NSEvent) {
        vimTerminal.handleKeyPress(event)
        needsDisplay = true
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        // Clear background
        context.setFillColor(NSColor.black.cgColor)
        context.fill(bounds)
        
        // Draw text content
        drawTextContent(in: context)
        
        // Draw cursor
        if showCursor {
            drawCursor(in: context)
        }
    }
    
    private func drawTextContent(in context: CGContext) {
        let lines = vimTerminal.getDisplayLines()
        
        for (row, line) in lines.enumerated() {
            let y = bounds.height - CGFloat(row + 1) * cellHeight
            
            for (col, char) in line.enumerated() {
                let x = CGFloat(col) * cellWidth
                
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                    .foregroundColor: NSColor.white
                ]
                
                let attributedString = NSAttributedString(string: String(char), attributes: attributes)
                attributedString.draw(at: CGPoint(x: x, y: y))
            }
        }
    }
    
    private func drawCursor(in context: CGContext) {
        let (row, col) = vimTerminal.getCursorPosition()
        let x = CGFloat(col) * cellWidth
        let y = bounds.height - CGFloat(row + 1) * cellHeight
        
        context.setFillColor(NSColor.white.cgColor)
        
        switch vimTerminal.currentMode {
        case .normal:
            // Block cursor
            context.fill(CGRect(x: x, y: y, width: cellWidth, height: cellHeight))
            
            // Draw character in black if there's text
            let lines = vimTerminal.getDisplayLines()
            if row < lines.count && col < lines[row].count {
                let char = lines[row][lines[row].index(lines[row].startIndex, offsetBy: col)]
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                    .foregroundColor: NSColor.black
                ]
                let attributedString = NSAttributedString(string: String(char), attributes: attributes)
                attributedString.draw(at: CGPoint(x: x, y: y))
            }
            
        case .command:
            // Underline cursor
            context.fill(CGRect(x: x, y: y, width: cellWidth, height: 2))
        case .insert:
            // Line cursor (though this mode isn't used in response view)
            context.fill(CGRect(x: x, y: y, width: 2, height: cellHeight))
        case .visual:
            // Block cursor with orange color for visual mode
            context.setFillColor(NSColor.orange.cgColor)
            context.fill(CGRect(x: x, y: y, width: cellWidth, height: cellHeight))
            
            // Draw character in black if there's text
            let lines = vimTerminal.getDisplayLines()
            if row < lines.count && col < lines[row].count {
                let char = lines[row][lines[row].index(lines[row].startIndex, offsetBy: col)]
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                    .foregroundColor: NSColor.black
                ]
                let attributedString = NSAttributedString(string: String(char), attributes: attributes)
                attributedString.draw(at: CGPoint(x: x, y: y))
            }
        }
    }
    
    func updateDisplay() {
        needsDisplay = true
    }
    
    deinit {
        cursorTimer?.invalidate()
    }
}