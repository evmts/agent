package app

import "github.com/williamcory/agent/sdk/agent"

// Internal message types for the app
type healthCheckMsg struct {
	healthy bool
	err     error
}

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
