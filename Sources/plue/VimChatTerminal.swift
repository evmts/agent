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
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.statusLine = ""
            }
            return 
        }
        
        // Check if content has actually changed
        if content == lastSentContent {
            statusLine = "No changes to submit"
            print("VimChatTerminal: Content unchanged, skipping submission")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.statusLine = ""
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
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.statusLine = ""
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

// MARK: - Vim Modes
enum VimMode {
    case normal
    case insert
    case command
}

