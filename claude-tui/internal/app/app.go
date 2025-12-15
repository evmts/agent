package app

import (
	"context"

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

// Model is the main application model
type Model struct {
	chat           chat.Model
	input          input.Model
	client         *client.Client
	program        *tea.Program
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
		state:  StateIdle,
		ready:  false,
	}
}

// SetProgram sets the tea.Program reference for SSE callbacks
func (m *Model) SetProgram(p *tea.Program) {
	m.program = p
}

// Init initializes the application
func (m Model) Init() tea.Cmd {
	return tea.Batch(
		m.input.Init(),
		m.chat.Init(),
	)
}
