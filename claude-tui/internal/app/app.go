package app

import (
	"context"
	"sync"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/williamcory/agent/sdk/agent"
	"claude-tui/internal/components/chat"
	"claude-tui/internal/components/input"
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
	chat    chat.Model
	input   input.Model
	client  *agent.Client
	shared  *SharedState
	state   State
	session *agent.Session
	width   int
	height  int
	err     error
	ctx     context.Context
	cancel  context.CancelFunc
	ready   bool

	// Token tracking
	totalTokens int
	totalCost   float64
}

// New creates a new application model
func New(client *agent.Client) Model {
	return Model{
		chat:   chat.New(80, 20),
		input:  input.New(80),
		client: client,
		shared: &SharedState{},
		state:  StateLoading,
		ready:  false,
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
		m.checkHealth(),
	)
}

// checkHealth checks if the backend is healthy
func (m Model) checkHealth() tea.Cmd {
	return func() tea.Msg {
		ctx, cancel := context.WithTimeout(context.Background(), 5000000000) // 5 seconds
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
