import SwiftUI

struct TerminalView: View {
    let appState: AppState
    let core: PlueCoreInterface
    @ObservedObject var settings: AppSettings = .shared

    @State private var inputText = ""
    @State private var terminalError: Error?
    @State private var terminalOutput = ""

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                // Terminal backend selection
                terminalContent
                    .background(Color(red: 22.0/255.0, green: 22.0/255.0, blue: 28.0/255.0))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(DesignSystem.Colors.border(for: appState.currentTheme).opacity(0.3), lineWidth: 1)
                    )
                    .padding()

                // Backend indicator (optional)
                if settings.showTerminalBackendIndicator {
                    Text(settings.terminalBackend.rawValue)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.5))
                        .foregroundColor(.white.opacity(0.7))
                        .cornerRadius(4)
                        .padding(.top, 24)
                        .padding(.trailing, 24)
                }
            }

            // Error display
            if let error = terminalError {
                Text("Terminal Error: \(error.localizedDescription)")
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }
        }
        .background(Color(red: 22.0/255.0, green: 22.0/255.0, blue: 28.0/255.0))
        .alert("Terminal Error", isPresented: .constant(terminalError != nil)) {
            Button("OK") { terminalError = nil }
        } message: {
            Text(terminalError?.localizedDescription ?? "Unknown error")
        }
    }

    @ViewBuilder
    private var terminalContent: some View {
        switch settings.terminalBackend {
        case .ghostty:
            GhosttyTerminalView(
                workingDirectory: FileManager.default.currentDirectoryPath,
                command: settings.defaultShell
            )
        case .swiftterm:
            SwiftTerminalView(
                inputText: $inputText,
                onError: { error in
                    terminalError = error
                    print("Terminal error: \(error)")
                },
                onOutput: { output in
                    terminalOutput += output
                }
            )
        }
    }
}

// #Preview {
//     TerminalView(appState: AppState.initial, core: PlueCore.shared)
//         .frame(width: 800, height: 600)
// }