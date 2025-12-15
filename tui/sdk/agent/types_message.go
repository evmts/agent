package agent

import "encoding/json"

// ModelInfo identifies a model and provider.
type ModelInfo struct {
	ProviderID string `json:"providerID"`
	ModelID    string `json:"modelID"`
}

// TokenInfo contains token usage statistics.
type TokenInfo struct {
	Input     int            `json:"input"`
	Output    int            `json:"output"`
	Reasoning int            `json:"reasoning"`
	Cache     map[string]int `json:"cache,omitempty"`
}

// PathInfo contains working directory info.
type PathInfo struct {
	Cwd  string `json:"cwd"`
	Root string `json:"root"`
}

// MessageTime represents timestamps for a message.
type MessageTime struct {
	Created   float64  `json:"created"`
	Completed *float64 `json:"completed,omitempty"`
}

// UserMessage represents a user's message.
type UserMessage struct {
	ID        string          `json:"id"`
	SessionID string          `json:"sessionID"`
	Role      string          `json:"role"` // "user"
	Time      MessageTime     `json:"time"`
	Agent     string          `json:"agent"`
	Model     ModelInfo       `json:"model"`
	System    *string         `json:"system,omitempty"`
	Tools     map[string]bool `json:"tools,omitempty"`
}

// AssistantMessage represents an assistant's response.
type AssistantMessage struct {
	ID         string          `json:"id"`
	SessionID  string          `json:"sessionID"`
	Role       string          `json:"role"` // "assistant"
	Time       MessageTime     `json:"time"`
	ParentID   string          `json:"parentID"`
	ModelID    string          `json:"modelID"`
	ProviderID string          `json:"providerID"`
	Mode       string          `json:"mode"`
	Path       PathInfo        `json:"path"`
	Cost       float64         `json:"cost"`
	Tokens     TokenInfo       `json:"tokens"`
	Finish     *string         `json:"finish,omitempty"`
	Summary    *bool           `json:"summary,omitempty"`
	Error      json.RawMessage `json:"error,omitempty"`
}

// Message represents either a user or assistant message.
// Use the Role field to determine the type.
type Message struct {
	// Common fields
	ID        string      `json:"id"`
	SessionID string      `json:"sessionID"`
	Role      string      `json:"role"` // "user" or "assistant"
	Time      MessageTime `json:"time"`

	// User message fields
	Agent  string          `json:"agent,omitempty"`
	Model  *ModelInfo      `json:"model,omitempty"`
	System *string         `json:"system,omitempty"`
	Tools  map[string]bool `json:"tools,omitempty"`

	// Assistant message fields
	ParentID   string          `json:"parentID,omitempty"`
	ModelID    string          `json:"modelID,omitempty"`
	ProviderID string          `json:"providerID,omitempty"`
	Mode       string          `json:"mode,omitempty"`
	Path       *PathInfo       `json:"path,omitempty"`
	Cost       float64         `json:"cost,omitempty"`
	Tokens     *TokenInfo      `json:"tokens,omitempty"`
	Finish     *string         `json:"finish,omitempty"`
	Summary    *bool           `json:"summary,omitempty"`
	Error      json.RawMessage `json:"error,omitempty"`
}

// IsUser returns true if this is a user message.
func (m *Message) IsUser() bool {
	return m.Role == "user"
}

// IsAssistant returns true if this is an assistant message.
func (m *Message) IsAssistant() bool {
	return m.Role == "assistant"
}

// MessageWithParts combines a message with its parts.
type MessageWithParts struct {
	Info  Message `json:"info"`
	Parts []Part  `json:"parts"`
}
