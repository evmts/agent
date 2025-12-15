package messages

import (
	"github.com/williamcory/agent/sdk/agent"
)

// SDK Event wrappers for Bubbletea

// StreamEventMsg wraps an SDK stream event
type StreamEventMsg struct {
	Event *agent.StreamEvent
}

// SessionsLoadedMsg is sent when sessions are loaded
type SessionsLoadedMsg struct {
	Sessions []agent.Session
}

// SessionCreatedMsg is sent when a new session is created
type SessionCreatedMsg struct {
	Session *agent.Session
}

// SessionSelectedMsg is sent when a session is selected
type SessionSelectedMsg struct {
	Session *agent.Session
}

// MessagesLoadedMsg is sent when messages are loaded for a session
type MessagesLoadedMsg struct {
	Messages []agent.MessageWithParts
}

// ErrorMsg represents an error
type ErrorMsg struct {
	Message string
}

// Internal app messages
type StreamStartMsg struct{}
type StreamEndMsg struct{}

// HealthCheckMsg is sent after health check
type HealthCheckMsg struct {
	Healthy bool
	Error   error
}
