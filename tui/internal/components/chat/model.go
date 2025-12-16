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
	showThinking    bool           // Whether to show thinking/reasoning content
	compactMode     bool           // Whether compact view mode is enabled
	compactExpanded bool           // Whether compact view is currently expanded
	compactCount    int            // Number of messages to show in compact mode (default 5)
	search          SearchState    // Search state
	codeBlocks      CodeBlockState // Code block navigation state
}

// New creates a new chat model
func New(width, height int) Model {
	vp := viewport.New(width, height)
	vp.SetContent("")
	vp.YPosition = 0

	// Initialize markdown renderer with current width
	// Ignore errors - if it fails, markdown will fall back to plain text
	_ = InitMarkdown(width)

	const DEFAULT_COMPACT_COUNT = 5

	return Model{
		viewport:        vp,
		messages:        []Message{},
		currentParts:    make(map[string]agent.Part),
		width:           width,
		height:          height,
		ready:           true,
		compactMode:     false,
		compactExpanded: false,
		compactCount:    DEFAULT_COMPACT_COUNT,
		search:          NewSearchState(),
		codeBlocks:      NewCodeBlockState(),
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

// ToggleCompact toggles compact view mode
func (m *Model) ToggleCompact() {
	m.compactMode = !m.compactMode
	if !m.compactMode {
		// Reset expansion state when disabling compact mode
		m.compactExpanded = false
	}
	m.updateContent()
}

// IsCompactMode returns whether compact view mode is enabled
func (m Model) IsCompactMode() bool {
	return m.compactMode
}

// ToggleCompactExpansion toggles the expanded state in compact mode
func (m *Model) ToggleCompactExpansion() {
	if m.compactMode {
		m.compactExpanded = !m.compactExpanded
		m.updateContent()
	}
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

// GetMessageCount returns the total number of messages
func (m Model) GetMessageCount() int {
	return len(m.messages)
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

// ActivateSearch activates search mode
func (m *Model) ActivateSearch() {
	m.search.ActivateSearch()
}

// DeactivateSearch deactivates search mode
func (m *Model) DeactivateSearch() {
	m.search.DeactivateSearch()
	m.updateContent()
}

// IsSearchActive returns true if search is active
func (m Model) IsSearchActive() bool {
	return m.search.Active
}

// UpdateSearchQuery updates the search query and performs search
func (m *Model) UpdateSearchQuery(query string) {
	m.search.SetQuery(query)
	m.search.PerformSearch(m.messages)
	m.scrollToCurrentMatch()
	m.updateContent()
}

// SearchNext moves to the next search match
func (m *Model) SearchNext() {
	m.search.NextMatch()
	m.scrollToCurrentMatch()
	m.updateContent()
}

// SearchPrev moves to the previous search match
func (m *Model) SearchPrev() {
	m.search.PrevMatch()
	m.scrollToCurrentMatch()
	m.updateContent()
}

// GetSearchQuery returns the current search query
func (m Model) GetSearchQuery() string {
	return m.search.Query
}

// GetSearchMatchCount returns the number of matches and current index
func (m Model) GetSearchMatchCount() (int, int) {
	return len(m.search.Matches), m.search.CurrentIndex
}

// scrollToCurrentMatch scrolls to the current match if available
func (m *Model) scrollToCurrentMatch() {
	matchIdx := m.search.GetMatchMessageIndex()
	if matchIdx >= 0 && matchIdx < len(m.messages) {
		// For now, scroll to bottom to show the match
		// In a more sophisticated implementation, we would calculate
		// the exact line position of the match
		m.viewport.GotoBottom()
	}
}

// GetSearchState returns the current search state
func (m Model) GetSearchState() SearchState {
	return m.search
}

// GetCurrentTool returns the currently executing or most recent tool part
func (m Model) GetCurrentTool() *agent.Part {
	if len(m.messages) == 0 {
		return nil
	}

	// Check the last message for tool parts
	lastMsg := m.messages[len(m.messages)-1]
	if lastMsg.Role != RoleAssistant {
		return nil
	}

	// Find the most recent tool part that's running or the last tool part
	var lastTool *agent.Part
	for i := range lastMsg.Parts {
		part := &lastMsg.Parts[i]
		if part.IsTool() {
			lastTool = part
			// If it's currently running, return immediately
			if part.State != nil && (part.State.Status == "running" || part.State.Status == "pending") {
				return part
			}
		}
	}

	return lastTool
}

// IsThinking returns true if the current message is in thinking mode
func (m Model) IsThinking() bool {
	if len(m.messages) == 0 {
		return false
	}

	lastMsg := m.messages[len(m.messages)-1]
	if lastMsg.Role != RoleAssistant {
		return false
	}

	// Check if there's a reasoning part
	for _, part := range lastMsg.Parts {
		if part.IsReasoning() {
			return true
		}
	}

	return false
}

// GetPartialThinking returns the partial thinking/reasoning text
func (m Model) GetPartialThinking() string {
	if len(m.messages) == 0 {
		return ""
	}

	lastMsg := m.messages[len(m.messages)-1]
	if lastMsg.Role != RoleAssistant {
		return ""
	}

	// Find the reasoning part
	for _, part := range lastMsg.Parts {
		if part.IsReasoning() {
			return part.Text
		}
	}

	return ""
}

// GetPartialText returns the partial text content being generated
func (m Model) GetPartialText() string {
	if len(m.messages) == 0 {
		return ""
	}

	lastMsg := m.messages[len(m.messages)-1]
	if lastMsg.Role != RoleAssistant {
		return ""
	}

	// Get the streaming text part if available
	if m.streamingPartID != "" {
		if part, ok := m.currentParts[m.streamingPartID]; ok {
			return part.Text
		}
	}

	// Otherwise get all text parts
	var text strings.Builder
	for _, part := range lastMsg.Parts {
		if part.IsText() {
			text.WriteString(part.Text)
		}
	}

	return text.String()
}

// NextCodeBlock navigates to the next code block
func (m *Model) NextCodeBlock() bool {
	if m.codeBlocks.NextBlock() {
		m.updateContent()
		return true
	}
	return false
}

// PrevCodeBlock navigates to the previous code block
func (m *Model) PrevCodeBlock() bool {
	if m.codeBlocks.PrevBlock() {
		m.updateContent()
		return true
	}
	return false
}

// HasCodeBlocks returns true if there are any code blocks
func (m Model) HasCodeBlocks() bool {
	return m.codeBlocks.HasBlocks()
}

// GetCurrentCodeBlock returns the currently selected code block
func (m Model) GetCurrentCodeBlock() *CodeBlock {
	return m.codeBlocks.GetCurrentBlock()
}

// GetCodeBlockInfo returns a formatted string with block count and current index
func (m Model) GetCodeBlockInfo() string {
	return m.codeBlocks.GetCodeBlockInfo()
}

// GetCodeBlockState returns the current code block state
func (m Model) GetCodeBlockState() CodeBlockState {
	return m.codeBlocks
}
