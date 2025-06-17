import Foundation

// Copy of AccessibilityIdentifiers for UI Tests
// UI tests run in a separate process and cannot access the main app's code directly
struct AccessibilityIdentifiers {
    // Tab Bar Buttons
    static let tabButtonPrompt = "tab_button_prompt"
    static let tabButtonFarcaster = "tab_button_farcaster"
    static let tabButtonAgent = "tab_button_agent"
    static let tabButtonTerminal = "tab_button_terminal"
    static let tabButtonWeb = "tab_button_web"
    static let tabButtonEditor = "tab_button_editor"
    static let tabButtonDiff = "tab_button_diff"
    static let tabButtonWorktree = "tab_button_worktree"
    
    // ModernChatView (Prompt Tab)
    static let chatInputField = "chat_input_field"
    static let chatSendButton = "chat_send_button"
    static let chatWelcomeTitle = "chat_welcome_title"
    
    // FarcasterView
    static let farcasterChannelPrefix = "farcaster_channel_" // e.g., "farcaster_channel_dev"
    static let farcasterNewCastButton = "farcaster_new_cast_button"
    
    // AgentView
    static let agentWelcomeTitle = "agent_welcome_title"
}