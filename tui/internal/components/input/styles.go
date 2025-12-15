package input

import (
	"github.com/charmbracelet/lipgloss"
	"tui/internal/styles"
)

var (
	// Container wraps the input area
	Container = lipgloss.NewStyle().
			Padding(0, 1)

	// Prompt is the input prompt indicator
	Prompt = lipgloss.NewStyle().
		Foreground(styles.Primary).
		Bold(true)

	// DisabledInput style when input is disabled
	DisabledInput = lipgloss.NewStyle().
			Foreground(styles.Muted).
			Italic(true)
)
