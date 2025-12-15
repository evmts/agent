package sidebar

import (
	"fmt"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/williamcory/agent/sdk/agent"
	"tui/internal/components/tabs"
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

// ActiveTab represents the current active tab in the sidebar
type ActiveTab string

const (
	TabSessions ActiveTab = "sessions"
	TabFiles    ActiveTab = "files"
	TabContext  ActiveTab = "context"
)

// Model represents the sidebar component
type Model struct {
	sessions      []agent.Session
	selectedIndex int
	width         int
	height        int
	visible       bool

	// Tab navigation
	tabs      tabs.Model
	activeTab ActiveTab

	// New fields for enhanced sidebar
	sections       SectionState
	contextInfo    ContextInfo
	diffs          []agent.FileDiff
	currentSession *agent.Session
}

// New creates a new sidebar model
func New(width, height int) Model {
	// Create tabs for sidebar navigation
	sidebarTabs := tabs.New([]tabs.Tab{
		{ID: "sessions", Title: "Sessions", Icon: "📋"},
		{ID: "files", Title: "Files", Icon: "📁"},
		{ID: "context", Title: "Context", Icon: "📊"},
	})
	sidebarTabs.SetVariant(tabs.VariantPills)

	return Model{
		sessions:      []agent.Session{},
		selectedIndex: 0,
		width:         width,
		height:        height,
		visible:       false,
		tabs:          sidebarTabs,
		activeTab:     TabSessions,
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

	var cmds []tea.Cmd

	switch msg := msg.(type) {
	case tabs.TabSelectedMsg:
		// Handle tab selection
		m.activeTab = ActiveTab(msg.Tab.ID)
		// Update tab badges
		m.updateTabBadges()
		return m, nil

	case tea.KeyMsg:
		switch msg.String() {
		case "tab":
			// Cycle through tabs
			var cmd tea.Cmd
			m.tabs, cmd = m.tabs.NextTab()
			if tab := m.tabs.GetActiveTab(); tab != nil {
				m.activeTab = ActiveTab(tab.ID)
			}
			cmds = append(cmds, cmd)
			return m, tea.Batch(cmds...)
		case "shift+tab":
			// Cycle backwards through tabs
			var cmd tea.Cmd
			m.tabs, cmd = m.tabs.PrevTab()
			if tab := m.tabs.GetActiveTab(); tab != nil {
				m.activeTab = ActiveTab(tab.ID)
			}
			cmds = append(cmds, cmd)
			return m, tea.Batch(cmds...)
		case "1":
			m.activeTab = TabSessions
			m.tabs.SelectTab(0)
			return m, nil
		case "2":
			m.activeTab = TabFiles
			m.tabs.SelectTab(1)
			return m, nil
		case "3":
			m.activeTab = TabContext
			m.tabs.SelectTab(2)
			return m, nil
		case "up", "k":
			if m.activeTab == TabSessions && m.selectedIndex > 0 {
				m.selectedIndex--
			}
		case "down", "j":
			if m.activeTab == TabSessions && m.selectedIndex < len(m.sessions)-1 {
				m.selectedIndex++
			}
		case "enter":
			// Return a message to switch sessions
			if m.activeTab == TabSessions && len(m.sessions) > 0 && m.selectedIndex < len(m.sessions) {
				return m, func() tea.Msg {
					return SessionSelectedMsg{Session: m.sessions[m.selectedIndex]}
				}
			}
		}
	}

	return m, nil
}

// updateTabBadges updates the badge text on each tab
func (m *Model) updateTabBadges() {
	// Sessions tab badge - show count
	if len(m.sessions) > 0 {
		m.tabs.UpdateBadge("sessions", fmt.Sprintf("%d", len(m.sessions)))
	} else {
		m.tabs.UpdateBadge("sessions", "")
	}

	// Files tab badge - show count of modified files
	if len(m.diffs) > 0 {
		m.tabs.UpdateBadge("files", fmt.Sprintf("%d", len(m.diffs)))
	} else {
		m.tabs.UpdateBadge("files", "")
	}

	// Context tab - show token count
	totalTokens := m.contextInfo.InputTokens + m.contextInfo.OutputTokens
	if totalTokens > 0 {
		m.tabs.UpdateBadge("context", formatNumber(totalTokens))
	} else {
		m.tabs.UpdateBadge("context", "")
	}
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
