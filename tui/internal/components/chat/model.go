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
	showThinking    bool // Whether to show thinking/reasoning content
}

// New creates a new chat model
func New(width, height int) Model {
	vp := viewport.New(width, height)
	vp.SetContent("")
	vp.YPosition = 0

	// Initialize markdown renderer with current width
	// Ignore errors - if it fails, markdown will fall back to plain text
	_ = InitMarkdown(width)

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
	// Let viewport handle mouse events, but key events are handled by app
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

// SetSize updates the chat dimensions
func (m *Model) SetSize(width, height int) {
	m.width = width
	m.height = height
	m.viewport.Width = width
	m.viewport.Height = height

	// Reinitialize markdown renderer with new width
	// Ignore errors - if it fails, markdown will fall back to plain text
	_ = InitMarkdown(width)

	m.updateContent()
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

// ScrollUp scrolls up by one line
func (m *Model) ScrollUp() {
	m.viewport.LineUp(1)
}

// ScrollDown scrolls down by one line
func (m *Model) ScrollDown() {
	m.viewport.LineDown(1)
}

// PageUp scrolls up by one page
func (m *Model) PageUp() {
	m.viewport.ViewUp()
}

// PageDown scrolls down by one page
func (m *Model) PageDown() {
	m.viewport.ViewDown()
}

// ScrollToTop scrolls to the top of the chat
func (m *Model) ScrollToTop() {
	m.viewport.GotoTop()
}

// ScrollToBottom scrolls to the bottom of the chat
func (m *Model) ScrollToBottom() {
	m.viewport.GotoBottom()
}

// ToggleThinking toggles the display of thinking/reasoning content
func (m *Model) ToggleThinking() {
	m.showThinking = !m.showThinking
	m.updateContent()
}

// IsShowingThinking returns true if thinking content is being displayed
func (m Model) IsShowingThinking() bool {
	return m.showThinking
}

// ToggleMarkdown toggles markdown rendering on/off
func (m *Model) ToggleMarkdown() bool {
	enabled := ToggleMarkdown()
	m.updateContent()
	return enabled
}

// IsMarkdownEnabled returns whether markdown rendering is enabled
func (m Model) IsMarkdownEnabled() bool {
	return IsMarkdownEnabled()
}

// GetLastMessageInfo returns the ID and whether it's a user message for the last message
// Returns empty string and false if no messages exist
func (m Model) GetLastMessageInfo() (string, bool) {
	if len(m.messages) == 0 {
		return "", false
	}
	lastMsg := m.messages[len(m.messages)-1]
	msgID := ""
	if lastMsg.Info != nil {
		msgID = lastMsg.Info.ID
	}
	return msgID, lastMsg.Role == RoleUser
}

// GetLastMessageText returns the text content of the last message
func (m Model) GetLastMessageText() string {
	if len(m.messages) == 0 {
		return ""
	}
	lastMsg := m.messages[len(m.messages)-1]
	var text strings.Builder
	for _, part := range lastMsg.Parts {
		if part.IsText() {
			text.WriteString(part.Text)
		}
	}
	return text.String()
}
