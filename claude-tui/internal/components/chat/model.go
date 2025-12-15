package chat

import (
	"strings"

	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
)

// Model represents the chat component
type Model struct {
	viewport      viewport.Model
	items         []ChatItem // Messages and tool events
	currentStream strings.Builder
	width         int
	height        int
	ready         bool
}

// New creates a new chat model
func New(width, height int) Model {
	vp := viewport.New(width, height)
	vp.SetContent("")
	vp.YPosition = 0

	return Model{
		viewport: vp,
		items:    []ChatItem{},
		width:    width,
		height:   height,
		ready:    true,
	}
}

// Init initializes the chat component
func (m Model) Init() tea.Cmd {
	return nil
}

// Update handles messages for the chat component
func (m Model) Update(msg tea.Msg) (Model, tea.Cmd) {
	var cmd tea.Cmd

	switch msg := msg.(type) {
	case tea.KeyMsg:
		// Handle scrolling
		switch msg.String() {
		case "pgup":
			m.viewport.ViewUp()
		case "pgdown":
			m.viewport.ViewDown()
		}
	}

	m.viewport, cmd = m.viewport.Update(msg)
	return m, cmd
}

// View renders the chat component
func (m Model) View() string {
	if !m.ready {
		return "Initializing..."
	}
	return m.viewport.View()
}

// AddUserMessage adds a user message to the chat
func (m *Model) AddUserMessage(content string) {
	m.items = append(m.items, Message{
		Role:    RoleUser,
		Content: content,
	})
	m.updateContent()
}

// StartAssistantMessage starts a new assistant message for streaming
func (m *Model) StartAssistantMessage() {
	m.currentStream.Reset()
	m.items = append(m.items, Message{
		Role:        RoleAssistant,
		Content:     "",
		IsStreaming: true,
	})
}

// AppendToken appends a token to the current streaming message
func (m *Model) AppendToken(token string) {
	m.currentStream.WriteString(token)
	// Update the last message with the accumulated content
	if len(m.items) > 0 {
		if msg, ok := m.items[len(m.items)-1].(Message); ok && msg.IsStreaming {
			m.items[len(m.items)-1] = Message{
				Role:        RoleAssistant,
				Content:     m.currentStream.String(),
				IsStreaming: true,
			}
		}
	}
	m.updateContent()
}

// EndAssistantMessage marks the current assistant message as complete
func (m *Model) EndAssistantMessage() {
	if len(m.items) > 0 {
		if msg, ok := m.items[len(m.items)-1].(Message); ok && msg.IsStreaming {
			m.items[len(m.items)-1] = Message{
				Role:        RoleAssistant,
				Content:     m.currentStream.String(),
				IsStreaming: false,
			}
		}
	}
	m.updateContent()
}

// AddToolEvent adds a tool event to the chat
func (m *Model) AddToolEvent(tool string, input map[string]any) {
	// Insert before the last message if it's streaming
	insertIdx := len(m.items)
	if insertIdx > 0 {
		if msg, ok := m.items[insertIdx-1].(Message); ok && msg.IsStreaming {
			// Insert before the streaming message
			insertIdx = insertIdx - 1
		}
	}

	event := ToolEvent{
		Tool:      tool,
		Input:     input,
		Completed: false,
	}

	if insertIdx == len(m.items) {
		m.items = append(m.items, event)
	} else {
		// Insert at position
		m.items = append(m.items[:insertIdx], append([]ChatItem{event}, m.items[insertIdx:]...)...)
	}
	m.updateContent()
}

// CompleteToolEvent marks a tool event as completed
func (m *Model) CompleteToolEvent(tool string, output string) {
	// Find the most recent uncompleted tool event with this name
	for i := len(m.items) - 1; i >= 0; i-- {
		if event, ok := m.items[i].(ToolEvent); ok && event.Tool == tool && !event.Completed {
			m.items[i] = ToolEvent{
				Tool:      tool,
				Input:     event.Input,
				Output:    output,
				Completed: true,
			}
			break
		}
	}
	m.updateContent()
}

// SetSize updates the chat dimensions
func (m *Model) SetSize(width, height int) {
	m.width = width
	m.height = height
	m.viewport.Width = width
	m.viewport.Height = height
	m.updateContent()
}

// updateContent rebuilds the viewport content from items
func (m *Model) updateContent() {
	var content strings.Builder

	for i, item := range m.items {
		content.WriteString(item.Render(m.width))
		if i < len(m.items)-1 {
			content.WriteString("\n\n")
		}
	}

	m.viewport.SetContent(content.String())
	m.viewport.GotoBottom()
}

// Clear clears all messages
func (m *Model) Clear() {
	m.items = []ChatItem{}
	m.currentStream.Reset()
	m.viewport.SetContent("")
}

// IsEmpty returns true if there are no messages
func (m Model) IsEmpty() bool {
	return len(m.items) == 0
}
