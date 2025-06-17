import Foundation
import AppKit

// MARK: - Terminal Cell
struct TerminalEmulatorCell {
    var character: Character = " "
    var foregroundColor: NSColor = NSColor(red: 0.976, green: 0.976, blue: 0.976, alpha: 1.0)
    var backgroundColor: NSColor = NSColor(red: 0.086, green: 0.086, blue: 0.11, alpha: 1.0)
    var isBold: Bool = false
    var isUnderlined: Bool = false
}

// MARK: - Terminal Buffer
class TerminalBuffer {
    var cols: Int
    var rows: Int
    private var buffer: [[TerminalEmulatorCell]]
    private var cursorRow: Int = 0
    private var cursorCol: Int = 0
    private var savedCursorRow: Int = 0
    private var savedCursorCol: Int = 0
    private var scrollTop: Int = 0
    private var scrollBottom: Int
    
    // Current attributes
    private var currentForeground: NSColor = NSColor(red: 0.976, green: 0.976, blue: 0.976, alpha: 1.0)
    private var currentBackground: NSColor = NSColor(red: 0.086, green: 0.086, blue: 0.11, alpha: 1.0)
    private var currentBold: Bool = false
    private var currentUnderline: Bool = false
    
    init(cols: Int, rows: Int) {
        self.cols = cols
        self.rows = rows
        self.scrollBottom = rows - 1
        self.buffer = Array(repeating: Array(repeating: TerminalEmulatorCell(), count: cols), count: rows)
    }
    
    // MARK: - Cursor Management
    
    func setCursor(row: Int, col: Int) {
        cursorRow = max(0, min(row, rows - 1))
        cursorCol = max(0, min(col, cols - 1))
    }
    
    func moveCursor(rows: Int, cols: Int) {
        setCursor(row: cursorRow + rows, col: cursorCol + cols)
    }
    
    func saveCursor() {
        savedCursorRow = cursorRow
        savedCursorCol = cursorCol
    }
    
    func restoreCursor() {
        cursorRow = savedCursorRow
        cursorCol = savedCursorCol
    }
    
    // MARK: - Writing
    
    func writeCharacter(_ char: Character) {
        if char == "\n" {
            newLine()
        } else if char == "\r" {
            cursorCol = 0
        } else if char == "\u{8}" { // Backspace
            if cursorCol > 0 {
                cursorCol -= 1
                buffer[cursorRow][cursorCol] = TerminalEmulatorCell()
            }
        } else if char == "\t" {
            // Move to next tab stop (every 8 columns)
            let nextTab = ((cursorCol / 8) + 1) * 8
            cursorCol = min(nextTab, cols - 1)
        } else if !char.isASCII || char.isLetter || char.isNumber || char.isPunctuation || char.isSymbol || char.isWhitespace {
            // Write the character
            if cursorCol < cols {
                buffer[cursorRow][cursorCol] = TerminalEmulatorCell(
                    character: char,
                    foregroundColor: currentForeground,
                    backgroundColor: currentBackground,
                    isBold: currentBold,
                    isUnderlined: currentUnderline
                )
                cursorCol += 1
                if cursorCol >= cols {
                    cursorCol = 0
                    newLine()
                }
            }
        }
    }
    
    func writeString(_ string: String) {
        for char in string {
            writeCharacter(char)
        }
    }
    
    private func newLine() {
        cursorCol = 0
        if cursorRow == scrollBottom {
            // Scroll up
            scrollUp()
        } else if cursorRow < rows - 1 {
            cursorRow += 1
        }
    }
    
    private func scrollUp() {
        // Move all lines up by one within the scroll region
        for row in scrollTop..<scrollBottom {
            buffer[row] = buffer[row + 1]
        }
        // Clear the bottom line
        buffer[scrollBottom] = Array(repeating: TerminalEmulatorCell(), count: cols)
    }
    
    // MARK: - Clearing
    
    func clearScreen() {
        buffer = Array(repeating: Array(repeating: TerminalEmulatorCell(), count: cols), count: rows)
        cursorRow = 0
        cursorCol = 0
    }
    
    func clearLine() {
        buffer[cursorRow] = Array(repeating: TerminalEmulatorCell(), count: cols)
    }
    
    func clearToEndOfLine() {
        for col in cursorCol..<cols {
            buffer[cursorRow][col] = TerminalEmulatorCell()
        }
    }
    
    func clearToEndOfScreen() {
        // Clear from cursor to end of line
        clearToEndOfLine()
        // Clear all lines below
        for row in (cursorRow + 1)..<rows {
            buffer[row] = Array(repeating: TerminalEmulatorCell(), count: cols)
        }
    }
    
    // MARK: - Attributes
    
    func setForegroundColor(_ color: NSColor) {
        currentForeground = color
    }
    
    func setBackgroundColor(_ color: NSColor) {
        currentBackground = color
    }
    
    func setBold(_ bold: Bool) {
        currentBold = bold
    }
    
    func setUnderline(_ underline: Bool) {
        currentUnderline = underline
    }
    
    func resetAttributes() {
        currentForeground = NSColor(red: 0.976, green: 0.976, blue: 0.976, alpha: 1.0)
        currentBackground = NSColor(red: 0.086, green: 0.086, blue: 0.11, alpha: 1.0)
        currentBold = false
        currentUnderline = false
    }
    
    // MARK: - Resize
    
    func resize(cols: Int, rows: Int) {
        let oldBuffer = buffer
        let oldRows = self.rows
        let oldCols = self.cols
        
        self.cols = cols
        self.rows = rows
        self.scrollBottom = rows - 1
        
        // Create new buffer
        buffer = Array(repeating: Array(repeating: TerminalEmulatorCell(), count: cols), count: rows)
        
        // Copy old content
        for row in 0..<min(oldRows, rows) {
            for col in 0..<min(oldCols, cols) {
                buffer[row][col] = oldBuffer[row][col]
            }
        }
        
        // Adjust cursor position
        cursorRow = min(cursorRow, rows - 1)
        cursorCol = min(cursorCol, cols - 1)
    }
    
    // MARK: - Rendering
    
    func getCell(row: Int, col: Int) -> TerminalEmulatorCell {
        guard row >= 0 && row < rows && col >= 0 && col < cols else {
            return TerminalEmulatorCell()
        }
        return buffer[row][col]
    }
    
    var cursorPosition: (row: Int, col: Int) {
        return (cursorRow, cursorCol)
    }
}

// MARK: - ANSI Escape Sequence Parser
class TerminalANSIParser {
    private var buffer: TerminalBuffer
    private var escapeBuffer: String = ""
    private var inEscapeSequence: Bool = false
    
    init(buffer: TerminalBuffer) {
        self.buffer = buffer
    }
    
    func parse(_ input: String) {
        for char in input {
            if inEscapeSequence {
                escapeBuffer.append(char)
                if isEscapeSequenceComplete() {
                    processEscapeSequence()
                    inEscapeSequence = false
                    escapeBuffer = ""
                }
            } else if char == "\u{1B}" { // ESC character
                inEscapeSequence = true
                escapeBuffer = String(char)
            } else {
                buffer.writeCharacter(char)
            }
        }
    }
    
    private func isEscapeSequenceComplete() -> Bool {
        guard escapeBuffer.count >= 2 else { return false }
        
        let chars = Array(escapeBuffer)
        
        // CSI sequences (ESC [ ...)
        if chars[1] == "[" {
            // Check if we have a final character
            if let last = chars.last {
                return (last >= "A" && last <= "Z") || (last >= "a" && last <= "z")
            }
        }
        // OSC sequences (ESC ] ...)
        else if chars[1] == "]" {
            // Look for BEL or ST terminator
            return escapeBuffer.contains("\u{7}") || escapeBuffer.contains("\u{1B}\\")
        }
        // Other sequences
        else {
            return true
        }
        
        return false
    }
    
    private func processEscapeSequence() {
        let chars = Array(escapeBuffer)
        guard chars.count >= 2 else { return }
        
        if chars[1] == "[" {
            processCSISequence(String(chars.dropFirst(2)))
        }
    }
    
    private func processCSISequence(_ sequence: String) {
        guard let command = sequence.last else { return }
        let params = String(sequence.dropLast())
        
        switch command {
        case "A": // Cursor up
            let n = Int(params) ?? 1
            buffer.moveCursor(rows: -n, cols: 0)
            
        case "B": // Cursor down
            let n = Int(params) ?? 1
            buffer.moveCursor(rows: n, cols: 0)
            
        case "C": // Cursor forward
            let n = Int(params) ?? 1
            buffer.moveCursor(rows: 0, cols: n)
            
        case "D": // Cursor back
            let n = Int(params) ?? 1
            buffer.moveCursor(rows: 0, cols: -n)
            
        case "H", "f": // Cursor position
            let parts = params.split(separator: ";").compactMap { Int($0) }
            let row = (parts.first ?? 1) - 1
            let col = (parts.count > 1 ? parts[1] : 1) - 1
            buffer.setCursor(row: row, col: col)
            
        case "J": // Clear screen
            let n = Int(params) ?? 0
            switch n {
            case 0: buffer.clearToEndOfScreen()
            case 1: break // Clear to beginning (not implemented)
            case 2: buffer.clearScreen()
            default: break
            }
            
        case "K": // Clear line
            let n = Int(params) ?? 0
            switch n {
            case 0: buffer.clearToEndOfLine()
            case 1: break // Clear to beginning (not implemented)
            case 2: buffer.clearLine()
            default: break
            }
            
        case "m": // Set graphics mode
            processGraphicsMode(params)
            
        case "s": // Save cursor
            buffer.saveCursor()
            
        case "u": // Restore cursor
            buffer.restoreCursor()
            
        default:
            // Ignore unhandled sequences
            break
        }
    }
    
    private func processGraphicsMode(_ params: String) {
        let codes = params.split(separator: ";").compactMap { Int($0) }
        
        for code in codes.isEmpty ? [0] : codes {
            switch code {
            case 0: // Reset
                buffer.resetAttributes()
            case 1: // Bold
                buffer.setBold(true)
            case 4: // Underline
                buffer.setUnderline(true)
            case 30...37: // Foreground colors
                if let ansiColor = ANSIColor(rawValue: code) {
                    buffer.setForegroundColor(ansiColor.toNSColor())
                }
            case 40...47: // Background colors
                if let ansiColor = ANSIColor(rawValue: code - 10) {
                    buffer.setBackgroundColor(ansiColor.toNSColor())
                }
            case 90...97: // Bright foreground colors
                if let ansiColor = ANSIColor(rawValue: code) {
                    buffer.setForegroundColor(ansiColor.toNSColor())
                }
            default:
                break
            }
        }
    }
}