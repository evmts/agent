package chat

import (
	"github.com/charmbracelet/lipgloss"
	"claude-tui/internal/styles"
)

var (
	// ChatContainer is the style for the overall chat container
	ChatContainer = lipgloss.NewStyle().
			Padding(1, 0)

	// EmptyState is shown when there are no messages
	EmptyState = lipgloss.NewStyle().
			Foreground(styles.Muted).
			Italic(true).
			Align(lipgloss.Center)

	// WelcomeMessage is shown on first load
	WelcomeText = `Welcome to Claude TUI!

Type a message and press Enter to start chatting.

Try:
• "Hello" - Get a greeting
• "Read the main.go file" - See file reading
• "Run ls command" - See command execution
• "Search for main function" - See code search`
)
