package input

import (
	"strings"

	"github.com/charmbracelet/bubbles/textarea"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"tui/internal/styles"
)

// Model represents the input component
type Model struct {
	textarea     textarea.Model
	width        int
	height       int
	history      []string
	histIdx      int
	focused      bool
	autocomplete AutocompleteModel
}

// New creates a new input model
func New(width int) Model {
	ta := textarea.New()
	ta.Placeholder = "Type your message..."
	ta.Focus()
	ta.CharLimit = 4096
	ta.SetWidth(width - 4)
	ta.SetHeight(3)
	ta.ShowLineNumbers = false
	ta.KeyMap.InsertNewline.SetKeys("shift+enter")

	// Style the textarea
	theme := styles.GetCurrentTheme()
	ta.FocusedStyle.CursorLine = ta.FocusedStyle.CursorLine.Background(theme.CodeBackground)
	ta.FocusedStyle.Placeholder = ta.FocusedStyle.Placeholder.Foreground(theme.Muted)
	ta.BlurredStyle.Placeholder = ta.BlurredStyle.Placeholder.Foreground(theme.Muted)

	ac := NewAutocomplete()
	ac.SetWidth(width)

	return Model{
		textarea:     ta,
		width:        width,
		height:       5,
		history:      []string{},
		histIdx:      -1,
		focused:      true,
		autocomplete: ac,
	}
}

// Init initializes the input component
func (m Model) Init() tea.Cmd {
	return textarea.Blink
}

// Update handles messages for the input component
func (m Model) Update(msg tea.Msg) (Model, tea.Cmd) {
	var cmd tea.Cmd

	switch msg := msg.(type) {
	case tea.KeyMsg:
		// Handle autocomplete keys first if active
		if m.autocomplete.IsActive() {
			switch msg.String() {
			case "tab", "down":
				m.autocomplete.SelectNext()
				return m, nil
			case "shift+tab", "up":
				m.autocomplete.SelectPrev()
				return m, nil
			case "enter":
				// Accept suggestion
				if suggestion := m.autocomplete.GetSelected(); suggestion != nil {
					m.acceptSuggestion(suggestion)
				}
				m.autocomplete.Close()
				return m, nil
			case "esc":
				m.autocomplete.Close()
				return m, nil
			}
		}

		switch msg.String() {
		case "up":
			// Navigate history when at the start of input (if autocomplete not active)
			if !m.autocomplete.IsActive() && (m.textarea.Value() == "" || m.histIdx >= 0) {
				if m.histIdx < len(m.history)-1 {
					m.histIdx++
					m.textarea.SetValue(m.history[len(m.history)-1-m.histIdx])
					// Move cursor to end
					m.textarea.CursorEnd()
				}
				return m, nil
			}
		case "down":
			// Navigate history forward
			if !m.autocomplete.IsActive() && m.histIdx >= 0 {
				if m.histIdx > 0 {
					m.histIdx--
					m.textarea.SetValue(m.history[len(m.history)-1-m.histIdx])
					m.textarea.CursorEnd()
				} else {
					m.histIdx = -1
					m.textarea.SetValue("")
				}
				return m, nil
			}
		case "ctrl+u":
			// Clear line
			m.textarea.SetValue("")
			m.histIdx = -1
			m.autocomplete.Close()
			return m, nil
		case "tab":
			// Trigger autocomplete if not active
			if !m.autocomplete.IsActive() {
				m.autocomplete.UpdateSuggestions(m.textarea.Value())
			}
			return m, nil
		}
	}

	if m.focused {
		m.textarea, cmd = m.textarea.Update(msg)
		// Update autocomplete suggestions on text change
		m.autocomplete.UpdateSuggestions(m.textarea.Value())
	}
	return m, cmd
}

// acceptSuggestion accepts a suggestion and updates the input
func (m *Model) acceptSuggestion(sug *Suggestion) {
	currentText := m.textarea.Value()
	prefix := m.autocomplete.GetPrefix()

	// Find where to replace
	if prefix != "" && strings.Contains(currentText, prefix) {
		lastIndex := strings.LastIndex(currentText, prefix)
		if lastIndex >= 0 {
			newText := currentText[:lastIndex] + sug.Value
			m.textarea.SetValue(newText)
			m.textarea.CursorEnd()
		}
	} else {
		m.textarea.SetValue(sug.Value)
		m.textarea.CursorEnd()
	}
}

// View renders the input component - Claude Code style with simple > prompt
func (m Model) View() string {
	theme := styles.GetCurrentTheme()

	// Claude Code style: simple ">" prompt
	promptStyle := lipgloss.NewStyle().
		Foreground(theme.Muted).
		Bold(true)
	prompt := promptStyle.Render("> ")

	// Get textarea content
	textareaView := m.textarea.View()

	// Combine prompt with input
	inputView := lipgloss.JoinHorizontal(lipgloss.Top, prompt, textareaView)

	// Show autocomplete dropdown if active
	if m.autocomplete.IsActive() {
		acView := m.autocomplete.View()
		return lipgloss.JoinVertical(lipgloss.Left, acView, inputView)
	}

	return inputView
}

// Value returns the current input value
func (m Model) Value() string {
	return m.textarea.Value()
}

// Clear clears the input and saves to history
func (m *Model) Clear() {
	value := m.textarea.Value()
	if value != "" {
		m.history = append(m.history, value)
	}
	m.textarea.Reset()
	m.histIdx = -1
}

// SetWidth updates the input width
func (m *Model) SetWidth(width int) {
	m.width = width
	m.textarea.SetWidth(width - 6)
	m.autocomplete.SetWidth(width)
}

// Focus focuses the input
func (m *Model) Focus() tea.Cmd {
	m.focused = true
	return m.textarea.Focus()
}

// Blur unfocuses the input
func (m *Model) Blur() {
	m.focused = false
	m.textarea.Blur()
}

// IsFocused returns whether the input is focused
func (m Model) IsFocused() bool {
	return m.focused
}

// SetValue sets the input value
func (m *Model) SetValue(value string) {
	m.textarea.SetValue(value)
}
