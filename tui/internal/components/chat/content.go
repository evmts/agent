package chat

import (
	"strings"

	"github.com/williamcory/agent/sdk/agent"
)

// LoadMessages loads messages from API response
func (m *Model) LoadMessages(messages []agent.MessageWithParts) {
	m.messages = []Message{}
	m.currentParts = make(map[string]agent.Part)

	for _, msg := range messages {
		role := RoleUser
		if msg.Info.IsAssistant() {
			role = RoleAssistant
		}

		m.messages = append(m.messages, Message{
			Role:        role,
			Parts:       msg.Parts,
			IsStreaming: false,
			Info:        &msg.Info,
		})
	}

	m.updateContent()
}

// AddUserMessage adds a user message to the chat
func (m *Model) AddUserMessage(content string) {
	// Create a simple text part for user message
	part := agent.Part{
		Type: "text",
		Text: content,
	}

	m.messages = append(m.messages, Message{
		Role:        RoleUser,
		Parts:       []agent.Part{part},
		IsStreaming: false,
	})
	m.updateContent()
}

// AddShellOutput adds shell command output to the chat as a system message
func (m *Model) AddShellOutput(output string) {
	// Create a text part for shell output with code formatting
	formattedOutput := "```\n" + output + "\n```"
	part := agent.Part{
		Type: "text",
		Text: formattedOutput,
	}

	m.messages = append(m.messages, Message{
		Role:        RoleAssistant,
		Parts:       []agent.Part{part},
		IsStreaming: false,
	})
	m.updateContent()
}

// updateContent rebuilds the viewport content from messages
func (m *Model) updateContent() {
	var content strings.Builder

	for i, msg := range m.messages {
		content.WriteString(msg.RenderWithOptions(m.width, m.showThinking))
		if i < len(m.messages)-1 {
			content.WriteString("\n")
		}
	}

	m.viewport.SetContent(content.String())
	m.viewport.GotoBottom()
}
