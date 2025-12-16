package sidebar

import (
	"fmt"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/williamcory/agent/sdk/agent"
	"github.com/williamcory/agent/tui/internal/components/tabs"
	"github.com/williamcory/agent/tui/internal/git"
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
	TabGit      ActiveTab = "git"
)

// GitViewMode represents which git section is active
type GitViewMode int

const (
	GitViewStaged GitViewMode = iota
	GitViewUnstaged
	GitViewUntracked
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

	// CLAUDE.md context
	claudeMdContext ClaudeMdContext

	// Git status tracking
	gitStatus        *git.GitStatus
	selectedGitIndex int
	gitViewMode      GitViewMode
}

// New creates a new sidebar model
func New(width, height int) Model {
	// Create tabs for sidebar navigation
	sidebarTabs := tabs.New([]tabs.Tab{
		{ID: "sessions", Title: "Sessions", Icon: "📋"},
		{ID: "files", Title: "Files", Icon: "📁"},
		{ID: "git", Title: "Git", Icon: "🔀"},
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
	case ClaudeMdRefreshMsg:
		m.claudeMdContext = msg.Context
		return m, nil

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
			m.activeTab = TabGit
			m.tabs.SelectTab(2)
			return m, nil
		case "4":
			m.activeTab = TabContext
			m.tabs.SelectTab(3)
			return m, nil
		case "up", "k":
			if m.activeTab == TabSessions && m.selectedIndex > 0 {
				m.selectedIndex--
			}
			if m.activeTab == TabGit {
				m.navigateGitUp()
			}
		case "down", "j":
			if m.activeTab == TabSessions && m.selectedIndex < len(m.sessions)-1 {
				m.selectedIndex++
			}
			if m.activeTab == TabGit {
				m.navigateGitDown()
			}
		case "enter":
			// Return a message to switch sessions
			if m.activeTab == TabSessions && len(m.sessions) > 0 && m.selectedIndex < len(m.sessions) {
				return m, func() tea.Msg {
					return SessionSelectedMsg{Session: m.sessions[m.selectedIndex]}
				}
			}
			// Git tab: stage/unstage file
			if m.activeTab == TabGit {
				return m, m.handleGitEnter()
			}
		case "a":
			// Git tab: stage all
			if m.activeTab == TabGit {
				return m, m.handleGitStageAll()
			}
		case "d":
			// Git tab: view diff
			if m.activeTab == TabGit {
				return m, m.handleGitDiff()
			}
		case "r":
			// Git tab: refresh
			if m.activeTab == TabGit {
				return m, m.handleGitRefresh()
			}
		case "c":
			// Git tab: commit
			if m.activeTab == TabGit {
				return m, m.handleGitCommit()
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

	// Git tab badge - show count of changes
	if m.gitStatus != nil && m.gitStatus.IsRepo {
		totalChanges := len(m.gitStatus.Staged) + len(m.gitStatus.Unstaged) + len(m.gitStatus.Untracked)
		if totalChanges > 0 {
			m.tabs.UpdateBadge("git", fmt.Sprintf("%d", totalChanges))
		} else {
			m.tabs.UpdateBadge("git", "")
		}
	} else {
		m.tabs.UpdateBadge("git", "")
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

// LoadClaudeMd loads CLAUDE.md files from standard locations
func (m *Model) LoadClaudeMd() {
	m.claudeMdContext = LoadClaudeMdContext()
}

// GetClaudeMdContext returns the current CLAUDE.md context
func (m Model) GetClaudeMdContext() ClaudeMdContext {
	return m.claudeMdContext
}

// RefreshClaudeMd reloads CLAUDE.md files
func (m *Model) RefreshClaudeMd() tea.Cmd {
	return func() tea.Msg {
		return ClaudeMdRefreshMsg{
			Context: LoadClaudeMdContext(),
		}
	}
}

// ClaudeMdRefreshMsg is sent when CLAUDE.md is refreshed
type ClaudeMdRefreshMsg struct {
	Context ClaudeMdContext
}

// SetGitStatus updates the git status
func (m *Model) SetGitStatus(status *git.GitStatus) {
	m.gitStatus = status
	m.updateTabBadges()
}

// GetGitStatus returns the current git status
func (m Model) GetGitStatus() *git.GitStatus {
	return m.gitStatus
}

// navigateGitUp navigates up in the git file list
func (m *Model) navigateGitUp() {
	if m.gitStatus == nil {
		return
	}

	totalFiles := len(m.gitStatus.Staged) + len(m.gitStatus.Unstaged) + len(m.gitStatus.Untracked)
	if totalFiles == 0 {
		return
	}

	if m.selectedGitIndex > 0 {
		m.selectedGitIndex--
		m.updateGitViewMode()
	}
}

// navigateGitDown navigates down in the git file list
func (m *Model) navigateGitDown() {
	if m.gitStatus == nil {
		return
	}

	totalFiles := len(m.gitStatus.Staged) + len(m.gitStatus.Unstaged) + len(m.gitStatus.Untracked)
	if totalFiles == 0 {
		return
	}

	if m.selectedGitIndex < totalFiles-1 {
		m.selectedGitIndex++
		m.updateGitViewMode()
	}
}

// updateGitViewMode updates the git view mode based on selected index
func (m *Model) updateGitViewMode() {
	if m.gitStatus == nil {
		return
	}

	stagedCount := len(m.gitStatus.Staged)
	unstagedCount := len(m.gitStatus.Unstaged)

	if m.selectedGitIndex < stagedCount {
		m.gitViewMode = GitViewStaged
	} else if m.selectedGitIndex < stagedCount+unstagedCount {
		m.gitViewMode = GitViewUnstaged
	} else {
		m.gitViewMode = GitViewUntracked
	}
}

// handleGitEnter handles the enter key in git tab (stage/unstage)
func (m *Model) handleGitEnter() tea.Cmd {
	if m.gitStatus == nil {
		return nil
	}

	return func() tea.Msg {
		return GitStageToggleMsg{
			Index:    m.selectedGitIndex,
			ViewMode: m.gitViewMode,
		}
	}
}

// handleGitStageAll handles staging all files
func (m *Model) handleGitStageAll() tea.Cmd {
	return func() tea.Msg {
		return GitStageAllMsg{}
	}
}

// handleGitDiff handles viewing diff for selected file
func (m *Model) handleGitDiff() tea.Cmd {
	if m.gitStatus == nil {
		return nil
	}

	return func() tea.Msg {
		return GitDiffMsg{
			Index:    m.selectedGitIndex,
			ViewMode: m.gitViewMode,
		}
	}
}

// handleGitRefresh handles refreshing git status
func (m *Model) handleGitRefresh() tea.Cmd {
	return func() tea.Msg {
		return GitRefreshMsg{}
	}
}

// handleGitCommit handles creating a commit
func (m *Model) handleGitCommit() tea.Cmd {
	if m.gitStatus == nil || len(m.gitStatus.Staged) == 0 {
		return nil
	}

	return func() tea.Msg {
		return GitCommitMsg{}
	}
}

// Git-related messages

// GitStageToggleMsg is sent to stage/unstage a file
type GitStageToggleMsg struct {
	Index    int
	ViewMode GitViewMode
}

// GitStageAllMsg is sent to stage all files
type GitStageAllMsg struct{}

// GitDiffMsg is sent to view diff for a file
type GitDiffMsg struct {
	Index    int
	ViewMode GitViewMode
}

// GitRefreshMsg is sent to refresh git status
type GitRefreshMsg struct{}

// GitCommitMsg is sent to create a commit
type GitCommitMsg struct{}

// GitStatusUpdatedMsg is sent when git status is updated
type GitStatusUpdatedMsg struct {
	Status *git.GitStatus
}
