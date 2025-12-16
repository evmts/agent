package dialog

import (
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/williamcory/agent/tui/internal/styles"
)

// ThemeSelectedMsg is sent when a theme is selected
type ThemeSelectedMsg struct {
	ThemeName string
}

// ThemeDialog displays a list of available themes for selection
type ThemeDialog struct {
	BaseDialog
	themes        []string
	selectedIndex int
	scrollOffset  int
	maxVisible    int
}

// NewThemeDialog creates a new theme selection dialog
func NewThemeDialog() *ThemeDialog {
	themes := styles.GetThemeNames()
	d := &ThemeDialog{
		BaseDialog:    NewBaseDialog("Select Theme", "", 60, 24),
		themes:        themes,
		selectedIndex: 0,
		scrollOffset:  0,
		maxVisible:    16,
	}
	// Find current theme in list
	currentTheme := styles.GetCurrentThemeName()
	for i, name := range themes {
		if name == currentTheme {
			d.selectedIndex = i
			break
		}
	}
	d.updateScrollOffset()
	d.BaseDialog.Content = d.buildContent()
	return d
}

// buildContent builds the theme selection content
func (d *ThemeDialog) buildContent() string {
	var lines []string
	theme := styles.GetCurrentTheme()

	// Header
	headerStyle := lipgloss.NewStyle().
		Foreground(theme.Muted).
		Bold(true)

	lines = append(lines, "")
	lines = append(lines, headerStyle.Render("  Use ↑/↓ to navigate, Enter to select, Esc to cancel"))
	lines = append(lines, "")

	// Theme list styles
	selectedStyle := lipgloss.NewStyle().
		Foreground(theme.TextPrimary).
		Background(theme.Primary).
		Bold(true).
		Padding(0, 1).
		Width(52)

	normalStyle := lipgloss.NewStyle().
		Foreground(theme.TextSecondary).
		Padding(0, 1).
		Width(52)

	currentStyle := lipgloss.NewStyle().
		Foreground(theme.Success)

	// Calculate visible range
	end := d.scrollOffset + d.maxVisible
	if end > len(d.themes) {
		end = len(d.themes)
	}

	// Scroll indicator (top)
	if d.scrollOffset > 0 {
		scrollStyle := lipgloss.NewStyle().Foreground(theme.Muted)
		lines = append(lines, scrollStyle.Render("    ↑ more themes above"))
	}

	// Render visible themes
	for i := d.scrollOffset; i < end; i++ {
		themeName := d.themes[i]
		cursor := "  "
		if i == d.selectedIndex {
			cursor = "▶ "
		}

		// Mark current theme
		suffix := ""
		if themeName == styles.GetCurrentThemeName() {
			suffix = currentStyle.Render(" (current)")
		}

		themeLine := cursor + themeName + suffix
		if i == d.selectedIndex {
			lines = append(lines, selectedStyle.Render(themeLine))
		} else {
			lines = append(lines, normalStyle.Render(themeLine))
		}
	}

	// Scroll indicator (bottom)
	if end < len(d.themes) {
		scrollStyle := lipgloss.NewStyle().Foreground(theme.Muted)
		lines = append(lines, scrollStyle.Render("    ↓ more themes below"))
	}

	// Preview section
	lines = append(lines, "")
	previewHeader := lipgloss.NewStyle().
		Foreground(theme.Primary).
		Bold(true).
		Render("  Preview:")
	lines = append(lines, previewHeader)
	lines = append(lines, d.renderPreview())

	return strings.Join(lines, "\n")
}

// renderPreview renders a theme preview
func (d *ThemeDialog) renderPreview() string {
	// Temporarily get the selected theme's colors for preview
	selectedThemeName := d.themes[d.selectedIndex]
	previewTheme := styles.GetThemeByName(selectedThemeName)
	if previewTheme == nil {
		return ""
	}

	// Build preview with theme colors
	var preview strings.Builder

	primaryStyle := lipgloss.NewStyle().Foreground(previewTheme.Primary)
	secondaryStyle := lipgloss.NewStyle().Foreground(previewTheme.Secondary)
	accentStyle := lipgloss.NewStyle().Foreground(previewTheme.Accent)
	successStyle := lipgloss.NewStyle().Foreground(previewTheme.Success)
	errorStyle := lipgloss.NewStyle().Foreground(previewTheme.Error)
	mutedStyle := lipgloss.NewStyle().Foreground(previewTheme.Muted)

	preview.WriteString("    ")
	preview.WriteString(primaryStyle.Render("Primary "))
	preview.WriteString(secondaryStyle.Render("Secondary "))
	preview.WriteString(accentStyle.Render("Accent "))
	preview.WriteString(successStyle.Render("Success "))
	preview.WriteString(errorStyle.Render("Error "))
	preview.WriteString(mutedStyle.Render("Muted"))

	return preview.String()
}

// updateScrollOffset updates scroll offset to keep selected item visible
func (d *ThemeDialog) updateScrollOffset() {
	if d.selectedIndex < d.scrollOffset {
		d.scrollOffset = d.selectedIndex
	} else if d.selectedIndex >= d.scrollOffset+d.maxVisible {
		d.scrollOffset = d.selectedIndex - d.maxVisible + 1
	}
}

// Update handles messages for the theme dialog
func (d *ThemeDialog) Update(msg tea.Msg) (*ThemeDialog, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "up", "k":
			if d.selectedIndex > 0 {
				d.selectedIndex--
				d.updateScrollOffset()
				d.BaseDialog.Content = d.buildContent()
			}
			return d, nil
		case "down", "j":
			if d.selectedIndex < len(d.themes)-1 {
				d.selectedIndex++
				d.updateScrollOffset()
				d.BaseDialog.Content = d.buildContent()
			}
			return d, nil
		case "enter":
			// Apply theme immediately
			selectedTheme := d.themes[d.selectedIndex]
			styles.SetTheme(selectedTheme)
			d.SetVisible(false)
			return d, func() tea.Msg {
				return ThemeSelectedMsg{ThemeName: selectedTheme}
			}
		case "esc":
			d.SetVisible(false)
			return d, nil
		}
	}
	return d, nil
}

// Render renders the theme dialog
func (d *ThemeDialog) Render(termWidth, termHeight int) string {
	return d.BaseDialog.Render(termWidth, termHeight)
}
