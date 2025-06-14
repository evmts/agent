import SwiftUI
import SwiftDown

struct VimPromptView: View {
    let appState: AppState
    let core: PlueCoreInterface
    
    @StateObject private var promptTerminal = PromptTerminal()
    @State private var isTerminalFocused = false
    
    var body: some View {
        HSplitView {
            // Left side - Ghostty Terminal
            VStack(spacing: 0) {
                // Header with controls
                HStack {
                    Text("Prompt Terminal")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    // OpenAI Status Indicator
                    HStack(spacing: 4) {
                        Circle()
                            .fill(appState.openAIAvailable ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(appState.openAIAvailable ? "OpenAI" : "Mock")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Text("Use your favorite editor")
                        .font(.caption)
                        .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.55))
                }
                .padding()
                .background(Color(red: 0.08, green: 0.08, blue: 0.09))
                
                Divider()
                    .background(Color(red: 0.2, green: 0.2, blue: 0.25))
                
                // Terminal View
                PromptTerminalView(terminal: promptTerminal, core: core)
                    .background(Color.black)
            }
            
            // Right side - Rich Markdown Preview
            VStack(spacing: 0) {
                // Header with action buttons
                HStack {
                    Text("Preview")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    // Action buttons
                    HStack(spacing: 12) {
                        Button(action: askInChat) {
                            HStack(spacing: 6) {
                                Image(systemName: "bubble.left.and.bubble.right")
                                Text("Ask in Chat")
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(promptTerminal.currentContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        
                        Button(action: launchClaudeCode) {
                            HStack(spacing: 6) {
                                Image(systemName: "terminal.fill")
                                Text("Claude Code")
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.purple)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding()
                .background(Color(red: 0.08, green: 0.08, blue: 0.09))
                
                Divider()
                    .background(Color(red: 0.2, green: 0.2, blue: 0.25))
                
                // Rich Markdown Preview
                if promptTerminal.currentContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack {
                        Spacer()
                        Image(systemName: "doc.text")
                            .font(.system(size: 48))
                            .foregroundColor(Color(red: 0.3, green: 0.3, blue: 0.35))
                        Text("Markdown Preview")
                            .font(.headline)
                            .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.55))
                        Text("Edit your prompt in the terminal")
                            .font(.subheadline)
                            .foregroundColor(Color(red: 0.4, green: 0.4, blue: 0.45))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(red: 0.05, green: 0.05, blue: 0.06))
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            SwiftDownEditor(text: .constant(promptTerminal.currentContent))
                                .disabled(true)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(Color(red: 0.05, green: 0.05, blue: 0.06))
                }
            }
            .frame(minWidth: 350)
        }
        .background(Color(red: 0.05, green: 0.05, blue: 0.06))
        .onAppear {
            promptTerminal.startSession()
        }
    }
    
    // MARK: - Action Functions
    
    private func askInChat() {
        let prompt = promptTerminal.currentContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        
        // Switch to chat tab and send the prompt
        core.handleEvent(.tabSwitched(.chat))
        core.handleEvent(.chatMessageSent(prompt))
    }
    
    private func launchClaudeCode() {
        // Launch Claude Code CLI with the current prompt
        let prompt = promptTerminal.currentContent.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !prompt.isEmpty {
            // Save prompt to a temp file and open with Claude Code
            launchClaudeCodeWithPrompt(prompt)
        } else {
            // Just launch Claude Code
            launchClaudeCodeCLI()
        }
    }
    
    private func launchClaudeCodeWithPrompt(_ prompt: String) {
        Task {
            do {
                // Create a temporary file with the prompt
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("plue_prompt_\(UUID().uuidString).md")
                
                try prompt.write(to: tempURL, atomically: true, encoding: .utf8)
                
                // Launch Claude Code with the file
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/local/bin/claude_code")
                process.arguments = [tempURL.path]
                
                try process.run()
                
                print("Launched Claude Code with prompt: \(tempURL.path)")
            } catch {
                print("Failed to launch Claude Code: \(error)")
                // Fallback to opening in default editor
                openInDefaultEditor(prompt)
            }
        }
    }
    
    private func launchClaudeCodeCLI() {
        Task {
            do {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/local/bin/claude_code")
                process.arguments = []
                
                try process.run()
                
                print("Launched Claude Code CLI")
            } catch {
                print("Failed to launch Claude Code CLI: \(error)")
                // Fallback to terminal
                openTerminal()
            }
        }
    }
    
    private func openInDefaultEditor(_ content: String) {
        // Fallback: create temp file and open with system default
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("plue_prompt_\(UUID().uuidString).md")
        
        do {
            try content.write(to: tempURL, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(tempURL)
        } catch {
            print("Failed to create temp file: \(error)")
        }
    }
    
    private func openTerminal() {
        // Open Terminal.app as fallback
        if let terminalURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
            NSWorkspace.shared.openApplication(at: terminalURL, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

#Preview {
    VimPromptView(appState: AppState.initial, core: PlueCore.shared)
        .frame(width: 1200, height: 800)
}