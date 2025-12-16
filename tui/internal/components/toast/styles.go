package toast

import (
	"github.com/charmbracelet/lipgloss"
	"github.com/williamcory/agent/tui/internal/styles"
)

// renderToast renders a single toast notification
func renderToast(toast Toast, maxWidth int) string {
	theme := styles.GetCurrentTheme()

	// Determine colors based on toast type
	var bgColor, fgColor lipgloss.Color
	var icon string

	switch toast.Type {
	case ToastInfo:
		bgColor = theme.Info
		fgColor = lipgloss.Color("#FFFFFF")
		icon = "ℹ"
	case ToastSuccess:
		bgColor = theme.Success
		fgColor = lipgloss.Color("#FFFFFF")
		icon = "✓"
	case ToastWarning:
		bgColor = theme.Warning
		fgColor = lipgloss.Color("#000000")
		icon = "⚠"
	case ToastError:
		bgColor = theme.Error
		fgColor = lipgloss.Color("#FFFFFF")
		icon = "✗"
	default:
		bgColor = theme.Info
		fgColor = lipgloss.Color("#FFFFFF")
		icon = "ℹ"
	}

	// Calculate toast width (max 60 chars or 80% of screen width, whichever is smaller)
	toastWidth := 60
	if maxWidth > 0 {
		maxToastWidth := int(float64(maxWidth) * 0.8)
		if maxToastWidth < toastWidth {
			toastWidth = maxToastWidth
		}
	}
	if toastWidth < 20 {
		toastWidth = 20
	}

	// Create the toast style
	toastStyle := lipgloss.NewStyle().
		Background(bgColor).
		Foreground(fgColor).
		Padding(0, 2).
		Width(toastWidth).
		Border(lipgloss.RoundedBorder()).
		BorderForeground(bgColor).
		Bold(true)

	// Format the message with icon
	message := icon + " " + toast.Message

	return toastStyle.Render(message)
}
