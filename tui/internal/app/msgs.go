package app

import (
	"github.com/williamcory/agent/sdk/agent"
	"tui/internal/config"
)

// Internal message types for the app
// Note: healthCheckMsg is defined in app.go

type sessionCreatedMsg struct {
	session *agent.Session
}

type messagesLoadedMsg struct {
	messages []agent.MessageWithParts
}

type sessionsLoadedMsg struct {
	sessions []agent.Session
}

type diffLoadedMsg struct {
	diffs []agent.FileDiff
}

type sessionForkedMsg struct {
	session *agent.Session
}

type sessionRevertedMsg struct {
	session *agent.Session
}

type showSessionListMsg struct{}

type gitBranchMsg struct {
	branch string
}

type sessionRenamedMsg struct {
	session *agent.Session
}

type shellCommandResultMsg struct {
	output string
	err    error
}

type editorResultMsg struct {
	content string
	err     error
}

type resumeCheckMsg struct {
	hasSession bool
	info       *config.LastSessionInfo
	preference config.ResumePreference
}

type resumeLoadSessionMsg struct {
	sessionID string
}

type resumeCreateNewSessionMsg struct{}

type resumeShowSessionListMsg struct{}
