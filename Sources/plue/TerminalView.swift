import SwiftUI

struct TerminalView: View {
    let appState: AppState
    let core: PlueCoreInterface
    
    @State private var inputText = ""
    @State private var terminalError: Error?
    @State private var terminalOutput = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Use SwiftTerm-based terminal
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
            .background(Color(red: 40.0/255.0, green: 44.0/255.0, blue: 52.0/255.0))
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
        .background(Color(red: 40.0/255.0, green: 44.0/255.0, blue: 52.0/255.0))
        .alert("Terminal Error", isPresented: .constant(terminalError != nil)) {
            Button("OK") { terminalError = nil }
        } message: {
            Text(terminalError?.localizedDescription ?? "Unknown error")
        }
    }
}

// #Preview {
//     TerminalView(appState: AppState.initial, core: PlueCore.shared)
//         .frame(width: 800, height: 600)
// }