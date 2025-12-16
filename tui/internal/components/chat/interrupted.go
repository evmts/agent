package chat

import (
	"fmt"
	"strings"
	"time"

	"github.com/charmbracelet/lipgloss"
	"github.com/williamcory/agent/tui/internal/styles"
)

// InterruptInfo contains information about an interrupted operation
type InterruptInfo struct {
	Timestamp   time.Time
	Operation   string
	Description string
	PartialText string
	TokensUsed  int
	Progress    string // Optional progress information
}

// RenderInterruptedBanner renders a visual banner showing the interrupted state
func RenderInterruptedBanner(info InterruptInfo, width int) string {
	theme := styles.GetCurrentTheme()

	// Warning symbol and title
	warningStyle := lipgloss.NewStyle().
		Foreground(theme.Warning).
		Bold(true)

	titleStyle := lipgloss.NewStyle().
		Foreground(theme.Warning).
		Bold(true)

	// Calculate elapsed time
	elapsed := time.Since(info.Timestamp)
	var timeStr string
	if elapsed < time.Minute {
		timeStr = fmt.Sprintf("%.0fs ago", elapsed.Seconds())
	} else if elapsed < time.Hour {
		timeStr = fmt.Sprintf("%.0fm ago", elapsed.Minutes())
	} else {
		timeStr = fmt.Sprintf("%.1fh ago", elapsed.Hours())
	}

	// Build the banner content
	var banner strings.Builder

	// Top border
	borderStyle := lipgloss.NewStyle().Foreground(theme.Warning)
	banner.WriteString(borderStyle.Render("┌" + strings.Repeat("─", width-2) + "┐"))
	banner.WriteString("\n")

	// Title line: ⚠ INTERRUPTED
	titleLine := warningStyle.Render("⚠ ") + titleStyle.Render("INTERRUPTED")
	timeStyle := lipgloss.NewStyle().Foreground(theme.Muted).Italic(true)
	paddedTitle := lipgloss.NewStyle().
		Foreground(theme.Warning).
		PaddingLeft(1).
		PaddingRight(1).
		Width(width - 2).
		Render(titleLine + strings.Repeat(" ", width-lipgloss.Width(titleLine)-lipgloss.Width(timeStyle.Render(timeStr))-4) + timeStyle.Render(timeStr))
	banner.WriteString(borderStyle.Render("│") + paddedTitle + borderStyle.Render("│"))
	banner.WriteString("\n")

	// Empty line
	banner.WriteString(borderStyle.Render("│") + strings.Repeat(" ", width-2) + borderStyle.Render("│"))
	banner.WriteString("\n")

	// Description line
	descStyle := lipgloss.NewStyle().Foreground(theme.TextPrimary)
	labelStyle := lipgloss.NewStyle().Foreground(theme.Muted).Bold(true)
	descLine := labelStyle.Render("Stopped while: ") + descStyle.Render(info.Description)
	if lipgloss.Width(descLine) > width-4 {
		descLine = descLine[:width-7] + "..."
	}
	paddedDesc := lipgloss.NewStyle().
		PaddingLeft(1).
		PaddingRight(1).
		Width(width - 2).
		Render(descLine)
	banner.WriteString(borderStyle.Render("│") + paddedDesc + borderStyle.Render("│"))
	banner.WriteString("\n")

	// Progress line (if available)
	if info.Progress != "" {
		progStyle := lipgloss.NewStyle().Foreground(theme.TextSecondary)
		progLine := labelStyle.Render("Progress: ") + progStyle.Render(info.Progress)
		paddedProg := lipgloss.NewStyle().
			PaddingLeft(1).
			PaddingRight(1).
			Width(width - 2).
			Render(progLine)
		banner.WriteString(borderStyle.Render("│") + paddedProg + borderStyle.Render("│"))
		banner.WriteString("\n")
	}

	// Tokens line
	if info.TokensUsed > 0 {
		tokenStyle := lipgloss.NewStyle().Foreground(theme.Muted)
		tokenLine := labelStyle.Render("Tokens used: ") + tokenStyle.Render(formatInterruptTokenCount(info.TokensUsed))
		paddedTokens := lipgloss.NewStyle().
			PaddingLeft(1).
			PaddingRight(1).
			Width(width - 2).
			Render(tokenLine)
		banner.WriteString(borderStyle.Render("│") + paddedTokens + borderStyle.Render("│"))
		banner.WriteString("\n")
	}

	// Partial text preview (if available)
	if info.PartialText != "" {
		// Empty line before preview
		banner.WriteString(borderStyle.Render("│") + strings.Repeat(" ", width-2) + borderStyle.Render("│"))
		banner.WriteString("\n")

		previewStyle := lipgloss.NewStyle().Foreground(theme.Muted).Italic(true)
		previewLabel := labelStyle.Render("Partial output:")
		paddedLabel := lipgloss.NewStyle().
			PaddingLeft(1).
			PaddingRight(1).
			Width(width - 2).
			Render(previewLabel)
		banner.WriteString(borderStyle.Render("│") + paddedLabel + borderStyle.Render("│"))
		banner.WriteString("\n")

		// Show first few lines of partial text
		lines := strings.Split(info.PartialText, "\n")
		maxLines := 3
		for i, line := range lines {
			if i >= maxLines {
				moreStyle := lipgloss.NewStyle().Foreground(theme.Muted)
				moreLine := moreStyle.Render(fmt.Sprintf("... (%d more lines)", len(lines)-maxLines))
				paddedMore := lipgloss.NewStyle().
					PaddingLeft(1).
					PaddingRight(1).
					Width(width - 2).
					Render(moreLine)
				banner.WriteString(borderStyle.Render("│") + paddedMore + borderStyle.Render("│"))
				banner.WriteString("\n")
				break
			}
			if len(line) > width-6 {
				line = line[:width-9] + "..."
			}
			paddedLine := lipgloss.NewStyle().
				PaddingLeft(1).
				PaddingRight(1).
				Width(width - 2).
				Render(previewStyle.Render(line))
			banner.WriteString(borderStyle.Render("│") + paddedLine + borderStyle.Render("│"))
			banner.WriteString("\n")
		}
	}

	// Empty line before actions
	banner.WriteString(borderStyle.Render("│") + strings.Repeat(" ", width-2) + borderStyle.Render("│"))
	banner.WriteString("\n")

	// Action hints
	actionStyle := lipgloss.NewStyle().Foreground(theme.Muted).Italic(true)
	keyStyle := lipgloss.NewStyle().Foreground(theme.Success).Bold(true)
	actionLine := keyStyle.Render("[R]") + actionStyle.Render(" Resume   ") +
		keyStyle.Render("[N]") + actionStyle.Render(" New message   ") +
		keyStyle.Render("[Enter]") + actionStyle.Render(" Continue chatting")
	paddedActions := lipgloss.NewStyle().
		PaddingLeft(1).
		PaddingRight(1).
		Width(width - 2).
		Render(actionLine)
	banner.WriteString(borderStyle.Render("│") + paddedActions + borderStyle.Render("│"))
	banner.WriteString("\n")

	// Bottom border
	banner.WriteString(borderStyle.Render("└" + strings.Repeat("─", width-2) + "┘"))

	return banner.String()
}

// RenderInterruptedIndicator renders a compact interrupted indicator
// Used for showing interrupted state in message list
func RenderInterruptedIndicator() string {
	theme := styles.GetCurrentTheme()
	warningStyle := lipgloss.NewStyle().
		Foreground(theme.Warning).
		Bold(true)
	textStyle := lipgloss.NewStyle().
		Foreground(theme.Muted).
		Italic(true)

	return warningStyle.Render("⚠ ") + textStyle.Render("Interrupted") + textStyle.Render(" (press R to resume)")
}

// formatInterruptTokenCount formats token count with k suffix for thousands
func formatInterruptTokenCount(count int) string {
	if count < 1000 {
		return fmt.Sprintf("%d", count)
	}
	return fmt.Sprintf("%.1fk", float64(count)/1000.0)
}
