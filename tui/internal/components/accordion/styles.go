package accordion

import (
	"github.com/charmbracelet/lipgloss"
	"tui/internal/styles"
)

// HeaderStyle returns the style for section headers
func HeaderStyle(selected bool) lipgloss.Style {
	theme := styles.GetCurrentTheme()
	if selected {
		return lipgloss.NewStyle().
			Foreground(theme.TextPrimary).
			Background(theme.Primary).
			Padding(0, 1).
			Bold(true)
	}
	return lipgloss.NewStyle().
		Foreground(theme.TextPrimary).
		Background(theme.CodeBackground).
		Padding(0, 1)
}

// ContentStyle returns the style for section content
func ContentStyle() lipgloss.Style {
	theme := styles.GetCurrentTheme()
	return lipgloss.NewStyle().
		Foreground(theme.TextSecondary).
		Padding(0, 2).
		MarginLeft(2)
}

// IndicatorStyle returns the style for expand/collapse indicator
func IndicatorStyle() lipgloss.Style {
	theme := styles.GetCurrentTheme()
	return lipgloss.NewStyle().
		Foreground(theme.Muted)
}

// BadgeStyle returns the style for section badges
func BadgeStyle() lipgloss.Style {
	theme := styles.GetCurrentTheme()
	return lipgloss.NewStyle().
		Foreground(theme.Accent).
		Bold(true)
}

// ContainerStyle returns the style for the accordion container
func ContainerStyle() lipgloss.Style {
	theme := styles.GetCurrentTheme()
	return lipgloss.NewStyle().
		BorderStyle(lipgloss.RoundedBorder()).
		BorderForeground(theme.Border)
}

// StickyHeaderStyle returns the style for sticky headers
func StickyHeaderStyle() lipgloss.Style {
	theme := styles.GetCurrentTheme()
	return lipgloss.NewStyle().
		Foreground(theme.TextPrimary).
		Background(theme.Primary).
		Padding(0, 1).
		Bold(true)
}
