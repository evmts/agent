package spinner

import (
	"github.com/charmbracelet/lipgloss"
	"github.com/williamcory/agent/tui/internal/styles"
)

// SpinnerStyle returns the default spinner style
func SpinnerStyle() lipgloss.Style {
	theme := styles.GetCurrentTheme()
	return lipgloss.NewStyle().Foreground(theme.Accent)
}

// StreamingStyle returns spinner style for streaming state
func StreamingStyle() lipgloss.Style {
	theme := styles.GetCurrentTheme()
	return lipgloss.NewStyle().Foreground(theme.Warning)
}

// LoadingStyle returns spinner style for loading state
func LoadingStyle() lipgloss.Style {
	theme := styles.GetCurrentTheme()
	return lipgloss.NewStyle().Foreground(theme.Info)
}

// SuccessStyle returns spinner style for success state
func SuccessStyle() lipgloss.Style {
	theme := styles.GetCurrentTheme()
	return lipgloss.NewStyle().Foreground(theme.Success)
}

// ErrorStyle returns spinner style for error state
func ErrorStyle() lipgloss.Style {
	theme := styles.GetCurrentTheme()
	return lipgloss.NewStyle().Foreground(theme.Error)
}
