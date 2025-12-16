package dialog

import (
	"fmt"
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/williamcory/agent/sdk/agent"
	"github.com/williamcory/agent/tui/internal/styles"
)

// SessionListSelectedMsg is sent when a session is selected from the list
type SessionListSelectedMsg struct {
	Session agent.Session
}

// SessionListDialog displays a searchable list of sessions
type SessionListDialog struct {
	sessions      []agent.Session
	filtered      []agent.Session
	selectedIndex int
	searchInput   textinput.Model
	visible       bool
	width         int
	height        int
}

// NewSessionListDialog creates a new session list dialog
func NewSessionListDialog(sessions []agent.Session) *SessionListDialog {
	ti := textinput.New()
	ti.Placeholder = "Search sessions..."
	ti.Focus()
	ti.CharLimit = 50
	ti.Width = 40

	return &SessionListDialog{
		sessions:      sessions,
		filtered:      sessions,
		selectedIndex: 0,
		searchInput:   ti,
		visible:       true,
		width:         70,
		height:        22,
	}
}

// SetSessions updates the session list
func (d *SessionListDialog) SetSessions(sessions []agent.Session) {
	d.sessions = sessions
	d.filterSessions()
}

// Update handles messages for the session list dialog
func (d *SessionListDialog) Update(msg tea.Msg) (Dialog, tea.Cmd) {
	var cmd tea.Cmd

	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "esc", "ctrl+s":
			d.visible = false
			return d, nil
		case "enter":
			if len(d.filtered) > 0 && d.selectedIndex < len(d.filtered) {
				d.visible = false
				return d, func() tea.Msg {
					return SessionListSelectedMsg{Session: d.filtered[d.selectedIndex]}
				}
			}
		case "up", "ctrl+k":
			if d.selectedIndex > 0 {
				d.selectedIndex--
			}
			return d, nil
		case "down", "ctrl+j":
			if d.selectedIndex < len(d.filtered)-1 {
				d.selectedIndex++
			}
			return d, nil
		}
	}

	// Update search input
	d.searchInput, cmd = d.searchInput.Update(msg)

	// Filter sessions based on search
	d.filterSessions()

	return d, cmd
}

// filterSessions filters the session list based on search input
func (d *SessionListDialog) filterSessions() {
	query := strings.ToLower(d.searchInput.Value())
	if query == "" {
		d.filtered = d.sessions
		d.selectedIndex = 0
		return
	}

	var filtered []agent.Session
	for _, s := range d.sessions {
		titleMatch := strings.Contains(strings.ToLower(s.Title), query)
		idMatch := strings.Contains(strings.ToLower(s.ID), query)
		if titleMatch || idMatch {
			filtered = append(filtered, s)
		}
	}
	d.filtered = filtered

	// Reset selection if out of bounds
	if d.selectedIndex >= len(d.filtered) {
		if len(d.filtered) > 0 {
			d.selectedIndex = len(d.filtered) - 1
		} else {
			d.selectedIndex = 0
		}
	}
}

// GetTitle returns the dialog title
func (d *SessionListDialog) GetTitle() string {
	return "Sessions"
}

// IsVisible returns whether the dialog is visible
func (d *SessionListDialog) IsVisible() bool {
	return d.visible
}

// SetVisible sets the visibility
func (d *SessionListDialog) SetVisible(visible bool) {
	d.visible = visible
}

// formatTimeAgo formats a Unix timestamp as a relative string
func formatTimeAgo(unixTime float64) string {
	if unixTime == 0 {
		return ""
	}

	t := time.Unix(int64(unixTime), 0)
	now := time.Now()
	diff := now.Sub(t)

	switch {
	case diff < time.Minute:
		return "just now"
	case diff < time.Hour:
		mins := int(diff.Minutes())
		if mins == 1 {
			return "1 min ago"
		}
		return fmt.Sprintf("%d mins ago", mins)
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

// Render renders the session list dialog
func (d *SessionListDialog) Render(termWidth, termHeight int) string {
	if !d.visible {
		return ""
	}

	theme := styles.GetCurrentTheme()

	// Calculate dimensions
	dialogWidth := d.width
	if dialogWidth > termWidth-4 {
		dialogWidth = termWidth - 4
	}

	// Title
	titleStyle := lipgloss.NewStyle().
		Foreground(theme.Primary).
		Bold(true).
		Padding(0, 1).
		Width(dialogWidth - 4).
		Align(lipgloss.Center)

	title := titleStyle.Render(fmt.Sprintf("Sessions (%d)", len(d.sessions)))

	// Search input
	inputStyle := lipgloss.NewStyle().
		Foreground(theme.TextPrimary).
		Padding(0, 1).
		Width(dialogWidth - 6)

	searchView := inputStyle.Render(d.searchInput.View())

	// Session list
	var listLines []string
	maxVisible := 12
	startIdx := 0
	if d.selectedIndex >= maxVisible {
		startIdx = d.selectedIndex - maxVisible + 1
	}

	if len(d.filtered) == 0 {
		emptyStyle := lipgloss.NewStyle().
			Foreground(theme.Muted).
			Italic(true).
			Padding(1, 2)
		listLines = append(listLines, emptyStyle.Render("No sessions found"))
	} else {
		for i := startIdx; i < len(d.filtered) && i < startIdx+maxVisible; i++ {
			sess := d.filtered[i]

			// Session line
			isSelected := i == d.selectedIndex
			sessTitle := sess.Title
			if sessTitle == "" {
				sessTitle = "Untitled"
			}

			// Truncate title if needed
			maxTitleLen := dialogWidth - 25
			if len(sessTitle) > maxTitleLen {
				sessTitle = sessTitle[:maxTitleLen-3] + "..."
			}

			// Format time
			timeStr := formatTimeAgo(sess.Time.Created)

			var lineStyle lipgloss.Style
			if isSelected {
				lineStyle = lipgloss.NewStyle().
					Foreground(theme.TextPrimary).
					Background(theme.Primary).
					Width(dialogWidth - 6).
					PaddingLeft(2)
			} else {
				lineStyle = lipgloss.NewStyle().
					Foreground(theme.TextPrimary).
					Width(dialogWidth - 6).
					PaddingLeft(2)
			}

			// Build the line with time on right
			timeWidth := len(timeStr)
			titleWidth := dialogWidth - 10 - timeWidth
			padding := titleWidth - len(sessTitle)
			if padding < 1 {
				padding = 1
			}

			timeStyle := lipgloss.NewStyle().Foreground(theme.Muted)
			if isSelected {
				timeStyle = timeStyle.Background(theme.Primary)
			}

			line := sessTitle + strings.Repeat(" ", padding) + timeStyle.Render(timeStr)
			listLines = append(listLines, lineStyle.Render(line))
		}
	}

	listContent := strings.Join(listLines, "\n")

	// Scroll indicator
	var scrollIndicator string
	if len(d.filtered) > maxVisible {
		scrollIndicator = fmt.Sprintf(" [%d-%d of %d]", startIdx+1, min(startIdx+maxVisible, len(d.filtered)), len(d.filtered))
	}

	// Help text
	helpStyle := lipgloss.NewStyle().
		Foreground(theme.Muted).
		Italic(true).
		Align(lipgloss.Center).
		Width(dialogWidth - 4)

	help := helpStyle.Render("↑↓ navigate • Enter select • Esc close" + scrollIndicator)

	// Border
	borderStyle := lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(theme.Primary).
		Padding(1, 1).
		Width(dialogWidth).
		MaxWidth(dialogWidth)

	dialogContent := lipgloss.JoinVertical(lipgloss.Left, title, searchView, listContent, help)
	dialog := borderStyle.Render(dialogContent)

	return centerDialog(dialog, termWidth, termHeight)
}
