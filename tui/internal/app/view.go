package app

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/lipgloss"
	"github.com/muesli/reflow/ansi"
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
		// Show disabled input during streaming with spinner
		theme := styles.GetCurrentTheme()
		spinnerView := m.spinner.View()
		if spinnerView == "" {
			spinnerView = "..."
		}
		disabledInput := lipgloss.NewStyle().
			Foreground(theme.Muted).
			Italic(true).
			Border(lipgloss.RoundedBorder()).
			BorderForeground(theme.Warning).
			Padding(0, 1).
			Width(contentWidth - 2).
			Render(spinnerView + " (Ctrl+C to cancel)")
		sections = append(sections, disabledInput)
	} else if m.state == StateLoading {
		theme := styles.GetCurrentTheme()
		spinnerView := m.spinner.View()
		if spinnerView == "" {
			spinnerView = "..."
		}
		loadingInput := lipgloss.NewStyle().
			Foreground(theme.Muted).
			Italic(true).
			Border(lipgloss.RoundedBorder()).
			BorderForeground(theme.Info).
			Padding(0, 1).
			Width(contentWidth - 2).
			Render(spinnerView)
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

	// If there are toasts, overlay them on top of the base view (top-right corner)
	if m.toast.HasToasts() {
		baseView = overlayToasts(baseView, m.toast.View(), m.width, m.height)
	}

	// If there's an active dialog, overlay it on top of everything
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
		tokenValue := lipgloss.NewStyle().Foreground(theme.TextPrimary).Render(
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
		stateText = "Ready"
		stateStyle = lipgloss.NewStyle().Foreground(theme.Success)
	case StateStreaming:
		spinnerFrame := m.spinner.Frame()
		stateText = spinnerFrame + " Streaming"
		stateStyle = lipgloss.NewStyle().Foreground(theme.Warning)
	case StateLoading:
		spinnerFrame := m.spinner.Frame()
		stateText = spinnerFrame + " Loading"
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
		Foreground(theme.TextPrimary)

	return statusStyle.Render(statusBar)
}

// overlayToasts overlays toast notifications in the top-right corner
func overlayToasts(base, toasts string, width, height int) string {
	if toasts == "" {
		return base
	}

	// Split both into lines
	baseLines := strings.Split(base, "\n")
	toastLines := strings.Split(toasts, "\n")

	// Calculate toast dimensions
	toastWidth := 0
	for _, line := range toastLines {
		lineWidth := ansi.PrintableRuneWidth(line)
		if lineWidth > toastWidth {
			toastWidth = lineWidth
		}
	}

	// Position: top-right corner with some padding
	rightPadding := 2
	topPadding := 1
	startX := width - toastWidth - rightPadding
	if startX < 0 {
		startX = 0
	}

	// Overlay toasts onto base
	for i, toastLine := range toastLines {
		lineIdx := topPadding + i
		if lineIdx >= len(baseLines) {
			break
		}

		baseLine := baseLines[lineIdx]
		baseLineWidth := ansi.PrintableRuneWidth(baseLine)

		// Pad the base line to startX if needed
		if baseLineWidth < startX {
			baseLine = baseLine + strings.Repeat(" ", startX-baseLineWidth)
		}

		// Convert to runes for proper handling
		baseRunes := []rune(baseLine)

		// Calculate where to insert the toast
		visualPos := 0
		insertPos := 0
		for insertPos < len(baseRunes) && visualPos < startX {
			visualPos += ansi.PrintableRuneWidth(string(baseRunes[insertPos]))
			insertPos++
		}

		// Replace the portion with the toast
		if insertPos < len(baseRunes) {
			baseLines[lineIdx] = string(baseRunes[:insertPos]) + toastLine
		} else {
			baseLines[lineIdx] = baseLine + toastLine
		}
	}

	return strings.Join(baseLines, "\n")
}
