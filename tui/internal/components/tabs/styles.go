package tabs

import (
	"github.com/charmbracelet/lipgloss"
	"tui/internal/styles"
)

// ActiveTabStyle returns the style for active tabs
func ActiveTabStyle() lipgloss.Style {
	theme := styles.GetCurrentTheme()
	return lipgloss.NewStyle().
		Foreground(theme.TextPrimary).
		Background(theme.Primary).
		Padding(0, 2).
		Bold(true)
}

// InactiveTabStyle returns the style for inactive tabs
func InactiveTabStyle() lipgloss.Style {
	theme := styles.GetCurrentTheme()
	return lipgloss.NewStyle().
		Foreground(theme.TextSecondary).
		Background(theme.Background).
		Padding(0, 2)
}

// TabBadgeStyle returns the style for tab badges
func TabBadgeStyle() lipgloss.Style {
	theme := styles.GetCurrentTheme()
	return lipgloss.NewStyle().
		Foreground(theme.Accent).
		Bold(true)
}

// TabContainerStyle returns the style for the tab container
func TabContainerStyle() lipgloss.Style {
	theme := styles.GetCurrentTheme()
	return lipgloss.NewStyle().
		BorderBottom(true).
		BorderStyle(lipgloss.NormalBorder()).
		BorderForeground(theme.Border)
}

// CloseButtonStyle returns the style for close buttons
func CloseButtonStyle(hover bool) lipgloss.Style {
	theme := styles.GetCurrentTheme()
	if hover {
		return lipgloss.NewStyle().
			Foreground(theme.Error).
			PaddingLeft(1)
	}
	return lipgloss.NewStyle().
		Foreground(theme.Muted).
		PaddingLeft(1)
}
