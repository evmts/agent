package app

import (
	"context"
	"fmt"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/williamcory/agent/sdk/agent"
	"tui/internal/messages"
)

// Internal message types
type sessionCreatedMsg struct {
	session *agent.Session
}

type messagesLoadedMsg struct {
	messages []agent.MessageWithParts
}

type sessionsLoadedMsg struct {
	sessions []agent.Session
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

// loadSessions loads all sessions from the backend
func (m Model) loadSessions() tea.Cmd {
	return func() tea.Msg {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()

		sessions, err := m.client.ListSessions(ctx)
		if err != nil {
			return messages.ErrorMsg{Message: fmt.Sprintf("Failed to load sessions: %v", err)}
		}
		return sessionsLoadedMsg{sessions: sessions}
	}
}

// loadSessionMessages loads messages for a specific session
func (m Model) loadSessionMessages(sessionID string) tea.Cmd {
	return func() tea.Msg {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()

		msgs, err := m.client.ListMessages(ctx, sessionID, nil)
		if err != nil {
			return messages.ErrorMsg{Message: fmt.Sprintf("Failed to load messages: %v", err)}
		}
		return messagesLoadedMsg{messages: msgs}
	}
}
