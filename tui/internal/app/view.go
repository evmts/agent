package app

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/lipgloss"
	"tui/internal/components/chat"
	"tui/internal/components/dialog"
	"tui/internal/styles"
)

// formatTokens formats token count for display
func formatTokens(count int) string {
	if count < 1000 {
		return fmt.Sprintf("%d", count)
	} else if count < 1000000 {
		return fmt.Sprintf("%.1fk", float64(count)/1000)
	}
	return fmt.Sprintf("%.1fM", float64(count)/1000000)
}

// formatCost formats cost for display
func formatCost(cost float64) string {
	if cost >= 1.0 {
		return fmt.Sprintf("$%.2f", cost)
	}
	return fmt.Sprintf("$%.4f", cost)
}

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
	theme := styles.GetCurrentTheme()

	// Build status bar sections from left to right
	var sections []string

	// Left section: Model name
	if m.currentModel != "" {
		modelStyle := lipgloss.NewStyle().Foreground(theme.Accent)
		sections = append(sections, modelStyle.Render(m.currentModel))
	}

	// Agent name (if available)
	if m.currentAgent != "" {
		agentStyle := lipgloss.NewStyle().Foreground(theme.Muted)
		sections = append(sections, agentStyle.Render(m.currentAgent))
	}

	// Token count (if available)
	if m.totalInputTokens > 0 || m.totalOutputTokens > 0 {
		tokenLabel := lipgloss.NewStyle().Foreground(theme.Muted).Render("Tokens:")
		tokenValue := lipgloss.NewStyle().Foreground(theme.Text).Render(
			fmt.Sprintf("%s↓ %s↑", formatTokens(m.totalInputTokens), formatTokens(m.totalOutputTokens)),
		)
		sections = append(sections, tokenLabel+" "+tokenValue)
	}

	// Cost (if available)
	if m.totalCost > 0 {
		costStyle := lipgloss.NewStyle().Foreground(theme.Success)
		sections = append(sections, costStyle.Render(formatCost(m.totalCost)))
	}

	// Session state
	var stateText string
	var stateStyle lipgloss.Style
	switch m.state {
	case StateIdle:
		stateText = "Idle"
		stateStyle = lipgloss.NewStyle().Foreground(theme.Muted)
	case StateStreaming:
		stateText = "Streaming"
		stateStyle = lipgloss.NewStyle().Foreground(theme.Warning)
	case StateLoading:
		stateText = "Loading"
		stateStyle = lipgloss.NewStyle().Foreground(theme.Info)
	case StateError:
		stateText = fmt.Sprintf("Error: %v", m.err)
		stateStyle = lipgloss.NewStyle().Foreground(theme.Error)
	}
	sections = append(sections, stateStyle.Render(stateText))

	// Join sections with separator
	separatorStyle := lipgloss.NewStyle().Foreground(theme.Muted)
	separator := separatorStyle.Render(" | ")

	statusBar := strings.Join(sections, separator)

	// Apply padding to fill the width
	statusStyle := lipgloss.NewStyle().
		Width(width).
		MaxWidth(width).
		Foreground(theme.Text)

	return statusStyle.Render(statusBar)
}
