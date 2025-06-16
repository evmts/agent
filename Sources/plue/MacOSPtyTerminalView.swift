import SwiftUI

struct MacOSPtyTerminalView: View {
    let appState: AppState
    let core: PlueCoreInterface
    
    @State private var inputText = ""
    @State private var terminalError: Error?
    @State private var terminalOutput = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Terminal Header
            terminalHeader
            
            // Terminal Surface (NSView-based)
            TerminalSurface(
                inputText: $inputText,
                onError: { error in
                    terminalError = error
                    print("Terminal error: \(error)")
                },
                onOutput: { output in
                    // We could track output here if needed
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
                Label("Terminal (macOS PTY)", systemImage: "terminal")
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
        print("MacOSPtyTerminalView: startTerminal() called")
        if terminal.initialize() {
            print("MacOSPtyTerminalView: terminal initialized successfully")
            
            if terminal.start() {
                print("MacOSPtyTerminalView: terminal started successfully")
            } else {
                print("MacOSPtyTerminalView: terminal failed to start")
            }
        } else {
            print("MacOSPtyTerminalView: terminal failed to initialize")
        }
    }
}

#Preview {
    MacOSPtyTerminalView(appState: AppState.initial, core: PlueCore.shared)
        .frame(width: 800, height: 600)
}