package agent

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

// ToolState represents the state of a tool execution.
type ToolState struct {
	Status   string                 `json:"status"` // "pending", "running", "completed"
	Input    map[string]interface{} `json:"input"`
	Raw      string                 `json:"raw,omitempty"`
	Output   string                 `json:"output,omitempty"`
	Title    *string                `json:"title,omitempty"`
	Metadata map[string]interface{} `json:"metadata,omitempty"`
	Time     *PartTime              `json:"time,omitempty"`
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
