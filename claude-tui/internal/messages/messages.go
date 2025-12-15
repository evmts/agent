package messages

// SSE Events from backend
type TokenMsg struct {
	Content string
}

type ToolUseMsg struct {
	Tool  string
	Input map[string]any
}

type ToolResultMsg struct {
	Tool   string
	Output string
}

type DoneMsg struct {
	ConversationID string
}

type ErrorMsg struct {
	Message string
}

// Internal app messages
type StreamStartMsg struct{}
type StreamEndMsg struct{}
