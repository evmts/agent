package input

import (
	"github.com/charmbracelet/lipgloss"
	"tui/internal/styles"
)

// Container wraps the input area
func Container() lipgloss.Style {
	return lipgloss.NewStyle().
		Padding(0, 1)
}

// Prompt is the input prompt indicator
func Prompt() lipgloss.Style {
	return lipgloss.NewStyle().
		Foreground(styles.GetCurrentTheme().Primary).
		Bold(true)
}

// DisabledInput style when input is disabled
func DisabledInput() lipgloss.Style {
	return lipgloss.NewStyle().
		Foreground(styles.GetCurrentTheme().Muted).
		Italic(true)
}
