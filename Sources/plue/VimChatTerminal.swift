import SwiftUI
import Foundation
import AppKit

// MARK: - Vim Chat Terminal
class VimChatTerminal: ObservableObject {
    @Published var terminalOutput: [String] = []
    @Published var currentMode: VimMode = .normal
    @Published var statusLine: String = "-- INSERT --"
    @Published var showCursor = true
    
    private var isNvimRunning = false
    
    var onMessageSent: ((String) -> Void)?
    var onMessageUpdated: ((String) -> Void)?
    var onNavigateUp: (() -> Void)?
    var onNavigateDown: (() -> Void)?
    var onPreviousChat: (() -> Void)?
    var onNextChat: (() -> Void)?
    
    // Terminal simulation
    private var bufferLines: [String] = [""]
    private var cursorRow = 0
    private var cursorCol = 0
    private var insertMode = false
    private var hasBeenSaved = false
    private var lastSentContent = ""
    
    // Visual mode selection
    private var visualStartRow = 0
    private var visualStartCol = 0
    private var visualType: VisualType = .characterwise
    
    init() {
        setupNvimSession()
    }
    
    func setupNvimSession() {
        // Simulate nvim startup
        startNvimSession()
    }
    
    private func startNvimSession() {
        isNvimRunning = true
        currentMode = .normal
        updateStatusLine()
        
        // Initialize with empty buffer
        bufferLines = [""]
        cursorRow = 0
        cursorCol = 0
        
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
    
    func handleKeyPress(_ event: NSEvent) {
        guard isNvimRunning else { 
            print("VimChatTerminal: Not running, ignoring keypress")
            return 
        }
        
        let characters = event.characters ?? ""
        let keyCode = event.keyCode
        let modifiers = event.modifierFlags
        
        print("VimChatTerminal: KeyPress - characters: '\(characters)', keyCode: \(keyCode), modifiers: \(modifiers.rawValue), mode: \(currentMode)")
        
        switch currentMode {
        case .normal:
            handleNormalModeKey(characters: characters, keyCode: keyCode, modifiers: modifiers)
        case .insert:
            handleInsertModeKey(characters: characters, keyCode: keyCode, modifiers: modifiers)
        case .command:
            handleCommandModeKey(characters: characters, keyCode: keyCode, modifiers: modifiers)
        case .visual:
            handleVisualModeKey(characters: characters, keyCode: keyCode, modifiers: modifiers)
        }
        
        updateDisplay()
    }
    
    private func handleNormalModeKey(characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        // Handle Control key shortcuts
        print("VimChatTerminal: Checking modifiers - raw: \(modifiers.rawValue)")
        print("VimChatTerminal: Contains .control: \(modifiers.contains(.control))")
        print("VimChatTerminal: Contains .command: \(modifiers.contains(.command))")
        print("VimChatTerminal: Character: '\(characters)', keyCode: \(keyCode)")
        
        // Debug the actual modifier values
        print("VimChatTerminal: NSEvent.ModifierFlags.control.rawValue = \(NSEvent.ModifierFlags.control.rawValue)")
        print("VimChatTerminal: Bitwise AND result = \(modifiers.rawValue & NSEvent.ModifierFlags.control.rawValue)")
        
        // Try multiple ways to detect control key
        let isControlPressed = modifiers.contains(.control) || 
                              (modifiers.rawValue & NSEvent.ModifierFlags.control.rawValue) != 0 ||
                              modifiers.rawValue == 131330 ||  // Specific value we're seeing
                              characters.unicodeScalars.first?.value ?? 0 < 32  // Control characters are < 32
        
        if isControlPressed && !characters.isEmpty {
            print("VimChatTerminal: Control key detected with character: '\(characters)'")
            
            // Handle control characters directly by keyCode since characters might be mangled
            switch keyCode {
            case 38: // J key
                print("VimChatTerminal: Navigate Down triggered (Ctrl+J)")
                onNavigateDown?()
                return
            case 40: // K key
                print("VimChatTerminal: Navigate Up triggered (Ctrl+K)")
                onNavigateUp?()
                return
            case 4: // H key
                print("VimChatTerminal: Previous Chat triggered (Ctrl+H)")
                onPreviousChat?()
                return
            case 37: // L key
                print("VimChatTerminal: Next Chat triggered (Ctrl+L)")
                onNextChat?()
                return
            default:
                print("VimChatTerminal: Control key with unhandled keyCode: \(keyCode)")
                break
            }
        }
        
        // Handle Control+V for block visual mode
        if modifiers.contains(.control) && characters.lowercased() == "v" {
            enterVisualMode(.blockwise)
            return
        }
        
        switch characters {
        case "i":
            enterInsertMode()
        case "a":
            enterInsertMode()
            if cursorRow < bufferLines.count {
                cursorCol = min(cursorCol + 1, bufferLines[cursorRow].count)
            }
        case "A":
            if cursorRow < bufferLines.count {
                cursorCol = bufferLines[cursorRow].count
            }
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
        case "v":
            enterVisualMode(.characterwise)
        case "V":
            enterVisualMode(.linewise)
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
            if cursorRow < bufferLines.count {
                cursorCol = max(0, bufferLines[cursorRow].count - 1)
            }
        case "x":
            deleteCharacterAtCursor()
        case "dd":
            deleteLine()
        default:
            break
        }
    }
    
    private func handleInsertModeKey(characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        // Handle Control key shortcuts in insert mode too
        let isControlPressed = modifiers.contains(.control) || 
                              (modifiers.rawValue & NSEvent.ModifierFlags.control.rawValue) != 0 ||
                              modifiers.rawValue == 131330 ||  // Specific value we're seeing
                              characters.unicodeScalars.first?.value ?? 0 < 32
        
        if isControlPressed && !characters.isEmpty {
            switch keyCode {
            case 38: // J key
                print("VimChatTerminal: Navigate Down triggered (Ctrl+J insert mode)")
                onNavigateDown?()
                return
            case 40: // K key
                print("VimChatTerminal: Navigate Up triggered (Ctrl+K insert mode)")
                onNavigateUp?()
                return
            case 4: // H key
                print("VimChatTerminal: Previous Chat triggered (Ctrl+H insert mode)")
                onPreviousChat?()
                return
            case 37: // L key
                print("VimChatTerminal: Next Chat triggered (Ctrl+L insert mode)")
                onNextChat?()
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
    
    private func executeCommand() {
        let command = statusLine.dropFirst() // Remove ':'
        print("VimChatTerminal: executeCommand called with command: '\(command)'")
        
        switch command {
        case "w":
            print("VimChatTerminal: Executing :w command")
            saveAndSendMessage()
            // Keep buffer content for :w
        case "wq":
            print("VimChatTerminal: Executing :wq command")
            saveAndSendMessage()
            // Clear buffer for next message
            clearBufferForNext()
        case "q":
            print("VimChatTerminal: Executing :q command")
            // Just exit command mode for now
            break
        default:
            print("VimChatTerminal: Unknown command: '\(command)'")
            break
        }
        
        currentMode = .normal
        statusLine = ""
    }
    
    private func saveAndSendMessage() {
        let content = bufferLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        print("VimChatTerminal: saveAndSendMessage called with content: '\(content)'")
        print("VimChatTerminal: hasBeenSaved = \(hasBeenSaved)")
        print("VimChatTerminal: lastSentContent = '\(lastSentContent)'")
        
        guard !content.isEmpty else { 
            statusLine = "No content to send"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.statusLine = ""
            }
            return 
        }
        
        // Check if content has actually changed
        if content == lastSentContent {
            statusLine = "No changes to submit"
            print("VimChatTerminal: Content unchanged, skipping submission")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.statusLine = ""
            }
            return
        }
        
        if hasBeenSaved {
            // This is a regeneration - update the last message
            print("VimChatTerminal: Updating last message: \(content)")
            print("VimChatTerminal: onMessageUpdated callback exists: \(onMessageUpdated != nil)")
            onMessageUpdated?(content)
            statusLine = "Message updated"
        } else {
            // First time saving - send new message
            print("VimChatTerminal: Sending new message: \(content)")
            print("VimChatTerminal: onMessageSent callback exists: \(onMessageSent != nil)")
            onMessageSent?(content)
            hasBeenSaved = true
            statusLine = "Message sent"
        }
        
        // Update last sent content
        lastSentContent = content
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.statusLine = ""
        }
    }
    
    private func clearBufferForNext() {
        // Clear buffer for next message
        bufferLines = [""]
        cursorRow = 0
        cursorCol = 0
        hasBeenSaved = false
        lastSentContent = ""
        updateDisplay()
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
    
    private func moveWordForward() {
        guard cursorRow < bufferLines.count else { return }
        
        let line = bufferLines[cursorRow]
        let safeCol = min(cursorCol, line.count)
        guard safeCol < line.count else { return }
        
        let startIndex = line.index(line.startIndex, offsetBy: safeCol)
        
        if let spaceRange = line[startIndex...].firstIndex(of: " ") {
            cursorCol = line.distance(from: line.startIndex, to: spaceRange) + 1
        } else {
            cursorCol = line.count
        }
    }
    
    private func moveWordBackward() {
        guard cursorRow < bufferLines.count else { return }
        
        let line = bufferLines[cursorRow]
        let safeCol = min(cursorCol, line.count)
        guard safeCol > 0 else { return }
        
        let endIndex = line.index(line.startIndex, offsetBy: safeCol - 1)
        
        if let spaceRange = line[..<endIndex].lastIndex(of: " ") {
            cursorCol = line.distance(from: line.startIndex, to: spaceRange) + 1
        } else {
            cursorCol = 0
        }
    }
    
    // MARK: - Text Editing
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
        // Bounds checking to prevent crashes
        guard cursorRow < bufferLines.count else { return }
        
        var line = bufferLines[cursorRow]
        
        // Ensure cursorCol is within valid bounds
        let safeCol = min(cursorCol, line.count)
        let insertIndex = line.index(line.startIndex, offsetBy: safeCol)
        line.insert(contentsOf: text, at: insertIndex)
        bufferLines[cursorRow] = line
        cursorCol = safeCol + text.count
    }
    
    private func insertNewline() {
        guard cursorRow < bufferLines.count else { return }
        
        let currentLine = bufferLines[cursorRow]
        let safeCol = min(cursorCol, currentLine.count)
        let leftPart = String(currentLine.prefix(safeCol))
        let rightPart = String(currentLine.suffix(currentLine.count - safeCol))
        
        bufferLines[cursorRow] = leftPart
        bufferLines.insert(rightPart, at: cursorRow + 1)
        cursorRow += 1
        cursorCol = 0
    }
    
    private func handleBackspace() {
        guard cursorRow < bufferLines.count else { return }
        
        if cursorCol > 0 {
            var line = bufferLines[cursorRow]
            let safeCol = min(cursorCol, line.count)
            if safeCol > 0 {
                let removeIndex = line.index(line.startIndex, offsetBy: safeCol - 1)
                line.remove(at: removeIndex)
                bufferLines[cursorRow] = line
                cursorCol = safeCol - 1
            }
        } else if cursorRow > 0 {
            // Join with previous line
            let currentLine = bufferLines.remove(at: cursorRow)
            cursorRow -= 1
            cursorCol = bufferLines[cursorRow].count
            bufferLines[cursorRow] += currentLine
        }
    }
    
    private func deleteCharacterAtCursor() {
        guard cursorRow < bufferLines.count else { return }
        
        let line = bufferLines[cursorRow]
        guard cursorCol < line.count else { return }
        
        var mutableLine = line
        let removeIndex = mutableLine.index(mutableLine.startIndex, offsetBy: cursorCol)
        mutableLine.remove(at: removeIndex)
        bufferLines[cursorRow] = mutableLine
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
    
    private func updateStatusLine() {
        switch currentMode {
        case .normal:
            statusLine = ""
        case .insert:
            statusLine = "-- INSERT --"
        case .command:
            if !statusLine.hasPrefix(":") {
                statusLine = ":"
            }
        case .visual:
            switch visualType {
            case .characterwise:
                statusLine = "-- VISUAL --"
            case .linewise:
                statusLine = "-- VISUAL LINE --"
            case .blockwise:
                statusLine = "-- VISUAL BLOCK --"
            }
        }
    }
    
    private func updateDisplay() {
        // Prevent race conditions by using weak self and checking state
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isNvimRunning else { return }
            self.objectWillChange.send()
        }
    }
    
    // MARK: - Visual Mode Operations
    private func enterVisualMode(_ type: VisualType) {
        currentMode = .visual
        visualType = type
        visualStartRow = cursorRow
        visualStartCol = cursorCol
        updateStatusLine()
    }
    
    private func handleVisualModeKey(characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        // Handle Control key shortcuts in visual mode
        let isControlPressed = modifiers.contains(.control) || 
                              (modifiers.rawValue & NSEvent.ModifierFlags.control.rawValue) != 0 ||
                              modifiers.rawValue == 131330 ||
                              characters.unicodeScalars.first?.value ?? 0 < 32
        
        if isControlPressed && !characters.isEmpty {
            switch keyCode {
            case 38: // J key
                onNavigateDown?()
                return
            case 40: // K key
                onNavigateUp?()
                return
            case 4: // H key
                onPreviousChat?()
                return
            case 37: // L key
                onNextChat?()
                return
            default:
                break
            }
        }
        
        switch keyCode {
        case 53: // Escape
            exitVisualMode()
        default:
            switch characters {
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
            case "d":
                deleteSelection()
                exitVisualMode()
            case "y":
                yankSelection()
                exitVisualMode()
            case "c":
                deleteSelection()
                enterInsertMode()
            case "v":
                // Switch visual mode types
                switch visualType {
                case .characterwise:
                    visualType = .linewise
                case .linewise:
                    visualType = .blockwise
                case .blockwise:
                    visualType = .characterwise
                }
                updateStatusLine()
            case "V":
                visualType = .linewise
                updateStatusLine()
            default:
                break
            }
        }
    }
    
    private func exitVisualMode() {
        currentMode = .normal
        updateStatusLine()
    }
    
    private func deleteSelection() {
        let (startRow, startCol, endRow, endCol) = getSelectionBounds()
        
        switch visualType {
        case .characterwise:
            deleteCharacterSelection(startRow: startRow, startCol: startCol, endRow: endRow, endCol: endCol)
        case .linewise:
            deleteLineSelection(startRow: startRow, endRow: endRow)
        case .blockwise:
            deleteBlockSelection(startRow: startRow, startCol: startCol, endRow: endRow, endCol: endCol)
        }
    }
    
    private func yankSelection() {
        // In a full implementation, this would copy to clipboard
        // For now, just simulate the operation
        statusLine = "Yanked selection"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.statusLine = ""
        }
    }
    
    private func getSelectionBounds() -> (startRow: Int, startCol: Int, endRow: Int, endCol: Int) {
        let startRow = min(visualStartRow, cursorRow)
        let endRow = max(visualStartRow, cursorRow)
        let startCol = min(visualStartCol, cursorCol)
        let endCol = max(visualStartCol, cursorCol)
        
        return (startRow, startCol, endRow, endCol)
    }
    
    private func deleteCharacterSelection(startRow: Int, startCol: Int, endRow: Int, endCol: Int) {
        if startRow == endRow {
            // Single line selection
            guard startRow < bufferLines.count else { return }
            var line = bufferLines[startRow]
            let safeStartCol = min(startCol, line.count)
            let safeEndCol = min(endCol, line.count - 1)
            guard safeStartCol <= safeEndCol && safeStartCol < line.count else { return }
            
            let startIndex = line.index(line.startIndex, offsetBy: safeStartCol)
            let endIndex = line.index(line.startIndex, offsetBy: min(safeEndCol + 1, line.count))
            line.removeSubrange(startIndex..<endIndex)
            bufferLines[startRow] = line
            cursorRow = startRow
            cursorCol = startCol
        } else {
            // Multi-line selection
            for row in (startRow...endRow).reversed() {
                if row == startRow {
                    // First line - delete from startCol to end
                    var line = bufferLines[row]
                    let startIndex = line.index(line.startIndex, offsetBy: startCol)
                    line.removeSubrange(startIndex...)
                    bufferLines[row] = line
                } else if row == endRow {
                    // Last line - delete from beginning to endCol
                    var line = bufferLines[row]
                    let endIndex = line.index(line.startIndex, offsetBy: min(endCol + 1, line.count))
                    line.removeSubrange(line.startIndex..<endIndex)
                    // Join with first line
                    bufferLines[startRow] += line
                    bufferLines.remove(at: row)
                } else {
                    // Middle lines - delete entirely
                    bufferLines.remove(at: row)
                }
            }
            cursorRow = startRow
            cursorCol = startCol
        }
    }
    
    private func deleteLineSelection(startRow: Int, endRow: Int) {
        for _ in startRow...endRow {
            if bufferLines.count > 1 {
                bufferLines.remove(at: startRow)
            } else {
                bufferLines[0] = ""
            }
        }
        cursorRow = min(startRow, bufferLines.count - 1)
        cursorCol = 0
    }
    
    private func deleteBlockSelection(startRow: Int, startCol: Int, endRow: Int, endCol: Int) {
        // Block selection deletes rectangular region
        for row in startRow...endRow {
            if row < bufferLines.count {
                var line = bufferLines[row]
                if startCol < line.count {
                    let actualEndCol = min(endCol, line.count - 1)
                    if actualEndCol >= startCol {
                        let startIndex = line.index(line.startIndex, offsetBy: startCol)
                        let endIndex = line.index(line.startIndex, offsetBy: actualEndCol + 1)
                        line.removeSubrange(startIndex..<endIndex)
                        bufferLines[row] = line
                    }
                }
            }
        }
        cursorRow = startRow
        cursorCol = startCol
    }
    
    // MARK: - Public Interface
    func getDisplayLines() -> [String] {
        return bufferLines
    }
    
    func getCursorPosition() -> (row: Int, col: Int) {
        return (cursorRow, cursorCol)
    }
    
    func getVisualSelection() -> (isActive: Bool, startRow: Int, startCol: Int, endRow: Int, endCol: Int, type: VisualType)? {
        guard currentMode == .visual else { return nil }
        let (startRow, startCol, endRow, endCol) = getSelectionBounds()
        return (true, startRow, startCol, endRow, endCol, visualType)
    }
}

// MARK: - Vim Modes
enum VimMode {
    case normal
    case insert
    case command
    case visual
}

// MARK: - Visual Mode Types
enum VisualType {
    case characterwise
    case linewise
    case blockwise
}

