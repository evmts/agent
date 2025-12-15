package chat

import (
	"github.com/charmbracelet/lipgloss"
	"tui/internal/styles"
)

// ChatContainer is the style for the overall chat container
func ChatContainer() lipgloss.Style {
	return lipgloss.NewStyle().
		Padding(1, 0)
}

// EmptyState is shown when there are no messages
func EmptyState() lipgloss.Style {
	return lipgloss.NewStyle().
		Foreground(styles.GetCurrentTheme().Muted).
		Italic(true).
		Align(lipgloss.Center)
}

// WelcomeText is the message shown on first load
var WelcomeText = `Welcome to Claude TUI!

Type a message and press Enter to start chatting.

Try:
• "Hello" - Get a greeting
• "Read the main.go file" - See file reading
• "Run ls command" - See command execution
• "Search for main function" - See code search`
