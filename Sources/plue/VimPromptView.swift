import SwiftUI
import SwiftDown

struct VimPromptView: View {
    let appState: AppState
    let core: PlueCoreInterface
    
    @State private var showPreview = false
    
    var body: some View {
        HSplitView {
            // Left side - Editor
            VStack(spacing: 0) {
                // Header with controls
                HStack {
                    Text("Prompt Editor")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Button(showPreview ? "Edit" : "Preview") {
                        showPreview.toggle()
                    }
                    .foregroundColor(Color(red: 0.0, green: 0.48, blue: 1.0))
                    
                    Spacer()
                    
                    Text("⌘+Enter to send")
                        .font(.caption)
                        .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.55))
                    
                    Button(action: processPrompt) {
                        HStack(spacing: 6) {
                            if appState.editorState.hasUnsavedChanges {
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: "paperplane.fill")
                            }
                            Text("Send")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(red: 0.0, green: 0.48, blue: 1.0))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .disabled(appState.editorState.hasUnsavedChanges || appState.editorState.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
                }
                .padding()
                .background(Color(red: 0.08, green: 0.08, blue: 0.09))
                
                Divider()
                    .background(Color(red: 0.2, green: 0.2, blue: 0.25))
                
                // Editor or Preview
                if showPreview {
                    ScrollView {
                        SwiftDownEditor(text: .constant(appState.editorState.content))
                            .disabled(true)
                            .padding()
                    }
                    .background(Color(red: 0.05, green: 0.05, blue: 0.06))
                } else {
                    // For now, use SwiftDown editor - vim support coming soon
                    SwiftDownEditor(text: Binding(
                        get: { appState.editorState.content },
                        set: { newContent in core.handleEvent(.editorContentChanged(newContent)) }
                    ))
                        .background(Color(red: 0.05, green: 0.05, blue: 0.06))
                }
            }
            
            // Right side - Responses (same as before)
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Responses")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    if !(appState.chatState.currentConversation?.messages.isEmpty ?? true) {
                        Button("Clear") {
                            core.handleEvent(.chatNewConversation)
                        }
                        .foregroundColor(Color(red: 0.0, green: 0.48, blue: 1.0))
                    }
                }
                .padding()
                .background(Color(red: 0.08, green: 0.08, blue: 0.09))
                
                Divider()
                    .background(Color(red: 0.2, green: 0.2, blue: 0.25))
                
                // Responses List
                if appState.chatState.currentConversation?.messages.isEmpty ?? true {
                    VStack {
                        Spacer()
                        Image(systemName: "terminal")
                            .font(.system(size: 48))
                            .foregroundColor(Color(red: 0.3, green: 0.3, blue: 0.35))
                        Text("No responses yet")
                            .font(.headline)
                            .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.55))
                        Text("Send a prompt with ⌘+Enter")
                            .font(.subheadline)
                            .foregroundColor(Color(red: 0.4, green: 0.4, blue: 0.45))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(red: 0.05, green: 0.05, blue: 0.06))
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(appState.chatState.currentConversation?.messages ?? []) { message in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(message.content)
                                        .font(.system(size: 14))
                                        .foregroundColor(.primary)
                                        .padding()
                                        .background(Color(red: 0.08, green: 0.08, blue: 0.09))
                                        .cornerRadius(8)
                                }
                            }
                        }
                        .padding()
                    }
                    .background(Color(red: 0.05, green: 0.05, blue: 0.06))
                }
            }
            .frame(minWidth: 300)
        }
        .background(Color(red: 0.05, green: 0.05, blue: 0.06))
    }
    
    private func processPrompt() {
        let prompt = appState.editorState.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        
        // Send prompt to core
        core.handleEvent(.chatMessageSent(prompt))
    }
}

#Preview {
    VimPromptView(appState: AppState.initial, core: PlueCore.shared)
        .frame(width: 1200, height: 800)
}