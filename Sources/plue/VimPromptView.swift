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
                // Left side - Professional Terminal Interface
                VStack(spacing: 0) {
                    // Professional Header
                    HStack(spacing: DesignSystem.Spacing.lg) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Terminal Editor")
                                .font(DesignSystem.Typography.titleMedium)
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                            
                            Text("Edit prompts with your favorite editor")
                                .font(DesignSystem.Typography.labelSmall)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                        }
                        
                        Spacer()
                        
                        // Enhanced Status Indicator
                        StatusIndicator(
                            status: appState.openAIAvailable ? .online : .warning,
                            text: appState.openAIAvailable ? "AI Ready" : "Mock Mode"
                        )
                    }
                    .padding(.horizontal, DesignSystem.Spacing.xl)
                    .padding(.vertical, DesignSystem.Spacing.lg)
                    .background(DesignSystem.Colors.surface)
                    .overlay(
                        Rectangle()
                            .frame(height: 1)
                            .foregroundColor(DesignSystem.Colors.border),
                        alignment: .bottom
                    )
                    
                    // Enhanced Terminal View
                    PromptTerminalView(terminal: promptTerminal, core: core)
                        .background(DesignSystem.Colors.backgroundSecondary)
                }
                .elevatedSurface()
            
                // Right side - Professional Markdown Preview
                VStack(spacing: 0) {
                    // Professional Header with Action Buttons
                    HStack(spacing: DesignSystem.Spacing.lg) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Markdown Preview")
                                .font(DesignSystem.Typography.titleMedium)
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                            
                            Text("Real-time preview of your prompt")
                                .font(DesignSystem.Typography.labelSmall)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                        }
                        
                        Spacer()
                        
                        // Professional Action Buttons
                        HStack(spacing: DesignSystem.Spacing.md) {
                            Button(action: askInChat) {
                                HStack(spacing: DesignSystem.Spacing.xs) {
                                    Image(systemName: "bubble.left.and.bubble.right.fill")
                                        .font(.system(size: DesignSystem.IconSize.small))
                                    Text("Ask in Chat")
                                        .font(DesignSystem.Typography.labelMedium)
                                }
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(promptTerminal.currentContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            
                            Button(action: launchClaudeCode) {
                                HStack(spacing: DesignSystem.Spacing.xs) {
                                    Image(systemName: "terminal.fill")
                                        .font(.system(size: DesignSystem.IconSize.small))
                                    Text("Claude Code")
                                        .font(DesignSystem.Typography.labelMedium)
                                }
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.xl)
                    .padding(.vertical, DesignSystem.Spacing.lg)
                    .background(DesignSystem.Colors.surface)
                    .overlay(
                        Rectangle()
                            .frame(height: 1)
                            .foregroundColor(DesignSystem.Colors.border),
                        alignment: .bottom
                    )
                
                    // Enhanced Markdown Preview
                    if promptTerminal.currentContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        VStack(spacing: DesignSystem.Spacing.xl) {
                            Spacer()
                            
                            // Professional empty state
                            VStack(spacing: DesignSystem.Spacing.lg) {
                                ZStack {
                                    Circle()
                                        .fill(DesignSystem.Colors.primaryGradient)
                                        .frame(width: 80, height: 80)
                                        .blur(radius: 15)
                                        .opacity(0.2)
                                    
                                    Circle()
                                        .fill(DesignSystem.Colors.surface)
                                        .frame(width: 64, height: 64)
                                        .overlay(
                                            Image(systemName: "doc.text.magnifyingglass")
                                                .font(.system(size: 28, weight: .light))
                                                .foregroundColor(DesignSystem.Colors.primary)
                                        )
                                }
                                
                                VStack(spacing: DesignSystem.Spacing.sm) {
                                    Text("Markdown Preview")
                                        .font(DesignSystem.Typography.titleMedium)
                                        .foregroundColor(DesignSystem.Colors.textPrimary)
                                    
                                    Text("Edit your prompt in the terminal editor\nto see a live preview here")
                                        .font(DesignSystem.Typography.bodyMedium)
                                        .foregroundColor(DesignSystem.Colors.textSecondary)
                                        .multilineTextAlignment(.center)
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