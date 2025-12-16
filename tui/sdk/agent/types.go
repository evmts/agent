// Package agent provides a Go SDK for the OpenCode-compatible agent server.
package agent

import (
	"encoding/json"
	"time"
)

// SessionTime represents timestamps for a session.
type SessionTime struct {
	Created  float64  `json:"created"`
	Updated  float64  `json:"updated"`
	Archived *float64 `json:"archived,omitempty"`
}

// FileDiff represents a file change.
type FileDiff struct {
	File      string `json:"file"`
	Before    string `json:"before"`
	After     string `json:"after"`
	Additions int    `json:"additions"`
	Deletions int    `json:"deletions"`
}

// SessionSummary contains summary of changes in a session.
type SessionSummary struct {
	Additions int        `json:"additions"`
	Deletions int        `json:"deletions"`
	Files     int        `json:"files"`
	Diffs     []FileDiff `json:"diffs,omitempty"`
}

// RevertInfo contains revert state for a session.
type RevertInfo struct {
	MessageID string  `json:"messageID"`
	PartID    *string `json:"partID,omitempty"`
	Snapshot  *string `json:"snapshot,omitempty"`
	Diff      *string `json:"diff,omitempty"`
}

// Session represents a chat session.
type Session struct {
	ID        string          `json:"id"`
	ProjectID string          `json:"projectID"`
	Directory string          `json:"directory"`
	Title     string          `json:"title"`
	Version   string          `json:"version"`
	Time      SessionTime     `json:"time"`
	ParentID  *string         `json:"parentID,omitempty"`
	Summary   *SessionSummary `json:"summary,omitempty"`
	Revert    *RevertInfo     `json:"revert,omitempty"`
}

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
	ID        string            `json:"id"`
	SessionID string            `json:"sessionID"`
	Role      string            `json:"role"` // "user"
	Time      MessageTime       `json:"time"`
	Agent     string            `json:"agent"`
	Model     ModelInfo         `json:"model"`
	System    *string           `json:"system,omitempty"`
	Tools     map[string]bool   `json:"tools,omitempty"`
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
	Agent  string            `json:"agent,omitempty"`
	Model  *ModelInfo        `json:"model,omitempty"`
	System *string           `json:"system,omitempty"`
	Tools  map[string]bool   `json:"tools,omitempty"`

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

// PartTime represents timestamps for a part.
type PartTime struct {
	Start float64  `json:"start"`
	End   *float64 `json:"end,omitempty"`
}

// TextPart represents a text content part.
type TextPart struct {
	ID        string    `json:"id"`
	SessionID string    `json:"sessionID"`
	MessageID string    `json:"messageID"`
	Type      string    `json:"type"` // "text"
	Text      string    `json:"text"`
	Time      *PartTime `json:"time,omitempty"`
}

// ReasoningPart represents reasoning/thinking content.
type ReasoningPart struct {
	ID        string   `json:"id"`
	SessionID string   `json:"sessionID"`
	MessageID string   `json:"messageID"`
	Type      string   `json:"type"` // "reasoning"
	Text      string   `json:"text"`
	Time      PartTime `json:"time"`
}

// ToolProgress represents progress information for a tool execution.
type ToolProgress struct {
	Type        ProgressType `json:"type"`
	Current     int64        `json:"current"`
	Total       int64        `json:"total"`
	Unit        string       `json:"unit"`        // "lines", "files", "bytes"
	StartTime   float64      `json:"startTime"`   // Unix timestamp
	LastUpdate  float64      `json:"lastUpdate"`  // Unix timestamp
	BytesPerSec float64      `json:"bytesPerSec"` // For ETA calculation
}

// ProgressType represents the type of progress indicator.
type ProgressType string

const (
	ProgressNone          ProgressType = "none"
	ProgressCount         ProgressType = "count"         // X of Y items
	ProgressBytes         ProgressType = "bytes"         // X of Y bytes
	ProgressTime          ProgressType = "time"          // Elapsed time only
	ProgressIndeterminate ProgressType = "indeterminate" // Spinner only
)

// Percentage returns the progress as a percentage (0-100).
func (p ToolProgress) Percentage() float64 {
	if p.Total == 0 {
		return 0
	}
	pct := (float64(p.Current) / float64(p.Total)) * 100
	if pct > 100 {
		pct = 100
	}
	return pct
}

// ETA calculates estimated time remaining in seconds.
func (p ToolProgress) ETA() float64 {
	if p.BytesPerSec == 0 || p.Current == 0 || p.Total == 0 {
		return 0
	}
	remaining := p.Total - p.Current
	return float64(remaining) / p.BytesPerSec
}

// ElapsedSeconds returns the elapsed time in seconds.
func (p ToolProgress) ElapsedSeconds() float64 {
	if p.StartTime == 0 {
		return 0
	}
	if p.LastUpdate > 0 {
		return p.LastUpdate - p.StartTime
	}
	return Now() - p.StartTime
}

// ToolState represents the state of a tool execution.
type ToolState struct {
	Status   string                 `json:"status"` // "pending", "running", "completed"
	Input    map[string]interface{} `json:"input"`
	Raw      string                 `json:"raw,omitempty"`
	Output   string                 `json:"output,omitempty"`
	Title    *string                `json:"title,omitempty"`
	Metadata map[string]interface{} `json:"metadata,omitempty"`
	Time     *PartTime              `json:"time,omitempty"`
	Progress *ToolProgress          `json:"progress,omitempty"`
}

// ToolPart represents a tool use/result.
type ToolPart struct {
	ID        string    `json:"id"`
	SessionID string    `json:"sessionID"`
	MessageID string    `json:"messageID"`
	Type      string    `json:"type"` // "tool"
	Tool      string    `json:"tool"`
	State     ToolState `json:"state"`
}

// FilePart represents a file attachment.
type FilePart struct {
	ID        string  `json:"id"`
	SessionID string  `json:"sessionID"`
	MessageID string  `json:"messageID"`
	Type      string  `json:"type"` // "file"
	Mime      string  `json:"mime"`
	URL       string  `json:"url"`
	Filename  *string `json:"filename,omitempty"`
}

// Part represents any message part. Use the Type field to determine the specific type.
type Part struct {
	ID        string `json:"id"`
	SessionID string `json:"sessionID"`
	MessageID string `json:"messageID"`
	Type      string `json:"type"` // "text", "reasoning", "tool", "file"

	// TextPart / ReasoningPart fields
	Text string    `json:"text,omitempty"`
	Time *PartTime `json:"time,omitempty"`

	// ToolPart fields
	Tool  string     `json:"tool,omitempty"`
	State *ToolState `json:"state,omitempty"`

	// FilePart fields
	Mime     string  `json:"mime,omitempty"`
	URL      string  `json:"url,omitempty"`
	Filename *string `json:"filename,omitempty"`
}

// IsText returns true if this is a text part.
func (p *Part) IsText() bool {
	return p.Type == "text"
}

// IsReasoning returns true if this is a reasoning part.
func (p *Part) IsReasoning() bool {
	return p.Type == "reasoning"
}

// IsTool returns true if this is a tool part.
func (p *Part) IsTool() bool {
	return p.Type == "tool"
}

// IsFile returns true if this is a file part.
func (p *Part) IsFile() bool {
	return p.Type == "file"
}

// MessageWithParts combines a message with its parts.
type MessageWithParts struct {
	Info  Message `json:"info"`
	Parts []Part  `json:"parts"`
}

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
	// ... other part fields
}

// Request types

// CreateSessionRequest is the request body for creating a session.
type CreateSessionRequest struct {
	ParentID *string `json:"parentID,omitempty"`
	Title    *string `json:"title,omitempty"`
}

// UpdateSessionRequest is the request body for updating a session.
type UpdateSessionRequest struct {
	Title *string                `json:"title,omitempty"`
	Time  map[string]interface{} `json:"time,omitempty"`
}

// TextPartInput represents text input for a message.
type TextPartInput struct {
	Type string `json:"type"` // "text"
	Text string `json:"text"`
}

// FilePartInput represents file input for a message.
type FilePartInput struct {
	Type     string  `json:"type"` // "file"
	Mime     string  `json:"mime"`
	URL      string  `json:"url"`
	Filename *string `json:"filename,omitempty"`
}

// PromptRequest is the request body for sending a message.
type PromptRequest struct {
	Parts     []interface{}       `json:"parts"` // TextPartInput or FilePartInput
	MessageID *string             `json:"messageID,omitempty"`
	Model     *ModelInfo          `json:"model,omitempty"`
	Agent     *string             `json:"agent,omitempty"`
	NoReply   *bool               `json:"noReply,omitempty"`
	System    *string             `json:"system,omitempty"`
	Tools     map[string]bool     `json:"tools,omitempty"`
}

// ForkRequest is the request body for forking a session.
type ForkRequest struct {
	MessageID *string `json:"messageID,omitempty"`
}

// RevertRequest is the request body for reverting a session.
type RevertRequest struct {
	MessageID string  `json:"messageID"`
	PartID    *string `json:"partID,omitempty"`
}

// HealthResponse is the response from the health endpoint.
type HealthResponse struct {
	Status          string `json:"status"`
	AgentConfigured bool   `json:"agent_configured"`
}

// MCP Server types

// MCPServerStatus represents the connection status of an MCP server.
type MCPServerStatus string

const (
	MCPStatusConnected    MCPServerStatus = "connected"
	MCPStatusDisconnected MCPServerStatus = "disconnected"
	MCPStatusError        MCPServerStatus = "error"
	MCPStatusConnecting   MCPServerStatus = "connecting"
)

// MCPTool represents a tool provided by an MCP server.
type MCPTool struct {
	Name        string                 `json:"name"`
	Description string                 `json:"description"`
	InputSchema map[string]interface{} `json:"inputSchema"`
	Examples    []string               `json:"examples,omitempty"`
}

// MCPServer represents an MCP server and its available tools.
type MCPServer struct {
	Name        string          `json:"name"`
	Description string          `json:"description"`
	Status      MCPServerStatus `json:"status"`
	URL         string          `json:"url,omitempty"`
	Tools       []MCPTool       `json:"tools"`
	LastError   string          `json:"lastError,omitempty"`
	ConnectedAt *float64        `json:"connectedAt,omitempty"`
}

// MCPServersResponse is the response from the MCP servers endpoint.
type MCPServersResponse struct {
	Servers []MCPServer `json:"servers"`
}

// Helper functions

// Now returns the current time as a Unix timestamp (float64).
func Now() float64 {
	return float64(time.Now().UnixNano()) / 1e9
}
