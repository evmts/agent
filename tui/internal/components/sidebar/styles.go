package sidebar

import (
	"fmt"
	"strings"
	"time"

	"github.com/charmbracelet/lipgloss"
	"github.com/williamcory/agent/sdk/agent"
	"tui/internal/styles"
)

// Style functions that use the current theme
func containerStyle() lipgloss.Style {
	return lipgloss.NewStyle().
		Border(lipgloss.NormalBorder(), false, true, false, false).
		BorderForeground(styles.GetCurrentTheme().Muted).
		Padding(0, 1)
}

func headerStyle() lipgloss.Style {
	return lipgloss.NewStyle().
		Foreground(styles.GetCurrentTheme().Primary).
		Bold(true).
		Padding(0, 0, 1, 0)
}

func sessionStyle() lipgloss.Style {
	return lipgloss.NewStyle().
		Padding(0, 1).
		Foreground(styles.GetCurrentTheme().TextSecondary)
}

func selectedSessionStyle() lipgloss.Style {
	return lipgloss.NewStyle().
		Padding(0, 1).
		Foreground(styles.GetCurrentTheme().TextPrimary).
		Background(styles.GetCurrentTheme().Primary).
		Bold(true)
}

func timestampStyle() lipgloss.Style {
	return lipgloss.NewStyle().
		Foreground(styles.GetCurrentTheme().Muted).
		Italic(true)
}

func emptyStyle() lipgloss.Style {
	return lipgloss.NewStyle().
		Foreground(styles.GetCurrentTheme().Muted).
		Italic(true).
		Padding(2, 0)
}

// sectionHeaderStyle returns a style for section headers
func sectionHeaderStyle() lipgloss.Style {
	return lipgloss.NewStyle().
		Foreground(styles.GetCurrentTheme().TextPrimary).
		Bold(true)
}

// sectionLabelStyle returns a style for section labels
func sectionLabelStyle() lipgloss.Style {
	return lipgloss.NewStyle().
		Foreground(styles.GetCurrentTheme().Muted)
}

// sectionValueStyle returns a style for section values
func sectionValueStyle() lipgloss.Style {
	return lipgloss.NewStyle().
		Foreground(styles.GetCurrentTheme().TextSecondary)
}

// diffAddedStyle returns a style for added lines
func diffAddedStyle() lipgloss.Style {
	return lipgloss.NewStyle().
		Foreground(styles.GetCurrentTheme().Success)
}

// diffRemovedStyle returns a style for removed lines
func diffRemovedStyle() lipgloss.Style {
	return lipgloss.NewStyle().
		Foreground(styles.GetCurrentTheme().Error)
}

// renderSidebar renders the sidebar view
func renderSidebar(m Model) string {
	if !m.visible {
		return ""
	}

	var content strings.Builder
	theme := styles.GetCurrentTheme()

	// Current session info (if available)
	if m.currentSession != nil {
		title := m.currentSession.Title
		if title == "" {
			title = "Untitled"
		}
		content.WriteString(sectionHeaderStyle().Render(title))
		content.WriteString("\n\n")
	}

	// Context section
	if m.sections.Context && (m.contextInfo.InputTokens > 0 || m.contextInfo.OutputTokens > 0) {
		expandIcon := "▼"
		if !m.sections.Context {
			expandIcon = "▶"
		}
		content.WriteString(sectionHeaderStyle().Render(expandIcon + " Context"))
		content.WriteString("\n")

		// Token counts
		tokenLine := fmt.Sprintf("%s tokens", formatNumber(m.contextInfo.InputTokens+m.contextInfo.OutputTokens))
		content.WriteString(sectionValueStyle().Render(tokenLine))
		content.WriteString("\n")

		// Context percentage
		if m.contextInfo.ContextUsed > 0 {
			percentLine := fmt.Sprintf("%d%% used", m.contextInfo.ContextUsed)
			content.WriteString(sectionLabelStyle().Render(percentLine))
			content.WriteString("\n")
		}

		// Cost
		if m.contextInfo.TotalCost > 0 {
			costLine := formatCost(m.contextInfo.TotalCost) + " spent"
			content.WriteString(sectionLabelStyle().Render(costLine))
			content.WriteString("\n")
		}
		content.WriteString("\n")
	}

	// Modified files section
	if len(m.diffs) > 0 {
		expandIcon := "▼"
		if !m.sections.Files {
			expandIcon = "▶"
		}
		content.WriteString(sectionHeaderStyle().Render(fmt.Sprintf("%s Modified Files", expandIcon)))
		content.WriteString("\n")

		if m.sections.Files {
			maxFiles := 5
			for i, diff := range m.diffs {
				if i >= maxFiles {
					remaining := len(m.diffs) - maxFiles
					content.WriteString(sectionLabelStyle().Render(fmt.Sprintf("  ... and %d more", remaining)))
					content.WriteString("\n")
					break
				}
				// Truncate file path
				file := diff.File
				if len(file) > 25 {
					file = "..." + file[len(file)-22:]
				}
				// Format additions/deletions
				stats := ""
				if diff.Additions > 0 {
					stats += diffAddedStyle().Render(fmt.Sprintf("+%d", diff.Additions))
				}
				if diff.Deletions > 0 {
					if stats != "" {
						stats += " "
					}
					stats += diffRemovedStyle().Render(fmt.Sprintf("-%d", diff.Deletions))
				}
				fileLine := fmt.Sprintf("  %s", file)
				if stats != "" {
					fileLine += " " + stats
				}
				content.WriteString(sectionValueStyle().Render(fileLine))
				content.WriteString("\n")
			}
		}
		content.WriteString("\n")
	}

	// Sessions section
	expandIcon := "▼"
	if !m.sections.Sessions {
		expandIcon = "▶"
	}
	content.WriteString(sectionHeaderStyle().Render(fmt.Sprintf("%s Sessions (%d)", expandIcon, len(m.sessions))))
	content.WriteString("\n")

	if m.sections.Sessions {
		// Session list
		if len(m.sessions) == 0 {
			empty := emptyStyle().Render("No sessions")
			content.WriteString(empty)
		} else {
			// Calculate max visible sessions based on height
			maxVisible := 5
			if m.height > 30 {
				maxVisible = 8
			}

			// Calculate scroll offset to keep selected item visible
			start := 0
			if m.selectedIndex >= maxVisible {
				start = m.selectedIndex - maxVisible + 1
			}
			end := start + maxVisible
			if end > len(m.sessions) {
				end = len(m.sessions)
			}

			for i := start; i < end; i++ {
				session := m.sessions[i]
				itemStr := formatSessionItemCompact(session, i == m.selectedIndex)
				content.WriteString(itemStr)
				content.WriteString("\n")
			}

			// Show scroll indicator if there are more sessions
			if len(m.sessions) > maxVisible {
				scrollInfo := sectionLabelStyle().Render(fmt.Sprintf("  [%d-%d of %d]", start+1, end, len(m.sessions)))
				content.WriteString(scrollInfo)
				content.WriteString("\n")
			}
		}
	}

	// Help text at bottom
	content.WriteString("\n")
	helpText := lipgloss.NewStyle().Foreground(theme.Muted).Render("↑↓: nav • Enter: select • Ctrl+/: hide")
	content.WriteString(helpText)

	// Apply container style and set dimensions
	rendered := containerStyle().
		Width(m.width - 2).
		Height(m.height - 2).
		Render(content.String())

	return rendered
}

// formatSessionItemCompact formats a session item in compact form (single line)
func formatSessionItemCompact(session agent.Session, selected bool) string {
	title := session.Title
	if title == "" {
		title = "Untitled"
	}

	// Truncate title if too long
	maxTitleLen := 20
	if len(title) > maxTitleLen {
		title = title[:maxTitleLen-3] + "..."
	}

	// Format timestamp
	timestamp := formatTimestampShort(session.Time.Updated)

	// Build the item string
	itemContent := fmt.Sprintf("%s %s", title, timestampStyle().Render(timestamp))

	// Apply style based on selection
	if selected {
		return selectedSessionStyle().Render("▶ " + itemContent)
	}
	return sessionStyle().Render("  " + itemContent)
}

// formatTimestampShort formats a Unix timestamp to a short relative time
func formatTimestampShort(unixTime float64) string {
	t := time.Unix(int64(unixTime), 0)
	now := time.Now()
	diff := now.Sub(t)

	switch {
	case diff < time.Hour:
		return fmt.Sprintf("%dm", int(diff.Minutes()))
	case diff < 24*time.Hour:
		return fmt.Sprintf("%dh", int(diff.Hours()))
	case diff < 7*24*time.Hour:
		return fmt.Sprintf("%dd", int(diff.Hours()/24))
	default:
		return t.Format("Jan 2")
	}
}

// formatNumber formats a number with K/M suffixes
func formatNumber(n int) string {
	if n < 1000 {
		return fmt.Sprintf("%d", n)
	}
	if n < 1000000 {
		return fmt.Sprintf("%.1fk", float64(n)/1000)
	}
	return fmt.Sprintf("%.1fM", float64(n)/1000000)
}

// formatCost formats cost for display
func formatCost(cost float64) string {
	if cost >= 1.0 {
		return fmt.Sprintf("$%.2f", cost)
	}
	return fmt.Sprintf("$%.4f", cost)
}

// formatSessionItem formats a single session item
func formatSessionItem(session agent.Session, selected bool) string {
	title := session.Title
	if title == "" {
		title = "Untitled Session"
	}

	// Truncate title if too long
	maxTitleLen := 25
	if len(title) > maxTitleLen {
		title = title[:maxTitleLen-3] + "..."
	}

	// Format timestamp
	timestamp := formatTimestamp(session.Time.Updated)

	// Build the item string
	var itemContent string
	if session.Summary != nil && session.Summary.Files > 0 {
		itemContent = fmt.Sprintf("%s\n%s • %d files",
			title,
			timestamp,
			session.Summary.Files,
		)
	} else {
		itemContent = fmt.Sprintf("%s\n%s",
			title,
			timestamp,
		)
	}

	// Apply style based on selection
	if selected {
		return selectedSessionStyle().Render("▶ " + itemContent)
	}
	return sessionStyle().Render("  " + itemContent)
}

// formatTimestamp formats a Unix timestamp to a relative time string
func formatTimestamp(unixTime float64) string {
	t := time.Unix(int64(unixTime), 0)
	now := time.Now()
	diff := now.Sub(t)

	switch {
	case diff < time.Minute:
		return "just now"
	case diff < time.Hour:
		minutes := int(diff.Minutes())
		if minutes == 1 {
			return "1 min ago"
		}
		return fmt.Sprintf("%d mins ago", minutes)
	case diff < 24*time.Hour:
		hours := int(diff.Hours())
		if hours == 1 {
			return "1 hour ago"
		}
		return fmt.Sprintf("%d hours ago", hours)
	case diff < 7*24*time.Hour:
		days := int(diff.Hours() / 24)
		if days == 1 {
			return "yesterday"
		}
		return fmt.Sprintf("%d days ago", days)
	default:
		return t.Format("Jan 2")
	}
}
