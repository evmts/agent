package sidebar

import (
	"fmt"
	"strings"
	"time"

	"github.com/charmbracelet/lipgloss"
	"github.com/williamcory/agent/sdk/agent"
	"github.com/williamcory/agent/tui/internal/styles"
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

	// Tab bar at top
	content.WriteString(m.tabs.View())
	content.WriteString("\n\n")

	// Render content based on active tab
	switch m.activeTab {
	case TabSessions:
		content.WriteString(renderSessionsTab(m))
	case TabFiles:
		content.WriteString(renderFilesTab(m))
	case TabGit:
		content.WriteString(renderGitTab(m))
	case TabContext:
		content.WriteString(renderContextTab(m))
	default:
		content.WriteString(renderSessionsTab(m))
	}

	// Help text at bottom
	content.WriteString("\n")
	helpText := lipgloss.NewStyle().Foreground(theme.Muted).Render("Tab: switch • ↑↓: nav • Ctrl+/: hide")
	content.WriteString(helpText)

	// Apply container style and set dimensions
	rendered := containerStyle().
		Width(m.width - 2).
		Height(m.height - 2).
		Render(content.String())

	return rendered
}

// renderSessionsTab renders the sessions tab content
func renderSessionsTab(m Model) string {
	var content strings.Builder

	// Current session info (if available)
	if m.currentSession != nil {
		title := m.currentSession.Title
		if title == "" {
			title = "Untitled"
		}
		content.WriteString(sectionHeaderStyle().Render("▸ " + title))
		content.WriteString("\n\n")
	}

	// Session list
	if len(m.sessions) == 0 {
		empty := emptyStyle().Render("No sessions")
		content.WriteString(empty)
	} else {
		// Calculate max visible sessions based on height
		maxVisible := 8
		if m.height < 30 {
			maxVisible = 5
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

	return content.String()
}

// renderFilesTab renders the modified files tab content
func renderFilesTab(m Model) string {
	var content strings.Builder

	if len(m.diffs) == 0 {
		content.WriteString(emptyStyle().Render("No file changes"))
		return content.String()
	}

	content.WriteString(sectionHeaderStyle().Render(fmt.Sprintf("Modified Files (%d)", len(m.diffs))))
	content.WriteString("\n\n")

	maxFiles := 10
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

	return content.String()
}

// renderContextTab renders the CLAUDE.md context tab content
func renderContextTab(m Model) string {
	var content strings.Builder
	theme := styles.GetCurrentTheme()

	// Check if we have any CLAUDE.md files
	if !m.claudeMdContext.HasAnySource() {
		// No CLAUDE.md found - show helpful message
		content.WriteString(sectionHeaderStyle().Render("⚠ No CLAUDE.md found"))
		content.WriteString("\n\n")

		content.WriteString(sectionLabelStyle().Render("Create a CLAUDE.md file to give\nthe agent project-specific\ninstructions."))
		content.WriteString("\n\n")

		content.WriteString(sectionLabelStyle().Render("Searched:"))
		content.WriteString("\n")

		for _, source := range m.claudeMdContext.Sources {
			icon := "✗"
			iconStyle := lipgloss.NewStyle().Foreground(theme.Error)
			path := source.Path
			// Abbreviate path if too long
			if len(path) > 22 {
				path = "..." + path[len(path)-19:]
			}
			content.WriteString("  " + iconStyle.Render(icon) + " " + sectionValueStyle().Render(path))
			content.WriteString("\n")
		}

		content.WriteString("\n")
		content.WriteString(sectionLabelStyle().Render("[Press N to create one]"))

		return content.String()
	}

	// CLAUDE.md found - show content
	content.WriteString(sectionHeaderStyle().Render("📄 Project Instructions"))
	content.WriteString("\n\n")

	// Show preview of content
	preview := m.claudeMdContext.GetPreview()
	// Render preview with proper wrapping
	lines := strings.Split(preview, "\n")
	maxWidth := m.width - 4
	if maxWidth < 20 {
		maxWidth = 20
	}

	for _, line := range lines {
		// Basic markdown rendering for headers
		if strings.HasPrefix(line, "# ") {
			headerText := strings.TrimPrefix(line, "# ")
			content.WriteString(lipgloss.NewStyle().
				Foreground(theme.Primary).
				Bold(true).
				Render(headerText))
		} else if strings.HasPrefix(line, "## ") {
			headerText := strings.TrimPrefix(line, "## ")
			content.WriteString(lipgloss.NewStyle().
				Foreground(theme.Secondary).
				Bold(true).
				Render(headerText))
		} else if strings.HasPrefix(line, "### ") {
			headerText := strings.TrimPrefix(line, "### ")
			content.WriteString(lipgloss.NewStyle().
				Foreground(theme.TextPrimary).
				Bold(true).
				Render(headerText))
		} else {
			// Regular text - wrap if needed
			if len(line) > maxWidth {
				// Simple word wrap
				words := strings.Fields(line)
				currentLine := ""
				for _, word := range words {
					if len(currentLine)+len(word)+1 > maxWidth {
						content.WriteString(sectionValueStyle().Render(currentLine))
						content.WriteString("\n")
						currentLine = word
					} else {
						if currentLine != "" {
							currentLine += " "
						}
						currentLine += word
					}
				}
				if currentLine != "" {
					content.WriteString(sectionValueStyle().Render(currentLine))
				}
			} else {
				content.WriteString(sectionValueStyle().Render(line))
			}
		}
		content.WriteString("\n")
	}

	// Footer with file info
	content.WriteString("\n")
	content.WriteString(sectionLabelStyle().Render("────────────────────────────────"))
	content.WriteString("\n")

	// File path
	formattedPath := m.claudeMdContext.GetFormattedPath()
	if len(formattedPath) > 28 {
		formattedPath = "..." + formattedPath[len(formattedPath)-25:]
	}
	content.WriteString(sectionLabelStyle().Render("ℹ Loaded from: "))
	content.WriteString(sectionValueStyle().Render(formattedPath))
	content.WriteString("\n")

	// Line count and update time
	lineCount := m.claudeMdContext.GetLineCount()
	updateTime := m.claudeMdContext.GetRelativeUpdateTime()
	infoLine := fmt.Sprintf("📏 %d lines · Updated %s", lineCount, updateTime)
	content.WriteString(sectionLabelStyle().Render(infoLine))
	content.WriteString("\n\n")

	// Help text
	content.WriteString(sectionLabelStyle().Render("[Press Ctrl+. for full view]"))

	return content.String()
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
