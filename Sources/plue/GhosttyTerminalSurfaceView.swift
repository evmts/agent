import SwiftUI
import AppKit
import Metal
import MetalKit

// MARK: - C Function Imports for Ghostty

@_silgen_name("ghostty_terminal_init")
func ghostty_terminal_init() -> Int32

@_silgen_name("ghostty_terminal_deinit")
func ghostty_terminal_deinit()

@_silgen_name("ghostty_terminal_create_surface")
func ghostty_terminal_create_surface() -> Int32

@_silgen_name("ghostty_terminal_set_size")
func ghostty_terminal_set_size(_ width: UInt32, _ height: UInt32, _ scale: Double)

@_silgen_name("ghostty_terminal_send_key")
func ghostty_terminal_send_key(_ key: UnsafePointer<CChar>, _ modifiers: UInt32, _ action: Int32)

@_silgen_name("ghostty_terminal_send_text")
func ghostty_terminal_send_text(_ text: UnsafePointer<CChar>)

@_silgen_name("ghostty_terminal_write")
func ghostty_terminal_write(_ data: UnsafePointer<UInt8>, _ len: Int) -> Int

@_silgen_name("ghostty_terminal_read")
func ghostty_terminal_read(_ buffer: UnsafeMutablePointer<UInt8>, _ len: Int) -> Int

@_silgen_name("ghostty_terminal_draw")
func ghostty_terminal_draw()

// MARK: - Metal View for Ghostty Rendering

class GhosttyMetalView: MTKView {
    private var isInitialized = false
    
    override init(frame frameRect: CGRect, device: MTLDevice?) {
        super.init(frame: frameRect, device: device ?? MTLCreateSystemDefaultDevice())
        setupMetal()
    }
    
    required init(coder: NSCoder) {
        super.init(coder: coder)
        setupMetal()
    }
    
    private func setupMetal() {
        // Configure Metal view for Ghostty
        self.colorPixelFormat = .bgra8Unorm
        self.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        self.isPaused = false
        self.enableSetNeedsDisplay = true
    }
    
    override func draw(_ rect: CGRect) {
        super.draw(rect)
        
        if isInitialized {
            // Let Ghostty handle the drawing
            ghostty_terminal_draw()
        }
    }
    
    func setInitialized(_ initialized: Bool) {
        self.isInitialized = initialized
    }
}

// MARK: - NSView-based Ghostty Terminal Surface

class GhosttyTerminalSurfaceView: NSView {
    // Terminal state
    private var isInitialized = false
    private var metalView: GhosttyMetalView?
    private var readSource: DispatchSourceRead?
    private var readFileDescriptor: Int32 = -1
    
    // Callbacks
    var onError: ((Error) -> Void)?
    var onOutput: ((String) -> Void)?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        
        // Create Metal view for Ghostty rendering
        let device = MTLCreateSystemDefaultDevice()
        metalView = GhosttyMetalView(frame: bounds, device: device)
        if let metalView = metalView {
            metalView.autoresizingMask = [.width, .height]
            addSubview(metalView)
        }
    }
    
    // MARK: - Terminal Lifecycle
    
    func startTerminal() {
        guard !isInitialized else { return }
        
        // Initialize Ghostty terminal
        if ghostty_terminal_init() != 0 {
            onError?(TerminalError.initializationFailed)
            return
        }
        
        // Create terminal surface
        if ghostty_terminal_create_surface() != 0 {
            onError?(TerminalError.startFailed)
            return
        }
        
        isInitialized = true
        metalView?.setInitialized(true)
        
        // Set initial size
        updateTerminalSize()
        
        // Start reading output
        setupReadHandler()
    }
    
    func stopTerminal() {
        readSource?.cancel()
        readSource = nil
        
        if isInitialized {
            ghostty_terminal_deinit()
            isInitialized = false
            metalView?.setInitialized(false)
        }
    }
    
    // MARK: - I/O Handling
    
    private func setupReadHandler() {
        // Create a pipe for reading terminal output
        var pipeFds: [Int32] = [0, 0]
        if pipe(&pipeFds) == 0 {
            readFileDescriptor = pipeFds[0]
            
            // Make read end non-blocking
            let flags = fcntl(readFileDescriptor, F_GETFL, 0)
            fcntl(readFileDescriptor, F_SETFL, flags | O_NONBLOCK)
            
            // Create dispatch source for efficient I/O
            readSource = DispatchSource.makeReadSource(
                fileDescriptor: readFileDescriptor,
                queue: .global(qos: .userInteractive)
            )
            
            readSource?.setEventHandler { [weak self] in
                self?.handleRead()
            }
            
            readSource?.setCancelHandler { [weak self] in
                if let fd = self?.readFileDescriptor, fd >= 0 {
                    close(fd)
                    self?.readFileDescriptor = -1
                }
            }
            
            readSource?.resume()
        }
    }
    
    private func handleRead() {
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        
        let bytesRead = ghostty_terminal_read(buffer, bufferSize)
        
        if bytesRead > 0 {
            let data = Data(bytes: buffer, count: bytesRead)
            if let text = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async { [weak self] in
                    self?.onOutput?(text)
                    self?.metalView?.setNeedsDisplay(self?.metalView?.bounds ?? .zero)
                }
            }
        }
    }
    
    func sendText(_ text: String) {
        guard isInitialized else { return }
        
        text.withCString { cString in
            ghostty_terminal_send_text(cString)
        }
        
        // Request redraw
        metalView?.setNeedsDisplay(metalView?.bounds ?? .zero)
    }
    
    // MARK: - Size Handling
    
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateTerminalSize()
    }
    
    private func updateTerminalSize() {
        guard isInitialized else { return }
        
        let scale = window?.backingScaleFactor ?? 1.0
        ghostty_terminal_set_size(
            UInt32(bounds.width),
            UInt32(bounds.height),
            Double(scale)
        )
        
        metalView?.setNeedsDisplay(metalView?.bounds ?? .zero)
    }
    
    // MARK: - Input Handling
    
    override var acceptsFirstResponder: Bool { true }
    
    override func becomeFirstResponder() -> Bool {
        metalView?.setNeedsDisplay(metalView?.bounds ?? .zero)
        return true
    }
    
    override func resignFirstResponder() -> Bool {
        metalView?.setNeedsDisplay(metalView?.bounds ?? .zero)
        return true
    }
    
    override func keyDown(with event: NSEvent) {
        guard isInitialized else { return }
        
        // Handle special keys
        if let specialKey = mapSpecialKey(event) {
            specialKey.withCString { cString in
                ghostty_terminal_send_key(
                    cString,
                    UInt32(event.modifierFlags.rawValue),
                    1 // Key press action
                )
            }
        } else if let characters = event.characters {
            // Send regular text
            sendText(characters)
        }
    }
    
    private func mapSpecialKey(_ event: NSEvent) -> String? {
        switch event.keyCode {
        case 126: return "Up"
        case 125: return "Down"
        case 123: return "Left"
        case 124: return "Right"
        case 36: return "Return"
        case 51: return "BackSpace"
        case 53: return "Escape"
        case 48: return "Tab"
        case 116: return "Page_Up"
        case 121: return "Page_Down"
        case 115: return "Home"
        case 119: return "End"
        case 117: return "Delete"
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        default: return nil
        }
    }
    
    // MARK: - Mouse Handling
    
    override func mouseDown(with event: NSEvent) {
        // Could implement mouse support for terminal selection
        super.mouseDown(with: event)
    }
    
    override func mouseDragged(with event: NSEvent) {
        // Could implement text selection
        super.mouseDragged(with: event)
    }
    
    // MARK: - Cleanup
    
    deinit {
        stopTerminal()
    }
}

// MARK: - SwiftUI Wrapper

struct GhosttyTerminalSurface: NSViewRepresentable {
    @Binding var inputText: String
    let onError: (Error) -> Void
    let onOutput: (String) -> Void
    
    func makeNSView(context: Context) -> GhosttyTerminalSurfaceView {
        let view = GhosttyTerminalSurfaceView()
        view.onError = onError
        view.onOutput = onOutput
        
        // Start terminal when view is created
        DispatchQueue.main.async {
            view.startTerminal()
        }
        
        return view
    }
    
    func updateNSView(_ nsView: GhosttyTerminalSurfaceView, context: Context) {
        // Handle any updates if needed
        if !inputText.isEmpty {
            nsView.sendText(inputText)
            DispatchQueue.main.async {
                inputText = ""
            }
        }
    }
    
    static func dismantleNSView(_ nsView: GhosttyTerminalSurfaceView, coordinator: ()) {
        nsView.stopTerminal()
    }
}

// MARK: - Terminal View with Ghostty

struct GhosttyTerminalView: View {
    let appState: AppState
    let core: PlueCoreInterface
    
    @State private var inputText = ""
    @State private var terminalError: Error?
    @State private var terminalOutput = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Terminal Header
            terminalHeader
            
            // Ghostty Terminal Surface
            GhosttyTerminalSurface(
                inputText: $inputText,
                onError: { error in
                    terminalError = error
                    print("Ghostty terminal error: \(error)")
                },
                onOutput: { output in
                    terminalOutput += output
                }
            )
            .background(Color.black)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(DesignSystem.Colors.border(for: appState.currentTheme).opacity(0.3), lineWidth: 1)
            )
            .padding()
            
            // Error display
            if let error = terminalError {
                Text("Terminal Error: \(error.localizedDescription)")
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }
        }
        .background(DesignSystem.Colors.background(for: appState.currentTheme))
        .alert("Terminal Error", isPresented: .constant(terminalError != nil)) {
            Button("OK") { terminalError = nil }
        } message: {
            Text(terminalError?.localizedDescription ?? "Unknown error")
        }
    }
    
    // MARK: - Terminal Header
    private var terminalHeader: some View {
        VStack(spacing: 0) {
            HStack {
                // Terminal Title
                Label("Ghostty Terminal", systemImage: "terminal")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textPrimary(for: appState.currentTheme))
                
                Spacer()
                
                // Status Indicator
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    
                    Text("Powered by Ghostty")
                        .font(.system(size: 12))
                        .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
                }
                
                // Clear Button
                Button(action: { 
                    terminalOutput = ""
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Clear terminal output")
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            
            Divider()
        }
        .background(DesignSystem.Colors.surface(for: appState.currentTheme))
    }
}

// #Preview {
//     GhosttyTerminalView(appState: AppState.initial, core: PlueCore.shared)
//         .frame(width: 800, height: 600)
// }