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
	"tui/internal/components/toast"
	"tui/internal/keybind"
)

// State represents the application state
type State int

const (
	StateIdle State = iota
	StateStreaming
	StateError
	StateLoading
)

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
	activeDialog dialog.Dialog

	// Token tracking
	totalInputTokens  int
	totalOutputTokens int
	totalCost         float64
	currentModel      string
	currentAgent      string
}

// New creates a new application model
func New(client *agent.Client) Model {
	return Model{
		chat:         chat.New(80, 20),
		input:        input.New(80),
		sidebar:      sidebar.New(30, 20),
		toast:        toast.New(),
		client:       client,
		shared:       &SharedState{},
		state:        StateLoading,
		ready:        false,
		keyMap:       keybind.DefaultKeyMap(),
		inputFocused: false,
		currentAgent: "build", // Default agent
	}
}

// SetProgram sets the tea.Program reference for SSE callbacks
func (m *Model) SetProgram(p *tea.Program) {
	m.shared.SetProgram(p)
}

// Init initializes the application
func (m Model) Init() tea.Cmd {
	return tea.Batch(
		m.input.Init(),
		m.chat.Init(),
		m.sidebar.Init(),
		m.checkHealth(),
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
