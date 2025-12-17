import SwiftUI
import SwiftTerm
import AppKit

// MARK: - SwiftTerm-based Terminal View
struct SwiftTerminalView: NSViewRepresentable {
    @Binding var inputText: String
    let onError: (Error) -> Void
    let onOutput: (String) -> Void
    
    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let terminalView = LocalProcessTerminalView(frame: .zero)
        
        // Configure appearance
        terminalView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        terminalView.nativeForegroundColor = NSColor(red: 0.976, green: 0.976, blue: 0.976, alpha: 1.0)
        terminalView.nativeBackgroundColor = NSColor(red: 0.086, green: 0.086, blue: 0.11, alpha: 1.0)
        
        // Comment out color scheme for now - SwiftTerm has different API
        // We'll use the default colors or configure them differently
        
        // Set coordinator
        terminalView.processDelegate = context.coordinator
        
        // Configure additional appearance
        terminalView.allowMouseReporting = true
        
        // Start the terminal with zsh
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        terminalView.startProcess(executable: shell, args: ["-l"])
        
        return terminalView
    }
    
    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        // Handle any updates if needed
        if !inputText.isEmpty {
            nsView.feed(text: inputText)
            DispatchQueue.main.async {
                inputText = ""
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onError: onError, onOutput: onOutput)
    }
    
    class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        let onError: (Error) -> Void
        let onOutput: (String) -> Void
        
        init(onError: @escaping (Error) -> Void, onOutput: @escaping (String) -> Void) {
            self.onError = onError
            self.onOutput = onOutput
        }
        
        func processTerminated (source: SwiftTerm.TerminalView, exitCode: Int32?) {
            if let exitCode = exitCode, exitCode != 0 {
                onError(SwiftTermError.processExitedWithCode(Int(exitCode)))
            }
        }
        
        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
            // Handle size changes if needed
        }
        
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
            // Handle title changes if needed
        }
        
        func hostCurrentDirectoryUpdate (source: SwiftTerm.TerminalView, directory: String?) {
            // Handle directory changes if needed
        }
        
    }
}

// MARK: - SwiftTerm Error
enum SwiftTermError: LocalizedError {
    case processExitedWithCode(Int)
    
    var errorDescription: String? {
        switch self {
        case .processExitedWithCode(let code):
            return "Process exited with code \(code)"
        }
    }
}