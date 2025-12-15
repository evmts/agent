package app

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/lipgloss"
	"tui/internal/components/chat"
	"tui/internal/components/dialog"
	"tui/internal/styles"
)

// View renders the application
func (m Model) View() string {
	if !m.ready {
		return "Initializing..."
	}

	// Build the main content area (header, chat, input, status)
	var sections []string

	// Calculate content width based on sidebar visibility
	contentWidth := m.width
	if m.sidebar.IsVisible() {
		contentWidth = m.width - m.sidebar.GetWidth()
	}

	// Header with session info
	header := m.renderHeader(contentWidth)
	sections = append(sections, header)

	// Chat area
	chatView := m.chat.View()
	if m.chat.IsEmpty() {
		// Show welcome message when empty
		welcomeStyle := lipgloss.NewStyle().
			Foreground(styles.GetCurrentTheme().Muted).
			Width(contentWidth).
			Align(lipgloss.Center).
			Padding(2, 0)
		chatView = welcomeStyle.Render(chat.WelcomeText)
	}
	sections = append(sections, chatView)

	// Input area
	if m.state == StateStreaming {
		// Show disabled input during streaming
		theme := styles.GetCurrentTheme()
		disabledInput := lipgloss.NewStyle().
			Foreground(theme.Muted).
			Italic(true).
			Border(lipgloss.RoundedBorder()).
			BorderForeground(theme.Muted).
			Padding(0, 1).
			Width(contentWidth - 2).
			Render("Waiting for response... (Ctrl+C to cancel)")
		sections = append(sections, disabledInput)
	} else if m.state == StateLoading {
		theme := styles.GetCurrentTheme()
		loadingInput := lipgloss.NewStyle().
			Foreground(theme.Muted).
			Italic(true).
			Border(lipgloss.RoundedBorder()).
			BorderForeground(theme.Muted).
			Padding(0, 1).
			Width(contentWidth - 2).
			Render("Connecting to server...")
		sections = append(sections, loadingInput)
	} else {
		sections = append(sections, m.input.View())
	}

	// Status bar
	statusBar := m.renderStatusBar(contentWidth)
	sections = append(sections, statusBar)

	mainContent := lipgloss.JoinVertical(lipgloss.Left, sections...)

	// If sidebar is visible, render it alongside the main content
	var baseView string
	if m.sidebar.IsVisible() {
		sidebarView := m.sidebar.View()
		baseView = lipgloss.JoinHorizontal(lipgloss.Top, sidebarView, mainContent)
	} else {
		baseView = mainContent
	}

	// If there's an active dialog, overlay it on top of the base view
	if m.HasActiveDialog() {
		dialogView := m.activeDialog.Render(m.width, m.height)
		return dialog.Overlay(baseView, dialogView, m.width, m.height)
	}

	return baseView
}

// renderHeader renders the header with session info
func (m Model) renderHeader(width int) string {
	title := styles.Header().Render("Claude TUI")

	var sessionInfo string
	if m.session != nil {
		sessionTitle := m.session.Title
		if sessionTitle == "" {
			sessionTitle = "Untitled"
		}
		sessionInfo = styles.MutedText().Render(fmt.Sprintf(" • %s", sessionTitle))
	}

	return title + sessionInfo + "\n"
}

// renderStatusBar renders the status bar at the bottom
func (m Model) renderStatusBar(width int) string {
	var status string
	var statusStyle lipgloss.Style

	switch m.state {
	case StateIdle:
		status = "Ready"
		statusStyle = styles.StatusBar()
	case StateStreaming:
		status = "Streaming..."
		statusStyle = styles.StatusBarStreaming()
	case StateLoading:
		status = "Loading..."
		statusStyle = styles.StatusBarStreaming()
	case StateError:
		status = fmt.Sprintf("Error: %v", m.err)
		statusStyle = styles.StatusBarError()
	}

	// Left side: status
	left := statusStyle.Render(status)

	// Center: token info (if available)
	var tokenInfo string
	if m.totalTokens > 0 {
		tokenInfo = styles.MutedText().Render(fmt.Sprintf("Tokens: %d", m.totalTokens))
		if m.totalCost > 0 {
			tokenInfo += styles.MutedText().Render(fmt.Sprintf(" • $%.4f", m.totalCost))
		}
	}

	// Right side: help - show sidebar toggle hint
	helpText := "Enter: send • Ctrl+N: new • Ctrl+/: sidebar • Ctrl+C: quit"
	help := styles.StatusBar().Render(helpText)

	// Calculate spacing
	leftWidth := lipgloss.Width(left)
	centerWidth := lipgloss.Width(tokenInfo)
	rightWidth := lipgloss.Width(help)
	totalContent := leftWidth + centerWidth + rightWidth

	spacerWidth := (width - totalContent - 4) / 2
	if spacerWidth < 1 {
		spacerWidth = 1
	}
	spacer := strings.Repeat(" ", spacerWidth)

	if tokenInfo != "" {
		return lipgloss.JoinHorizontal(lipgloss.Top, left, spacer, tokenInfo, spacer, help)
	}

	// If no token info, just spread left and right
	totalSpacer := width - leftWidth - rightWidth - 2
	if totalSpacer < 0 {
		totalSpacer = 0
	}
	return lipgloss.JoinHorizontal(lipgloss.Top, left, strings.Repeat(" ", totalSpacer), help)
}
