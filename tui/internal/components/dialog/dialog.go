package dialog

import (
	"strings"

	"github.com/charmbracelet/lipgloss"
	"github.com/williamcory/agent/tui/internal/styles"
)

// Dialog represents a modal dialog box
type Dialog interface {
	// Render renders the dialog content
	Render(width, height int) string
	// GetTitle returns the dialog title
	GetTitle() string
	// IsVisible returns whether the dialog is visible
	IsVisible() bool
	// SetVisible sets the visibility
	SetVisible(bool)
}

// BaseDialog is a base implementation of Dialog
type BaseDialog struct {
	Title   string
	Content string
	Visible bool
	Width   int
	Height  int
}

// NewBaseDialog creates a new base dialog
func NewBaseDialog(title, content string, width, height int) BaseDialog {
	return BaseDialog{
		Title:   title,
		Content: content,
		Visible: true,
		Width:   width,
		Height:  height,
	}
}

// GetTitle returns the dialog title
func (d BaseDialog) GetTitle() string {
	return d.Title
}

// IsVisible returns whether the dialog is visible
func (d BaseDialog) IsVisible() bool {
	return d.Visible
}

// SetVisible sets the visibility
func (d *BaseDialog) SetVisible(visible bool) {
	d.Visible = visible
}

// Render renders a centered modal dialog box
func (d BaseDialog) Render(termWidth, termHeight int) string {
	if !d.Visible {
		return ""
	}

	// Dialog dimensions
	dialogWidth := d.Width
	dialogHeight := d.Height

	// Ensure dialog fits on screen
	if dialogWidth > termWidth-4 {
		dialogWidth = termWidth - 4
	}
	if dialogHeight > termHeight-4 {
		dialogHeight = termHeight - 4
	}

	// Get current theme
	theme := styles.GetCurrentTheme()

	// Title style
	titleStyle := lipgloss.NewStyle().
		Foreground(theme.Primary).
		Bold(true).
		Padding(0, 1).
		Width(dialogWidth - 4).
		Align(lipgloss.Center)

	title := titleStyle.Render(d.Title)

	// Content style
	contentStyle := lipgloss.NewStyle().
		Foreground(theme.TextPrimary).
		Padding(1, 2).
		Width(dialogWidth - 4)

	content := contentStyle.Render(d.Content)

	// Border style
	borderStyle := lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(theme.Primary).
		Padding(1, 1).
		Width(dialogWidth).
		MaxWidth(dialogWidth)

	// Combine title and content
	dialogContent := lipgloss.JoinVertical(lipgloss.Left, title, content)
	dialog := borderStyle.Render(dialogContent)

	// Center the dialog on screen
	return centerDialog(dialog, termWidth, termHeight)
}

// centerDialog centers a dialog on the screen
func centerDialog(dialog string, termWidth, termHeight int) string {
	lines := strings.Split(dialog, "\n")
	dialogHeight := len(lines)
	dialogWidth := lipgloss.Width(dialog)

	// Calculate padding to center
	verticalPadding := (termHeight - dialogHeight) / 2
	if verticalPadding < 0 {
		verticalPadding = 0
	}

	horizontalPadding := (termWidth - dialogWidth) / 2
	if horizontalPadding < 0 {
		horizontalPadding = 0
	}

	// Add vertical padding
	paddedLines := make([]string, 0, termHeight)
	for i := 0; i < verticalPadding; i++ {
		paddedLines = append(paddedLines, "")
	}

	// Add horizontal padding to each line
	for _, line := range lines {
		paddedLine := strings.Repeat(" ", horizontalPadding) + line
		paddedLines = append(paddedLines, paddedLine)
	}

	return strings.Join(paddedLines, "\n")
}

// Overlay renders a dialog on top of a base view
func Overlay(baseView string, dialog string, termWidth, termHeight int) string {
	if dialog == "" {
		return baseView
	}

	baseLines := strings.Split(baseView, "\n")
	dialogLines := strings.Split(dialog, "\n")

	// Ensure we have enough base lines
	for len(baseLines) < termHeight {
		baseLines = append(baseLines, strings.Repeat(" ", termWidth))
	}

	// Overlay dialog lines on base lines
	for i, dialogLine := range dialogLines {
		if i < len(baseLines) {
			// Replace base line with dialog line if dialog line is not empty
			if strings.TrimSpace(dialogLine) != "" {
				// Ensure the line is exactly termWidth
				if len(dialogLine) < termWidth {
					dialogLine += strings.Repeat(" ", termWidth-len(dialogLine))
				} else if len(dialogLine) > termWidth {
					dialogLine = dialogLine[:termWidth]
				}
				baseLines[i] = dialogLine
			}
		}
	}

	return strings.Join(baseLines, "\n")
}
