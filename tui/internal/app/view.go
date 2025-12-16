package app

import (
	"fmt"
	"strings"
	"time"

	"github.com/charmbracelet/lipgloss"
	"github.com/muesli/reflow/ansi"
	"github.com/williamcory/agent/tui/internal/components/chat"
	"github.com/williamcory/agent/tui/internal/components/dialog"
	"github.com/williamcory/agent/tui/internal/components/progress"
	"github.com/williamcory/agent/tui/internal/styles"
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

// formatDuration formats a duration for display (e.g., "3m 30s")
func formatDuration(d time.Duration) string {
	if d < time.Minute {
		return fmt.Sprintf("%ds", int(d.Seconds()))
	}
	minutes := int(d.Minutes())
	seconds := int(d.Seconds()) % 60
	if seconds == 0 {
		return fmt.Sprintf("%dm", minutes)
	}
	return fmt.Sprintf("%dm %ds", minutes, seconds)
}

// formatCost formats cost for display
func formatCost(cost float64) string {
	if cost >= 1.0 {
		return fmt.Sprintf("$%.2f", cost)
	}
	return fmt.Sprintf("$%.4f", cost)
}

// renderTaskStatus renders the current task status in Claude Code style
// Format: * Task description... (esc to interrupt · ctrl+t to show todos · 3m 30s · ↑ 5.0k tokens)
//         └ Next: Next task description
func (m Model) renderTaskStatus(width int) string {
	if m.currentTask == "" && m.state != StateStreaming {
		return ""
	}

	theme := styles.GetCurrentTheme()
	var result strings.Builder

	// Current task line with red asterisk
	asteriskStyle := lipgloss.NewStyle().Foreground(theme.Error).Bold(true)
	taskStyle := lipgloss.NewStyle().Foreground(theme.TextPrimary)
	hintStyle := lipgloss.NewStyle().Foreground(theme.Muted)

	// Calculate task duration
	var duration time.Duration
	if !m.taskStartTime.IsZero() {
		duration = time.Since(m.taskStartTime)
	}

	// Build the task line
	taskText := m.currentTask
	if taskText == "" && m.state == StateStreaming {
		taskText = "Processing..."
	}

	result.WriteString(asteriskStyle.Render("* "))
	result.WriteString(taskStyle.Render(taskText))

	// Add hints in parentheses
	hints := []string{
		"esc to interrupt",
		"ctrl+t to show todos",
	}
	if duration > 0 {
		hints = append(hints, formatDuration(duration))
	}
	if m.taskTokensUsed > 0 {
		hints = append(hints, fmt.Sprintf("↑ %s tokens", formatTokens(m.taskTokensUsed)))
	}

	if len(hints) > 0 {
		result.WriteString(hintStyle.Render(" (" + strings.Join(hints, " · ") + ")"))
	}

	// Next task line with tree character
	if m.nextTask != "" {
		result.WriteString("\n")
		treeStyle := lipgloss.NewStyle().Foreground(theme.Muted)
		nextStyle := lipgloss.NewStyle().Foreground(theme.TextSecondary)
		result.WriteString(treeStyle.Render("└ "))
		result.WriteString(nextStyle.Render("Next: " + m.nextTask))
	}

	return result.String()
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

	// Search overlay (shown above input when active)
	if m.chat.IsSearchActive() {
		searchOverlay := chat.RenderSearchOverlay(m.getSearchState(), contentWidth)
		sections = append(sections, searchOverlay)
	}

	// Interrupt banner - show if we have an interrupt context
	if m.interruptContext != nil {
		// Convert interrupt context to InterruptInfo for rendering
		info := chat.InterruptInfo{
			Timestamp:   m.interruptContext.Timestamp,
			Operation:   m.interruptContext.Operation.String(),
			Description: m.interruptContext.Description,
			PartialText: m.interruptContext.PartialText,
			TokensUsed:  m.interruptContext.TokensUsed,
		}

		// Add progress information for tool operations
		if m.interruptContext.Operation == OpToolExecution && m.interruptContext.ToolName != "" {
			info.Progress = fmt.Sprintf("Tool: %s", m.interruptContext.ToolName)
		}

		bannerWidth := contentWidth
		if bannerWidth > 100 {
			bannerWidth = 100
		}
		interruptBanner := chat.RenderInterruptedBanner(info, bannerWidth)
		sections = append(sections, "\n"+interruptBanner)
	}

	// Task status (Claude Code style) - shown during streaming
	if m.state == StateStreaming || m.currentTask != "" {
		taskStatus := m.renderTaskStatus(contentWidth)
		if taskStatus != "" {
			sections = append(sections, taskStatus)
		}
	}

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
		baseView = dialog.Overlay(baseView, dialogView, m.width, m.height)
	}

	// If there's a shortcuts overlay, overlay it on top of everything (including dialogs)
	if m.HasShortcutsOverlay() {
		shortcutsView := m.shortcutsOverlay.Render(m.width, m.height)
		return dialog.Overlay(baseView, shortcutsView, m.width, m.height)
	}

	return baseView
}

// renderHeader renders the enhanced header with session info, tokens, cost, and provider
func (m Model) renderHeader(width int) string {
	theme := styles.GetCurrentTheme()

	// Left side: Title and session
	title := styles.Header().Render("Claude TUI")
	var sessionInfo string
	if m.session != nil {
		sessionTitle := m.session.Title
		if sessionTitle == "" {
			sessionTitle = "Untitled"
		}
		sessionStyle := lipgloss.NewStyle().Foreground(theme.Muted)
		sessionInfo = sessionStyle.Render(" • " + sessionTitle)
	}
	leftSide := title + sessionInfo

	// Right side: Tokens, Cost, Provider
	var rightParts []string

	// Context tokens with mini progress bar
	totalTokens := m.totalInputTokens + m.totalOutputTokens
	if totalTokens > 0 || m.maxContextTokens > 0 {
		prog := progress.New(progress.VariantTokens, m.maxContextTokens)
		prog.SetProgress(totalTokens)
		prog.SetThresholds(0.75, 0.90)
		tokenDisplay := prog.View()
		rightParts = append(rightParts, tokenDisplay)
	}

	// Cost display (prominent)
	if m.totalCost > 0 {
		costStyle := lipgloss.NewStyle().
			Foreground(theme.Success).
			Bold(true)
		rightParts = append(rightParts, costStyle.Render(formatCost(m.totalCost)))
	}

	// Provider badge with connection status
	if m.provider != "" {
		// Connection status dot
		var statusDot string
		if m.connected {
			statusDot = lipgloss.NewStyle().Foreground(theme.Success).Render("●")
		} else {
			statusDot = lipgloss.NewStyle().Foreground(theme.Error).Render("○")
		}

		providerStyle := lipgloss.NewStyle().
			Foreground(theme.Accent).
			Background(theme.CodeBackground).
			Padding(0, 1).
			Bold(true)
		providerBadge := statusDot + " " + providerStyle.Render(m.provider)
		rightParts = append(rightParts, providerBadge)
	}

	// Join right side parts
	rightSide := ""
	if len(rightParts) > 0 {
		separator := lipgloss.NewStyle().Foreground(theme.Muted).Render(" │ ")
		rightSide = strings.Join(rightParts, separator)
	}

	// Calculate spacing between left and right
	leftWidth := ansi.PrintableRuneWidth(leftSide)
	rightWidth := ansi.PrintableRuneWidth(rightSide)
	spacing := width - leftWidth - rightWidth - 2
	if spacing < 1 {
		spacing = 1
	}

	headerLine := leftSide + strings.Repeat(" ", spacing) + rightSide

	// Add a subtle border underneath
	borderStyle := lipgloss.NewStyle().Foreground(theme.Border)
	border := borderStyle.Render(strings.Repeat("─", width))

	return headerLine + "\n" + border + "\n"
}

// renderStatusBar renders the status bar in Claude Code style
func (m Model) renderStatusBar(width int) string {
	theme := styles.GetCurrentTheme()

	// Claude Code style status bar:
	// Line 1: >> permissions mode (hint)                    [compact mode indicator] token count
	// Line 2: version info

	// Left section: Permissions mode with >> indicator
	arrowStyle := lipgloss.NewStyle().Foreground(theme.Warning).Bold(true)
	permStyle := lipgloss.NewStyle().Foreground(theme.TextPrimary).Bold(true)
	hintStyle := lipgloss.NewStyle().Foreground(theme.Muted)

	permText := "bypass permissions"
	if m.permissionsMode == "ask" {
		permText = "ask permissions"
	} else if m.permissionsMode == "deny" {
		permText = "deny permissions"
	}

	leftSide := arrowStyle.Render("▶▶ ") + permStyle.Render(permText+" on") + hintStyle.Render(" (shift+tab to cycle)")

	// Right section: Compact mode indicator + Token count
	var rightParts []string

	// Add compact mode indicator if enabled
	if m.chat.IsCompactMode() {
		compactStyle := lipgloss.NewStyle().
			Foreground(theme.Accent).
			Background(theme.CodeBackground).
			Padding(0, 1).
			Bold(true)
		rightParts = append(rightParts, compactStyle.Render("COMPACT"))
	}

	// Token count
	totalTokens := m.totalInputTokens + m.totalOutputTokens
	tokenStyle := lipgloss.NewStyle().Foreground(theme.TextSecondary)
	rightParts = append(rightParts, tokenStyle.Render(fmt.Sprintf("%s tokens", formatTokens(totalTokens))))

	// Join right side parts
	rightSide := strings.Join(rightParts, " ")

	// Calculate spacing
	leftWidth := ansi.PrintableRuneWidth(leftSide)
	rightWidth := ansi.PrintableRuneWidth(rightSide)
	spacing := width - leftWidth - rightWidth - 2
	if spacing < 1 {
		spacing = 1
	}

	statusLine1 := leftSide + strings.Repeat(" ", spacing) + rightSide

	// Line 2: Version info (Claude Code style)
	versionStyle := lipgloss.NewStyle().Foreground(theme.Muted)
	dotStyle := lipgloss.NewStyle().Foreground(theme.Muted)

	versionInfo := ""
	if m.appVersion != "" {
		versionInfo = versionStyle.Render("version: "+m.appVersion) +
			dotStyle.Render(" · ") +
			versionStyle.Render("latest: "+m.latestVersion)
	}

	// Right-align version info
	versionWidth := ansi.PrintableRuneWidth(versionInfo)
	versionSpacing := width - versionWidth - 2
	if versionSpacing < 0 {
		versionSpacing = 0
	}

	statusLine2 := strings.Repeat(" ", versionSpacing) + versionInfo

	// Apply container style
	statusStyle := lipgloss.NewStyle().
		Width(width).
		MaxWidth(width)

	return statusStyle.Render(statusLine1) + "\n" + statusStyle.Render(statusLine2)
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
