package dialog

import (
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"tui/internal/styles"
)

// HelpDialog displays keyboard shortcuts and help information
type HelpDialog struct {
	BaseDialog
}

// NewHelpDialog creates a new help dialog
func NewHelpDialog() *HelpDialog {
	content := buildHelpContent()
	return &HelpDialog{
		BaseDialog: NewBaseDialog("Keyboard Shortcuts", content, 60, 20),
	}
}

// buildHelpContent builds the help content with all keyboard shortcuts
func buildHelpContent() string {
	type shortcut struct {
		key  string
		desc string
	}

	shortcuts := []shortcut{
		{"Enter", "Send message"},
		{"Ctrl+C", "Quit application (or cancel streaming)"},
		{"Esc", "Close dialog (or cancel streaming)"},
		{"Ctrl+N", "Start new session"},
		{"Ctrl+L", "Clear chat history"},
		{"PgUp/PgDn", "Scroll chat"},
		{"?", "Show this help dialog"},
	}

	var lines []string
	lines = append(lines, "")

	theme := styles.GetCurrentTheme()
	keyStyle := lipgloss.NewStyle().
		Foreground(theme.Primary).
		Bold(true)

	descStyle := lipgloss.NewStyle().
		Foreground(theme.TextSecondary)

	for _, s := range shortcuts {
		key := keyStyle.Render(s.key)
		desc := descStyle.Render(s.desc)
		line := lipgloss.JoinHorizontal(lipgloss.Top,
			key,
			strings.Repeat(" ", 15-lipgloss.Width(s.key)),
			desc,
		)
		lines = append(lines, "  "+line)
	}

	lines = append(lines, "")
	lines = append(lines, styles.MutedText().Render("  Press Esc or ? to close this dialog"))
	lines = append(lines, "")

	return strings.Join(lines, "\n")
}

// Update handles messages for the help dialog
func (d *HelpDialog) Update(msg tea.Msg) (*HelpDialog, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "esc", "?":
			d.SetVisible(false)
			return d, nil
		}
	}
	return d, nil
}

// Render renders the help dialog
func (d *HelpDialog) Render(termWidth, termHeight int) string {
	return d.BaseDialog.Render(termWidth, termHeight)
}
