package sidebar

import (
	tea "github.com/charmbracelet/bubbletea"
	"github.com/williamcory/agent/sdk/agent"
)

// SectionState tracks which sections are expanded
type SectionState struct {
	Sessions bool
	Context  bool
	Files    bool
	Todos    bool
}

// ContextInfo tracks token and cost information
type ContextInfo struct {
	InputTokens   int
	OutputTokens  int
	TotalCost     float64
	ContextUsed   int // percentage 0-100
	ModelName     string
	AgentName     string
}

// Model represents the sidebar component
type Model struct {
	sessions      []agent.Session
	selectedIndex int
	width         int
	height        int
	visible       bool

	// New fields for enhanced sidebar
	sections      SectionState
	contextInfo   ContextInfo
	diffs         []agent.FileDiff
	currentSession *agent.Session
}

// New creates a new sidebar model
func New(width, height int) Model {
	return Model{
		sessions:      []agent.Session{},
		selectedIndex: 0,
		width:         width,
		height:        height,
		visible:       false,
		sections: SectionState{
			Sessions: true,
			Context:  true,
			Files:    true,
			Todos:    true,
		},
	}
}

// Init initializes the sidebar
func (m Model) Init() tea.Cmd {
	return nil
}

// Update handles sidebar messages
func (m Model) Update(msg tea.Msg) (Model, tea.Cmd) {
	if !m.visible {
		return m, nil
	}

	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "up", "k":
			if m.selectedIndex > 0 {
				m.selectedIndex--
			}
		case "down", "j":
			if m.selectedIndex < len(m.sessions)-1 {
				m.selectedIndex++
			}
		case "enter":
			// Return a message to switch sessions
			if len(m.sessions) > 0 && m.selectedIndex < len(m.sessions) {
				return m, func() tea.Msg {
					return SessionSelectedMsg{Session: m.sessions[m.selectedIndex]}
				}
			}
		}
	}

	return m, nil
}

// View renders the sidebar
func (m Model) View() string {
	if !m.visible {
		return ""
	}

	return renderSidebar(m)
}

// SetSessions updates the session list
func (m *Model) SetSessions(sessions []agent.Session) {
	m.sessions = sessions
	// Ensure selected index is still valid
	if m.selectedIndex >= len(m.sessions) && len(m.sessions) > 0 {
		m.selectedIndex = len(m.sessions) - 1
	}
	if len(m.sessions) == 0 {
		m.selectedIndex = 0
	}
}

// GetSelected returns the currently selected session
func (m Model) GetSelected() *agent.Session {
	if len(m.sessions) == 0 || m.selectedIndex >= len(m.sessions) {
		return nil
	}
	return &m.sessions[m.selectedIndex]
}

// Toggle toggles the sidebar visibility
func (m *Model) Toggle() {
	m.visible = !m.visible
}

// SetVisible sets the sidebar visibility
func (m *Model) SetVisible(visible bool) {
	m.visible = visible
}

// IsVisible returns whether the sidebar is visible
func (m Model) IsVisible() bool {
	return m.visible
}

// SetSize updates the sidebar dimensions
func (m *Model) SetSize(width, height int) {
	m.width = width
	m.height = height
}

// GetWidth returns the sidebar width
func (m Model) GetWidth() int {
	return m.width
}

// SessionSelectedMsg is sent when a session is selected from the sidebar
type SessionSelectedMsg struct {
	Session agent.Session
}

// GetSessions returns all sessions
func (m Model) GetSessions() []agent.Session {
	return m.sessions
}

// SetContextInfo updates the context tracking information
func (m *Model) SetContextInfo(info ContextInfo) {
	m.contextInfo = info
}

// SetDiffs updates the file diffs
func (m *Model) SetDiffs(diffs []agent.FileDiff) {
	m.diffs = diffs
}

// SetCurrentSession sets the current session being viewed
func (m *Model) SetCurrentSession(session *agent.Session) {
	m.currentSession = session
}

// ToggleSection toggles a section's expanded/collapsed state
func (m *Model) ToggleSection(section string) {
	switch section {
	case "sessions":
		m.sections.Sessions = !m.sections.Sessions
	case "context":
		m.sections.Context = !m.sections.Context
	case "files":
		m.sections.Files = !m.sections.Files
	case "todos":
		m.sections.Todos = !m.sections.Todos
	}
}
