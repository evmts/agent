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
    private var alternateBuffer: [[TerminalEmulatorCell]]?
    private var usingAlternateBuffer = false
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
    
    // Terminal modes
    private var insertMode = false
    private var autoWrap = true
    private var originMode = false
    private var reverseVideo = false
    private var cursorVisible = true
    private var cursorKeysMode = false
    private var keypadApplicationMode = false
    private var alternateCharacterSet = false
    private var bracketedPasteMode = false
    private var lineFeedMode = false
    
    // Tab stops
    private var tabStops: Set<Int> = []
    
    init(cols: Int, rows: Int) {
        self.cols = cols
        self.rows = rows
        self.scrollBottom = rows - 1
        self.buffer = Array(repeating: Array(repeating: TerminalEmulatorCell(), count: cols), count: rows)
        
        // Initialize default tab stops every 8 columns
        for i in stride(from: 0, to: cols, by: 8) {
            tabStops.insert(i)
        }
    }
    
    // MARK: - Buffer Management
    
    private var activeBuffer: [[TerminalEmulatorCell]] {
        get { return usingAlternateBuffer ? (alternateBuffer ?? buffer) : buffer }
        set { 
            if usingAlternateBuffer {
                alternateBuffer = newValue
            } else {
                buffer = newValue
            }
        }
    }
    
    // MARK: - Cursor Management
    
    func setCursor(row: Int, col: Int) {
        if originMode {
            cursorRow = max(scrollTop, min(row + scrollTop, scrollBottom))
        } else {
            cursorRow = max(0, min(row, rows - 1))
        }
        cursorCol = max(0, min(col, cols - 1))
    }
    
    func setCursorRow(_ row: Int) {
        setCursor(row: row, col: cursorCol)
    }
    
    func setCursorColumn(_ col: Int) {
        setCursor(row: cursorRow, col: col)
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
                activeBuffer[cursorRow][cursorCol] = TerminalEmulatorCell()
            }
        } else if char == "\t" {
            // Move to next tab stop
            var nextTab = cursorCol + 1
            while nextTab < cols && !tabStops.contains(nextTab) {
                nextTab += 1
            }
            cursorCol = min(nextTab, cols - 1)
        } else if char == "\u{7}" { // BEL
            // Bell - ignore for now
        } else if char == "\u{0B}" || char == "\u{0C}" { // VT or FF
            newLine()
        } else {
            // Handle special drawing characters if in alternate character set
            let displayChar = alternateCharacterSet ? mapAlternateCharacter(char) : char
            
            // Insert mode handling
            if insertMode && cursorCol < cols - 1 {
                // Shift characters to the right
                for col in (cursorCol..<cols-1).reversed() {
                    activeBuffer[cursorRow][col + 1] = activeBuffer[cursorRow][col]
                }
            }
            
            // Write the character
            if cursorCol < cols {
                activeBuffer[cursorRow][cursorCol] = TerminalEmulatorCell(
                    character: displayChar,
                    foregroundColor: reverseVideo ? currentBackground : currentForeground,
                    backgroundColor: reverseVideo ? currentForeground : currentBackground,
                    isBold: currentBold,
                    isUnderlined: currentUnderline
                )
                cursorCol += 1
                if cursorCol >= cols {
                    if autoWrap {
                        cursorCol = 0
                        newLine()
                    } else {
                        cursorCol = cols - 1
                    }
                }
            }
        }
    }
    
    private func mapAlternateCharacter(_ char: Character) -> Character {
        // VT100 Special Graphics Character Set mapping
        switch char {
        case "j": return "\u{2518}"  // Lower right corner
        case "k": return "\u{2510}"  // Upper right corner
        case "l": return "\u{250C}"  // Upper left corner
        case "m": return "\u{2514}"  // Lower left corner
        case "n": return "\u{253C}"  // Crossing lines
        case "q": return "\u{2500}"  // Horizontal line
        case "t": return "\u{251C}"  // Left tee
        case "u": return "\u{2524}"  // Right tee
        case "v": return "\u{2534}"  // Bottom tee
        case "w": return "\u{252C}"  // Top tee
        case "x": return "\u{2502}"  // Vertical line
        case "~": return "\u{00B7}"  // Centered dot
        case "`": return "\u{25C6}"  // Diamond
        case "a": return "\u{2592}"  // Checkerboard
        case "f": return "\u{00B0}"  // Degree symbol
        case "g": return "\u{00B1}"  // Plus/minus
        case "o": return "\u{23AF}"  // Scan line 1
        case "s": return "_"  // Scan line 9
        case "0": return "\u{25AE}"  // Solid block
        default: return char
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
            activeBuffer[row] = activeBuffer[row + 1]
        }
        // Clear the bottom line
        activeBuffer[scrollBottom] = Array(repeating: TerminalEmulatorCell(), count: cols)
    }
    
    private func scrollDown() {
        // Move all lines down by one within the scroll region
        for row in (scrollTop+1...scrollBottom).reversed() {
            activeBuffer[row] = activeBuffer[row - 1]
        }
        // Clear the top line
        activeBuffer[scrollTop] = Array(repeating: TerminalEmulatorCell(), count: cols)
    }
    
    // MARK: - Clearing
    
    func clearScreen() {
        activeBuffer = Array(repeating: Array(repeating: TerminalEmulatorCell(), count: cols), count: rows)
        cursorRow = 0
        cursorCol = 0
    }
    
    func clearToBeginningOfScreen() {
        // Clear from beginning to cursor
        for row in 0..<cursorRow {
            activeBuffer[row] = Array(repeating: TerminalEmulatorCell(), count: cols)
        }
        clearToBeginningOfLine()
    }
    
    func clearScrollback() {
        // Clear scrollback buffer if implemented
    }
    
    func clearLine() {
        activeBuffer[cursorRow] = Array(repeating: TerminalEmulatorCell(), count: cols)
    }
    
    func clearToBeginningOfLine() {
        for col in 0...cursorCol {
            activeBuffer[cursorRow][col] = TerminalEmulatorCell()
        }
    }
    
    func clearToEndOfLine() {
        for col in cursorCol..<cols {
            activeBuffer[cursorRow][col] = TerminalEmulatorCell()
        }
    }
    
    func clearToEndOfScreen() {
        // Clear from cursor to end of line
        clearToEndOfLine()
        // Clear all lines below
        for row in (cursorRow + 1)..<rows {
            activeBuffer[row] = Array(repeating: TerminalEmulatorCell(), count: cols)
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
        let oldBuffer = activeBuffer
        let oldRows = self.rows
        let oldCols = self.cols
        
        self.cols = cols
        self.rows = rows
        self.scrollBottom = rows - 1
        
        // Create new buffer
        activeBuffer = Array(repeating: Array(repeating: TerminalEmulatorCell(), count: cols), count: rows)
        
        // Copy old content
        for row in 0..<min(oldRows, rows) {
            for col in 0..<min(oldCols, cols) {
                activeBuffer[row][col] = oldBuffer[row][col]
            }
        }
        
        // Resize alternate buffer if it exists
        if alternateBuffer != nil {
            alternateBuffer = Array(repeating: Array(repeating: TerminalEmulatorCell(), count: cols), count: rows)
        }
        
        // Adjust cursor position
        cursorRow = min(cursorRow, rows - 1)
        cursorCol = min(cursorCol, cols - 1)
        
        // Reset tab stops
        tabStops.removeAll()
        for i in stride(from: 0, to: cols, by: 8) {
            tabStops.insert(i)
        }
    }
    
    // MARK: - Rendering
    
    func getCell(row: Int, col: Int) -> TerminalEmulatorCell {
        guard row >= 0 && row < rows && col >= 0 && col < cols else {
            return TerminalEmulatorCell()
        }
        return activeBuffer[row][col]
    }
    
    var cursorPosition: (row: Int, col: Int) {
        return (cursorRow, cursorCol)
    }
    
    // MARK: - Additional Terminal Operations
    
    func insertLines(_ count: Int) {
        guard cursorRow >= scrollTop && cursorRow <= scrollBottom else { return }
        
        for _ in 0..<count {
            // Move lines down
            for row in (cursorRow..<scrollBottom).reversed() {
                activeBuffer[row + 1] = activeBuffer[row]
            }
            // Clear the current line
            activeBuffer[cursorRow] = Array(repeating: TerminalEmulatorCell(), count: cols)
        }
    }
    
    func deleteLines(_ count: Int) {
        guard cursorRow >= scrollTop && cursorRow <= scrollBottom else { return }
        
        for _ in 0..<count {
            // Move lines up
            for row in cursorRow..<scrollBottom {
                activeBuffer[row] = activeBuffer[row + 1]
            }
            // Clear the bottom line
            activeBuffer[scrollBottom] = Array(repeating: TerminalEmulatorCell(), count: cols)
        }
    }
    
    func insertCharacters(_ count: Int) {
        guard cursorCol < cols else { return }
        
        let shiftCount = min(count, cols - cursorCol - 1)
        if shiftCount > 0 {
            // Shift characters to the right
            for col in (cursorCol..<cols-shiftCount).reversed() {
                activeBuffer[cursorRow][col + shiftCount] = activeBuffer[cursorRow][col]
            }
            // Clear the inserted space
            for col in cursorCol..<cursorCol+shiftCount {
                activeBuffer[cursorRow][col] = TerminalEmulatorCell()
            }
        }
    }
    
    func deleteCharacters(_ count: Int) {
        guard cursorCol < cols else { return }
        
        let deleteCount = min(count, cols - cursorCol)
        // Shift characters to the left
        for col in cursorCol..<cols-deleteCount {
            activeBuffer[cursorRow][col] = activeBuffer[cursorRow][col + deleteCount]
        }
        // Clear the end
        for col in cols-deleteCount..<cols {
            activeBuffer[cursorRow][col] = TerminalEmulatorCell()
        }
    }
    
    func eraseCharacters(_ count: Int) {
        let eraseCount = min(count, cols - cursorCol)
        for col in cursorCol..<cursorCol+eraseCount {
            activeBuffer[cursorRow][col] = TerminalEmulatorCell()
        }
    }
    
    func scrollUp(_ count: Int) {
        for _ in 0..<count {
            scrollUp()
        }
    }
    
    func scrollDown(_ count: Int) {
        for _ in 0..<count {
            scrollDown()
        }
    }
    
    func setScrollRegion(top: Int, bottom: Int) {
        scrollTop = max(0, min(top, rows - 1))
        scrollBottom = max(scrollTop, min(bottom, rows - 1))
        // Move cursor to home position
        setCursor(row: 0, col: 0)
    }
    
    func index() {
        if cursorRow == scrollBottom {
            scrollUp()
        } else if cursorRow < rows - 1 {
            cursorRow += 1
        }
    }
    
    func reverseIndex() {
        if cursorRow == scrollTop {
            scrollDown()
        } else if cursorRow > 0 {
            cursorRow -= 1
        }
    }
    
    func nextLine() {
        cursorCol = 0
        index()
    }
    
    func setTabStop() {
        tabStops.insert(cursorCol)
    }
    
    func clearTabStop() {
        tabStops.remove(cursorCol)
    }
    
    func clearAllTabStops() {
        tabStops.removeAll()
    }
    
    func reset() {
        clearScreen()
        cursorRow = 0
        cursorCol = 0
        savedCursorRow = 0
        savedCursorCol = 0
        scrollTop = 0
        scrollBottom = rows - 1
        resetAttributes()
        
        // Reset modes
        insertMode = false
        autoWrap = true
        originMode = false
        reverseVideo = false
        cursorVisible = true
        cursorKeysMode = false
        keypadApplicationMode = false
        alternateCharacterSet = false
        bracketedPasteMode = false
        lineFeedMode = false
        
        // Reset tab stops
        tabStops.removeAll()
        for i in stride(from: 0, to: cols, by: 8) {
            tabStops.insert(i)
        }
    }
    
    // MARK: - Mode Settings
    
    func setInsertMode(_ enabled: Bool) {
        insertMode = enabled
    }
    
    func setAutoWrap(_ enabled: Bool) {
        autoWrap = enabled
    }
    
    func setOriginMode(_ enabled: Bool) {
        originMode = enabled
        if enabled {
            setCursor(row: 0, col: 0)
        }
    }
    
    func setReverseVideo(_ enabled: Bool) {
        reverseVideo = enabled
    }
    
    func setCursorVisible(_ enabled: Bool) {
        cursorVisible = enabled
    }
    
    func setCursorKeysMode(_ enabled: Bool) {
        cursorKeysMode = enabled
    }
    
    func setKeypadApplicationMode(_ enabled: Bool) {
        keypadApplicationMode = enabled
    }
    
    func setAlternateCharacterSet(_ enabled: Bool) {
        alternateCharacterSet = enabled
    }
    
    func setBracketedPasteMode(_ enabled: Bool) {
        bracketedPasteMode = enabled
    }
    
    func setLineFeedMode(_ enabled: Bool) {
        lineFeedMode = enabled
    }
    
    func setAlternateScreenBuffer(_ enabled: Bool) {
        if enabled && !usingAlternateBuffer {
            // Switch to alternate buffer
            alternateBuffer = Array(repeating: Array(repeating: TerminalEmulatorCell(), count: cols), count: rows)
            usingAlternateBuffer = true
            // Clear the alternate buffer
            clearScreen()
        } else if !enabled && usingAlternateBuffer {
            // Switch back to main buffer
            usingAlternateBuffer = false
            alternateBuffer = nil
        }
    }
    
    var isCursorVisible: Bool {
        return cursorVisible
    }
}

// MARK: - ANSI Escape Sequence Parser
class TerminalANSIParser {
    private var buffer: TerminalBuffer
    private var escapeBuffer: String = ""
    private var inEscapeSequence: Bool = false
    private var parserState: ParserState = .normal
    
    // Parser states for more complex sequences
    private enum ParserState {
        case normal
        case escape
        case csi
        case osc
        case dcs
        case sos
        case pm
        case apc
    }
    
    init(buffer: TerminalBuffer) {
        self.buffer = buffer
    }
    
    func parse(_ input: String) {
        let data = input.data(using: .utf8) ?? Data()
        
        for byte in data {
            switch parserState {
            case .normal:
                if byte == 0x1B { // ESC
                    parserState = .escape
                    escapeBuffer = ""
                } else if byte == 0x0E { // SO - Shift Out (alternate character set)
                    buffer.setAlternateCharacterSet(true)
                } else if byte == 0x0F { // SI - Shift In (normal character set)
                    buffer.setAlternateCharacterSet(false)
                } else {
                    // Handle normal characters and UTF-8
                    handleNormalByte(byte, data: data)
                }
                
            case .escape:
                escapeBuffer.append(Character(UnicodeScalar(byte)))
                switch byte {
                case 0x5B: // [
                    parserState = .csi
                    escapeBuffer = ""
                case 0x5D: // ]
                    parserState = .osc
                    escapeBuffer = ""
                case 0x50: // P
                    parserState = .dcs
                    escapeBuffer = ""
                case 0x58: // X
                    parserState = .sos
                    escapeBuffer = ""
                case 0x5E: // ^
                    parserState = .pm
                    escapeBuffer = ""
                case 0x5F: // _
                    parserState = .apc
                    escapeBuffer = ""
                case 0x28, 0x29, 0x2A, 0x2B: // Character set sequences
                    // Handle in next byte
                    break
                case 0x3D: // DECKPAM - Keypad Application Mode
                    buffer.setKeypadApplicationMode(true)
                    parserState = .normal
                case 0x3E: // DECKPNM - Keypad Numeric Mode
                    buffer.setKeypadApplicationMode(false)
                    parserState = .normal
                case 0x37: // DECSC - Save cursor
                    buffer.saveCursor()
                    parserState = .normal
                case 0x38: // DECRC - Restore cursor
                    buffer.restoreCursor()
                    parserState = .normal
                case 0x4D: // RI - Reverse Index
                    buffer.reverseIndex()
                    parserState = .normal
                case 0x45: // NEL - Next Line
                    buffer.nextLine()
                    parserState = .normal
                case 0x63: // RIS - Reset to Initial State
                    buffer.reset()
                    parserState = .normal
                default:
                    if byte >= 0x40 && byte <= 0x5F {
                        // Two-character escape sequence
                        processSimpleEscape(byte)
                        parserState = .normal
                    }
                }
                
            case .csi:
                if byte >= 0x40 && byte <= 0x7E { // Final byte
                    processCSISequence(escapeBuffer + String(Character(UnicodeScalar(byte))))
                    parserState = .normal
                    escapeBuffer = ""
                } else {
                    escapeBuffer.append(Character(UnicodeScalar(byte)))
                }
                
            case .osc:
                if byte == 0x07 { // BEL
                    processOSCSequence(escapeBuffer)
                    parserState = .normal
                    escapeBuffer = ""
                } else if byte == 0x1B { // Check for ST (ESC \)
                    // Will be handled in next iteration
                    escapeBuffer.append(Character(UnicodeScalar(byte)))
                } else if escapeBuffer.hasSuffix("\u{1B}\\") {
                    processOSCSequence(String(escapeBuffer.dropLast(2)))
                    parserState = .normal
                    escapeBuffer = ""
                } else {
                    escapeBuffer.append(Character(UnicodeScalar(byte)))
                }
                
            case .dcs, .sos, .pm, .apc:
                // For now, consume until ST (ESC \)
                if byte == 0x1B {
                    escapeBuffer.append(Character(UnicodeScalar(byte)))
                } else if escapeBuffer.hasSuffix("\u{1B}") && byte == 0x5C { // \
                    parserState = .normal
                    escapeBuffer = ""
                } else {
                    escapeBuffer.append(Character(UnicodeScalar(byte)))
                }
            }
        }
    }
    
    private var utf8Buffer: [UInt8] = []
    private var utf8BytesNeeded = 0
    
    private func handleNormalByte(_ byte: UInt8, data: Data) {
        // Handle UTF-8 properly
        if byte < 0x80 {
            // ASCII character
            buffer.writeCharacter(Character(UnicodeScalar(byte)))
        } else if (byte & 0xE0) == 0xC0 {
            // Start of 2-byte UTF-8 sequence
            utf8Buffer = [byte]
            utf8BytesNeeded = 1
        } else if (byte & 0xF0) == 0xE0 {
            // Start of 3-byte UTF-8 sequence
            utf8Buffer = [byte]
            utf8BytesNeeded = 2
        } else if (byte & 0xF8) == 0xF0 {
            // Start of 4-byte UTF-8 sequence
            utf8Buffer = [byte]
            utf8BytesNeeded = 3
        } else if (byte & 0xC0) == 0x80 && utf8BytesNeeded > 0 {
            // Continuation byte
            utf8Buffer.append(byte)
            utf8BytesNeeded -= 1
            
            if utf8BytesNeeded == 0 {
                // UTF-8 sequence complete
                if let string = String(data: Data(utf8Buffer), encoding: .utf8),
                   let char = string.first {
                    buffer.writeCharacter(char)
                }
                utf8Buffer.removeAll()
            }
        } else {
            // Invalid UTF-8 byte - skip
            utf8Buffer.removeAll()
            utf8BytesNeeded = 0
        }
    }
    
    private func processSimpleEscape(_ byte: UInt8) {
        // Handle simple two-character escape sequences
        switch byte {
        case 0x44: // IND - Index
            buffer.index()
        case 0x45: // NEL - Next Line
            buffer.nextLine()
        case 0x48: // HTS - Horizontal Tab Set
            buffer.setTabStop()
        case 0x4D: // RI - Reverse Index
            buffer.reverseIndex()
        default:
            break
        }
    }
    
    private func processOSCSequence(_ sequence: String) {
        // Handle Operating System Command sequences
        let parts = sequence.split(separator: ";")
        guard let code = parts.first.flatMap({ Int($0) }) else { return }
        
        switch code {
        case 0: // Set window title
            // Not implemented in terminal buffer
            break
        case 4: // Set color palette
            // Not implemented
            break
        default:
            break
        }
    }
    
    private func processCSISequence(_ sequence: String) {
        guard let command = sequence.last else { return }
        let params = String(sequence.dropLast())
        
        // Check for private mode character
        let isPrivate = params.first == "?"
        let actualParams = isPrivate ? String(params.dropFirst()) : params
        
        switch command {
        case "A": // CUU - Cursor up
            let n = Int(actualParams) ?? 1
            buffer.moveCursor(rows: -n, cols: 0)
            
        case "B": // CUD - Cursor down
            let n = Int(actualParams) ?? 1
            buffer.moveCursor(rows: n, cols: 0)
            
        case "C": // CUF - Cursor forward
            let n = Int(actualParams) ?? 1
            buffer.moveCursor(rows: 0, cols: n)
            
        case "D": // CUB - Cursor back
            let n = Int(actualParams) ?? 1
            buffer.moveCursor(rows: 0, cols: -n)
            
        case "E": // CNL - Cursor next line
            let n = Int(actualParams) ?? 1
            buffer.moveCursor(rows: n, cols: 0)
            buffer.setCursorColumn(0)
            
        case "F": // CPL - Cursor previous line
            let n = Int(actualParams) ?? 1
            buffer.moveCursor(rows: -n, cols: 0)
            buffer.setCursorColumn(0)
            
        case "G": // CHA - Cursor horizontal absolute
            let n = Int(actualParams) ?? 1
            buffer.setCursorColumn(n - 1)
            
        case "H", "f": // CUP - Cursor position
            let parts = actualParams.split(separator: ";").compactMap { Int($0) }
            let row = (parts.first ?? 1) - 1
            let col = (parts.count > 1 ? parts[1] : 1) - 1
            buffer.setCursor(row: row, col: col)
            
        case "J": // ED - Erase display
            let n = Int(actualParams) ?? 0
            switch n {
            case 0: buffer.clearToEndOfScreen()
            case 1: buffer.clearToBeginningOfScreen()
            case 2: buffer.clearScreen()
            case 3: buffer.clearScrollback()
            default: break
            }
            
        case "K": // EL - Erase line
            let n = Int(actualParams) ?? 0
            switch n {
            case 0: buffer.clearToEndOfLine()
            case 1: buffer.clearToBeginningOfLine()
            case 2: buffer.clearLine()
            default: break
            }
            
        case "L": // IL - Insert lines
            let n = Int(actualParams) ?? 1
            buffer.insertLines(n)
            
        case "M": // DL - Delete lines
            let n = Int(actualParams) ?? 1
            buffer.deleteLines(n)
            
        case "P": // DCH - Delete characters
            let n = Int(actualParams) ?? 1
            buffer.deleteCharacters(n)
            
        case "S": // SU - Scroll up
            let n = Int(actualParams) ?? 1
            buffer.scrollUp(n)
            
        case "T": // SD - Scroll down
            let n = Int(actualParams) ?? 1
            buffer.scrollDown(n)
            
        case "X": // ECH - Erase characters
            let n = Int(actualParams) ?? 1
            buffer.eraseCharacters(n)
            
        case "c": // DA - Device attributes
            // Send response through terminal
            break
            
        case "d": // VPA - Vertical position absolute
            let n = Int(actualParams) ?? 1
            buffer.setCursorRow(n - 1)
            
        case "g": // TBC - Tab clear
            let n = Int(actualParams) ?? 0
            switch n {
            case 0: buffer.clearTabStop()
            case 3: buffer.clearAllTabStops()
            default: break
            }
            
        case "h": // SM - Set mode
            if isPrivate {
                processPrivateMode(actualParams, enable: true)
            } else {
                processMode(actualParams, enable: true)
            }
            
        case "l": // RM - Reset mode
            if isPrivate {
                processPrivateMode(actualParams, enable: false)
            } else {
                processMode(actualParams, enable: false)
            }
            
        case "m": // SGR - Set graphics rendition
            processGraphicsMode(actualParams)
            
        case "n": // DSR - Device status report
            processDSR(actualParams)
            
        case "r": // DECSTBM - Set scrolling region
            let parts = actualParams.split(separator: ";").compactMap { Int($0) }
            let top = (parts.first ?? 1) - 1
            let bottom = (parts.count > 1 ? parts[1] : buffer.rows) - 1
            buffer.setScrollRegion(top: top, bottom: bottom)
            
        case "s": // Save cursor (ANSI.SYS)
            buffer.saveCursor()
            
        case "u": // Restore cursor (ANSI.SYS)
            buffer.restoreCursor()
            
        case "@": // ICH - Insert characters
            let n = Int(actualParams) ?? 1
            buffer.insertCharacters(n)
            
        default:
            // Ignore unhandled sequences
            break
        }
    }
    
    private func processPrivateMode(_ params: String, enable: Bool) {
        let modes = params.split(separator: ";").compactMap { Int($0) }
        for mode in modes {
            switch mode {
            case 1: // DECCKM - Cursor keys
                buffer.setCursorKeysMode(enable)
            case 3: // DECCOLM - 132 column mode
                // Not implemented
                break
            case 4: // DECSCLM - Smooth scroll
                // Not implemented
                break
            case 5: // DECSCNM - Reverse video
                buffer.setReverseVideo(enable)
            case 6: // DECOM - Origin mode
                buffer.setOriginMode(enable)
            case 7: // DECAWM - Auto wrap
                buffer.setAutoWrap(enable)
            case 25: // DECTCEM - Cursor visible
                buffer.setCursorVisible(enable)
            case 47, 1047: // Alternate screen buffer
                buffer.setAlternateScreenBuffer(enable)
            case 1048: // Save/restore cursor
                if enable {
                    buffer.saveCursor()
                } else {
                    buffer.restoreCursor()
                }
            case 1049: // Save cursor and use alternate screen buffer
                if enable {
                    buffer.saveCursor()
                    buffer.setAlternateScreenBuffer(true)
                } else {
                    buffer.setAlternateScreenBuffer(false)
                    buffer.restoreCursor()
                }
            case 2004: // Bracketed paste mode
                buffer.setBracketedPasteMode(enable)
            default:
                break
            }
        }
    }
    
    private func processMode(_ params: String, enable: Bool) {
        let modes = params.split(separator: ";").compactMap { Int($0) }
        for mode in modes {
            switch mode {
            case 4: // IRM - Insert mode
                buffer.setInsertMode(enable)
            case 20: // LNM - Line feed/new line mode
                buffer.setLineFeedMode(enable)
            default:
                break
            }
        }
    }
    
    private func processDSR(_ params: String) {
        guard let code = Int(params) else { return }
        
        switch code {
        case 5: // Device status
            // Send "OK" response: ESC [ 0 n
            break
        case 6: // Cursor position report
            // Send cursor position: ESC [ row ; col R
            break
        default:
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