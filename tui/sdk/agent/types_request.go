package agent

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
	Parts     []interface{}   `json:"parts"` // TextPartInput or FilePartInput
	MessageID *string         `json:"messageID,omitempty"`
	Model     *ModelInfo      `json:"model,omitempty"`
	Agent     *string         `json:"agent,omitempty"`
	NoReply   *bool           `json:"noReply,omitempty"`
	System    *string         `json:"system,omitempty"`
	Tools     map[string]bool `json:"tools,omitempty"`
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
