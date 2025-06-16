import Cocoa
import Foundation

@objc class PlueAppleScriptSupport: NSObject {
    @objc static let shared = PlueAppleScriptSupport()
    
    private override init() {
        super.init()
    }
    
    // MARK: - Terminal Control
    
    @objc func runTerminalCommand(_ command: String) -> String {
        let script = """
        tell application "Terminal"
            activate
            do script "\(command.replacingOccurrences(of: "\"", with: "\\\""))"
            return "Command sent to Terminal"
        end tell
        """
        
        return executeAppleScript(script) ?? "Failed to execute command"
    }
    
    @objc func runTerminalCommandInNewTab(_ command: String) -> String {
        let script = """
        tell application "Terminal"
            activate
            tell application "System Events" to keystroke "t" using command down
            delay 0.5
            do script "\(command.replacingOccurrences(of: "\"", with: "\\\""))" in front window
            return "Command sent to new Terminal tab"
        end tell
        """
        
        return executeAppleScript(script) ?? "Failed to execute command in new tab"
    }
    
    @objc func getTerminalOutput() -> String {
        let script = """
        tell application "Terminal"
            set frontTab to selected tab of front window
            return contents of frontTab
        end tell
        """
        
        return executeAppleScript(script) ?? "Failed to get terminal output"
    }
    
    @objc func closeTerminalWindow() -> String {
        let script = """
        tell application "Terminal"
            close front window
            return "Terminal window closed"
        end tell
        """
        
        return executeAppleScript(script) ?? "Failed to close terminal window"
    }
    
    // MARK: - Chat and Agent Control
    
    @objc func sendChatMessage(_ message: String) -> String {
        // This would integrate with your chat system
        let core = PlueCore.shared
        core.handleEvent(.chatMessageSent(message))
        return "Message sent: \(message)"
    }
    
    @objc func getCurrentChatMessages() -> String {
        let core = PlueCore.shared
        let state = core.getCurrentState()
        
        // Convert chat messages to a string format suitable for AppleScript
        guard let conversation = state.promptState.currentConversation else {
            return "No active conversation"
        }
        
        let messages = conversation.messages.map { msg in
            "\(msg.type): \(msg.content)"
        }.joined(separator: "\n")
        
        return messages.isEmpty ? "No messages" : messages
    }
    
    @objc func switchToTab(_ tabName: String) -> String {
        let tabMap: [String: TabType] = [
            "prompt": .prompt,
            "farcaster": .farcaster,
            "agent": .agent,
            "terminal": .terminal,
            "web": .web,
            "editor": .editor,
            "diff": .diff,
            "worktree": .worktree
        ]
        
        guard let tab = tabMap[tabName.lowercased()] else {
            return "Invalid tab name. Use: prompt, farcaster, agent, terminal, web, editor, diff, or worktree"
        }
        
        let core = PlueCore.shared
        core.handleEvent(.tabSwitched(tab))
        return "Switched to \(tabName) tab"
    }
    
    // MARK: - File Operations
    
    @objc func openFile(_ path: String) -> String {
        let core = PlueCore.shared
        core.handleEvent(.fileOpened(path))
        return "Opened file: \(path)"
    }
    
    @objc func saveCurrentFile() -> String {
        let core = PlueCore.shared
        core.handleEvent(.fileSaved)
        return "File saved"
    }
    
    // MARK: - Utility Methods
    
    @objc func getApplicationState() -> String {
        let core = PlueCore.shared
        let state = core.getCurrentState()
        
        // Return a simplified string representation of the app state
        let messageCount = state.promptState.currentConversation?.messages.count ?? 0
        return """
        Current Tab: \(state.currentTab)
        Chat Messages: \(messageCount)
        Is Initialized: \(state.isInitialized)
        """
    }
    
    // MARK: - Private Methods
    
    private func executeAppleScript(_ source: String) -> String? {
        var error: NSDictionary?
        if let script = NSAppleScript(source: source) {
            let result = script.executeAndReturnError(&error)
            
            if let error = error {
                print("AppleScript error: \(error)")
                return nil
            }
            
            return result.stringValue
        }
        
        return nil
    }
}

// MARK: - AppleScript Command Handler

@objc class PlueScriptCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        let scriptSupport = PlueAppleScriptSupport.shared
        
        // Map command codes to actions
        let commandCode = self.commandDescription.commandName
        
        // Add the command type to arguments for processing
        var modifiedArguments = self.evaluatedArguments ?? [:]
        
        switch commandCode {
        case "run terminal command":
            modifiedArguments["command"] = "runTerminal"
        case "run terminal command in new tab":
            modifiedArguments["command"] = "runTerminalNewTab"
        case "get terminal output":
            modifiedArguments["command"] = "getTerminalOutput"
        case "close terminal window":
            modifiedArguments["command"] = "closeTerminal"
        case "send chat message":
            modifiedArguments["command"] = "sendChat"
        case "get chat messages":
            modifiedArguments["command"] = "getChatMessages"
        case "switch to tab":
            modifiedArguments["command"] = "switchTab"
        case "open file":
            modifiedArguments["command"] = "openFile"
        case "save file":
            modifiedArguments["command"] = "saveFile"
        case "get application state":
            modifiedArguments["command"] = "getState"
        default:
            return "Unknown command: \(commandCode)"
        }
        
        // Handle different command types
        if let command = modifiedArguments["command"] as? String {
            switch command {
            case "runTerminal":
                if let terminalCommand = modifiedArguments["terminalCommand"] as? String {
                    return scriptSupport.runTerminalCommand(terminalCommand)
                }
            case "runTerminalNewTab":
                if let terminalCommand = modifiedArguments["terminalCommand"] as? String {
                    return scriptSupport.runTerminalCommandInNewTab(terminalCommand)
                }
            case "getTerminalOutput":
                return scriptSupport.getTerminalOutput()
            case "closeTerminal":
                return scriptSupport.closeTerminalWindow()
            case "sendChat":
                if let message = modifiedArguments["message"] as? String {
                    return scriptSupport.sendChatMessage(message)
                }
            case "getChatMessages":
                return scriptSupport.getCurrentChatMessages()
            case "switchTab":
                if let tabName = modifiedArguments["tab"] as? String {
                    return scriptSupport.switchToTab(tabName)
                }
            case "openFile":
                if let path = modifiedArguments["path"] as? String {
                    return scriptSupport.openFile(path)
                }
            case "saveFile":
                return scriptSupport.saveCurrentFile()
            case "getState":
                return scriptSupport.getApplicationState()
            default:
                return "Unknown command: \(command)"
            }
        }
        
        return "No command specified"
    }
}

// MARK: - AppleScript Examples

/*
Example AppleScript usage:

-- Run a terminal command
tell application "Plue"
    run terminal command "ls -la"
end tell

-- Send a chat message
tell application "Plue"
    send chat message "Hello from AppleScript!"
end tell

-- Switch tabs
tell application "Plue"
    switch to tab "terminal"
end tell

-- Get current chat messages
tell application "Plue"
    get chat messages
end tell

-- Run command in new terminal tab
tell application "Plue"
    run terminal command "cd ~/Documents && pwd" in new tab
end tell

-- Get application state
tell application "Plue"
    get application state
end tell
*/