import SwiftUI
import AppKit

// MARK: - NSView-based Terminal Surface
class TerminalSurfaceView: NSView {
    // Terminal state
    private var terminalFd: Int32 = -1
    private var isInitialized = false
    private var readSource: DispatchSourceRead?
    
    // Display properties
    private let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    private var textStorage = NSTextStorage()
    private var layoutManager = NSLayoutManager()
    private var textContainer = NSTextContainer()
    private let ansiParser = ANSIParser()
    
    // Terminal dimensions
    private var cols: Int = 80
    private var rows: Int = 24
    
    // Callbacks
    var onError: ((Error) -> Void)?
    var onOutput: ((String) -> Void)?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupTextSystem()
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupTextSystem() {
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)
        textContainer.lineFragmentPadding = 0
        textContainer.widthTracksTextView = true
        textContainer.containerSize = CGSize(width: bounds.width, height: .greatestFiniteMagnitude)
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
        // Get the file descriptor from our Zig backend
        let fd = terminal_get_fd()
        guard fd >= 0 else {
            onError?(TerminalError.invalidFileDescriptor)
            return
        }
        
        // Create dispatch source for efficient I/O
        readSource = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .global(qos: .userInteractive))
        
        readSource?.setEventHandler { [weak self] in
            self?.handleRead()
        }
        
        readSource?.setCancelHandler {
            // Cleanup if needed
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
                    self?.appendText(text)
                    self?.onOutput?(text)
                }
            }
        } else if bytesRead < 0 {
            DispatchQueue.main.async { [weak self] in
                self?.onError?(TerminalError.readError)
            }
        }
    }
    
    func sendText(_ text: String) {
        guard isInitialized else { return }
        
        text.withCString { cString in
            terminal_send_text(cString)
        }
    }
    
    // MARK: - Display
    
    private func appendText(_ text: String) {
        // Parse ANSI escape sequences
        let attributedString = ansiParser.parse(text)
        
        textStorage.append(attributedString)
        
        // Limit buffer size
        if textStorage.length > 100000 {
            textStorage.deleteCharacters(in: NSRange(location: 0, length: 50000))
        }
        
        needsDisplay = true
        
        // Auto-scroll to bottom
        if let scrollView = self.enclosingScrollView {
            let maxY = max(0, bounds.height - scrollView.contentView.bounds.height)
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: maxY))
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        // Clear background
        NSColor.black.setFill()
        dirtyRect.fill()
        
        // Draw text
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        let textOrigin = CGPoint(x: 5, y: 5)
        
        layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: textOrigin)
    }
    
    // MARK: - Size Handling
    
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        textContainer.containerSize = CGSize(width: newSize.width - 10, height: .greatestFiniteMagnitude)
        updateTerminalSize()
    }
    
    private func updateTerminalSize() {
        guard isInitialized else { return }
        
        // Calculate rows and columns based on font metrics
        let charWidth = font.maximumAdvancement.width
        let lineHeight = layoutManager.defaultLineHeight(for: font)
        
        let newCols = Int((bounds.width - 10) / charWidth)
        let newRows = Int((bounds.height - 10) / lineHeight)
        
        if newCols != cols || newRows != rows {
            cols = newCols
            rows = newRows
            
            // Update terminal size
            terminal_resize(UInt16(cols), UInt16(rows))
        }
    }
    
    // MARK: - Input Handling
    
    override var acceptsFirstResponder: Bool { true }
    
    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return true
    }
    
    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return true
    }
    
    override func keyDown(with event: NSEvent) {
        guard isInitialized else { return }
        
        if let characters = event.characters {
            sendText(characters)
        }
    }
    
    // MARK: - Cleanup
    
    deinit {
        stopTerminal()
    }
}

// MARK: - SwiftUI Wrapper

struct TerminalSurface: NSViewRepresentable {
    @Binding var inputText: String
    let onError: (Error) -> Void
    let onOutput: (String) -> Void
    
    func makeNSView(context: Context) -> TerminalSurfaceView {
        let view = TerminalSurfaceView()
        view.onError = onError
        view.onOutput = onOutput
        
        // Start terminal when view is created
        DispatchQueue.main.async {
            view.startTerminal()
        }
        
        return view
    }
    
    func updateNSView(_ nsView: TerminalSurfaceView, context: Context) {
        // Handle any updates if needed
        if !inputText.isEmpty {
            nsView.sendText(inputText)
            DispatchQueue.main.async {
                inputText = ""
            }
        }
    }
    
    static func dismantleNSView(_ nsView: TerminalSurfaceView, coordinator: ()) {
        nsView.stopTerminal()
    }
}

// MARK: - Error Types

enum TerminalError: LocalizedError {
    case initializationFailed
    case startFailed
    case invalidFileDescriptor
    case readError
    
    var errorDescription: String? {
        switch self {
        case .initializationFailed:
            return "Failed to initialize terminal"
        case .startFailed:
            return "Failed to start terminal process"
        case .invalidFileDescriptor:
            return "Invalid file descriptor"
        case .readError:
            return "Error reading from terminal"
        }
    }
}

// MARK: - C Function Imports

@_silgen_name("terminal_get_fd")
func terminal_get_fd() -> Int32

@_silgen_name("terminal_resize")
func terminal_resize(_ cols: UInt16, _ rows: UInt16)