package input

import (
	"os"
	"path/filepath"
	"strings"

	"github.com/charmbracelet/lipgloss"
	"github.com/williamcory/agent/tui/internal/styles"
)

// SuggestionType defines the type of suggestion
type SuggestionType int

const (
	SuggestionCommand SuggestionType = iota
	SuggestionFile
	SuggestionMention
)

// Suggestion represents an autocomplete suggestion
type Suggestion struct {
	Value       string
	Display     string
	Description string
	Type        SuggestionType
}

// AutocompleteModel handles autocomplete functionality
type AutocompleteModel struct {
	suggestions   []Suggestion
	selectedIndex int
	active        bool
	prefix        string // The text before the cursor that triggered autocomplete
	width         int
}

// NewAutocomplete creates a new autocomplete model
func NewAutocomplete() AutocompleteModel {
	return AutocompleteModel{
		suggestions:   []Suggestion{},
		selectedIndex: 0,
		active:        false,
	}
}

// predefinedCommands are slash commands available
var predefinedCommands = []Suggestion{
	{Value: "/help", Display: "/help", Description: "Show help information", Type: SuggestionCommand},
	{Value: "/model", Display: "/model", Description: "Switch AI model", Type: SuggestionCommand},
	{Value: "/agent", Display: "/agent", Description: "Switch agent", Type: SuggestionCommand},
	{Value: "/clear", Display: "/clear", Description: "Clear chat history", Type: SuggestionCommand},
	{Value: "/new", Display: "/new", Description: "Start new session", Type: SuggestionCommand},
	{Value: "/sessions", Display: "/sessions", Description: "List sessions", Type: SuggestionCommand},
	{Value: "/fork", Display: "/fork", Description: "Fork current session", Type: SuggestionCommand},
	{Value: "/revert", Display: "/revert", Description: "Revert changes", Type: SuggestionCommand},
	{Value: "/diff", Display: "/diff", Description: "Show file changes", Type: SuggestionCommand},
	{Value: "/theme", Display: "/theme", Description: "Change theme", Type: SuggestionCommand},
	{Value: "/settings", Display: "/settings", Description: "Open settings", Type: SuggestionCommand},
	{Value: "/status", Display: "/status", Description: "Show status", Type: SuggestionCommand},
}

// UpdateSuggestions updates suggestions based on input text
func (ac *AutocompleteModel) UpdateSuggestions(text string) {
	ac.suggestions = nil
	ac.selectedIndex = 0

	if text == "" {
		ac.active = false
		return
	}

	// Check for slash command
	if strings.HasPrefix(text, "/") {
		ac.prefix = text
		ac.updateCommandSuggestions(text)
		return
	}

	// Check for file path (starts with ./ or / or contains path separators)
	lastSpace := strings.LastIndex(text, " ")
	var lastWord string
	if lastSpace >= 0 {
		lastWord = text[lastSpace+1:]
	} else {
		lastWord = text
	}

	if strings.HasPrefix(lastWord, "./") || strings.HasPrefix(lastWord, "/") || strings.HasPrefix(lastWord, "~") {
		ac.prefix = lastWord
		ac.updateFileSuggestions(lastWord)
		return
	}

	// Check for @ mention
	if strings.HasPrefix(lastWord, "@") {
		ac.prefix = lastWord
		ac.updateMentionSuggestions(lastWord)
		return
	}

	ac.active = false
}

// updateCommandSuggestions updates command suggestions
func (ac *AutocompleteModel) updateCommandSuggestions(text string) {
	text = strings.ToLower(text)
	for _, cmd := range predefinedCommands {
		if strings.HasPrefix(strings.ToLower(cmd.Value), text) {
			ac.suggestions = append(ac.suggestions, cmd)
		}
	}
	ac.active = len(ac.suggestions) > 0
}

// updateFileSuggestions updates file path suggestions
func (ac *AutocompleteModel) updateFileSuggestions(path string) {
	// Expand ~ to home directory
	if strings.HasPrefix(path, "~") {
		home, err := os.UserHomeDir()
		if err == nil {
			path = strings.Replace(path, "~", home, 1)
		}
	}

	// Get directory and prefix
	dir := filepath.Dir(path)
	prefix := filepath.Base(path)
	if strings.HasSuffix(path, "/") {
		dir = path
		prefix = ""
	}

	// Read directory
	entries, err := os.ReadDir(dir)
	if err != nil {
		ac.active = false
		return
	}

	for _, entry := range entries {
		name := entry.Name()
		if strings.HasPrefix(strings.ToLower(name), strings.ToLower(prefix)) {
			fullPath := filepath.Join(dir, name)
			display := name
			if entry.IsDir() {
				display += "/"
			}

			ac.suggestions = append(ac.suggestions, Suggestion{
				Value:       fullPath,
				Display:     display,
				Description: "",
				Type:        SuggestionFile,
			})
		}
	}

	// Limit suggestions
	if len(ac.suggestions) > 10 {
		ac.suggestions = ac.suggestions[:10]
	}

	ac.active = len(ac.suggestions) > 0
}

// updateMentionSuggestions updates @ mention suggestions
func (ac *AutocompleteModel) updateMentionSuggestions(text string) {
	// Predefined mentions
	mentions := []Suggestion{
		{Value: "@file:", Display: "@file:", Description: "Reference a file", Type: SuggestionMention},
		{Value: "@url:", Display: "@url:", Description: "Reference a URL", Type: SuggestionMention},
		{Value: "@image:", Display: "@image:", Description: "Reference an image", Type: SuggestionMention},
		{Value: "@git:", Display: "@git:", Description: "Reference git info", Type: SuggestionMention},
	}

	text = strings.ToLower(text)
	for _, mention := range mentions {
		if strings.HasPrefix(strings.ToLower(mention.Value), text) {
			ac.suggestions = append(ac.suggestions, mention)
		}
	}

	ac.active = len(ac.suggestions) > 0
}

// SelectNext moves selection to next suggestion
func (ac *AutocompleteModel) SelectNext() {
	if len(ac.suggestions) > 0 {
		ac.selectedIndex = (ac.selectedIndex + 1) % len(ac.suggestions)
	}
}

// SelectPrev moves selection to previous suggestion
func (ac *AutocompleteModel) SelectPrev() {
	if len(ac.suggestions) > 0 {
		ac.selectedIndex--
		if ac.selectedIndex < 0 {
			ac.selectedIndex = len(ac.suggestions) - 1
		}
	}
}

// GetSelected returns the currently selected suggestion
func (ac *AutocompleteModel) GetSelected() *Suggestion {
	if ac.active && len(ac.suggestions) > 0 && ac.selectedIndex < len(ac.suggestions) {
		return &ac.suggestions[ac.selectedIndex]
	}
	return nil
}

// IsActive returns whether autocomplete is active
func (ac *AutocompleteModel) IsActive() bool {
	return ac.active && len(ac.suggestions) > 0
}

// Close closes the autocomplete
func (ac *AutocompleteModel) Close() {
	ac.active = false
	ac.suggestions = nil
	ac.selectedIndex = 0
}

// GetPrefix returns the prefix that triggered autocomplete
func (ac *AutocompleteModel) GetPrefix() string {
	return ac.prefix
}

// SetWidth sets the width for rendering
func (ac *AutocompleteModel) SetWidth(width int) {
	ac.width = width
}

// View renders the autocomplete dropdown
func (ac *AutocompleteModel) View() string {
	if !ac.active || len(ac.suggestions) == 0 {
		return ""
	}

	theme := styles.GetCurrentTheme()

	// Container style
	containerStyle := lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(theme.Border).
		Background(theme.CodeBackground).
		Padding(0, 1).
		Width(ac.width - 4)

	// Suggestion styles
	selectedStyle := lipgloss.NewStyle().
		Foreground(theme.TextPrimary).
		Background(theme.Primary).
		Bold(true).
		Width(ac.width - 8)

	normalStyle := lipgloss.NewStyle().
		Foreground(theme.TextSecondary).
		Width(ac.width - 8)

	descStyle := lipgloss.NewStyle().
		Foreground(theme.Muted).
		Italic(true)

	var lines []string

	for i, sug := range ac.suggestions {
		line := sug.Display
		if sug.Description != "" {
			line += " " + descStyle.Render(sug.Description)
		}

		if i == ac.selectedIndex {
			lines = append(lines, selectedStyle.Render(line))
		} else {
			lines = append(lines, normalStyle.Render(line))
		}
	}

	content := strings.Join(lines, "\n")
	return containerStyle.Render(content)
}
