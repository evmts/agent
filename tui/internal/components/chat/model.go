package chat

import (
	"strings"

	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/williamcory/agent/sdk/agent"
)

// Model represents the chat component
type Model struct {
	viewport        viewport.Model
	messages        []Message
	currentParts    map[string]agent.Part // Part ID -> Part (for updates)
	currentMessage  *agent.Message
	streamingPartID string
	width           int
	height          int
	ready           bool
}

// New creates a new chat model
func New(width, height int) Model {
	vp := viewport.New(width, height)
	vp.SetContent("")
	vp.YPosition = 0

	return Model{
		viewport:     vp,
		messages:     []Message{},
		currentParts: make(map[string]agent.Part),
		width:        width,
		height:       height,
		ready:        true,
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

// LoadMessages loads messages from API response
func (m *Model) LoadMessages(messages []agent.MessageWithParts) {
	m.messages = []Message{}
	m.currentParts = make(map[string]agent.Part)

	for _, msg := range messages {
		role := RoleUser
		if msg.Info.IsAssistant() {
			role = RoleAssistant
		}

		m.messages = append(m.messages, Message{
			Role:        role,
			Parts:       msg.Parts,
			IsStreaming: false,
			Info:        &msg.Info,
		})
	}

	m.updateContent()
}

// AddUserMessage adds a user message to the chat
func (m *Model) AddUserMessage(content string) {
	// Create a simple text part for user message
	part := agent.Part{
		Type: "text",
		Text: content,
	}

	m.messages = append(m.messages, Message{
		Role:        RoleUser,
		Parts:       []agent.Part{part},
		IsStreaming: false,
	})
	m.updateContent()
}

// StartAssistantMessage starts a new assistant message for streaming
func (m *Model) StartAssistantMessage() {
	m.currentParts = make(map[string]agent.Part)
	m.currentMessage = nil
	m.streamingPartID = ""

	m.messages = append(m.messages, Message{
		Role:        RoleAssistant,
		Parts:       []agent.Part{},
		IsStreaming: true,
	})
}

// HandleStreamEvent processes a streaming event from the SDK
func (m *Model) HandleStreamEvent(event *agent.StreamEvent) {
	if event == nil {
		return
	}

	switch event.Type {
	case "message.updated":
		if event.Message != nil {
			m.currentMessage = event.Message
			// Update the last message's info
			if len(m.messages) > 0 {
				m.messages[len(m.messages)-1].Info = event.Message
			}
		}

	case "part.updated":
		if event.Part != nil {
			m.currentParts[event.Part.ID] = *event.Part

			// Track streaming text part
			if event.Part.IsText() {
				m.streamingPartID = event.Part.ID
			}

			// Rebuild parts for the current message
			m.rebuildCurrentMessageParts()
		}
	}

	m.updateContent()
}

// rebuildCurrentMessageParts rebuilds the parts slice from the map
func (m *Model) rebuildCurrentMessageParts() {
	if len(m.messages) == 0 {
		return
	}

	// Convert map to slice, maintaining some order
	var parts []agent.Part
	for _, part := range m.currentParts {
		parts = append(parts, part)
	}

	m.messages[len(m.messages)-1].Parts = parts
}

// EndAssistantMessage marks the current assistant message as complete
func (m *Model) EndAssistantMessage() {
	if len(m.messages) > 0 {
		m.messages[len(m.messages)-1].IsStreaming = false
	}
	m.streamingPartID = ""
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

// updateContent rebuilds the viewport content from messages
func (m *Model) updateContent() {
	var content strings.Builder

	for i, msg := range m.messages {
		content.WriteString(msg.Render(m.width))
		if i < len(m.messages)-1 {
			content.WriteString("\n")
		}
	}

	m.viewport.SetContent(content.String())
	m.viewport.GotoBottom()
}

// Clear clears all messages
func (m *Model) Clear() {
	m.messages = []Message{}
	m.currentParts = make(map[string]agent.Part)
	m.currentMessage = nil
	m.streamingPartID = ""
	m.viewport.SetContent("")
}

// IsEmpty returns true if there are no messages
func (m Model) IsEmpty() bool {
	return len(m.messages) == 0
}

// GetCurrentTokens returns token info from the current message
func (m Model) GetCurrentTokens() *agent.TokenInfo {
	if m.currentMessage != nil && m.currentMessage.Tokens != nil {
		return m.currentMessage.Tokens
	}
	return nil
}

// GetCurrentCost returns cost from the current message
func (m Model) GetCurrentCost() float64 {
	if m.currentMessage != nil {
		return m.currentMessage.Cost
	}
	return 0
}
