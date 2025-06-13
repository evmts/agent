import SwiftUI
import MetalKit
import AppKit

struct TerminalView: View {
    @StateObject private var terminal = MockTerminal()
    @State private var metalView: TerminalMetalView?
    @FocusState private var isTerminalFocused: Bool
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Terminal Metal View
                TerminalMetalViewRepresentable(terminal: terminal)
                    .focused($isTerminalFocused)
                    .onAppear {
                        isTerminalFocused = true
                        // Start mock shell session
                        terminal.startSession()
                    }
                    .background(Color.black)
                
                // Overlay for selection and cursor when not using Metal
                if !terminal.useMetalRendering {
                    terminalOverlay
                }
                
                // Status overlay
                if terminal.showConnectionStatus {
                    connectionStatusOverlay
                }
            }
        }
        .background(Color.black)
        .onReceive(terminal.$needsRedraw) { _ in
            // Force SwiftUI update when terminal content changes
        }
    }
    
    // MARK: - Terminal Overlay (for non-Metal rendering) - Optimized
    private var terminalOverlay: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(0..<min(terminal.rows, 50)), id: \.self) { row in
                LazyHStack(spacing: 0) {
                    ForEach(Array(0..<min(terminal.cols, 120)), id: \.self) { col in
                        let cell = terminal.getCell(row: row, col: col)
                        Text(String(cell.character))
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundColor(cell.foregroundColor)
                            .background(cell.backgroundColor)
                            .frame(width: terminal.cellWidth, height: terminal.cellHeight)
                    }
                }
            }
        }
        .background(Color.black)
        .drawingGroup() // Flatten into single layer for better performance
    }
    
    // MARK: - Connection Status Overlay
    private var connectionStatusOverlay: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                HStack(spacing: 8) {
                    Circle()
                        .fill(terminal.isConnected ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    
                    Text(terminal.isConnected ? "Connected" : "Connecting...")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                )
                .padding(.trailing, 16)
            }
            .padding(.bottom, 16)
        }
    }
}

// MARK: - Metal View Representable
struct TerminalMetalViewRepresentable: NSViewRepresentable {
    let terminal: MockTerminal
    
    func makeNSView(context: Context) -> TerminalMetalView {
        let metalView = TerminalMetalView(terminal: terminal)
        
        // Delay first responder assignment to avoid race conditions
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak metalView] in
            guard let metalView = metalView, metalView.window != nil else { return }
            metalView.window?.makeFirstResponder(metalView)
        }
        
        return metalView
    }
    
    func updateNSView(_ nsView: TerminalMetalView, context: Context) {
        // Only update if view is still in window hierarchy
        guard nsView.window != nil else { return }
        nsView.setNeedsDisplay(nsView.bounds)
    }
}

// MARK: - Metal View Implementation
class TerminalMetalView: MTKView {
    private let terminal: MockTerminal
    private var renderer: TerminalRenderer?
    
    init(terminal: MockTerminal) {
        self.terminal = terminal
        
        // Initialize Metal device
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal not supported on this device")
        }
        
        super.init(frame: .zero, device: device)
        
        self.colorPixelFormat = .bgra8Unorm
        self.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0)
        self.isPaused = false
        self.enableSetNeedsDisplay = true
        
        // Initialize renderer
        self.renderer = TerminalRenderer(device: device, terminal: terminal)
        self.delegate = self.renderer
        
        // Setup input handling
        setupInputHandling()
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        // Clean up Metal resources on main thread to avoid race conditions
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.renderer = nil
            self.delegate = nil
        }
    }
    
    override var acceptsFirstResponder: Bool {
        return true
    }
    
    override func becomeFirstResponder() -> Bool {
        return true
    }
    
    private func setupInputHandling() {
        // Handle key input
        // This would be expanded to handle all terminal key combinations
    }
    
    override func keyDown(with event: NSEvent) {
        // Convert NSEvent to terminal input
        let characters = event.characters ?? ""
        
        // Handle special keys
        switch event.keyCode {
        case 36: // Return
            terminal.handleInput("\r")
        case 51: // Delete/Backspace
            terminal.handleInput("\u{7F}")
        case 123: // Left arrow
            terminal.handleInput("\u{1B}[D")
        case 124: // Right arrow
            terminal.handleInput("\u{1B}[C")
        case 125: // Down arrow
            terminal.handleInput("\u{1B}[B")
        case 126: // Up arrow
            terminal.handleInput("\u{1B}[A")
        default:
            // Regular character input
            if !characters.isEmpty {
                terminal.handleInput(characters)
            }
        }
    }
    
    override func flagsChanged(with event: NSEvent) {
        // Handle modifier key changes
        super.flagsChanged(with: event)
    }
}

// MARK: - Metal Renderer
class TerminalRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let terminal: MockTerminal
    private var commandQueue: MTLCommandQueue
    
    init(device: MTLDevice, terminal: MockTerminal) {
        self.device = device
        self.terminal = terminal
        self.commandQueue = device.makeCommandQueue()!
        super.init()
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Update terminal size based on view size
        let cellWidth: CGFloat = 8.0  // Approximate monospace character width
        let cellHeight: CGFloat = 16.0 // Approximate line height
        
        let cols = Int(size.width / cellWidth)
        let rows = Int(size.height / cellHeight)
        
        terminal.resize(rows: max(1, rows), cols: max(1, cols))
    }
    
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }
        
        // For now, just clear the screen
        // In a real implementation, this would render terminal text using Metal shaders
        renderEncoder.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
        
        // Trigger SwiftUI update if terminal content changed
        if terminal.needsRedraw {
            DispatchQueue.main.async {
                self.terminal.needsRedraw = false
            }
        }
    }
}

#Preview {
    TerminalView()
        .frame(width: 800, height: 600)
}