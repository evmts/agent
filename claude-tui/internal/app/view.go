package app

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/lipgloss"
	"claude-tui/internal/components/chat"
	"claude-tui/internal/styles"
)

// View renders the application
func (m Model) View() string {
	if !m.ready {
		return "Initializing..."
	}

	var sections []string

	// Header
	header := styles.Header.Render("Claude TUI")
	sections = append(sections, header)

	// Chat area
	chatView := m.chat.View()
	if m.chat.IsEmpty() {
		// Show welcome message when empty
		welcomeStyle := lipgloss.NewStyle().
			Foreground(styles.Muted).
			Width(m.width).
			Align(lipgloss.Center).
			Padding(2, 0)
		chatView = welcomeStyle.Render(chat.WelcomeText)
	}
	sections = append(sections, chatView)

	// Input area
	if m.state == StateStreaming {
		// Show disabled input during streaming
		disabledInput := lipgloss.NewStyle().
			Foreground(styles.Muted).
			Italic(true).
			Border(lipgloss.RoundedBorder()).
			BorderForeground(styles.Muted).
			Padding(0, 1).
			Width(m.width - 2).
			Render("Waiting for response... (Ctrl+C to cancel)")
		sections = append(sections, disabledInput)
	} else {
		sections = append(sections, m.input.View())
	}

	// Status bar
	statusBar := m.renderStatusBar()
	sections = append(sections, statusBar)

	return lipgloss.JoinVertical(lipgloss.Left, sections...)
}

// renderStatusBar renders the status bar at the bottom
func (m Model) renderStatusBar() string {
	var status string
	var statusStyle lipgloss.Style

	switch m.state {
	case StateIdle:
		status = "Ready"
		statusStyle = styles.StatusBar
	case StateStreaming:
		status = "Streaming..."
		statusStyle = styles.StatusBarStreaming
	case StateError:
		status = fmt.Sprintf("Error: %v", m.err)
		statusStyle = styles.StatusBarError
	}

	// Left side: status
	left := statusStyle.Render(status)

	// Right side: help
	help := styles.StatusBar.Render("Enter: send • Ctrl+C: quit • Ctrl+L: clear")

	// Calculate spacing
	leftWidth := lipgloss.Width(left)
	rightWidth := lipgloss.Width(help)
	spacerWidth := m.width - leftWidth - rightWidth - 2
	if spacerWidth < 0 {
		spacerWidth = 0
	}
	spacer := strings.Repeat(" ", spacerWidth)

	return lipgloss.JoinHorizontal(lipgloss.Top, left, spacer, help)
}
