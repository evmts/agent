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

	// Determine which messages to render based on compact mode
	startIdx := 0
	hiddenCount := 0

	if m.compactMode && !m.compactExpanded && len(m.messages) > m.compactCount {
		// Show only the last N messages
		startIdx = len(m.messages) - m.compactCount
		hiddenCount = startIdx

		// Render compact header for hidden messages
		content.WriteString(renderCompactHeader(hiddenCount, m.width, false))
	} else if m.compactMode && m.compactExpanded && len(m.messages) > m.compactCount {
		// Show all messages with expanded header
		hiddenCount = len(m.messages) - m.compactCount
		content.WriteString(renderCompactHeader(hiddenCount, m.width, true))
	}

	// Render messages with search highlighting
	for i := startIdx; i < len(m.messages); i++ {
		// Determine if this message contains the current match
		currentMatchIdx := m.search.GetMatchMessageIndex()
		isCurrentMatchMessage := m.search.Active && currentMatchIdx == i

		content.WriteString(m.messages[i].RenderWithSearch(m.width, m.showThinking, m.search.Query, isCurrentMatchMessage))
		if i < len(m.messages)-1 {
			content.WriteString("\n")
		}
	}

	m.viewport.SetContent(content.String())
	m.viewport.GotoBottom()
}
