import SwiftUI

/// A SwiftUI view that integrates with the Ghostty terminal emulator
/// 
/// NOTE: This is currently using stub implementations while we resolve
/// Ghostty's build dependencies (objc, cimgui, ziglyph, macos, build_options).
/// Once integrated, this will provide a fully functional terminal emulator.
struct GhosttyTerminalView: View {
    @State private var terminalInitialized = false
    @State private var terminalSize: CGSize = .zero
    @State private var inputText = ""
    
    var body: some View {
        VStack {
            // Terminal display area
            GeometryReader { geometry in
                ZStack {
                    Color.black
                        .onAppear {
                            initializeTerminal()
                            updateTerminalSize(geometry.size)
                        }
                        .onChange(of: geometry.size) { newSize in
                            updateTerminalSize(newSize)
                        }
                    
                    if !terminalInitialized {
                        VStack {
                            Text("Ghostty Terminal Integration")
                                .foregroundColor(.white)
                                .font(.headline)
                            Text("Pending: Resolving Ghostty dependencies")
                                .foregroundColor(.gray)
                                .font(.caption)
                        }
                    }
                }
            }
            
            // Input field
            HStack {
                TextField("Type command...", text: $inputText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onSubmit {
                        sendTextToTerminal(inputText + "\n")
                        inputText = ""
                    }
                
                Button("Send") {
                    sendTextToTerminal(inputText + "\n")
                    inputText = ""
                }
            }
            .padding()
        }
    }
    
    private func initializeTerminal() {
        let terminal = GhosttyTerminal.shared
        if terminal.initialize() {
            terminalInitialized = terminal.createSurface()
        }
    }
    
    private func updateTerminalSize(_ size: CGSize) {
        guard terminalInitialized else { return }
        
        // Convert size to pixels and update terminal
        let scale = NSScreen.main?.backingScaleFactor ?? 1.0
        GhosttyTerminal.shared.setSize(
            width: Int(size.width),
            height: Int(size.height),
            scale: scale
        )
        
        terminalSize = size
    }
    
    private func sendTextToTerminal(_ text: String) {
        guard terminalInitialized else { return }
        
        GhosttyTerminal.shared.sendText(text)
    }
}

struct GhosttyTerminalView_Previews: PreviewProvider {
    static var previews: some View {
        GhosttyTerminalView()
            .frame(width: 800, height: 600)
    }
}