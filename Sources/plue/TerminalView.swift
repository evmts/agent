import SwiftUI
import MetalKit
import AppKit

// MARK: - Terminal Tab Model
struct TerminalTab: Identifiable {
    let id: Int
    let title: String
    let isActive: Bool
}

struct TerminalView: View {
    let appState: AppState
    let core: PlueCoreInterface
    
    @StateObject private var terminal = MockTerminal()
    @State private var selectedTab = 0
    @State private var tabs: [TerminalTab] = [TerminalTab(id: 0, title: "zsh", isActive: true)]
    @FocusState private var isTerminalFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Professional Terminal Header with Tabs
            terminalHeader
            
            // Terminal Content Area
            ZStack {
                // Background with subtle texture
                DesignSystem.Colors.background(for: appState.currentTheme)
                    .overlay(
                        Rectangle()
                            .fill(Color.black.opacity(0.9))
                    )
                
                // Professional Terminal Content
                professionalTerminalContent
            }
        }
        .background(DesignSystem.Colors.background(for: appState.currentTheme))
        .preferredColorScheme(appState.currentTheme == .dark ? .dark : .light)
    }
    
    // MARK: - Professional Terminal Header
    private var terminalHeader: some View {
        VStack(spacing: 0) {
            // Tab Bar
            HStack(spacing: 0) {
                // Terminal Tabs
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 1) {
                        ForEach(tabs) { tab in
                            terminalTabButton(tab)
                        }
                        
                        // Add Tab Button
                        Button(action: addNewTab) {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                                .frame(width: 24, height: 28)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(DesignSystem.Colors.surface(for: appState.currentTheme).opacity(0.5))
                        )
                    }
                    .padding(.horizontal, 12)
                }
                
                Spacer()
                
                // Connection Status
                HStack(spacing: 8) {
                    Circle()
                        .fill(terminal.isConnected ? DesignSystem.Colors.success : DesignSystem.Colors.warning)
                        .frame(width: 6, height: 6)
                    
                    Text(terminal.isConnected ? "ssh://server" : "connecting...")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
                }
                .padding(.trailing, 16)
            }
            .frame(height: 40)
            .background(DesignSystem.Colors.surface(for: appState.currentTheme))
            
            // Subtle border
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(DesignSystem.Colors.border(for: appState.currentTheme).opacity(0.3))
        }
    }
    
    private func terminalTabButton(_ tab: TerminalTab) -> some View {
        Button(action: { selectedTab = tab.id }) {
            HStack(spacing: 6) {
                Text(tab.title)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(
                        tab.isActive 
                            ? DesignSystem.Colors.textPrimary(for: appState.currentTheme)
                            : DesignSystem.Colors.textSecondary(for: appState.currentTheme)
                    )
                
                if tabs.count > 1 {
                    Button(action: { closeTab(tab.id) }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(tab.isActive ? DesignSystem.Colors.background(for: appState.currentTheme) : Color.clear)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Professional Terminal Content
    private var professionalTerminalContent: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(0..<min(terminal.rows, 50)), id: \.self) { row in
                    LazyHStack(spacing: 0) {
                        ForEach(Array(0..<min(terminal.cols, 120)), id: \.self) { col in
                            let cell = terminal.getCell(row: row, col: col)
                            Text(String(cell.character))
                                .font(.custom("SF Mono", size: 13).weight(.regular))
                                .foregroundColor(cell.foregroundColor)
                                .background(cell.backgroundColor)
                                .frame(width: 7.8, height: 16) // Precise character grid
                        }
                    }
                }
            }
            .padding(16)
        }
        .focused($isTerminalFocused)
        .onAppear {
            isTerminalFocused = true
            terminal.startSession()
        }
        .background(Color.black)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(DesignSystem.Colors.border(for: appState.currentTheme).opacity(0.2), lineWidth: 1)
        )
        .padding(16)
    }
    
    // MARK: - Tab Management
    private func addNewTab() {
        let newTab = TerminalTab(
            id: tabs.count,
            title: "zsh \(tabs.count + 1)",
            isActive: false
        )
        
        // Deactivate current tabs
        tabs = tabs.map { tab in
            TerminalTab(id: tab.id, title: tab.title, isActive: false)
        }
        
        tabs.append(newTab)
        selectedTab = newTab.id
        
        // Activate the new tab
        if let index = tabs.firstIndex(where: { $0.id == newTab.id }) {
            tabs[index] = TerminalTab(id: newTab.id, title: newTab.title, isActive: true)
        }
    }
    
    private func closeTab(_ tabId: Int) {
        guard tabs.count > 1 else { return }
        
        tabs.removeAll { $0.id == tabId }
        
        // If closed tab was active, activate the first tab
        if selectedTab == tabId {
            selectedTab = tabs.first?.id ?? 0
            if let index = tabs.firstIndex(where: { $0.id == selectedTab }) {
                tabs[index] = TerminalTab(
                    id: tabs[index].id,
                    title: tabs[index].title,
                    isActive: true
                )
            }
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
    TerminalView(appState: AppState.initial, core: PlueCore.shared)
        .frame(width: 800, height: 600)
}