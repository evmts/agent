import SwiftUI

struct ProperTerminalView: View {
    let appState: AppState
    let core: PlueCoreInterface
    
    @StateObject private var terminal = PtyTerminal.shared
    @State private var terminalSize: CGSize = .zero
    
    var body: some View {
        VStack(spacing: 0) {
            // Terminal Header
            terminalHeader
            
            // Terminal Content
            ZStack {
                // Background
                Color.black
                
                // Terminal Display
                GeometryReader { geometry in
                    ScrollViewReader { proxy in
                        ScrollView {
                            Text(terminal.output)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                .padding(10)
                                .textSelection(.enabled)
                                .id("bottom")
                        }
                        .background(Color.black)
                        .onChange(of: terminal.output) { _ in
                            withAnimation(.easeOut(duration: 0.1)) {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        }
                        .onAppear {
                            updateTerminalSize(geometry.size)
                        }
                        .onChange(of: geometry.size) { newSize in
                            updateTerminalSize(newSize)
                        }
                    }
                }
            }
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(DesignSystem.Colors.border(for: appState.currentTheme).opacity(0.3), lineWidth: 1)
            )
            .padding()
        }
        .background(DesignSystem.Colors.background(for: appState.currentTheme))
        .onAppear {
            startTerminal()
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
    
    // MARK: - Private Methods
    private func startTerminal() {
        print("ProperTerminalView: startTerminal() called")
        if terminal.initialize() {
            print("ProperTerminalView: terminal initialized successfully")
            
            if terminal.start() {
                print("ProperTerminalView: terminal started successfully")
                // The shell will display its own prompt
            } else {
                print("ProperTerminalView: terminal failed to start")
            }
        } else {
            print("ProperTerminalView: terminal failed to initialize")
        }
    }
    
    private func updateTerminalSize(_ size: CGSize) {
        // Calculate terminal size in characters
        // Assuming ~7 pixels width per character and ~15 pixels height per line
        let cols = Int(size.width / 7)
        let rows = Int(size.height / 15)
        
        // Ensure reasonable minimum size
        let finalCols = max(20, cols)
        let finalRows = max(10, rows)
        
        if terminalSize != size {
            terminalSize = size
            terminal.resize(cols: finalCols, rows: finalRows)
        }
    }
}

#Preview {
    ProperTerminalView(appState: AppState.initial, core: PlueCore.shared)
        .frame(width: 800, height: 600)
}