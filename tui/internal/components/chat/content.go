package chat

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/lipgloss"
	"github.com/williamcory/agent/sdk/agent"
	"tui/internal/styles"
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
	// Extract code blocks from all messages
	m.codeBlocks.ExtractCodeBlocks(m.messages)

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

	// Render messages with search highlighting and code block selection
	for i := startIdx; i < len(m.messages); i++ {
		// Determine if this message contains the current match
		currentMatchIdx := m.search.GetMatchMessageIndex()
		isCurrentMatchMessage := m.search.Active && currentMatchIdx == i

		// Render message with code block state
		content.WriteString(m.renderMessageWithCodeBlocks(i, isCurrentMatchMessage))
		if i < len(m.messages)-1 {
			content.WriteString("\n")
		}
	}

	m.viewport.SetContent(content.String())
	m.viewport.GotoBottom()
}

// renderMessageWithCodeBlocks renders a message with code block highlighting
func (m *Model) renderMessageWithCodeBlocks(msgIdx int, isCurrentMatch bool) string {
	msg := m.messages[msgIdx]
	var sb strings.Builder
	theme := styles.GetCurrentTheme()

	// Build header (same as renderWithSearchInternal)
	var headerParts []string
	switch msg.Role {
	case RoleUser:
		headerParts = append(headerParts, styles.UserLabel().Render("You"))
	case RoleAssistant:
		headerParts = append(headerParts, styles.AssistantLabel().Render("Assistant"))
		if msg.Info != nil && msg.Info.ModelID != "" {
			modelStyle := lipgloss.NewStyle().Foreground(theme.Muted).Italic(true)
			headerParts = append(headerParts, modelStyle.Render(fmt.Sprintf("(%s)", msg.Info.ModelID)))
		}
	}

	sb.WriteString(strings.Join(headerParts, " "))

	// Add token info for assistant messages
	if msg.Role == RoleAssistant && msg.Info != nil {
		tokenInfo := formatTokenInfo(msg.Info.Tokens, msg.Info.Cost, theme)
		if tokenInfo != "" {
			headerText := strings.Join(headerParts, " ")
			headerLen := lipgloss.Width(headerText)
			tokenInfoLen := lipgloss.Width(tokenInfo)
			padding := m.width - headerLen - tokenInfoLen - 2
			if padding > 0 {
				sb.WriteString(strings.Repeat(" ", padding))
			}
			sb.WriteString(tokenInfo)
		}
	}

	sb.WriteString("\n")

	// Render parts with code block highlighting
	for partIdx, part := range msg.Parts {
		partView := m.renderPartWithCodeBlocks(part, msgIdx, partIdx, isCurrentMatch)
		if partView != "" {
			sb.WriteString(partView)
			sb.WriteString("\n")
		}
	}

	// Add streaming cursor
	if msg.IsStreaming {
		sb.WriteString(styles.StreamingCursor().Render("▊"))
	}

	return sb.String()
}

// renderPartWithCodeBlocks renders a part with code block highlighting
func (m *Model) renderPartWithCodeBlocks(part agent.Part, msgIdx, partIdx int, isCurrentMatch bool) string {
	if part.IsText() {
		return m.renderTextPartWithCodeBlocks(part, msgIdx, partIdx, isCurrentMatch)
	} else if part.IsReasoning() {
		return renderReasoningPartWithSearch(part, m.width-4, m.showThinking, m.search.Query, isCurrentMatch)
	} else if part.IsTool() {
		opts := MessageOptions{
			ShowThinking:   m.showThinking,
			ShowTimestamps: false,
			ExpandedTools:  make(map[string]bool),
		}
		return renderToolPartWithSearch(part, m.width-4, opts, partIdx, m.search.Query, isCurrentMatch)
	} else if part.IsFile() {
		return renderFilePart(part, m.width-4)
	}
	return ""
}

// renderTextPartWithCodeBlocks renders text with code block highlighting
func (m *Model) renderTextPartWithCodeBlocks(part agent.Part, msgIdx, partIdx int, isCurrentMatch bool) string {
	content := part.Text
	if content == "" {
		return ""
	}

	theme := styles.GetCurrentTheme()

	// Render markdown
	rendered := RenderMarkdown(content)
	content = strings.TrimSpace(rendered)

	// Apply search highlighting if active
	if m.search.Query != "" {
		content = HighlightMatches(content, m.search.Query, isCurrentMatch)
	}

	// Check if there's a selected code block in this part
	hasSelectedBlock := false
	if block := m.codeBlocks.GetCurrentBlock(); block != nil {
		if block.MessageIndex == msgIdx && block.PartIndex == partIdx {
			hasSelectedBlock = true
		}
	}

	// Add code block hint
	if hasSelectedBlock {
		selectedHint := lipgloss.NewStyle().
			Foreground(theme.Accent).
			Bold(true).
			Render("  [Code block selected - press 'c' to copy]")
		content = content + "\n" + selectedHint
	} else if strings.Contains(part.Text, "```") {
		// Show navigation hint
		copyHint := lipgloss.NewStyle().
			Foreground(theme.Muted).
			Italic(true).
			Render("  [Code block - use '[' and ']' to navigate]")
		content = content + "\n" + copyHint
	}

	return styles.AssistantMessage().Width(m.width - 4).Render(content)
}
