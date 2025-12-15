package dialog

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/williamcory/agent/sdk/agent"
	"tui/internal/styles"
)

// DiffDialog displays file diffs for a session
type DiffDialog struct {
	diffs    []agent.FileDiff
	viewport viewport.Model
	visible  bool
	width    int
	height   int
}

// NewDiffDialog creates a new diff dialog
func NewDiffDialog(diffs []agent.FileDiff, width, height int) *DiffDialog {
	vp := viewport.New(width-6, height-8)
	vp.SetContent(renderDiffs(diffs, width-8))

	return &DiffDialog{
		diffs:    diffs,
		viewport: vp,
		visible:  true,
		width:    width,
		height:   height,
	}
}

// renderDiffs renders all diffs as a string
func renderDiffs(diffs []agent.FileDiff, width int) string {
	if len(diffs) == 0 {
		return "No file changes in this session."
	}

	theme := styles.GetCurrentTheme()

	var sb strings.Builder

	fileStyle := lipgloss.NewStyle().
		Foreground(theme.Primary).
		Bold(true)

	addStyle := lipgloss.NewStyle().
		Foreground(theme.Success)

	delStyle := lipgloss.NewStyle().
		Foreground(theme.Error)

	for i, diff := range diffs {
		if i > 0 {
			sb.WriteString("\n" + strings.Repeat("─", width) + "\n\n")
		}

		// File header
		sb.WriteString(fileStyle.Render(diff.File))
		sb.WriteString(fmt.Sprintf(" (+%d/-%d)\n\n", diff.Additions, diff.Deletions))

		// Generate unified diff
		if diff.Before == "" && diff.After != "" {
			// New file
			sb.WriteString(addStyle.Render("[NEW FILE]") + "\n")
			for _, line := range strings.Split(diff.After, "\n")[:min(20, len(strings.Split(diff.After, "\n")))] {
				sb.WriteString(addStyle.Render("+ " + line) + "\n")
			}
			if len(strings.Split(diff.After, "\n")) > 20 {
				sb.WriteString(fmt.Sprintf("... and %d more lines\n", len(strings.Split(diff.After, "\n"))-20))
			}
		} else if diff.After == "" && diff.Before != "" {
			// Deleted file
			sb.WriteString(delStyle.Render("[DELETED FILE]") + "\n")
			for _, line := range strings.Split(diff.Before, "\n")[:min(20, len(strings.Split(diff.Before, "\n")))] {
				sb.WriteString(delStyle.Render("- " + line) + "\n")
			}
			if len(strings.Split(diff.Before, "\n")) > 20 {
				sb.WriteString(fmt.Sprintf("... and %d more lines\n", len(strings.Split(diff.Before, "\n"))-20))
			}
		} else {
			// Modified file - show simple before/after summary
			beforeLines := strings.Split(diff.Before, "\n")
			afterLines := strings.Split(diff.After, "\n")

			sb.WriteString(fmt.Sprintf("[MODIFIED: %d lines -> %d lines]\n\n", len(beforeLines), len(afterLines)))

			// Show first few changed lines
			maxLines := 15
			shown := 0
			for i := 0; i < len(beforeLines) && shown < maxLines; i++ {
				if i >= len(afterLines) || beforeLines[i] != afterLines[i] {
					if i < len(beforeLines) {
						sb.WriteString(delStyle.Render("- " + truncateLine(beforeLines[i], width-4)) + "\n")
					}
					if i < len(afterLines) {
						sb.WriteString(addStyle.Render("+ " + truncateLine(afterLines[i], width-4)) + "\n")
					}
					shown++
				}
			}
			if diff.Additions+diff.Deletions > maxLines {
				sb.WriteString(fmt.Sprintf("\n... and %d more changes\n", diff.Additions+diff.Deletions-maxLines))
			}
		}
	}

	return sb.String()
}

func truncateLine(line string, maxLen int) string {
	if len(line) <= maxLen {
		return line
	}
	return line[:maxLen-3] + "..."
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

// Update handles input
func (d *DiffDialog) Update(msg tea.Msg) (Dialog, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "q", "esc", "enter":
			d.visible = false
			return d, nil
		case "up", "k":
			d.viewport.LineUp(1)
		case "down", "j":
			d.viewport.LineDown(1)
		case "pgup":
			d.viewport.ViewUp()
		case "pgdown":
			d.viewport.ViewDown()
		}
	}
	return d, nil
}

// GetTitle returns the dialog title
func (d *DiffDialog) GetTitle() string {
	return "File Changes"
}

// IsVisible returns whether the dialog is visible
func (d *DiffDialog) IsVisible() bool {
	return d.visible
}

// SetVisible sets the visibility
func (d *DiffDialog) SetVisible(visible bool) {
	d.visible = visible
}

// Render renders the diff dialog
func (d *DiffDialog) Render(termWidth, termHeight int) string {
	if !d.visible {
		return ""
	}

	theme := styles.GetCurrentTheme()

	// Title
	titleStyle := lipgloss.NewStyle().
		Foreground(theme.Primary).
		Bold(true).
		Padding(0, 1).
		Width(d.width - 4).
		Align(lipgloss.Center)

	title := titleStyle.Render(fmt.Sprintf("File Changes (%d files)", len(d.diffs)))

	// Help text
	helpStyle := lipgloss.NewStyle().
		Foreground(theme.Muted).
		Italic(true).
		Align(lipgloss.Center).
		Width(d.width - 4)

	help := helpStyle.Render("j/k: scroll • q/esc: close")

	// Content
	contentStyle := lipgloss.NewStyle().
		Width(d.width - 4).
		Height(d.height - 8)

	content := contentStyle.Render(d.viewport.View())

	// Border
	borderStyle := lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(theme.Primary).
		Padding(1, 1).
		Width(d.width).
		MaxWidth(d.width)

	dialogContent := lipgloss.JoinVertical(lipgloss.Left, title, content, help)
	dialog := borderStyle.Render(dialogContent)

	return centerDialog(dialog, termWidth, termHeight)
}
