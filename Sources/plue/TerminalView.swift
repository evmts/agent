import SwiftUI

struct TerminalView: View {
    let appState: AppState
    let core: PlueCoreInterface
    
    @StateObject private var terminal = PtyTerminal.shared
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool
    @State private var commandHistory: [String] = []
    @State private var historyIndex = -1
    
    var body: some View {
        VStack(spacing: 0) {
            // Terminal Header
            terminalHeader
            
            // Terminal Content
            ZStack {
                // Background
                DesignSystem.Colors.background(for: appState.currentTheme)
                    .overlay(Color.black.opacity(0.95))
                
                // Terminal Display
                GeometryReader { geometry in
                    VStack(spacing: 0) {
                        // Terminal Output Area
                        ScrollViewReader { proxy in
                            ScrollView {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(terminal.output)
                                        .font(.system(size: 13, design: .monospaced))
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity, alignment: .topLeading)
                                        .textSelection(.enabled)
                                    
                                    // Spacer to push content to top
                                    Spacer(minLength: 0)
                                        .frame(maxWidth: .infinity)
                                        .id("bottom")
                                }
                                .frame(minHeight: geometry.size.height - 50) // Leave space for input
                            }
                            .background(Color.black)
                            .onChange(of: terminal.output) { _ in
                                withAnimation(.easeOut(duration: 0.1)) {
                                    proxy.scrollTo("bottom", anchor: .bottom)
                                }
                            }
                        }
                        .frame(maxHeight: .infinity)
                        
                        // Input Area at bottom
                        inputArea
                            .frame(height: 50)
                    }
                }
                .padding(8)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(DesignSystem.Colors.border(for: appState.currentTheme).opacity(0.3), lineWidth: 1)
                )
                .padding()
            }
        }
        .background(DesignSystem.Colors.background(for: appState.currentTheme))
        .onAppear {
            print("TerminalView: onAppear called")
            startTerminal()
            isInputFocused = true
            print("TerminalView: onAppear completed")
        }
        .onDisappear {
            terminal.stop()
        }
    }
    
    // MARK: - Terminal Header
    private var terminalHeader: some View {
        VStack(spacing: 0) {
            HStack {
                // Terminal Title
                Label("Terminal", systemImage: "terminal")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textPrimary(for: appState.currentTheme))
                
                Spacer()
                
                // Status Indicator
                HStack(spacing: 6) {
                    Circle()
                        .fill(terminal.isRunning ? DesignSystem.Colors.success : DesignSystem.Colors.error)
                        .frame(width: 8, height: 8)
                    
                    Text(terminal.isRunning ? "Connected" : "Disconnected")
                        .font(.system(size: 12))
                        .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
                }
                
                // Clear Button
                Button(action: { terminal.clearOutput() }) {
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
    
    // MARK: - Input Area
    private var inputArea: some View {
        HStack(spacing: 8) {
            // Prompt (removed since PTY will show its own)
            // The PTY shows the actual shell prompt
            
            // Input Field
            TextField("", text: $inputText)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.white)
                .focused($isInputFocused)
                .onSubmit {
                    sendCommand()
                }
                .onKeyPress { keyPress in
                    handleKeyPress(keyPress)
                }
            
            // Send Button
            Button(action: sendCommand) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(DesignSystem.Colors.accent)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(inputText.isEmpty)
        }
        .padding()
        .background(Color.black.opacity(0.8))
    }
    
    // MARK: - Private Methods
    private func startTerminal() {
        print("TerminalView: startTerminal() called")
        if terminal.initialize() {
            print("TerminalView: terminal initialized successfully")
            // Set initial size
            terminal.resize(cols: 80, rows: 24) // Default terminal size
            
            if terminal.start() {
                print("TerminalView: terminal started successfully")
                // Terminal is ready, shell will show its own prompt
            } else {
                print("TerminalView: terminal failed to start")
            }
        } else {
            print("TerminalView: terminal failed to initialize")
        }
    }
    
    private func sendCommand() {
        guard !inputText.isEmpty else { return }
        
        // Add to history
        commandHistory.append(inputText)
        historyIndex = -1
        
        // Send to terminal (PTY will echo the command)
        terminal.sendCommand(inputText)
        
        // Clear input
        inputText = ""
    }
    
    private func handleKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        switch keyPress.key {
        case .upArrow:
            // Navigate command history up
            if !commandHistory.isEmpty && historyIndex < commandHistory.count - 1 {
                historyIndex += 1
                inputText = commandHistory[commandHistory.count - 1 - historyIndex]
            }
            return .handled
            
        case .downArrow:
            // Navigate command history down
            if historyIndex > 0 {
                historyIndex -= 1
                inputText = commandHistory[commandHistory.count - 1 - historyIndex]
            } else if historyIndex == 0 {
                historyIndex = -1
                inputText = ""
            }
            return .handled
            
        default:
            return .ignored
        }
    }
}

#Preview {
    TerminalView(appState: AppState.initial, core: PlueCore.shared)
        .frame(width: 800, height: 600)
}