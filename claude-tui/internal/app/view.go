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

	// Header with session info
	header := m.renderHeader()
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
	} else if m.state == StateLoading {
		loadingInput := lipgloss.NewStyle().
			Foreground(styles.Muted).
			Italic(true).
			Border(lipgloss.RoundedBorder()).
			BorderForeground(styles.Muted).
			Padding(0, 1).
			Width(m.width - 2).
			Render("Connecting to server...")
		sections = append(sections, loadingInput)
	} else {
		sections = append(sections, m.input.View())
	}

	// Status bar
	statusBar := m.renderStatusBar()
	sections = append(sections, statusBar)

	return lipgloss.JoinVertical(lipgloss.Left, sections...)
}

// renderHeader renders the header with session info
func (m Model) renderHeader() string {
	title := styles.Header.Render("Claude TUI")

	var sessionInfo string
	if m.session != nil {
		sessionTitle := m.session.Title
		if sessionTitle == "" {
			sessionTitle = "Untitled"
		}
		sessionInfo = styles.MutedText.Render(fmt.Sprintf(" • %s", sessionTitle))
	}

	return title + sessionInfo + "\n"
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
	case StateLoading:
		status = "Loading..."
		statusStyle = styles.StatusBarStreaming
	case StateError:
		status = fmt.Sprintf("Error: %v", m.err)
		statusStyle = styles.StatusBarError
	}

	// Left side: status
	left := statusStyle.Render(status)

	// Center: token info (if available)
	var tokenInfo string
	if m.totalTokens > 0 {
		tokenInfo = styles.MutedText.Render(fmt.Sprintf("Tokens: %d", m.totalTokens))
		if m.totalCost > 0 {
			tokenInfo += styles.MutedText.Render(fmt.Sprintf(" • $%.4f", m.totalCost))
		}
	}

	// Right side: help
	help := styles.StatusBar.Render("Enter: send • Ctrl+N: new • Ctrl+C: quit")

	// Calculate spacing
	leftWidth := lipgloss.Width(left)
	centerWidth := lipgloss.Width(tokenInfo)
	rightWidth := lipgloss.Width(help)
	totalContent := leftWidth + centerWidth + rightWidth

	spacerWidth := (m.width - totalContent - 4) / 2
	if spacerWidth < 1 {
		spacerWidth = 1
	}
	spacer := strings.Repeat(" ", spacerWidth)

	if tokenInfo != "" {
		return lipgloss.JoinHorizontal(lipgloss.Top, left, spacer, tokenInfo, spacer, help)
	}

	// If no token info, just spread left and right
	totalSpacer := m.width - leftWidth - rightWidth - 2
	if totalSpacer < 0 {
		totalSpacer = 0
	}
	return lipgloss.JoinHorizontal(lipgloss.Top, left, strings.Repeat(" ", totalSpacer), help)
}
