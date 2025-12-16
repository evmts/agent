package dialog

import (
	"fmt"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"tui/internal/config"
	"tui/internal/styles"
)

// ResumeAction represents the action chosen from the resume dialog
type ResumeAction int

const (
	// ResumeContinue means continue the previous session
	ResumeContinue ResumeAction = iota
	// ResumeNew means create a new session
	ResumeNew
	// ResumeSelect means show the session list
	ResumeSelect
	// ResumeCancel means cancel/close the dialog
	ResumeCancel
)

// ResumeSelectedMsg is sent when the user makes a resume choice
type ResumeSelectedMsg struct {
	Action            ResumeAction
	SessionID         string
	RememberPreference bool
	Preference         config.ResumePreference
}

// ResumeDialog displays the session resume prompt
type ResumeDialog struct {
	info              *config.LastSessionInfo
	selectedOption    int // 0=Continue, 1=New, 2=Select
	rememberChoice    bool
	visible           bool
	width             int
	height            int
}

// NewResumeDialog creates a new resume dialog
func NewResumeDialog(info *config.LastSessionInfo) *ResumeDialog {
	return &ResumeDialog{
		info:           info,
		selectedOption: 0, // Default to "Continue"
		rememberChoice: false,
		visible:        true,
		width:          60,
		height:         18,
	}
}

// Update handles messages for the resume dialog
func (d *ResumeDialog) Update(msg tea.Msg) (Dialog, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "esc":
			d.visible = false
			return d, func() tea.Msg {
				return ResumeSelectedMsg{
					Action:            ResumeCancel,
					RememberPreference: false,
				}
			}
		case "y", "Y":
			// Continue session
			d.visible = false
			pref := config.ResumeAlwaysAsk
			if d.rememberChoice {
				pref = config.ResumeAlwaysContinue
			}
			return d, func() tea.Msg {
				return ResumeSelectedMsg{
					Action:            ResumeContinue,
					SessionID:         d.info.SessionID,
					RememberPreference: d.rememberChoice,
					Preference:         pref,
				}
			}
		case "n", "N":
			// New session
			d.visible = false
			pref := config.ResumeAlwaysAsk
			if d.rememberChoice {
				pref = config.ResumeAlwaysNew
			}
			return d, func() tea.Msg {
				return ResumeSelectedMsg{
					Action:            ResumeNew,
					RememberPreference: d.rememberChoice,
					Preference:         pref,
				}
			}
		case "s", "S":
			// Select from session list
			d.visible = false
			return d, func() tea.Msg {
				return ResumeSelectedMsg{
					Action:            ResumeSelect,
					RememberPreference: false,
				}
			}
		case "r", "R", " ":
			// Toggle remember choice
			d.rememberChoice = !d.rememberChoice
			return d, nil
		case "left", "h":
			if d.selectedOption > 0 {
				d.selectedOption--
			}
			return d, nil
		case "right", "l":
			if d.selectedOption < 2 {
				d.selectedOption++
			}
			return d, nil
		case "enter":
			// Execute selected option
			d.visible = false
			var action ResumeAction
			var pref config.ResumePreference

			switch d.selectedOption {
			case 0:
				action = ResumeContinue
				pref = config.ResumeAlwaysContinue
			case 1:
				action = ResumeNew
				pref = config.ResumeAlwaysNew
			case 2:
				action = ResumeSelect
			}

			if !d.rememberChoice {
				pref = config.ResumeAlwaysAsk
			}

			return d, func() tea.Msg {
				return ResumeSelectedMsg{
					Action:            action,
					SessionID:         d.info.SessionID,
					RememberPreference: d.rememberChoice && action != ResumeSelect,
					Preference:         pref,
				}
			}
		}
	}
	return d, nil
}

// GetTitle returns the dialog title
func (d *ResumeDialog) GetTitle() string {
	return "Continue Session"
}

// IsVisible returns whether the dialog is visible
func (d *ResumeDialog) IsVisible() bool {
	return d.visible
}

// SetVisible sets the visibility
func (d *ResumeDialog) SetVisible(visible bool) {
	d.visible = visible
}

// formatResumeTimeAgo formats a time as a relative string for the resume dialog
func formatResumeTimeAgo(t time.Time) string {
	now := time.Now()
	diff := now.Sub(t)

	switch {
	case diff < time.Minute:
		return "just now"
	case diff < time.Hour:
		mins := int(diff.Minutes())
		if mins == 1 {
			return "1 minute ago"
		}
		return fmt.Sprintf("%d minutes ago", mins)
	case diff < 24*time.Hour:
		hours := int(diff.Hours())
		if hours == 1 {
			return "1 hour ago"
		}
		return fmt.Sprintf("%d hours ago", hours)
	default:
		return t.Format("Jan 2 at 3:04 PM")
	}
}

// Render renders the resume dialog
func (d *ResumeDialog) Render(termWidth, termHeight int) string {
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

	title := titleStyle.Render("Continue previous session?")

	// Session info box
	sessionTitle := d.info.Title
	if sessionTitle == "" {
		sessionTitle = "Untitled Session"
	}

	// Format the session info
	timeAgo := formatResumeTimeAgo(d.info.LastActive)

	sessionInfoStyle := lipgloss.NewStyle().
		Foreground(theme.TextPrimary).
		Border(lipgloss.RoundedBorder()).
		BorderForeground(theme.Muted).
		Padding(0, 1).
		Width(dialogWidth - 8).
		Margin(0, 2)

	sessionInfoLines := []string{
		lipgloss.NewStyle().Bold(true).Foreground(theme.Primary).Render("📝 " + sessionTitle),
		"",
		lipgloss.NewStyle().Foreground(theme.Muted).Render(fmt.Sprintf("Last active: %s", timeAgo)),
		lipgloss.NewStyle().Foreground(theme.Muted).Render(fmt.Sprintf("Messages: %d", d.info.MessageCount)),
	}

	// Add last message preview if available
	if d.info.LastMessage != "" {
		sessionInfoLines = append(sessionInfoLines, "")
		sessionInfoLines = append(sessionInfoLines, lipgloss.NewStyle().Foreground(theme.Muted).Render("Last message:"))

		// Wrap the message text
		maxLineLen := dialogWidth - 14
		messageLines := wrapText(d.info.LastMessage, maxLineLen)
		for _, line := range messageLines {
			sessionInfoLines = append(sessionInfoLines, lipgloss.NewStyle().Foreground(theme.TextSecondary).Italic(true).Render("  "+line))
		}
	}

	sessionInfo := sessionInfoStyle.Render(strings.Join(sessionInfoLines, "\n"))

	// Options
	optionsStyle := lipgloss.NewStyle().
		Foreground(theme.TextPrimary).
		Padding(0, 0).
		Width(dialogWidth - 4).
		Align(lipgloss.Center)

	// Build option buttons
	continueBtn := d.buildButton("Y", "Continue", 0, *theme)
	newBtn := d.buildButton("N", "New", 1, *theme)
	selectBtn := d.buildButton("S", "Select", 2, *theme)

	options := lipgloss.JoinHorizontal(lipgloss.Center,
		continueBtn,
		"   ",
		newBtn,
		"   ",
		selectBtn,
	)

	// Remember choice checkbox
	checkboxStyle := lipgloss.NewStyle().
		Foreground(theme.Muted).
		Width(dialogWidth - 4).
		Align(lipgloss.Center)

	checkbox := "☐"
	if d.rememberChoice {
		checkbox = "☑"
	}
	rememberLine := checkboxStyle.Render(fmt.Sprintf("%s Remember my choice (press R to toggle)", checkbox))

	// Help text
	helpStyle := lipgloss.NewStyle().
		Foreground(theme.Muted).
		Italic(true).
		Align(lipgloss.Center).
		Width(dialogWidth - 4).
		Padding(1, 0, 0, 0)

	help := helpStyle.Render("←→ navigate • Enter select • Esc cancel")

	// Spacing
	spacing := "\n"

	// Border
	borderStyle := lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(theme.Primary).
		Padding(1, 1).
		Width(dialogWidth).
		MaxWidth(dialogWidth)

	dialogContent := lipgloss.JoinVertical(lipgloss.Left,
		title,
		spacing,
		sessionInfo,
		spacing,
		optionsStyle.Render(options),
		spacing,
		rememberLine,
		help,
	)
	dialog := borderStyle.Render(dialogContent)

	return centerDialog(dialog, termWidth, termHeight)
}

// buildButton creates a button string for an option
func (d *ResumeDialog) buildButton(key, label string, index int, theme styles.Theme) string {
	isSelected := d.selectedOption == index

	keyStyle := lipgloss.NewStyle().
		Foreground(theme.Primary).
		Bold(true)

	if isSelected {
		// Highlighted button
		return lipgloss.NewStyle().
			Foreground(theme.TextPrimary).
			Background(theme.Primary).
			Padding(0, 1).
			Render(fmt.Sprintf("[%s] %s", key, label))
	}

	// Normal button
	return lipgloss.NewStyle().
		Foreground(theme.TextPrimary).
		Render(fmt.Sprintf("[%s] %s", keyStyle.Render(key), label))
}

// wrapText wraps text to fit within a maximum line length
func wrapText(text string, maxLen int) []string {
	if maxLen <= 0 {
		return []string{text}
	}

	var lines []string
	words := strings.Fields(text)

	if len(words) == 0 {
		return []string{""}
	}

	currentLine := words[0]
	for _, word := range words[1:] {
		if len(currentLine)+1+len(word) <= maxLen {
			currentLine += " " + word
		} else {
			lines = append(lines, currentLine)
			currentLine = word
		}
	}
	lines = append(lines, currentLine)

	return lines
}
