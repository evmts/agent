import SwiftUI
import SwiftDown

struct VimPromptView: View {
    let appState: AppState
    let core: PlueCoreInterface
    
    @StateObject private var promptTerminal = PromptTerminal()
    @State private var isTerminalFocused = false
    
    var body: some View {
        ZStack {
            DesignSystem.Colors.background
                .ignoresSafeArea()
            
            HSplitView {
                // Left side - Minimal Terminal Interface (Ghostty-inspired)
                VStack(spacing: 0) {
                    // Minimal Header
                    HStack(spacing: DesignSystem.Spacing.md) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Terminal")
                                .font(DesignSystem.Typography.labelMedium)
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                            
                            Text("vim-mode editing")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.textTertiary)
                        }
                        
                        Spacer()
                        
                        // Minimal Status Indicator
                        HStack(spacing: 4) {
                            Circle()
                                .fill(appState.openAIAvailable ? DesignSystem.Colors.success : DesignSystem.Colors.warning)
                                .frame(width: 6, height: 6)
                            
                            Text(appState.openAIAvailable ? "ready" : "mock")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.textTertiary)
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.vertical, DesignSystem.Spacing.md)
                    .background(DesignSystem.Colors.surface)
                    .overlay(
                        Rectangle()
                            .frame(height: 0.5)
                            .foregroundColor(DesignSystem.Colors.border.opacity(0.3)),
                        alignment: .bottom
                    )
                    
                    // Enhanced Terminal View
                    PromptTerminalView(terminal: promptTerminal, core: core)
                        .background(DesignSystem.Colors.backgroundSecondary)
                }
                .elevatedSurface()
            
                // Right side - Minimal Preview Panel
                VStack(spacing: 0) {
                    // Minimal Header with Actions
                    HStack(spacing: DesignSystem.Spacing.md) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Preview")
                                .font(DesignSystem.Typography.labelMedium)
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                            
                            Text("live markdown")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.textTertiary)
                        }
                        
                        Spacer()
                        
                        // Minimal Action Buttons
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
                            .disabled(promptTerminal.currentContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            
                            Button(action: launchClaudeCode) {
                                HStack(spacing: 4) {
                                    Image(systemName: "terminal")
                                        .font(.system(size: 11, weight: .medium))
                                    Text("code")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(DesignSystem.Colors.surface)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 4)
                                                .stroke(DesignSystem.Colors.border, lineWidth: 0.5)
                                        )
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.vertical, DesignSystem.Spacing.md)
                    .background(DesignSystem.Colors.surface)
                    .overlay(
                        Rectangle()
                            .frame(height: 0.5)
                            .foregroundColor(DesignSystem.Colors.border.opacity(0.3)),
                        alignment: .bottom
                    )
                
                    // Minimal Markdown Preview
                    if promptTerminal.currentContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        VStack {
                            Spacer()
                            
                            // Minimal empty state
                            VStack(spacing: 12) {
                                Circle()
                                    .fill(DesignSystem.Colors.textTertiary.opacity(0.1))
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Image(systemName: "doc.text")
                                            .font(.system(size: 16, weight: .light))
                                            .foregroundColor(DesignSystem.Colors.textTertiary)
                                    )
                                
                                VStack(spacing: 4) {
                                    Text("empty")
                                        .font(DesignSystem.Typography.labelMedium)
                                        .foregroundColor(DesignSystem.Colors.textSecondary)
                                    
                                    Text("start typing to see preview")
                                        .font(DesignSystem.Typography.caption)
                                        .foregroundColor(DesignSystem.Colors.textTertiary)
                                }
                            }
                            
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(DesignSystem.Colors.backgroundSecondary)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                SwiftDownEditor(text: .constant(promptTerminal.currentContent))
                                    .disabled(true)
                            }
                            .padding(DesignSystem.Spacing.xl)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .background(DesignSystem.Colors.backgroundSecondary)
                    }
                }
                .elevatedSurface()
                .frame(minWidth: 350)
            }
        }
        .preferredColorScheme(.dark)
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