import SwiftUI
import SwiftDown

struct PromptView: View {
    @State private var markdownText = """
# Prompt Engineering Interface

Write your prompts here using **Markdown** formatting.

## Features
- Rich text editing with live preview
- Syntax highlighting for code blocks
- Support for lists, headers, and formatting

```swift
// Code blocks are supported
let example = "Hello, World!"
```

## Usage
1. Write your prompt using Markdown
2. Click the send button to process with Zig core
3. View responses below

---

*Start writing your prompt below...*
"""
    
    @State private var responses: [PromptResponse] = []
    @State private var plueCore: PlueCore?
    @State private var isProcessing = false
    
    var body: some View {
        HSplitView {
            // Left side - Markdown Editor
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Prompt Editor")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button(action: processPrompt) {
                        HStack(spacing: 6) {
                            if isProcessing {
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: "paperplane.fill")
                            }
                            Text("Send Prompt")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(red: 0.0, green: 0.48, blue: 1.0))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .disabled(isProcessing || markdownText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()
                .background(Color(red: 0.08, green: 0.08, blue: 0.09))
                
                Divider()
                    .background(Color(red: 0.2, green: 0.2, blue: 0.25))
                
                // Markdown Editor
                SwiftDownEditor(text: $markdownText)
                    .background(Color(red: 0.05, green: 0.05, blue: 0.06))
            }
            
            // Right side - Responses
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
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 48))
                            .foregroundColor(Color(red: 0.3, green: 0.3, blue: 0.35))
                        Text("No responses yet")
                            .font(.headline)
                            .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.55))
                        Text("Send a prompt to see responses here")
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
        // Legacy PromptView - no longer initializes core
        print("Legacy PromptView - PlueCore initialization skipped")
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
            // Legacy PromptView - no longer used
            result = "Legacy PromptView response for: \(prompt)"
            
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

struct PromptResponse: Identifiable {
    let id: UUID
    let prompt: String
    let response: String?
    let timestamp: Date
    let isProcessing: Bool
}

struct PromptResponseView: View {
    let response: PromptResponse
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Timestamp
            HStack {
                Text(formatTimestamp(response.timestamp))
                    .font(.caption)
                    .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.55))
                Spacer()
            }
            
            // Prompt Preview
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "person.fill")
                        .foregroundColor(Color(red: 0.0, green: 0.48, blue: 1.0))
                    Text("Prompt")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(Color(red: 0.0, green: 0.48, blue: 1.0))
                }
                
                Text(response.prompt.prefix(200) + (response.prompt.count > 200 ? "..." : ""))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Color(red: 0.8, green: 0.8, blue: 0.85))
                    .padding(8)
                    .background(Color(red: 0.1, green: 0.1, blue: 0.12))
                    .cornerRadius(6)
            }
            
            // Response
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "cpu")
                        .foregroundColor(Color(red: 0.2, green: 0.8, blue: 0.4))
                    Text("Response")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(Color(red: 0.2, green: 0.8, blue: 0.4))
                }
                
                if response.isProcessing {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Processing...")
                            .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.55))
                    }
                } else if let responseText = response.response {
                    Text(responseText)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white)
                        .textSelection(.enabled)
                        .padding(8)
                        .background(Color(red: 0.1, green: 0.1, blue: 0.12))
                        .cornerRadius(6)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .foregroundColor(Color(red: 0.08, green: 0.08, blue: 0.09))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(red: 0.2, green: 0.2, blue: 0.25), lineWidth: 1)
                )
        )
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, HH:mm:ss"
        return formatter.string(from: date)
    }
}

#Preview {
    PromptView()
        .frame(width: 1200, height: 800)
}