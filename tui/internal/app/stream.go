package app

import (
	"context"
	"fmt"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/williamcory/agent/sdk/agent"
	"tui/internal/messages"
)

// sendMessage sends the current input to the backend
func (m Model) sendMessage() (tea.Model, tea.Cmd) {
	content := m.input.Value()

	// Add user message to chat
	m.chat.AddUserMessage(content)

	// Clear input and unfocus
	m.input.Clear()
	m.input.Blur()
	m.inputFocused = false

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
