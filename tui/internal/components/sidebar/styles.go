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

// renderSidebar renders the sidebar view
func renderSidebar(m Model) string {
	if !m.visible {
		return ""
	}

	var content strings.Builder

	// Header
	header := headerStyle().Render("Sessions")
	content.WriteString(header)
	content.WriteString("\n\n")

	// Session list
	if len(m.sessions) == 0 {
		empty := emptyStyle().Render("No sessions")
		content.WriteString(empty)
	} else {
		// Calculate max visible sessions based on height
		// Reserve space for header (3 lines), help text (2 lines), padding
		maxVisible := m.height - 7
		if maxVisible < 1 {
			maxVisible = 1
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
			itemStr := formatSessionItem(session, i == m.selectedIndex)
			content.WriteString(itemStr)
			content.WriteString("\n")
		}
	}

	// Help text at bottom
	content.WriteString("\n")
	helpText := styles.MutedText().Render("↑/↓: navigate • Enter: select")
	content.WriteString(helpText)

	// Apply container style and set dimensions
	rendered := containerStyle().
		Width(m.width - 2).
		Height(m.height - 2).
		Render(content.String())

	return rendered
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
