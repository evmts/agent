package client

// ChatRequest is the request body for the /chat endpoint
type ChatRequest struct {
	Message        string  `json:"message"`
	ConversationID *string `json:"conversation_id,omitempty"`
}

// SSE Event payloads
type TokenEvent struct {
	Content string `json:"content"`
}

type ToolUseEvent struct {
	Tool  string         `json:"tool"`
	Input map[string]any `json:"input"`
}

type ToolResultEvent struct {
	Tool   string `json:"tool"`
	Output string `json:"output"`
}

type DoneEvent struct {
	ConversationID string `json:"conversation_id"`
}

type ErrorEvent struct {
	Message string `json:"message"`
}
