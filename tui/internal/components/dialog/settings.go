package dialog

import (
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/williamcory/agent/tui/internal/styles"
)

// SettingChangedMsg is sent when a setting is toggled
type SettingChangedMsg struct {
	Key   string
	Value bool
}

// Setting represents a toggleable setting
type Setting struct {
	Key         string
	Label       string
	Description string
	Enabled     bool
}

// SettingsDialog displays and allows toggling of settings
type SettingsDialog struct {
	BaseDialog
	settings      []Setting
	selectedIndex int
}

// NewSettingsDialog creates a new settings dialog
func NewSettingsDialog(settings []Setting) *SettingsDialog {
	d := &SettingsDialog{
		BaseDialog:    NewBaseDialog("Settings", "", 60, 22),
		settings:      settings,
		selectedIndex: 0,
	}
	d.BaseDialog.Content = d.buildContent()
	return d
}

// NewDefaultSettingsDialog creates a settings dialog with default settings
func NewDefaultSettingsDialog(showThinking, showMarkdown, mouseEnabled bool) *SettingsDialog {
	settings := []Setting{
		{
			Key:         "show_thinking",
			Label:       "Show Thinking",
			Description: "Display AI reasoning/thinking content",
			Enabled:     showThinking,
		},
		{
			Key:         "render_markdown",
			Label:       "Render Markdown",
			Description: "Render markdown formatting in messages",
			Enabled:     showMarkdown,
		},
		{
			Key:         "mouse_mode",
			Label:       "Mouse Mode",
			Description: "Enable mouse for scrolling (disable for text selection)",
			Enabled:     mouseEnabled,
		},
	}
	return NewSettingsDialog(settings)
}

// buildContent builds the settings content
func (d *SettingsDialog) buildContent() string {
	var lines []string
	theme := styles.GetCurrentTheme()

	// Header
	headerStyle := lipgloss.NewStyle().
		Foreground(theme.Muted).
		Bold(true)

	lines = append(lines, "")
	lines = append(lines, headerStyle.Render("  Use ↑/↓ to navigate, Space/Enter to toggle, Esc to close"))
	lines = append(lines, "")

	// Setting styles
	selectedStyle := lipgloss.NewStyle().
		Foreground(theme.TextPrimary).
		Background(theme.Primary).
		Bold(true).
		Padding(0, 1).
		Width(54)

	normalStyle := lipgloss.NewStyle().
		Foreground(theme.TextPrimary).
		Padding(0, 1).
		Width(54)

	descStyle := lipgloss.NewStyle().
		Foreground(theme.Muted).
		Italic(true)

	enabledStyle := lipgloss.NewStyle().
		Foreground(theme.Success).
		Bold(true)

	disabledStyle := lipgloss.NewStyle().
		Foreground(theme.Muted)

	// Render each setting
	for i, setting := range d.settings {
		cursor := "  "
		if i == d.selectedIndex {
			cursor = "▶ "
		}

		// Toggle indicator
		var toggle string
		if setting.Enabled {
			toggle = enabledStyle.Render("[✓]")
		} else {
			toggle = disabledStyle.Render("[ ]")
		}

		settingLine := cursor + toggle + " " + setting.Label

		if i == d.selectedIndex {
			lines = append(lines, selectedStyle.Render(settingLine))
		} else {
			lines = append(lines, normalStyle.Render(settingLine))
		}

		// Description
		lines = append(lines, "       "+descStyle.Render(setting.Description))
		lines = append(lines, "")
	}

	return strings.Join(lines, "\n")
}

// Update handles messages for the settings dialog
func (d *SettingsDialog) Update(msg tea.Msg) (*SettingsDialog, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "up", "k":
			if d.selectedIndex > 0 {
				d.selectedIndex--
				d.BaseDialog.Content = d.buildContent()
			}
			return d, nil
		case "down", "j":
			if d.selectedIndex < len(d.settings)-1 {
				d.selectedIndex++
				d.BaseDialog.Content = d.buildContent()
			}
			return d, nil
		case "enter", " ":
			// Toggle the setting
			if d.selectedIndex >= 0 && d.selectedIndex < len(d.settings) {
				d.settings[d.selectedIndex].Enabled = !d.settings[d.selectedIndex].Enabled
				d.BaseDialog.Content = d.buildContent()
				setting := d.settings[d.selectedIndex]
				return d, func() tea.Msg {
					return SettingChangedMsg{Key: setting.Key, Value: setting.Enabled}
				}
			}
			return d, nil
		case "esc":
			d.SetVisible(false)
			return d, nil
		}
	}
	return d, nil
}

// Render renders the settings dialog
func (d *SettingsDialog) Render(termWidth, termHeight int) string {
	return d.BaseDialog.Render(termWidth, termHeight)
}

// GetSetting returns the value of a setting by key
func (d *SettingsDialog) GetSetting(key string) bool {
	for _, setting := range d.settings {
		if setting.Key == key {
			return setting.Enabled
		}
	}
	return false
}

// SetSetting sets the value of a setting by key
func (d *SettingsDialog) SetSetting(key string, value bool) {
	for i := range d.settings {
		if d.settings[i].Key == key {
			d.settings[i].Enabled = value
			d.BaseDialog.Content = d.buildContent()
			break
		}
	}
}
