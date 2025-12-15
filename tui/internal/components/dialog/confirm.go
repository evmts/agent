package dialog

import (
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"tui/internal/styles"
)

// ConfirmDialog displays a yes/no confirmation prompt
type ConfirmDialog struct {
	BaseDialog
	Message   string
	OnConfirm tea.Cmd
	OnCancel  tea.Cmd
}

// ConfirmResult is the result of a confirmation dialog
type ConfirmResult struct {
	Confirmed bool
	Data      interface{}
}

// NewConfirmDialog creates a new confirmation dialog
func NewConfirmDialog(message string, onConfirm, onCancel tea.Cmd) *ConfirmDialog {
	content := buildConfirmContent(message)
	return &ConfirmDialog{
		BaseDialog: NewBaseDialog("Confirm", content, 50, 10),
		Message:    message,
		OnConfirm:  onConfirm,
		OnCancel:   onCancel,
	}
}

// buildConfirmContent builds the confirmation dialog content
func buildConfirmContent(message string) string {
	var lines []string
	lines = append(lines, "")

	// Get current theme
	theme := styles.GetCurrentTheme()

	// Message
	messageStyle := lipgloss.NewStyle().
		Foreground(theme.TextPrimary).
		Width(44).
		Align(lipgloss.Center)

	lines = append(lines, messageStyle.Render(message))
	lines = append(lines, "")
	lines = append(lines, "")

	// Buttons
	yesStyle := lipgloss.NewStyle().
		Foreground(theme.TextPrimary).
		Background(theme.Secondary).
		Bold(true).
		Padding(0, 2)

	noStyle := lipgloss.NewStyle().
		Foreground(theme.TextPrimary).
		Background(theme.Error).
		Bold(true).
		Padding(0, 2)

	hintStyle := lipgloss.NewStyle().
		Foreground(theme.Muted)

	yesButton := yesStyle.Render("Yes (Y)")
	noButton := noStyle.Render("No (N)")

	// Center buttons
	buttonsLine := lipgloss.JoinHorizontal(lipgloss.Top,
		yesButton,
		"    ",
		noButton,
	)

	buttonWidth := lipgloss.Width(buttonsLine)
	padding := (44 - buttonWidth) / 2
	if padding < 0 {
		padding = 0
	}

	lines = append(lines, strings.Repeat(" ", padding)+buttonsLine)
	lines = append(lines, "")

	hint := hintStyle.Render("Press Y to confirm, N to cancel, or Esc to close")
	hintWidth := lipgloss.Width(hint)
	hintPadding := (44 - hintWidth) / 2
	if hintPadding < 0 {
		hintPadding = 0
	}
	lines = append(lines, strings.Repeat(" ", hintPadding)+hint)
	lines = append(lines, "")

	return strings.Join(lines, "\n")
}

// Update handles messages for the confirm dialog
func (d *ConfirmDialog) Update(msg tea.Msg) (*ConfirmDialog, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch strings.ToLower(msg.String()) {
		case "y":
			d.SetVisible(false)
			return d, d.OnConfirm
		case "n", "esc":
			d.SetVisible(false)
			return d, d.OnCancel
		}
	}
	return d, nil
}

// Render renders the confirm dialog
func (d *ConfirmDialog) Render(termWidth, termHeight int) string {
	return d.BaseDialog.Render(termWidth, termHeight)
}
