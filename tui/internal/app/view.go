package app

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/lipgloss"
	"github.com/muesli/reflow/ansi"
	"tui/internal/components/chat"
	"tui/internal/components/dialog"
	"tui/internal/components/progress"
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

// renderStatusBar renders the enhanced status bar at the bottom
func (m Model) renderStatusBar(width int) string {
	theme := styles.GetCurrentTheme()

	// Left section: Model, Agent, Git branch
	var leftParts []string

	// Model name with icon
	if m.currentModel != "" {
		modelStyle := lipgloss.NewStyle().Foreground(theme.Accent).Bold(true)
		leftParts = append(leftParts, modelStyle.Render("⚡ "+m.currentModel))
	}

	// Agent name
	if m.currentAgent != "" {
		agentStyle := lipgloss.NewStyle().
			Foreground(theme.TextSecondary).
			Background(theme.CodeBackground).
			Padding(0, 1)
		leftParts = append(leftParts, agentStyle.Render(m.currentAgent))
	}

	// Git branch (if available)
	if m.gitBranch != "" {
		branchStyle := lipgloss.NewStyle().Foreground(theme.Warning)
		leftParts = append(leftParts, branchStyle.Render(" "+m.gitBranch))
	}

	// Center section: State with spinner
	var stateText string
	var stateStyle lipgloss.Style
	switch m.state {
	case StateIdle:
		stateText = "● Ready"
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
		errMsg := "Error"
		if m.err != nil {
			errMsg = m.err.Error()
			if len(errMsg) > 30 {
				errMsg = errMsg[:27] + "..."
			}
		}
		stateText = "✕ " + errMsg
		stateStyle = lipgloss.NewStyle().Foreground(theme.Error)
	}

	// Right section: Context-sensitive keybind hints
	var rightParts []string

	hintStyle := lipgloss.NewStyle().Foreground(theme.Muted)
	keyStyle := lipgloss.NewStyle().Foreground(theme.TextSecondary).Bold(true)

	switch m.state {
	case StateStreaming:
		// Show cancel hint during streaming
		rightParts = append(rightParts, hintStyle.Render("Press ")+keyStyle.Render("Ctrl+C")+hintStyle.Render(" to cancel"))
	case StateIdle:
		// Show context-sensitive hints
		if m.HasActiveDialog() {
			rightParts = append(rightParts, keyStyle.Render("Esc")+hintStyle.Render(" close"))
		} else if m.sidebar.IsVisible() {
			rightParts = append(rightParts, keyStyle.Render("Tab")+hintStyle.Render(" switch"))
			rightParts = append(rightParts, keyStyle.Render("Ctrl+/")+hintStyle.Render(" hide"))
		} else {
			rightParts = append(rightParts, keyStyle.Render("?")+hintStyle.Render(" help"))
			rightParts = append(rightParts, keyStyle.Render("Ctrl+K")+hintStyle.Render(" cmd"))
		}
	default:
		// Show basic hints
		rightParts = append(rightParts, keyStyle.Render("?")+hintStyle.Render(" help"))
	}

	// Build the status bar with proper spacing
	separatorStyle := lipgloss.NewStyle().Foreground(theme.Border)
	separator := separatorStyle.Render(" │ ")

	leftSide := strings.Join(leftParts, separator)
	centerSection := stateStyle.Render(stateText)
	rightSide := strings.Join(rightParts, " ")

	// Calculate widths
	leftWidth := ansi.PrintableRuneWidth(leftSide)
	centerWidth := ansi.PrintableRuneWidth(centerSection)
	rightWidth := ansi.PrintableRuneWidth(rightSide)

	// Distribute spacing
	totalContent := leftWidth + centerWidth + rightWidth
	totalSpacing := width - totalContent - 4 // Leave some margin
	if totalSpacing < 2 {
		totalSpacing = 2
	}
	leftSpacing := totalSpacing / 2
	rightSpacing := totalSpacing - leftSpacing

	// Add a subtle top border
	borderStyle := lipgloss.NewStyle().Foreground(theme.Border)
	topBorder := borderStyle.Render(strings.Repeat("─", width))

	statusLine := leftSide + strings.Repeat(" ", leftSpacing) + centerSection + strings.Repeat(" ", rightSpacing) + rightSide

	// Apply container style
	statusStyle := lipgloss.NewStyle().
		Width(width).
		MaxWidth(width)

	return topBorder + "\n" + statusStyle.Render(statusLine)
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
