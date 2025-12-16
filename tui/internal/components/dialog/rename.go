package dialog

import (
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/bubbles/textinput"
	"github.com/charmbracelet/lipgloss"
	"github.com/williamcory/agent/tui/internal/styles"
)

// RenameConfirmedMsg is sent when a rename is confirmed
type RenameConfirmedMsg struct {
	SessionID string
	NewTitle  string
}

// RenameCancelledMsg is sent when rename is cancelled
type RenameCancelledMsg struct{}

// RenameDialog displays a dialog for renaming a session
type RenameDialog struct {
	BaseDialog
	sessionID   string
	input       textinput.Model
	errorMsg    string
	originalTitle string
}

// NewRenameDialog creates a new rename dialog
func NewRenameDialog(sessionID, currentTitle string) *RenameDialog {
	ti := textinput.New()
	ti.Placeholder = "Enter new name..."
	ti.Focus()
	ti.CharLimit = 100
	ti.Width = 40
	ti.SetValue(currentTitle)

	d := &RenameDialog{
		BaseDialog:    NewBaseDialog("Rename Session", "", 50, 12),
		sessionID:     sessionID,
		input:         ti,
		originalTitle: currentTitle,
	}
	d.BaseDialog.Content = d.buildContent()
	return d
}

// buildContent builds the rename dialog content
func (d *RenameDialog) buildContent() string {
	var lines []string
	theme := styles.GetCurrentTheme()

	lines = append(lines, "")

	// Instructions
	helpStyle := lipgloss.NewStyle().Foreground(theme.Muted)
	lines = append(lines, helpStyle.Render("  Enter a new name for this session:"))
	lines = append(lines, "")

	// Input field
	inputStyle := lipgloss.NewStyle().
		BorderStyle(lipgloss.RoundedBorder()).
		BorderForeground(theme.Primary).
		Padding(0, 1).
		Width(44)

	lines = append(lines, "  "+inputStyle.Render(d.input.View()))
	lines = append(lines, "")

	// Error message if any
	if d.errorMsg != "" {
		errorStyle := lipgloss.NewStyle().Foreground(theme.Error)
		lines = append(lines, "  "+errorStyle.Render(d.errorMsg))
		lines = append(lines, "")
	}

	// Action hints
	hintStyle := lipgloss.NewStyle().Foreground(theme.Muted)
	keyStyle := lipgloss.NewStyle().Foreground(theme.Accent).Bold(true)

	hints := keyStyle.Render("Enter") + hintStyle.Render(" confirm • ") +
		keyStyle.Render("Esc") + hintStyle.Render(" cancel")
	lines = append(lines, "  "+hints)

	return strings.Join(lines, "\n")
}

// Update handles messages for the rename dialog
func (d *RenameDialog) Update(msg tea.Msg) (*RenameDialog, tea.Cmd) {
	var cmds []tea.Cmd

	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "enter":
			// Validate input
			newTitle := strings.TrimSpace(d.input.Value())
			if newTitle == "" {
				d.errorMsg = "Name cannot be empty"
				d.BaseDialog.Content = d.buildContent()
				return d, nil
			}
			if newTitle == d.originalTitle {
				// No change, just close
				d.SetVisible(false)
				return d, func() tea.Msg { return RenameCancelledMsg{} }
			}

			d.SetVisible(false)
			return d, func() tea.Msg {
				return RenameConfirmedMsg{
					SessionID: d.sessionID,
					NewTitle:  newTitle,
				}
			}

		case "esc":
			d.SetVisible(false)
			return d, func() tea.Msg { return RenameCancelledMsg{} }
		}
	}

	// Update text input
	var cmd tea.Cmd
	d.input, cmd = d.input.Update(msg)
	cmds = append(cmds, cmd)

	// Clear error on typing
	if d.errorMsg != "" {
		d.errorMsg = ""
	}
	d.BaseDialog.Content = d.buildContent()

	return d, tea.Batch(cmds...)
}

// Render renders the rename dialog
func (d *RenameDialog) Render(termWidth, termHeight int) string {
	return d.BaseDialog.Render(termWidth, termHeight)
}

// GetNewTitle returns the current input value
func (d *RenameDialog) GetNewTitle() string {
	return strings.TrimSpace(d.input.Value())
}

// SetError sets an error message
func (d *RenameDialog) SetError(msg string) {
	d.errorMsg = msg
	d.BaseDialog.Content = d.buildContent()
}
