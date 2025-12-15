package agent

import "encoding/json"

// Event represents an SSE event from the server.
type Event struct {
	Type       string          `json:"type"`
	Properties json.RawMessage `json:"properties"`
}

// SessionEvent contains session data from an event.
type SessionEvent struct {
	Info Session `json:"info"`
}

// MessageEvent contains message data from an event.
type MessageEvent struct {
	Info Message `json:"info"`
}

// PartEvent contains part data from an event.
type PartEvent struct {
	ID        string `json:"id"`
	SessionID string `json:"sessionID"`
	MessageID string `json:"messageID"`
	Type      string `json:"type"`
	Text      string `json:"text,omitempty"`
	Tool      string `json:"tool,omitempty"`
}
