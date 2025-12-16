package app

import (
	"context"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"tui/internal/config"
	"tui/internal/messages"
)

// checkResumeSession checks if there's a session to resume
func (m Model) checkResumeSession() tea.Cmd {
	return func() tea.Msg {
		// Load preferences
		prefs, err := config.LoadPreferences()
		if err != nil {
			// If we can't load prefs, just skip resume
			return resumeCheckMsg{hasSession: false}
		}

		// Get last session info
		lastSession, err := config.GetLastSession()
		if err != nil || lastSession == nil {
			// No session to resume
			return resumeCheckMsg{hasSession: false}
		}

		// Return resume check with the info
		return resumeCheckMsg{
			hasSession: true,
			info:       lastSession,
			preference: prefs.ResumePreference,
		}
	}
}

// loadExistingSession loads an existing session by ID
func (m Model) loadExistingSession(sessionID string) tea.Cmd {
	return func() tea.Msg {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()

		// Get the session
		session, err := m.client.GetSession(ctx, sessionID)
		if err != nil {
			return messages.ErrorMsg{Message: "Failed to load session: " + err.Error()}
		}

		return sessionCreatedMsg{session: session}
	}
}

// saveCurrentSessionInfo saves the current session information to preferences
func (m Model) saveCurrentSessionInfo() {
	if m.session == nil {
		return
	}

	// Get the last message preview
	lastMessageText := m.chat.GetLastMessageText()
	if lastMessageText == "" {
		lastMessageText = "No messages yet"
	}

	// Count messages from chat
	messageCount := m.chat.GetMessageCount()

	// Save to preferences (async, ignore errors)
	go func() {
		_ = config.SaveLastSession(
			m.session.ID,
			m.session.Title,
			messageCount,
			lastMessageText,
		)
	}()
}
