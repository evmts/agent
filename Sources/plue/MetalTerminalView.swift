import SwiftUI
import MetalKit
import AppKit

// MARK: - Metal Terminal View (MTKView)
class MetalTerminalNSView: MTKView {
    // Terminal components
    private var buffer: TerminalBuffer
    private var parser: TerminalANSIParser
    private var renderer: MetalTerminalRenderer!
    private var terminalFd: Int32 = -1
    private var isInitialized = false
    private var readSource: DispatchSourceRead?
    
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
    
    override init(frame frameRect: CGRect, device: MTLDevice?) {
        self.buffer = TerminalBuffer(cols: cols, rows: rows)
        self.parser = TerminalANSIParser(buffer: buffer)
        
        super.init(frame: frameRect, device: device)
        
        setupView()
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        // Configure Metal view
        clearColor = MTLClearColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
        isPaused = false
        enableSetNeedsDisplay = true
        
        // Setup renderer
        guard let device = device else {
            onError?(TerminalError.initializationFailed)
            return
        }
        
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        guard let renderer = MetalTerminalRenderer(metalDevice: device, font: font) else {
            onError?(TerminalError.initializationFailed)
            return
        }
        
        self.renderer = renderer
        self.delegate = self
        
        // Setup cursor blinking
        cursorTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.showCursor.toggle()
            self?.needsDisplay = true
        }
        
        // Setup tracking area for mouse events
        updateTrackingAreas()
    }
    
    override func updateTrackingAreas() {
        trackingAreas.forEach { removeTrackingArea($0) }
        
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
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
    
    // MARK: - Size Handling
    
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateTerminalSize()
    }
    
    private func updateTerminalSize() {
        guard isInitialized else { return }
        
        // Get cell size from renderer (this would be calculated based on font metrics)
        let cellWidth: CGFloat = 8  // Placeholder
        let cellHeight: CGFloat = 16 // Placeholder
        
        let newCols = Int(bounds.width / cellWidth)
        let newRows = Int(bounds.height / cellHeight)
        
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
    
    // MARK: - Mouse Handling
    
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let cellWidth: CGFloat = 8  // Placeholder
        let cellHeight: CGFloat = 16 // Placeholder
        
        let col = Int(point.x / cellWidth)
        let row = Int(point.y / cellHeight)
        
        isSelecting = true
        selectionStart = (row: row, col: col)
        selectionEnd = (row: row, col: col)
        needsDisplay = true
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard isSelecting else { return }
        
        let point = convert(event.locationInWindow, from: nil)
        let cellWidth: CGFloat = 8  // Placeholder
        let cellHeight: CGFloat = 16 // Placeholder
        
        let col = Int(point.x / cellWidth)
        let row = Int(point.y / cellHeight)
        
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

// MARK: - MTKViewDelegate
extension MetalTerminalNSView: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Handle size changes if needed
    }
    
    func draw(in view: MTKView) {
        var selection: TerminalSelection? = nil
        
        if let start = selectionStart, let end = selectionEnd {
            selection = TerminalSelection(
                startRow: min(start.row, end.row),
                startCol: start.row < end.row ? start.col : min(start.col, end.col),
                endRow: max(start.row, end.row),
                endCol: start.row > end.row ? end.col : max(start.col, end.col)
            )
        }
        
        renderer.render(buffer: buffer, cursorVisible: showCursor, selection: selection, in: view)
    }
}

// MARK: - SwiftUI Wrapper
struct MetalTerminalView: NSViewRepresentable {
    @Binding var inputText: String
    let onError: (Error) -> Void
    let onOutput: (String) -> Void
    
    func makeNSView(context: Context) -> MetalTerminalNSView {
        guard let device = MTLCreateSystemDefaultDevice() else {
            onError(TerminalError.initializationFailed)
            return MetalTerminalNSView(frame: .zero, device: nil)
        }
        
        let view = MetalTerminalNSView(frame: .zero, device: device)
        view.onError = onError
        view.onOutput = onOutput
        
        // Start terminal when view is created
        DispatchQueue.main.async {
            view.startTerminal()
        }
        
        return view
    }
    
    func updateNSView(_ nsView: MetalTerminalNSView, context: Context) {
        // Handle any updates if needed
        if !inputText.isEmpty {
            nsView.sendText(inputText)
            DispatchQueue.main.async {
                inputText = ""
            }
        }
    }
    
    static func dismantleNSView(_ nsView: MetalTerminalNSView, coordinator: ()) {
        nsView.stopTerminal()
    }
}