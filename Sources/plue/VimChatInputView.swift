import SwiftUI
import AppKit

struct VimChatInputView: View {
    let appState: AppState
    let core: PlueCoreInterface
    @FocusState private var isTerminalFocused: Bool
    @State private var inputText: String = ""
    
    let onMessageSent: (String) -> Void
    var onMessageUpdated: ((String) -> Void)?
    var onNavigateUp: (() -> Void)?
    var onNavigateDown: (() -> Void)?
    var onPreviousChat: (() -> Void)?
    var onNextChat: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 0) {
            // Terminal display area (placeholder for now)
            ZStack {
                Color.black
                Text(inputText.isEmpty ? "Type your message..." : inputText)
                    .foregroundColor(.white)
                    .font(.system(size: 13, design: .monospaced))
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 80, maxHeight: 120)
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .onTapGesture {
                isTerminalFocused = true
            }
            
            // Status line
            statusLineView
        }
        .background(Color.black)
        .overlay(
            Rectangle()
                .stroke(isTerminalFocused ? Color.blue.opacity(0.5) : Color.gray.opacity(0.3), lineWidth: 1)
        )
        .onAppear {
            isTerminalFocused = true
        }
    }
    
    private var statusLineView: some View {
        HStack {
            Text("-- NORMAL --")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
            
            Spacer()
            
            Text("1:1")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.gray)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.8))
    }
}

// #Preview {
//     VimChatInputView(
//         appState: AppState.initial,
//         core: MockPlueCore(),
//         onMessageSent: { message in
//             print("Preview: Message sent: \(message)")
//         },
//         onMessageUpdated: { message in
//             print("Preview: Message updated: \(message)")
//         }
//     )
//     .frame(width: 600, height: 200)
//     .padding()
// }