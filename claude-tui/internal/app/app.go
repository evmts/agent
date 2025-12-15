package app

import (
	"context"
	"sync"

	tea "github.com/charmbracelet/bubbletea"
	"claude-tui/internal/client"
	"claude-tui/internal/components/chat"
	"claude-tui/internal/components/input"
)

// State represents the application state
type State int

const (
	StateIdle State = iota
	StateStreaming
	StateError
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
	chat           chat.Model
	input          input.Model
	client         *client.Client
	shared         *SharedState
	state          State
	conversationID *string
	width          int
	height         int
	err            error
	ctx            context.Context
	cancel         context.CancelFunc
	ready          bool
}

// New creates a new application model
func New(sseClient *client.Client) Model {
	return Model{
		chat:   chat.New(80, 20),
		input:  input.New(80),
		client: sseClient,
		shared: &SharedState{},
		state:  StateIdle,
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
	)
}
