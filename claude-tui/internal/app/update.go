package app

import (
	"context"
	"fmt"

	tea "github.com/charmbracelet/bubbletea"
	"claude-tui/internal/messages"
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
		// Reserve space for: header (1), input (5), status bar (1), padding (2)
		chatHeight := msg.Height - 9
		if chatHeight < 5 {
			chatHeight = 5
		}

		m.chat.SetSize(msg.Width, chatHeight)
		m.input.SetWidth(msg.Width)
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
			// Only send if idle and has content
			if m.state == StateIdle && m.input.Value() != "" {
				return m.sendMessage()
			}

		case "ctrl+l":
			// Clear chat
			m.chat.Clear()
			m.conversationID = nil
			return m, nil
		}

	// SSE Events
	case messages.StreamStartMsg:
		m.state = StateStreaming
		m.chat.StartAssistantMessage()
		return m, nil

	case messages.TokenMsg:
		m.chat.AppendToken(msg.Content)
		return m, nil

	case messages.ToolUseMsg:
		m.chat.AddToolEvent(msg.Tool, msg.Input)
		return m, nil

	case messages.ToolResultMsg:
		m.chat.CompleteToolEvent(msg.Tool, msg.Output)
		return m, nil

	case messages.DoneMsg:
		m.conversationID = &msg.ConversationID
		m.chat.EndAssistantMessage()
		m.state = StateIdle
		return m, m.input.Focus()

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
	return m, m.client.StreamChat(m.ctx, content, m.conversationID, p)
}
