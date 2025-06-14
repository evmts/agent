import SwiftUI
import SwiftDown

struct VimPromptView: View {
    let appState: AppState
    let core: PlueCoreInterface
    
    // Use a state object that can be shared between the Vim buffer and the preview
    @StateObject private var promptState = PromptState()
    
    var body: some View {
        // Use a simple HSplitView for a perfect 50/50 split
        HSplitView {
            // Left Pane: The Vim Buffer
            VimBufferView(
                content: $promptState.vimContent,
                title: "Prompt",
                status: "READY",
                theme: appState.currentTheme
            )
            
            // Right Pane: The Live Markdown Preview
            MarkdownPreviewView(
                content: promptState.vimContent,
                title: "Live Preview",
                core: core,
                appState: appState
            )
        }
        .background(DesignSystem.Colors.background(for: appState.currentTheme))
        .preferredColorScheme(appState.currentTheme == .dark ? .dark : .light)
    }
}

// Create a local state object for this view
class PromptState: ObservableObject {
    @Published var vimContent: String = """
# Your Prompt

Start typing your prompt here. The live preview will update on the right.

Use `:w` in the Vim buffer to send this prompt to the Chat tab.
"""
}

// A new reusable Vim Buffer component
struct VimBufferView: View {
    @Binding var content: String
    let title: String
    let status: String
    let theme: DesignSystem.Theme
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(DesignSystem.Typography.labelMedium)
                        .foregroundColor(DesignSystem.Colors.textPrimary(for: theme))
                    
                    Text("vim-mode editing")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textTertiary(for: theme))
                }
                
                Spacer()
                
                Text(status)
                    .font(DesignSystem.Typography.monoSmall)
                    .foregroundColor(DesignSystem.Colors.textTertiary(for: theme))
            }
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.surface(for: theme))
            .overlay(
                Rectangle()
                    .frame(height: 0.5)
                    .foregroundColor(DesignSystem.Colors.border(for: theme).opacity(0.3)),
                alignment: .bottom
            )
            
            // We will replace this with a real Vim component later.
            // For now, TextEditor simulates the buffer.
            TextEditor(text: $content)
                .font(DesignSystem.Typography.monoMedium)
                .padding(DesignSystem.Spacing.sm)
                .background(DesignSystem.Colors.backgroundSecondary(for: theme))
                .scrollContentBackground(.hidden)
        }
    }
}

// A new reusable Markdown Preview component
struct MarkdownPreviewView: View {
    let content: String
    let title: String
    let core: PlueCoreInterface
    let appState: AppState
    
    private func askInChat() {
        let prompt = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        core.handleEvent(.tabSwitched(.chat))
        core.handleEvent(.chatMessageSent(prompt))
    }
    
    private func launchClaudeCode() {
        // Launch Claude Code CLI with the current prompt
        let prompt = content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !prompt.isEmpty {
            // Save prompt to a temp file and open with Claude Code
            launchClaudeCodeWithPrompt(prompt)
        } else {
            // Just launch Claude Code
            launchClaudeCodeCLI()
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with Actions
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(DesignSystem.Typography.labelMedium)
                        .foregroundColor(DesignSystem.Colors.textPrimary(for: appState.currentTheme))
                    
                    Text("live markdown")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                }
                
                Spacer()
                
                // Action Buttons
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Button(action: askInChat) {
                        HStack(spacing: 4) {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 11, weight: .medium))
                            Text("chat")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(DesignSystem.Colors.primary)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    
                    Button(action: launchClaudeCode) {
                        HStack(spacing: 4) {
                            Image(systemName: "terminal")
                                .font(.system(size: 11, weight: .medium))
                            Text("code")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(DesignSystem.Colors.surface(for: appState.currentTheme))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(DesignSystem.Colors.border(for: appState.currentTheme), lineWidth: 0.5)
                                )
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.surface(for: appState.currentTheme))
            .overlay(
                Rectangle()
                    .frame(height: 0.5)
                    .foregroundColor(DesignSystem.Colors.border(for: appState.currentTheme).opacity(0.3)),
                alignment: .bottom
            )

            // Use the SwiftDown component for rendering
            if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack {
                    Spacer()
                    
                    // Minimal empty state
                    VStack(spacing: 12) {
                        Circle()
                            .fill(DesignSystem.Colors.textTertiary(for: appState.currentTheme).opacity(0.1))
                            .frame(width: 40, height: 40)
                            .overlay(
                                Image(systemName: "doc.text")
                                    .font(.system(size: 16, weight: .light))
                                    .foregroundColor(DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                            )
                        
                        VStack(spacing: 4) {
                            Text("empty")
                                .font(DesignSystem.Typography.labelMedium)
                                .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
                            
                            Text("start typing to see preview")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                        }
                    }
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DesignSystem.Colors.backgroundSecondary(for: appState.currentTheme))
            } else {
                ScrollView {
                    SwiftDownEditor(text: .constant(content))
                        .disabled(true)
                        .padding(DesignSystem.Spacing.lg)
                }
                .background(DesignSystem.Colors.backgroundSecondary(for: appState.currentTheme))
            }
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