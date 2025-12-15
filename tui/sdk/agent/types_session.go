package agent

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
