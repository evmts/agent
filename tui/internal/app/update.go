package app

import (
	"context"
	"fmt"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/williamcory/agent/sdk/agent"
	"tui/internal/messages"
)

// Update handles all application messages
func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmds []tea.Cmd

	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		m.ready = true

		// Calculate component sizes
		// Reserve space for: header (2), input (5), status bar (2), padding (2)
		chatHeight := msg.Height - 11
		if chatHeight < 5 {
			chatHeight = 5
		}

		m.chat.SetSize(msg.Width, chatHeight)
		m.input.SetWidth(msg.Width)
		return m, nil

	case healthCheckMsg:
		if msg.healthy {
			// Create a new session on startup
			return m, m.createSession()
		} else {
			m.state = StateError
			m.err = msg.err
			return m, nil
		}

	case sessionCreatedMsg:
		m.session = msg.session
		m.state = StateIdle
		return m, m.input.Focus()

	case messagesLoadedMsg:
		m.chat.LoadMessages(msg.messages)
		m.state = StateIdle
		return m, nil

	case tea.KeyMsg:
		switch msg.String() {
		case "ctrl+c":
			if m.state == StateStreaming && m.cancel != nil {
				// Cancel the current stream
				m.cancel()
				m.state = StateIdle
				m.chat.EndAssistantMessage()
				return m, m.input.Focus()
			}
			return m, tea.Quit

		case "esc":
			if m.state == StateStreaming && m.cancel != nil {
				m.cancel()
				m.state = StateIdle
				m.chat.EndAssistantMessage()
				return m, m.input.Focus()
			}
			return m, tea.Quit

		case "enter":
			// Only send if idle, has session, and has content
			if m.state == StateIdle && m.session != nil && m.input.Value() != "" {
				return m.sendMessage()
			}

		case "ctrl+n":
			// New session
			if m.state == StateIdle {
				m.chat.Clear()
				m.session = nil
				m.state = StateLoading
				return m, m.createSession()
			}

		case "ctrl+l":
			// Clear chat (but keep session)
			m.chat.Clear()
			return m, nil
		}

	// SDK Stream Events
	case messages.StreamEventMsg:
		if msg.Event != nil {
			m.chat.HandleStreamEvent(msg.Event)

			// Update token tracking
			if msg.Event.Message != nil && msg.Event.Message.Tokens != nil {
				tokens := msg.Event.Message.Tokens
				m.totalTokens = tokens.Input + tokens.Output + tokens.Reasoning
				m.totalCost = msg.Event.Message.Cost
			}
		}
		return m, nil

	case messages.StreamStartMsg:
		m.state = StateStreaming
		m.chat.StartAssistantMessage()
		return m, nil

	case messages.StreamEndMsg:
		if m.state == StateStreaming {
			m.chat.EndAssistantMessage()
		}
		m.state = StateIdle
		return m, m.input.Focus()

	case messages.ErrorMsg:
		m.err = fmt.Errorf("%s", msg.Message)
		m.state = StateError
		m.chat.EndAssistantMessage()
		return m, m.input.Focus()
	}

	// Update child components when idle
	if m.state == StateIdle {
		var cmd tea.Cmd
		m.input, cmd = m.input.Update(msg)
		cmds = append(cmds, cmd)
	}

	// Always allow chat scrolling
	var cmd tea.Cmd
	m.chat, cmd = m.chat.Update(msg)
	cmds = append(cmds, cmd)

	return m, tea.Batch(cmds...)
}

// Internal message types
type sessionCreatedMsg struct {
	session *agent.Session
}

type messagesLoadedMsg struct {
	messages []agent.MessageWithParts
}

// createSession creates a new session
func (m Model) createSession() tea.Cmd {
	return func() tea.Msg {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()

		session, err := m.client.CreateSession(ctx, &agent.CreateSessionRequest{
			Title: agent.String("Claude TUI Session"),
		})
		if err != nil {
			return messages.ErrorMsg{Message: fmt.Sprintf("Failed to create session: %v", err)}
		}
		return sessionCreatedMsg{session: session}
	}
}

// sendMessage sends the current input to the backend
func (m Model) sendMessage() (tea.Model, tea.Cmd) {
	content := m.input.Value()

	// Add user message to chat
	m.chat.AddUserMessage(content)

	// Clear input
	m.input.Clear()
	m.input.Blur()

	// Create cancellable context
	m.ctx, m.cancel = context.WithCancel(context.Background())

	// Get program from shared state
	p := m.shared.GetProgram()

	// Start streaming
	return m, m.streamMessage(m.ctx, m.session.ID, content, p)
}

// streamMessage streams a message using the SDK
func (m Model) streamMessage(ctx context.Context, sessionID, content string, p *tea.Program) tea.Cmd {
	return func() tea.Msg {
		// Prepare the request
		req := &agent.PromptRequest{
			Parts: []interface{}{
				agent.TextPartInput{Type: "text", Text: content},
			},
		}

		// Start streaming
		eventCh, errCh, err := m.client.SendMessage(ctx, sessionID, req)
		if err != nil {
			return messages.ErrorMsg{Message: fmt.Sprintf("Failed to send message: %v", err)}
		}

		// Signal stream start
		p.Send(messages.StreamStartMsg{})

		// Process events
		for {
			select {
			case <-ctx.Done():
				return messages.StreamEndMsg{}
			case err := <-errCh:
				if err != nil {
					return messages.ErrorMsg{Message: fmt.Sprintf("Stream error: %v", err)}
				}
				return messages.StreamEndMsg{}
			case event, ok := <-eventCh:
				if !ok {
					return messages.StreamEndMsg{}
				}
				// Send event to the program
				p.Send(messages.StreamEventMsg{Event: event})
			}
		}
	}
}
