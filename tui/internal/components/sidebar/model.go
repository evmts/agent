package sidebar

import (
	tea "github.com/charmbracelet/bubbletea"
	"github.com/williamcory/agent/sdk/agent"
)

// Model represents the sidebar component
type Model struct {
	sessions      []agent.Session
	selectedIndex int
	width         int
	height        int
	visible       bool
}

// New creates a new sidebar model
func New(width, height int) Model {
	return Model{
		sessions:      []agent.Session{},
		selectedIndex: 0,
		width:         width,
		height:        height,
		visible:       false,
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
