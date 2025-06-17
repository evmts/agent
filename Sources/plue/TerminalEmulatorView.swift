import SwiftUI
import AppKit
import Darwin

// MARK: - NSView-based Terminal Emulator View
class TerminalEmulatorNSView: NSView {
    // Terminal components
    private var buffer: TerminalBuffer
    private var parser: TerminalANSIParser
    private var terminalFd: Int32 = -1
    private var isInitialized = false
    private var readSource: DispatchSourceRead?
    
    // Display properties
    private let font = NSFont(name: "SF Mono", size: 13) ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    private var charWidth: CGFloat = 0
    private var lineHeight: CGFloat = 0
    private let backgroundColor = NSColor(red: 0.086, green: 0.086, blue: 0.11, alpha: 1.0) // Ghostty-like background
    private let textColor = NSColor(red: 0.976, green: 0.976, blue: 0.976, alpha: 1.0) // Slightly off-white
    
    // Terminal dimensions
    private var cols: Int = 80
    private var rows: Int = 24
    
    // Cursor
    private var showCursor = true
    private var cursorTimer: Timer?
    
    // Selection
    private var isSelecting = false
    private var selectionStart: (row: Int, col: Int)?
    private var selectionEnd: (row: Int, col: Int)?
    
    // Callbacks
    var onError: ((Error) -> Void)?
    var onOutput: ((String) -> Void)?
    
    override init(frame frameRect: NSRect) {
        self.buffer = TerminalBuffer(cols: cols, rows: rows)
        self.parser = TerminalANSIParser(buffer: buffer)
        super.init(frame: frameRect)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = backgroundColor.cgColor
        
        // Add subtle shadow for depth
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.3
        layer?.shadowOffset = CGSize(width: 0, height: -2)
        layer?.shadowRadius = 4
        
        // Calculate font metrics
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let sampleSize = NSAttributedString(string: "M", attributes: attributes).size()
        charWidth = sampleSize.width
        lineHeight = font.capHeight + font.descender + font.leading + 4 // Add some padding
        
        // Setup cursor blinking
        cursorTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.showCursor.toggle()
            self?.needsDisplay = true
        }
    }
    
    // MARK: - Terminal Lifecycle
    
    func startTerminal() {
        guard !isInitialized else { return }
        
        // Initialize terminal
        if terminal_init() != 0 {
            onError?(TerminalError.initializationFailed)
            return
        }
        
        // Start terminal
        if terminal_start() != 0 {
            onError?(TerminalError.startFailed)
            return
        }
        
        isInitialized = true
        setupReadHandler()
        
        // Send initial resize
        updateTerminalSize()
    }
    
    func stopTerminal() {
        cursorTimer?.invalidate()
        cursorTimer = nil
        
        readSource?.cancel()
        readSource = nil
        
        if isInitialized {
            terminal_stop()
            terminal_deinit()
            isInitialized = false
        }
    }
    
    // MARK: - I/O Handling
    
    private func setupReadHandler() {
        let fd = terminal_get_fd()
        guard fd >= 0 else {
            onError?(TerminalError.invalidFileDescriptor)
            return
        }
        
        terminalFd = fd
        
        // Make the file descriptor non-blocking
        let flags = fcntl(fd, F_GETFL, 0)
        fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        
        // Create dispatch source for efficient I/O
        readSource = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .global(qos: .userInteractive))
        
        readSource?.setEventHandler { [weak self] in
            self?.handleRead()
        }
        
        readSource?.resume()
    }
    
    private func handleRead() {
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        
        let bytesRead = terminal_read(buffer, bufferSize)
        
        if bytesRead > 0 {
            let data = Data(bytes: buffer, count: bytesRead)
            if let text = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async { [weak self] in
                    self?.parser.parse(text)
                    self?.needsDisplay = true
                    self?.onOutput?(text)
                }
            }
        }
    }
    
    func sendText(_ text: String) {
        guard isInitialized else { return }
        
        text.withCString { cString in
            terminal_send_text(cString)
        }
    }
    
    // MARK: - Drawing
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        // Clear background with our custom color
        backgroundColor.setFill()
        dirtyRect.fill()
        
        // Draw each cell
        for row in 0..<rows {
            for col in 0..<cols {
                drawCell(row: row, col: col)
            }
        }
        
        // Draw selection first (behind text)
        if selectionStart != nil && selectionEnd != nil {
            drawSelection()
        }
        
        // Draw cursor last (on top)
        if showCursor {
            drawCursor()
        }
    }
    
    private func drawCell(row: Int, col: Int) {
        let cell = buffer.getCell(row: row, col: col)
        let x = CGFloat(col) * charWidth
        let y = bounds.height - CGFloat(row + 1) * lineHeight // Flip Y coordinate
        
        // Draw background if not default
        if cell.backgroundColor != backgroundColor {
            cell.backgroundColor.setFill()
            NSRect(x: x, y: y, width: charWidth, height: lineHeight).fill()
        }
        
        // Draw character
        if cell.character != " " {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: cell.isBold ? NSFont.boldSystemFont(ofSize: font.pointSize) : font,
                .foregroundColor: cell.foregroundColor,
                .underlineStyle: cell.isUnderlined ? NSUnderlineStyle.single.rawValue : 0
            ]
            
            let str = String(cell.character)
            let attributedString = NSAttributedString(string: str, attributes: attributes)
            attributedString.draw(at: NSPoint(x: x, y: y))
        }
    }
    
    private func drawCursor() {
        let (row, col) = buffer.cursorPosition
        let x = CGFloat(col) * charWidth
        let y = bounds.height - CGFloat(row + 1) * lineHeight
        
        // Use a vibrant cursor color
        NSColor(red: 0.5, green: 0.8, blue: 1.0, alpha: 0.8).setFill()
        
        // Draw a block cursor
        let cursorRect = NSRect(x: x, y: y, width: charWidth, height: lineHeight)
        cursorRect.fill()
        
        // Draw the character in inverted color if there is one
        let cell = buffer.getCell(row: row, col: col)
        if cell.character != " " {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: backgroundColor
            ]
            
            let str = String(cell.character)
            let attributedString = NSAttributedString(string: str, attributes: attributes)
            attributedString.draw(at: NSPoint(x: x, y: y))
        }
    }
    
    private func drawSelection() {
        guard let start = selectionStart, let end = selectionEnd else { return }
        
        NSColor.selectedTextBackgroundColor.setFill()
        
        let startRow = min(start.row, end.row)
        let endRow = max(start.row, end.row)
        let startCol = start.row < end.row || (start.row == end.row && start.col < end.col) ? start.col : end.col
        let endCol = start.row > end.row || (start.row == end.row && start.col > end.col) ? start.col : end.col
        
        for row in startRow...endRow {
            let colStart = row == startRow ? startCol : 0
            let colEnd = row == endRow ? endCol : cols - 1
            
            let x = CGFloat(colStart) * charWidth
            let y = bounds.height - CGFloat(row + 1) * lineHeight
            let width = CGFloat(colEnd - colStart + 1) * charWidth
            
            NSRect(x: x, y: y, width: width, height: lineHeight).fill(using: .sourceAtop)
        }
    }
    
    // MARK: - Size Handling
    
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateTerminalSize()
    }
    
    private func updateTerminalSize() {
        guard isInitialized else { return }
        
        let newCols = Int(bounds.width / charWidth)
        let newRows = Int(bounds.height / lineHeight)
        
        if newCols != cols || newRows != rows {
            cols = max(1, newCols)
            rows = max(1, newRows)
            
            buffer.resize(cols: cols, rows: rows)
            terminal_resize(UInt16(cols), UInt16(rows))
            
            needsDisplay = true
        }
    }
    
    // MARK: - Input Handling
    
    override var acceptsFirstResponder: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        guard isInitialized else { return }
        
        // Handle special keys
        if event.modifierFlags.contains(.control) {
            if let char = event.charactersIgnoringModifiers?.first {
                // Convert to control character
                let controlChar = Character(UnicodeScalar(Int(char.asciiValue ?? 0) & 0x1F)!)
                sendText(String(controlChar))
                return
            }
        }
        
        // Handle regular keys
        if let characters = event.characters {
            sendText(characters)
        }
    }
    
    // MARK: - Mouse Handling for Selection
    
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let col = Int(point.x / charWidth)
        let row = rows - 1 - Int(point.y / lineHeight) // Flip Y coordinate
        
        isSelecting = true
        selectionStart = (row: row, col: col)
        selectionEnd = (row: row, col: col)
        needsDisplay = true
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard isSelecting else { return }
        
        let point = convert(event.locationInWindow, from: nil)
        let col = Int(point.x / charWidth)
        let row = rows - 1 - Int(point.y / lineHeight)
        
        selectionEnd = (row: row, col: col)
        needsDisplay = true
    }
    
    override func mouseUp(with event: NSEvent) {
        isSelecting = false
        
        // Copy selection to clipboard if there is one
        if let selectedText = getSelectedText() {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(selectedText, forType: .string)
        }
    }
    
    private func getSelectedText() -> String? {
        guard let start = selectionStart, let end = selectionEnd else { return nil }
        
        var text = ""
        let startRow = min(start.row, end.row)
        let endRow = max(start.row, end.row)
        
        for row in startRow...endRow {
            let colStart = row == startRow ? start.col : 0
            let colEnd = row == endRow ? end.col : cols - 1
            
            for col in colStart...colEnd {
                let cell = buffer.getCell(row: row, col: col)
                text.append(cell.character)
            }
            
            if row < endRow {
                text.append("\n")
            }
        }
        
        return text.trimmingCharacters(in: .whitespaces).isEmpty ? nil : text
    }
    
    // MARK: - Cleanup
    
    deinit {
        stopTerminal()
    }
}

// MARK: - SwiftUI Wrapper
struct TerminalEmulator: NSViewRepresentable {
    @Binding var inputText: String
    let onError: (Error) -> Void
    let onOutput: (String) -> Void
    
    func makeNSView(context: Context) -> TerminalEmulatorNSView {
        let view = TerminalEmulatorNSView()
        view.onError = onError
        view.onOutput = onOutput
        
        // Start terminal when view is created
        DispatchQueue.main.async {
            view.startTerminal()
        }
        
        return view
    }
    
    func updateNSView(_ nsView: TerminalEmulatorNSView, context: Context) {
        // Handle any updates if needed
        if !inputText.isEmpty {
            nsView.sendText(inputText)
            DispatchQueue.main.async {
                inputText = ""
            }
        }
    }
    
    static func dismantleNSView(_ nsView: TerminalEmulatorNSView, coordinator: ()) {
        nsView.stopTerminal()
    }
}