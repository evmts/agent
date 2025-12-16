package app

import (
	"context"
	"fmt"
	"os/exec"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/williamcory/agent/sdk/agent"
	"github.com/williamcory/agent/tui/internal/messages"
)

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

// loadSessionDiff loads the file diffs for a session
func (m Model) loadSessionDiff(sessionID string) tea.Cmd {
	return func() tea.Msg {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()

		diffs, err := m.client.GetSessionDiff(ctx, sessionID, nil)
		if err != nil {
			return messages.ErrorMsg{Message: fmt.Sprintf("Failed to load diff: %v", err)}
		}
		return diffLoadedMsg{diffs: diffs}
	}
}

// forkSession creates a fork of the current session
func (m Model) forkSession(sessionID string) tea.Cmd {
	return func() tea.Msg {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()

		session, err := m.client.ForkSession(ctx, sessionID, &agent.ForkRequest{})
		if err != nil {
			return messages.ErrorMsg{Message: fmt.Sprintf("Failed to fork session: %v", err)}
		}
		return sessionForkedMsg{session: session}
	}
}

// renameSession renames a session
func (m Model) renameSession(sessionID, newTitle string) tea.Cmd {
	return func() tea.Msg {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()

		session, err := m.client.UpdateSession(ctx, sessionID, &agent.UpdateSessionRequest{
			Title: &newTitle,
		})
		if err != nil {
			return messages.ErrorMsg{Message: fmt.Sprintf("Failed to rename session: %v", err)}
		}
		return sessionRenamedMsg{session: session}
	}
}

// revertSession reverts the session to the last checkpoint
func (m Model) revertSession(sessionID string) tea.Cmd {
	return func() tea.Msg {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()

		// Get the latest message to find a revert point
		msgs, err := m.client.ListMessages(ctx, sessionID, agent.Int(1))
		if err != nil || len(msgs) == 0 {
			return messages.ErrorMsg{Message: "No messages to revert to"}
		}

		// Revert to the last message
		session, err := m.client.RevertSession(ctx, sessionID, &agent.RevertRequest{
			MessageID: msgs[0].Info.ID,
		})
		if err != nil {
			return messages.ErrorMsg{Message: fmt.Sprintf("Failed to revert session: %v", err)}
		}
		return sessionRevertedMsg{session: session}
	}
}

// revertToMessage reverts to a specific message
func (m Model) revertToMessage(sessionID, messageID string) tea.Cmd {
	return func() tea.Msg {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()

		session, err := m.client.RevertSession(ctx, sessionID, &agent.RevertRequest{
			MessageID: messageID,
		})
		if err != nil {
			return messages.ErrorMsg{Message: fmt.Sprintf("Failed to revert: %v", err)}
		}
		return sessionRevertedMsg{session: session}
	}
}

// forkFromMessage creates a fork from a specific message
func (m Model) forkFromMessage(sessionID, messageID string) tea.Cmd {
	return func() tea.Msg {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()

		session, err := m.client.ForkSession(ctx, sessionID, &agent.ForkRequest{
			MessageID: &messageID,
		})
		if err != nil {
			return messages.ErrorMsg{Message: fmt.Sprintf("Failed to fork: %v", err)}
		}
		return sessionForkedMsg{session: session}
	}
}

// detectGitBranch detects the current git branch and refreshes git status
func (m Model) detectGitBranch() tea.Cmd {
	return func() tea.Msg {
		cmd := exec.Command("git", "rev-parse", "--abbrev-ref", "HEAD")
		output, err := cmd.Output()
		branch := ""
		if err == nil {
			branch = strings.TrimSpace(string(output))
		}
		// Return a message that will trigger both branch update and git status refresh
		return gitBranchMsg{branch: branch}
	}
}
