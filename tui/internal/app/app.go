package app

import (
	"context"
	"sync"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/williamcory/agent/sdk/agent"
	"tui/internal/components/chat"
	"tui/internal/components/dialog"
	"tui/internal/components/input"
	"tui/internal/components/sidebar"
	"tui/internal/components/spinner"
	"tui/internal/components/toast"
	"tui/internal/config"
	"tui/internal/keybind"
	"tui/internal/notification"
)

// State represents the application state
type State int

const (
	StateIdle State = iota
	StateStreaming
	StateError
	StateLoading
)

// OperationType represents the type of operation that can be interrupted
type OperationType int

const (
	OpThinking OperationType = iota
	OpGenerating
	OpToolExecution
	OpToolWaiting
)

// String returns the string representation of the operation type
func (op OperationType) String() string {
	switch op {
	case OpThinking:
		return "Thinking"
	case OpGenerating:
		return "Generating response"
	case OpToolExecution:
		return "Executing tool"
	case OpToolWaiting:
		return "Waiting for tool"
	default:
		return "Unknown"
	}
}

// InterruptContext captures the state when an operation is interrupted
type InterruptContext struct {
	Timestamp   time.Time
	Operation   OperationType
	Description string
	ToolName    string
	ToolInput   map[string]interface{}
	PartialText string
	TokensUsed  int
	CanResume   bool
}

// SharedState holds state that needs to be shared between model copies
type SharedState struct {
	mu      sync.Mutex
	program *tea.Program
}

// SetProgram sets the program reference
func (s *SharedState) SetProgram(p *tea.Program) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.program = p
}

// GetProgram gets the program reference
func (s *SharedState) GetProgram() *tea.Program {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.program
}

// Model is the main application model
type Model struct {
	chat         chat.Model
	input        input.Model
	sidebar      sidebar.Model
	toast        toast.Model
	spinner      spinner.Model
	client       *agent.Client
	shared       *SharedState
	state        State
	session      *agent.Session
	width        int
	height       int
	err          error
	ctx          context.Context
	cancel       context.CancelFunc
	ready        bool
	keyMap       *keybind.KeyMap
	inputFocused bool

	// Dialog support
	activeDialog     dialog.Dialog
	shortcutsOverlay *dialog.ShortcutsOverlay
	mcpDialog        *dialog.MCPDialog

	// Token tracking
	totalInputTokens  int
	totalOutputTokens int
	totalCost         float64
	currentModel      string
	currentAgent      string
	maxContextTokens  int    // Maximum context window size
	provider          string // Provider name (e.g., "Anthropic", "OpenAI")

	// Connection status
	connected bool
	gitBranch string

	// Mouse mode (enabled by default for scrolling, can be toggled for text selection)
	mouseEnabled bool

	// Double-escape interrupt tracking
	lastEscapeTime time.Time

	// Permissions mode - Claude Code style (bypass permissions, ask, etc.)
	permissionsMode string

	// Version info
	appVersion    string
	latestVersion string

	// Task tracking - Claude Code style
	currentTask     string    // Current active task description
	nextTask        string    // Next task in queue
	taskStartTime   time.Time // When the current task started
	taskTokensUsed  int       // Tokens used for current task

	// Interrupt tracking
	currentOperation  OperationType
	interruptContext  *InterruptContext
	lastInterruptTime time.Time

	// Notification configuration
	notificationConfig notification.NotificationConfig
}

// New creates a new application model
func New(client *agent.Client) Model {
	// Load notification preferences
	prefs, err := config.LoadPreferences()
	var notifConfig notification.NotificationConfig
	if err != nil {
		// Use defaults if loading fails
		notifConfig = notification.DefaultNotificationConfig()
	} else {
		notifConfig = convertNotificationPreferences(prefs.Notifications)
	}

	return Model{
		chat:               chat.New(80, 20),
		input:              input.New(80),
		sidebar:            sidebar.New(30, 20),
		toast:              toast.New(),
		spinner:            spinner.New(spinner.StyleDots),
		client:             client,
		shared:             &SharedState{},
		state:              StateLoading,
		ready:              false,
		keyMap:             keybind.DefaultKeyMap(),
		inputFocused:       false,
		mcpDialog:          dialog.NewMCPDialog(),
		currentAgent:       "build",           // Default agent
		mouseEnabled:       true,              // Mouse mode enabled by default
		maxContextTokens:   200000,            // Default Claude context window
		provider:           "Anthropic",       // Default provider
		connected:          false,
		permissionsMode:    "bypass",          // Claude Code style: bypass, ask, deny
		appVersion:         "1.0.0",           // Version info
		latestVersion:      "1.0.0",
		notificationConfig: notifConfig,
	}
}

// SetProgram sets the tea.Program reference for SSE callbacks
func (m *Model) SetProgram(p *tea.Program) {
	m.shared.SetProgram(p)
}

// Init initializes the application
func (m Model) Init() tea.Cmd {
	m.spinner.SetMessage("Connecting...")
	// Load CLAUDE.md context on startup
	m.sidebar.LoadClaudeMd()
	return tea.Batch(
		m.input.Init(),
		m.chat.Init(),
		m.sidebar.Init(),
		m.spinner.Start(),
		m.checkHealth(),
		m.checkResumeSession(),
	)
}

// checkHealth checks if the backend is healthy
func (m Model) checkHealth() tea.Cmd {
	return func() tea.Msg {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()

		_, err := m.client.Health(ctx)
		if err != nil {
			return healthCheckMsg{healthy: false, err: err}
		}
		return healthCheckMsg{healthy: true}
	}
}

type healthCheckMsg struct {
	healthy bool
	err     error
}

// ShowHelp shows the help dialog
func (m *Model) ShowHelp() {
	m.activeDialog = dialog.NewHelpDialog()
}

// ShowModelDialog shows the model selection dialog
func (m *Model) ShowModelDialog() {
	m.activeDialog = dialog.NewModelDialog()
}

// ShowConfirm shows a confirmation dialog
func (m *Model) ShowConfirm(message string, onConfirm, onCancel tea.Cmd) {
	m.activeDialog = dialog.NewConfirmDialog(message, onConfirm, onCancel)
	// Play confirmation notification
	go notification.NotifyConfirmation(m.notificationConfig)
}

// ShowAgentDialog shows the agent selection dialog
func (m *Model) ShowAgentDialog() {
	m.activeDialog = dialog.NewAgentDialog()
}

// CloseDialog closes the active dialog
func (m *Model) CloseDialog() {
	m.activeDialog = nil
}

// HasActiveDialog returns true if there is an active dialog
func (m *Model) HasActiveDialog() bool {
	return m.activeDialog != nil && m.activeDialog.IsVisible()
}

// ShowToast displays a toast notification
func (m *Model) ShowToast(message string, toastType toast.ToastType, duration time.Duration) tea.Cmd {
	return m.toast.Add(message, toastType, duration)
}

// ToggleThinking toggles the display of thinking/reasoning content
func (m *Model) ToggleThinking() {
	m.chat.ToggleThinking()
}

// IsShowingThinking returns true if thinking content is being displayed
func (m *Model) IsShowingThinking() bool {
	return m.chat.IsShowingThinking()
}

// IsMouseEnabled returns true if mouse mode is enabled
func (m *Model) IsMouseEnabled() bool {
	return m.mouseEnabled
}

// ShowDiffDialog shows the file changes diff dialog
func (m *Model) ShowDiffDialog(diffs []agent.FileDiff) {
	width := m.width * 3 / 4
	height := m.height * 3 / 4
	if width < 60 {
		width = 60
	}
	if height < 20 {
		height = 20
	}
	m.activeDialog = dialog.NewDiffDialog(diffs, width, height)
}

// ShowCommandDialog shows the command palette
func (m *Model) ShowCommandDialog() {
	m.activeDialog = dialog.NewCommandDialog(m.keyMap)
}

// ShowSessionListDialog shows the session list dialog
func (m *Model) ShowSessionListDialog(sessions []agent.Session) {
	m.activeDialog = dialog.NewSessionListDialog(sessions)
}

// GetSessions returns the cached sessions from sidebar
func (m *Model) GetSessions() []agent.Session {
	return m.sidebar.GetSessions()
}

// ShowContextMenu shows the message context menu
func (m *Model) ShowContextMenu(messageID string, isUserMessage bool) {
	m.activeDialog = dialog.NewContextMenuDialog(messageID, isUserMessage)
}

// ShowThemeDialog shows the theme selection dialog
func (m *Model) ShowThemeDialog() {
	m.activeDialog = dialog.NewThemeDialog()
}

// ShowStatusDialog shows the system status dialog
func (m *Model) ShowStatusDialog() {
	sessionID := ""
	if m.session != nil {
		sessionID = m.session.ID
	}
	info := dialog.StatusInfo{
		Connected:    m.connected,
		Provider:     m.provider,
		Model:        m.currentModel,
		Agent:        m.currentAgent,
		SessionID:    sessionID,
		InputTokens:  m.totalInputTokens,
		OutputTokens: m.totalOutputTokens,
		TotalCost:    m.totalCost,
		GitBranch:    m.gitBranch,
	}
	m.activeDialog = dialog.NewStatusDialog(info)
}

// ShowSettingsDialog shows the settings dialog
func (m *Model) ShowSettingsDialog() {
	m.activeDialog = dialog.NewDefaultSettingsDialog(
		m.IsShowingThinking(),
		m.chat.IsMarkdownEnabled(),
		m.mouseEnabled,
	)
}

// ShowRenameDialog shows the session rename dialog
func (m *Model) ShowRenameDialog() {
	if m.session != nil {
		title := m.session.Title
		if title == "" {
			title = ""
		}
		m.activeDialog = dialog.NewRenameDialog(m.session.ID, title)
	}
}

// ShowResumeDialog shows the resume session dialog
func (m *Model) ShowResumeDialog(info *config.LastSessionInfo) {
	m.activeDialog = dialog.NewResumeDialog(info)
}

// ShowContextDialog shows the CLAUDE.md context dialog
func (m *Model) ShowContextDialog() {
	context := m.sidebar.GetClaudeMdContext()
	m.activeDialog = dialog.NewContextDialog(context)
}

// ShowShortcutsOverlay shows the keyboard shortcuts overlay
func (m *Model) ShowShortcutsOverlay() {
	m.shortcutsOverlay = dialog.NewShortcutsOverlay(m.keyMap, m.inputFocused, m.HasActiveDialog())
}

// CloseShortcutsOverlay closes the shortcuts overlay
func (m *Model) CloseShortcutsOverlay() {
	m.shortcutsOverlay = nil
}

// HasShortcutsOverlay returns true if the shortcuts overlay is visible
func (m *Model) HasShortcutsOverlay() bool {
	return m.shortcutsOverlay != nil && m.shortcutsOverlay.IsVisible()
}

// GetLastMessageInfo returns the ID and role of the last message in the chat
func (m *Model) GetLastMessageInfo() (string, bool) {
	return m.chat.GetLastMessageInfo()
}

// cyclePermissionsMode cycles through permissions modes (bypass -> ask -> deny -> bypass)
func (m *Model) cyclePermissionsMode() {
	switch m.permissionsMode {
	case "bypass":
		m.permissionsMode = "ask"
	case "ask":
		m.permissionsMode = "deny"
	case "deny":
		m.permissionsMode = "bypass"
	default:
		m.permissionsMode = "bypass"
	}
}

// SetCurrentTask sets the current task for display
func (m *Model) SetCurrentTask(task string) {
	m.currentTask = task
	if task != "" && m.taskStartTime.IsZero() {
		m.taskStartTime = time.Now()
	}
}

// SetNextTask sets the next task for display
func (m *Model) SetNextTask(task string) {
	m.nextTask = task
}

// ClearTask clears the current task
func (m *Model) ClearTask() {
	m.currentTask = ""
	m.nextTask = ""
	m.taskStartTime = time.Time{}
	m.taskTokensUsed = 0
}

// captureInterruptContext captures the current operation state for interrupt handling
func (m *Model) captureInterruptContext() InterruptContext {
	ctx := InterruptContext{
		Timestamp: time.Now(),
		CanResume: true,
		TokensUsed: m.totalOutputTokens,
	}

	// Check if we're currently executing a tool
	if tool := m.chat.GetCurrentTool(); tool != nil {
		ctx.Operation = OpToolExecution
		ctx.ToolName = tool.Tool
		if tool.State != nil {
			ctx.ToolInput = tool.State.Input
			ctx.Description = formatToolDescription(tool.Tool, tool.State.Input)
		} else {
			ctx.Description = "Executing " + tool.Tool
		}
		return ctx
	}

	// Check if we're in thinking mode
	if m.chat.IsThinking() {
		ctx.Operation = OpThinking
		ctx.Description = "Thinking about the response"
		ctx.PartialText = m.chat.GetPartialThinking()
		return ctx
	}

	// Otherwise we're generating text
	ctx.Operation = OpGenerating
	ctx.Description = "Generating response"
	ctx.PartialText = m.chat.GetPartialText()

	return ctx
}

// formatToolDescription creates a human-readable description of a tool operation
func formatToolDescription(toolName string, input map[string]interface{}) string {
	if input == nil {
		return "Executing " + toolName
	}

	switch toolName {
	case "Read":
		if path, ok := input["file_path"].(string); ok {
			return "Reading " + path
		}
	case "Bash":
		if cmd, ok := input["command"].(string); ok {
			return "Running: " + cmd
		}
	case "Glob":
		if pattern, ok := input["pattern"].(string); ok {
			return "Searching for files matching " + pattern
		}
	case "Grep":
		if pattern, ok := input["pattern"].(string); ok {
			return "Searching for pattern: " + pattern
		}
	case "Edit":
		if path, ok := input["file_path"].(string); ok {
			return "Editing " + path
		}
	case "Write":
		if path, ok := input["file_path"].(string); ok {
			return "Writing to " + path
		}
	case "WebFetch":
		if url, ok := input["url"].(string); ok {
			return "Fetching " + url
		}
	case "WebSearch":
		if query, ok := input["query"].(string); ok {
			return "Searching for: " + query
		}
	}

	return "Executing " + toolName
}

// getSearchState returns the chat's search state for rendering
func (m Model) getSearchState() chat.SearchState {
	return m.chat.GetSearchState()
}
