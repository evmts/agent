import SwiftUI
import Foundation

// MARK: - Terminal Cell
struct TerminalCell {
    let character: Character
    let foregroundColor: Color
    let backgroundColor: Color
    let attributes: Set<CellAttribute>
    
    static let empty = TerminalCell(
        character: " ",
        foregroundColor: .white,
        backgroundColor: .clear,
        attributes: []
    )
}

enum CellAttribute {
    case bold
    case italic
    case underline
    case reverse
}

// MARK: - Mock Terminal Implementation
class MockTerminal: ObservableObject {
    // Terminal dimensions
    @Published var rows: Int = 25
    @Published var cols: Int = 80
    @Published var needsRedraw = false
    
    // Terminal state
    @Published var isConnected = false
    @Published var showConnectionStatus = true
    
    // Rendering options
    let useMetalRendering = false // Set to true when Metal rendering is implemented
    let cellWidth: CGFloat = 8.0
    let cellHeight: CGFloat = 16.0
    
    // Terminal buffer
    private var buffer: [[TerminalCell]]
    private var cursorRow = 0
    private var cursorCol = 0
    private var currentDirectory = "/Users/user"
    private var commandHistory: [String] = []
    private var currentCommand = ""
    
    // Colors
    private let colors = TerminalColors()
    
    init() {
        self.buffer = Array(repeating: Array(repeating: TerminalCell.empty, count: 80), count: 25)
        setupInitialContent()
    }
    
    func getCell(row: Int, col: Int) -> TerminalCell {
        guard row >= 0, row < rows, col >= 0, col < cols else {
            return TerminalCell.empty
        }
        return buffer[row][col]
    }
    
    func resize(rows: Int, cols: Int) {
        self.rows = max(1, rows)
        self.cols = max(1, cols)
        
        // Resize buffer
        buffer = Array(repeating: Array(repeating: TerminalCell.empty, count: self.cols), count: self.rows)
        
        // Reset cursor if it's out of bounds
        cursorRow = min(cursorRow, self.rows - 1)
        cursorCol = min(cursorCol, self.cols - 1)
        
        redraw()
    }
    
    func startSession() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.isConnected = true
            self.showWelcomeMessage()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.showConnectionStatus = false
                self.showPrompt()
            }
        }
    }
    
    func handleInput(_ input: String) {
        for char in input {
            switch char {
            case "\r", "\n":
                handleEnter()
            case "\u{7F}": // Backspace
                handleBackspace()
            case "\u{1B}": // Escape sequence start
                // Handle escape sequences (arrow keys, etc.)
                break
            default:
                handleCharacter(char)
            }
        }
        redraw()
    }
    
    private func setupInitialContent() {
        clearScreen()
    }
    
    private func showWelcomeMessage() {
        clearScreen()
        
        let welcomeLines = [
            "Plue Terminal v1.0.0",
            "Built with libghostty architecture patterns",
            "",
            "Connecting to shell..."
        ]
        
        for (index, line) in welcomeLines.enumerated() {
            writeLineAt(row: index + 2, text: line, color: colors.cyan)
        }
        
        redraw()
    }
    
    private func showPrompt() {
        let promptText = "user@plue:\(currentDirectory)$ "
        writeAt(row: cursorRow, col: 0, text: promptText, color: colors.green)
        cursorCol = promptText.count
        currentCommand = ""
        redraw()
    }
    
    private func handleCharacter(_ char: Character) {
        if cursorCol < cols - 1 {
            buffer[cursorRow][cursorCol] = TerminalCell(
                character: char,
                foregroundColor: colors.white,
                backgroundColor: .clear,
                attributes: []
            )
            cursorCol += 1
            currentCommand.append(char)
        }
    }
    
    private func handleBackspace() {
        if cursorCol > getPromptLength() {
            cursorCol -= 1
            buffer[cursorRow][cursorCol] = TerminalCell.empty
            if !currentCommand.isEmpty {
                currentCommand.removeLast()
            }
        }
    }
    
    private func handleEnter() {
        // Move to next line
        cursorRow += 1
        cursorCol = 0
        
        // Process command
        processCommand(currentCommand.trimmingCharacters(in: .whitespaces))
        
        // Show new prompt
        if cursorRow >= rows - 1 {
            scrollUp()
        }
        showPrompt()
    }
    
    private func processCommand(_ command: String) {
        commandHistory.append(command)
        
        // Simulate command execution
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.executeCommand(command)
        }
    }
    
    private func executeCommand(_ command: String) {
        let parts = command.split(separator: " ").map(String.init)
        guard !parts.isEmpty else { return }
        
        let cmd = parts[0]
        let args = Array(parts.dropFirst())
        
        switch cmd {
        case "ls":
            handleLSCommand(args: args)
        case "pwd":
            writeOutput(currentDirectory)
        case "cd":
            handleCDCommand(args: args)
        case "echo":
            writeOutput(args.joined(separator: " "))
        case "clear":
            clearScreen()
            return // Don't show prompt after clear
        case "help":
            showHelpMessage()
        case "date":
            let formatter = DateFormatter()
            formatter.dateStyle = .full
            formatter.timeStyle = .full
            writeOutput(formatter.string(from: Date()))
        case "whoami":
            writeOutput("user")
        case "uname":
            writeOutput("Darwin plue.local 23.0.0 Darwin Kernel")
        case "ps":
            showProcessList()
        default:
            writeOutput("\(cmd): command not found")
        }
    }
    
    private func handleLSCommand(args: [String]) {
        let files = [
            "Documents/", "Downloads/", "Desktop/", "Pictures/",
            "file1.txt", "file2.swift", "project.zip", ".hidden"
        ]
        
        let showHidden = args.contains("-a") || args.contains("-la")
        let longFormat = args.contains("-l") || args.contains("-la")
        
        for file in files {
            if file.hasPrefix(".") && !showHidden {
                continue
            }
            
            if longFormat {
                let permissions = file.hasSuffix("/") ? "drwxr-xr-x" : "-rw-r--r--"
                let size = file.hasSuffix("/") ? "0" : "1024"
                let date = "Dec 13 10:30"
                writeOutput("\(permissions)  1 user staff  \(size) \(date) \(file)")
            } else {
                writeOutput(file)
            }
        }
    }
    
    private func handleCDCommand(args: [String]) {
        guard let newDir = args.first else {
            currentDirectory = "/Users/user"
            return
        }
        
        if newDir.hasPrefix("/") {
            currentDirectory = newDir
        } else if newDir == ".." {
            let components = currentDirectory.split(separator: "/").dropLast()
            currentDirectory = "/" + components.joined(separator: "/")
            if currentDirectory == "/" && !components.isEmpty {
                currentDirectory = "/Users"
            }
        } else {
            if currentDirectory.hasSuffix("/") {
                currentDirectory += newDir
            } else {
                currentDirectory += "/" + newDir
            }
        }
    }
    
    private func showHelpMessage() {
        let helpText = [
            "Available commands:",
            "  ls [-a] [-l]  - List directory contents",
            "  pwd           - Print working directory",
            "  cd <dir>      - Change directory",
            "  echo <text>   - Display text",
            "  clear         - Clear screen",
            "  date          - Show current date and time",
            "  whoami        - Show current user",
            "  uname         - Show system information",
            "  ps            - Show running processes",
            "  help          - Show this help message"
        ]
        
        for line in helpText {
            writeOutput(line)
        }
    }
    
    private func showProcessList() {
        let processes = [
            "  PID TTY           TIME CMD",
            " 1234 ttys000    0:00.01 /bin/zsh",
            " 5678 ttys000    0:00.02 plue",
            " 9101 ttys000    0:00.00 ps"
        ]
        
        for process in processes {
            writeOutput(process)
        }
    }
    
    private func writeOutput(_ text: String) {
        ensureNewLine()
        writeAt(row: cursorRow, col: 0, text: text, color: colors.white)
        newLine()
    }
    
    private func writeAt(row: Int, col: Int, text: String, color: Color) {
        guard row >= 0, row < rows else { return }
        
        var currentCol = col
        for char in text {
            guard currentCol < cols else { break }
            buffer[row][currentCol] = TerminalCell(
                character: char,
                foregroundColor: color,
                backgroundColor: .clear,
                attributes: []
            )
            currentCol += 1
        }
    }
    
    private func writeLineAt(row: Int, text: String, color: Color) {
        writeAt(row: row, col: 0, text: text, color: color)
    }
    
    private func clearScreen() {
        buffer = Array(repeating: Array(repeating: TerminalCell.empty, count: cols), count: rows)
        cursorRow = 0
        cursorCol = 0
        redraw()
    }
    
    private func scrollUp() {
        // Move all lines up by one
        for row in 1..<rows {
            buffer[row - 1] = buffer[row]
        }
        // Clear the last line
        buffer[rows - 1] = Array(repeating: TerminalCell.empty, count: cols)
        
        if cursorRow > 0 {
            cursorRow -= 1
        }
    }
    
    private func ensureNewLine() {
        if cursorCol > 0 {
            newLine()
        }
    }
    
    private func newLine() {
        cursorRow += 1
        cursorCol = 0
        
        if cursorRow >= rows {
            scrollUp()
        }
    }
    
    private func getPromptLength() -> Int {
        return "user@plue:\(currentDirectory)$ ".count
    }
    
    private var redrawPending = false
    
    private func redraw() {
        guard !redrawPending else { return }
        redrawPending = true
        
        DispatchQueue.main.async {
            self.needsRedraw.toggle()
            self.redrawPending = false
        }
    }
}

// MARK: - Terminal Colors
struct TerminalColors {
    let black = Color.black
    let red = Color.red
    let green = Color.green
    let yellow = Color.yellow
    let blue = Color.blue
    let magenta = Color.purple
    let cyan = Color.cyan
    let white = Color.white
    
    // Bright variants
    let brightBlack = Color.gray
    let brightRed = Color.red.opacity(0.8)
    let brightGreen = Color.green.opacity(0.8)
    let brightYellow = Color.yellow.opacity(0.8)
    let brightBlue = Color.blue.opacity(0.8)
    let brightMagenta = Color.purple.opacity(0.8)
    let brightCyan = Color.cyan.opacity(0.8)
    let brightWhite = Color.white.opacity(0.9)
}