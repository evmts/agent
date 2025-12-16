package dialog

import (
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/williamcory/agent/tui/internal/components/sidebar"
	"github.com/williamcory/agent/tui/internal/styles"
)

// ContextDialog displays the full CLAUDE.md context
type ContextDialog struct {
	BaseDialog
	context      sidebar.ClaudeMdContext
	scrollOffset int
}

// NewContextDialog creates a new context dialog
func NewContextDialog(context sidebar.ClaudeMdContext) *ContextDialog {
	content := buildContextContent(context, 0)
	width := 80
	height := 30

	title := "Project Instructions (CLAUDE.md)"
	if !context.HasAnySource() {
		title = "No CLAUDE.md Found"
	}

	return &ContextDialog{
		BaseDialog:   NewBaseDialog(title, content, width, height),
		context:      context,
		scrollOffset: 0,
	}
}

// buildContextContent builds the full context content
func buildContextContent(ctx sidebar.ClaudeMdContext, scrollOffset int) string {
	theme := styles.GetCurrentTheme()

	// Check if we have any CLAUDE.md files
	if !ctx.HasAnySource() {
		var lines []string
		lines = append(lines, "")

		labelStyle := lipgloss.NewStyle().Foreground(theme.Muted)
		errorStyle := lipgloss.NewStyle().Foreground(theme.Error)

		lines = append(lines, labelStyle.Render("No CLAUDE.md file found in the following locations:"))
		lines = append(lines, "")

		for _, source := range ctx.Sources {
			lines = append(lines, "  "+errorStyle.Render("✗")+" "+labelStyle.Render(source.Path))
		}

		lines = append(lines, "")
		lines = append(lines, labelStyle.Render("Create a CLAUDE.md file in your project root or"))
		lines = append(lines, labelStyle.Render("~/.claude/ directory to provide project-specific"))
		lines = append(lines, labelStyle.Render("instructions to the agent."))
		lines = append(lines, "")

		return strings.Join(lines, "\n")
	}

	// CLAUDE.md found - show full content
	source := ctx.GetPrimarySource()
	if source == nil {
		return ""
	}

	var lines []string

	// Add header with file info
	headerStyle := lipgloss.NewStyle().
		Foreground(theme.Primary).
		Bold(true)
	labelStyle := lipgloss.NewStyle().Foreground(theme.Muted)
	valueStyle := lipgloss.NewStyle().Foreground(theme.TextSecondary)

	lines = append(lines, "")
	lines = append(lines, labelStyle.Render("Source: ")+valueStyle.Render(ctx.GetFormattedPath()))
	lines = append(lines, labelStyle.Render("Lines: ")+valueStyle.Render(formatInt(ctx.GetLineCount())))
	lines = append(lines, labelStyle.Render("Updated: ")+valueStyle.Render(ctx.GetRelativeUpdateTime()))
	lines = append(lines, "")
	lines = append(lines, strings.Repeat("─", 60))
	lines = append(lines, "")

	// Render the content with markdown styling
	contentLines := strings.Split(source.Content, "\n")

	// Apply scroll offset
	if scrollOffset > 0 && scrollOffset < len(contentLines) {
		contentLines = contentLines[scrollOffset:]
	}

	for _, line := range contentLines {
		// Basic markdown rendering
		if strings.HasPrefix(line, "# ") {
			headerText := strings.TrimPrefix(line, "# ")
			lines = append(lines, headerStyle.Render(headerText))
		} else if strings.HasPrefix(line, "## ") {
			headerText := strings.TrimPrefix(line, "## ")
			h2Style := lipgloss.NewStyle().
				Foreground(theme.Secondary).
				Bold(true)
			lines = append(lines, h2Style.Render(headerText))
		} else if strings.HasPrefix(line, "### ") {
			headerText := strings.TrimPrefix(line, "### ")
			h3Style := lipgloss.NewStyle().
				Foreground(theme.TextPrimary).
				Bold(true)
			lines = append(lines, h3Style.Render(headerText))
		} else if strings.HasPrefix(line, "- ") || strings.HasPrefix(line, "* ") {
			// List items
			listStyle := lipgloss.NewStyle().Foreground(theme.TextSecondary)
			lines = append(lines, listStyle.Render(line))
		} else if strings.HasPrefix(line, "```") {
			// Code fence
			codeStyle := lipgloss.NewStyle().Foreground(theme.Muted)
			lines = append(lines, codeStyle.Render(line))
		} else {
			// Regular text
			textStyle := lipgloss.NewStyle().Foreground(theme.TextSecondary)
			lines = append(lines, textStyle.Render(line))
		}
	}

	lines = append(lines, "")

	return strings.Join(lines, "\n")
}

// Update handles messages for the context dialog
func (d *ContextDialog) Update(msg tea.Msg) (*ContextDialog, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "esc", "q", "ctrl+.":
			d.SetVisible(false)
			return d, nil
		case "up", "k":
			if d.scrollOffset > 0 {
				d.scrollOffset--
				d.Content = buildContextContent(d.context, d.scrollOffset)
			}
		case "down", "j":
			maxScroll := d.context.GetLineCount() - 20
			if maxScroll < 0 {
				maxScroll = 0
			}
			if d.scrollOffset < maxScroll {
				d.scrollOffset++
				d.Content = buildContextContent(d.context, d.scrollOffset)
			}
		case "pageup", "pgup":
			d.scrollOffset -= 10
			if d.scrollOffset < 0 {
				d.scrollOffset = 0
			}
			d.Content = buildContextContent(d.context, d.scrollOffset)
		case "pagedown", "pgdown":
			maxScroll := d.context.GetLineCount() - 20
			if maxScroll < 0 {
				maxScroll = 0
			}
			d.scrollOffset += 10
			if d.scrollOffset > maxScroll {
				d.scrollOffset = maxScroll
			}
			d.Content = buildContextContent(d.context, d.scrollOffset)
		case "home", "g":
			d.scrollOffset = 0
			d.Content = buildContextContent(d.context, d.scrollOffset)
		case "end", "G":
			maxScroll := d.context.GetLineCount() - 20
			if maxScroll < 0 {
				maxScroll = 0
			}
			d.scrollOffset = maxScroll
			d.Content = buildContextContent(d.context, d.scrollOffset)
		}
	}
	return d, nil
}

// Render renders the context dialog
func (d *ContextDialog) Render(termWidth, termHeight int) string {
	// Use larger dimensions for full screen view
	d.Width = termWidth * 3 / 4
	d.Height = termHeight * 3 / 4

	if d.Width < 60 {
		d.Width = 60
	}
	if d.Height < 20 {
		d.Height = 20
	}

	return d.BaseDialog.Render(termWidth, termHeight)
}

// formatInt formats an integer to string
func formatInt(n int) string {
	if n == 0 {
		return "0"
	}

	var digits []byte
	for n > 0 {
		digits = append([]byte{byte('0' + n%10)}, digits...)
		n /= 10
	}
	return string(digits)
}
