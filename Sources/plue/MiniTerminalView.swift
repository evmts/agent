import SwiftUI

struct MiniTerminalView: View {
    @StateObject private var terminal = MiniTerminal.shared
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Terminal output display
            ScrollViewReader { proxy in
                ScrollView {
                    Text(terminal.output)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .textSelection(.enabled)
                        .id("bottom")
                }
                .background(Color(NSColor.textBackgroundColor))
                .onChange(of: terminal.output) { _ in
                    // Auto-scroll to bottom when new output arrives
                    withAnimation {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
            
            Divider()
            
            // Input area
            HStack {
                TextField("Type command...", text: $inputText)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .focused($isInputFocused)
                    .onSubmit {
                        sendCommand()
                    }
                
                Button("Send") {
                    sendCommand()
                }
                .keyboardShortcut(.return, modifiers: [])
                
                Button("Clear") {
                    terminal.clearOutput()
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
        }
        .onAppear {
            startTerminal()
            isInputFocused = true
        }
        .onDisappear {
            terminal.stop()
        }
    }
    
    private func startTerminal() {
        if terminal.initialize() {
            _ = terminal.start()
        }
    }
    
    private func sendCommand() {
        guard !inputText.isEmpty else { return }
        
        // Display the command in the output
        terminal.output += "> \(inputText)\n"
        
        // Send to terminal
        terminal.sendCommand(inputText)
        
        // Clear input
        inputText = ""
    }
}

// Preview
struct MiniTerminalView_Previews: PreviewProvider {
    static var previews: some View {
        MiniTerminalView()
            .frame(width: 800, height: 600)
    }
}