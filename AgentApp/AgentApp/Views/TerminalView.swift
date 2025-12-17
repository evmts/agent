#if os(macOS)
import SwiftUI
import SwiftTerm
import AppKit

/// A SwiftUI wrapper for SwiftTerm's LocalProcessTerminalView
struct TerminalViewWrapper: NSViewRepresentable {
    let workingDirectory: String?
    let onData: ((Data) -> Void)?

    init(workingDirectory: String? = nil, onData: ((Data) -> Void)? = nil) {
        self.workingDirectory = workingDirectory
        self.onData = onData
    }

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let terminal = LocalProcessTerminalView(frame: .zero)

        // Set font
        terminal.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        // Set up the terminal delegate
        terminal.processDelegate = context.coordinator

        // Start the shell process
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"

        terminal.startProcess(
            executable: shell,
            args: [],
            environment: nil,
            execName: nil
        )

        return terminal
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        // Update if needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onData: onData)
    }

    class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        var onData: ((Data) -> Void)?

        init(onData: ((Data) -> Void)?) {
            self.onData = onData
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
            // Handle terminal size changes
        }

        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
            // Handle title changes
        }

        func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {
            // Handle directory changes
        }

        func processTerminated(source: SwiftTerm.TerminalView, exitCode: Int32?) {
            // Handle process termination
            print("Terminal process exited with code: \(exitCode ?? -1)")
        }
    }
}

// Typealias for cleaner usage in SwiftUI
typealias TerminalView = TerminalViewWrapper

#elseif os(iOS)
import SwiftUI
import SwiftTerm
import UIKit

/// iOS version - no local process, designed for remote connections
struct TerminalViewWrapper: UIViewRepresentable {
    let onData: ((Data) -> Void)?

    init(workingDirectory: String? = nil, onData: ((Data) -> Void)? = nil) {
        self.onData = onData
    }

    func makeUIView(context: Context) -> SwiftTerm.TerminalView {
        let terminal = SwiftTerm.TerminalView(frame: .zero)

        // Configure terminal
        terminal.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        terminal.terminalDelegate = context.coordinator

        return terminal
    }

    func updateUIView(_ uiView: SwiftTerm.TerminalView, context: Context) {
        // Update if needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onData: onData)
    }

    class Coordinator: NSObject, SwiftTerm.TerminalViewDelegate {
        var onData: ((Data) -> Void)?

        init(onData: ((Data) -> Void)?) {
            self.onData = onData
        }

        func send(source: SwiftTerm.TerminalView, data: ArraySlice<UInt8>) {
            onData?(Data(data))
        }

        func scrolled(source: SwiftTerm.TerminalView, position: Double) {
            // Handle scroll
        }

        func setTerminalTitle(source: SwiftTerm.TerminalView, title: String) {
            // Handle title
        }

        func sizeChanged(source: SwiftTerm.TerminalView, newCols: Int, newRows: Int) {
            // Handle size
        }

        func clipboardCopy(source: SwiftTerm.TerminalView, content: Data) {
            UIPasteboard.general.setData(content, forPasteboardType: "public.utf8-plain-text")
        }

        func rangeChanged(source: SwiftTerm.TerminalView, startY: Int, endY: Int) {
            // Handle range changes
        }
    }
}

// Typealias for cleaner usage in SwiftUI
typealias TerminalView = TerminalViewWrapper
#endif
