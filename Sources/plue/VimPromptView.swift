import SwiftUI
import SwiftDown

struct VimPromptView: View {
    @State private var markdownText = """
# Prompt Engineering Interface

Write your prompts here using **Markdown** formatting.

## Features
- Rich text editing with markdown syntax highlighting
- Live preview capability
- Toggle between edit and preview modes
- Integration with Zig core processing
- Vim keybindings (coming soon)

```swift
// Code blocks with syntax highlighting
let vimMode = true
print("Vim keybindings enabled!")
```

## Usage
1. Use vim commands to edit your prompt
2. Press `Cmd+Enter` to send prompt to Zig core
3. View responses in the right panel

---

*Click the edit/preview button to toggle between modes...*
"""
    
    @State private var responses: [PromptResponse] = []
    @State private var plueCore: PlueCore?
    @State private var isProcessing = false
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
                            if isProcessing {
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
                    .disabled(isProcessing || markdownText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
                }
                .padding()
                .background(Color(red: 0.08, green: 0.08, blue: 0.09))
                
                Divider()
                    .background(Color(red: 0.2, green: 0.2, blue: 0.25))
                
                // Editor or Preview
                if showPreview {
                    ScrollView {
                        SwiftDownEditor(text: .constant(markdownText))
                            .disabled(true)
                            .padding()
                    }
                    .background(Color(red: 0.05, green: 0.05, blue: 0.06))
                } else {
                    // For now, use SwiftDown editor - vim support coming soon
                    SwiftDownEditor(text: $markdownText)
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
                    
                    if !responses.isEmpty {
                        Button("Clear") {
                            responses.removeAll()
                        }
                        .foregroundColor(Color(red: 0.0, green: 0.48, blue: 1.0))
                    }
                }
                .padding()
                .background(Color(red: 0.08, green: 0.08, blue: 0.09))
                
                Divider()
                    .background(Color(red: 0.2, green: 0.2, blue: 0.25))
                
                // Responses List
                if responses.isEmpty {
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
                            ForEach(responses) { response in
                                PromptResponseView(response: response)
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
        .onAppear {
            initializeCore()
        }
    }
    
    private func initializeCore() {
        do {
            plueCore = try PlueCore()
        } catch {
            print("Failed to initialize PlueCore: \(error)")
        }
    }
    
    private func processPrompt() {
        let prompt = markdownText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        
        isProcessing = true
        
        // Create new response entry
        let newResponse = PromptResponse(
            id: UUID(),
            prompt: prompt,
            response: nil,
            timestamp: Date(),
            isProcessing: true
        )
        responses.append(newResponse)
        
        // Process in background
        DispatchQueue.global(qos: .userInitiated).async {
            let result: String
            if let core = plueCore {
                result = core.processMessage(prompt)
            } else {
                result = "Error: Plue core not initialized"
            }
            
            DispatchQueue.main.async {
                // Update the response
                if let index = responses.firstIndex(where: { $0.id == newResponse.id }) {
                    responses[index] = PromptResponse(
                        id: newResponse.id,
                        prompt: newResponse.prompt,
                        response: result,
                        timestamp: newResponse.timestamp,
                        isProcessing: false
                    )
                }
                isProcessing = false
            }
        }
    }
}

#Preview {
    VimPromptView()
        .frame(width: 1200, height: 800)
}