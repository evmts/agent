package dialog

import (
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"tui/internal/styles"
)

// ModelInfo represents information about an AI model
type ModelInfo struct {
	ID          string
	Name        string
	Provider    string
	Description string
}

// ModelSelectedMsg is sent when a model is selected
type ModelSelectedMsg struct {
	Model ModelInfo
}

// ModelDialog displays a list of available AI models for selection
type ModelDialog struct {
	BaseDialog
	models        []ModelInfo
	selectedIndex int
}

// NewModelDialog creates a new model selection dialog
func NewModelDialog() *ModelDialog {
	models := getDefaultModels()
	content := buildModelContent(models, 0)
	return &ModelDialog{
		BaseDialog:    NewBaseDialog("Select AI Model", content, 70, 18),
		models:        models,
		selectedIndex: 0,
	}
}

// getDefaultModels returns the list of predefined models
func getDefaultModels() []ModelInfo {
	return []ModelInfo{
		{
			ID:          "claude-sonnet-4-20250514",
			Name:        "Claude Sonnet 4",
			Provider:    "Anthropic",
			Description: "Default, balanced performance",
		},
		{
			ID:          "claude-opus-4-20250514",
			Name:        "Claude Opus 4",
			Provider:    "Anthropic",
			Description: "Most capable, highest quality",
		},
		{
			ID:          "claude-haiku-3-20240307",
			Name:        "Claude Haiku 3",
			Provider:    "Anthropic",
			Description: "Fast and efficient",
		},
		{
			ID:          "gpt-4o",
			Name:        "GPT-4 Omni",
			Provider:    "OpenAI",
			Description: "GPT-4 Omni model",
		},
		{
			ID:          "gpt-4o-mini",
			Name:        "GPT-4 Omni Mini",
			Provider:    "OpenAI",
			Description: "Fast GPT-4 variant",
		},
	}
}

// buildModelContent builds the model selection content
func buildModelContent(models []ModelInfo, selectedIndex int) string {
	var lines []string
	lines = append(lines, "")

	theme := styles.GetCurrentTheme()

	// Header style
	headerStyle := lipgloss.NewStyle().
		Foreground(theme.Muted).
		Bold(true)

	lines = append(lines, "  "+headerStyle.Render("Use ↑/↓ to navigate, Enter to select, Esc to cancel"))
	lines = append(lines, "")

	// Model list styles
	selectedStyle := lipgloss.NewStyle().
		Foreground(theme.TextPrimary).
		Background(theme.Primary).
		Bold(true).
		Padding(0, 1)

	normalStyle := lipgloss.NewStyle().
		Foreground(theme.TextPrimary).
		Padding(0, 1)

	nameStyle := lipgloss.NewStyle().
		Foreground(theme.Primary).
		Bold(true)

	providerStyle := lipgloss.NewStyle().
		Foreground(theme.Secondary)

	descStyle := lipgloss.NewStyle().
		Foreground(theme.Muted)

	// Render each model
	for i, model := range models {
		cursor := "  "
		if i == selectedIndex {
			cursor = "> "
		}

		// Format model display
		name := nameStyle.Render(model.Name)
		provider := providerStyle.Render("[" + model.Provider + "]")
		desc := descStyle.Render(model.Description)

		modelLine := lipgloss.JoinHorizontal(lipgloss.Top,
			name,
			" ",
			provider,
		)

		// Apply selection style if selected
		if i == selectedIndex {
			modelLine = selectedStyle.Render(cursor + modelLine)
			lines = append(lines, modelLine)
			lines = append(lines, "    "+desc)
		} else {
			modelLine = normalStyle.Render(cursor + modelLine)
			lines = append(lines, modelLine)
			lines = append(lines, "    "+desc)
		}
		lines = append(lines, "")
	}

	return strings.Join(lines, "\n")
}

// Update handles messages for the model dialog
func (d *ModelDialog) Update(msg tea.Msg) (*ModelDialog, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "up", "k":
			if d.selectedIndex > 0 {
				d.selectedIndex--
				d.BaseDialog.Content = buildModelContent(d.models, d.selectedIndex)
			}
			return d, nil
		case "down", "j":
			if d.selectedIndex < len(d.models)-1 {
				d.selectedIndex++
				d.BaseDialog.Content = buildModelContent(d.models, d.selectedIndex)
			}
			return d, nil
		case "enter":
			d.SetVisible(false)
			selectedModel := d.models[d.selectedIndex]
			return d, func() tea.Msg {
				return ModelSelectedMsg{Model: selectedModel}
			}
		case "esc":
			d.SetVisible(false)
			return d, nil
		}
	}
	return d, nil
}

// GetSelected returns the currently selected model
func (d *ModelDialog) GetSelected() ModelInfo {
	if d.selectedIndex >= 0 && d.selectedIndex < len(d.models) {
		return d.models[d.selectedIndex]
	}
	return d.models[0]
}

// Render renders the model dialog
func (d *ModelDialog) Render(termWidth, termHeight int) string {
	return d.BaseDialog.Render(termWidth, termHeight)
}
