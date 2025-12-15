package input

import (
	"github.com/charmbracelet/bubbles/textarea"
	tea "github.com/charmbracelet/bubbletea"
	"tui/internal/styles"
)

// Model represents the input component
type Model struct {
	textarea textarea.Model
	width    int
	height   int
	history  []string
	histIdx  int
	focused  bool
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
	ta.FocusedStyle.CursorLine = ta.FocusedStyle.CursorLine.Background(styles.AssistantBg)
	ta.FocusedStyle.Placeholder = ta.FocusedStyle.Placeholder.Foreground(styles.Muted)
	ta.BlurredStyle.Placeholder = ta.BlurredStyle.Placeholder.Foreground(styles.Muted)

	return Model{
		textarea: ta,
		width:    width,
		height:   5,
		history:  []string{},
		histIdx:  -1,
		focused:  true,
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
		switch msg.String() {
		case "up":
			// Navigate history when at the start of input
			if m.textarea.Value() == "" || m.histIdx >= 0 {
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
			if m.histIdx >= 0 {
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
			return m, nil
		}
	}

	if m.focused {
		m.textarea, cmd = m.textarea.Update(msg)
	}
	return m, cmd
}

// View renders the input component
func (m Model) View() string {
	return styles.InputBorder.Width(m.width - 2).Render(m.textarea.View())
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
