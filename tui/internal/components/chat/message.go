package chat

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/glamour"
	"github.com/charmbracelet/lipgloss"
	"github.com/williamcory/agent/sdk/agent"
	"tui/internal/styles"
)

// Role represents who sent the message
type Role string

const (
	RoleUser      Role = "user"
	RoleAssistant Role = "assistant"
)

// Message represents a chat message with its parts
type Message struct {
	Role        Role
	Parts       []agent.Part
	IsStreaming bool
	Info        *agent.Message // Original message info
}

// Render renders a message with the given width
func (m Message) Render(width int) string {
	var sb strings.Builder

	// Add role label
	switch m.Role {
	case RoleUser:
		sb.WriteString(styles.UserLabel.Render("You"))
		sb.WriteString("\n")
	case RoleAssistant:
		sb.WriteString(styles.AssistantLabel.Render("Assistant"))
		// Add model info if available
		if m.Info != nil && m.Info.ModelID != "" {
			modelInfo := styles.MutedText.Render(fmt.Sprintf(" (%s)", m.Info.ModelID))
			sb.WriteString(modelInfo)
		}
		sb.WriteString("\n")
	}

	// Render all parts
	for _, part := range m.Parts {
		partView := renderPart(part, width-4)
		if partView != "" {
			sb.WriteString(partView)
			sb.WriteString("\n")
		}
	}

	// Add streaming cursor
	if m.IsStreaming {
		sb.WriteString(styles.StreamingCursor.Render("▊"))
	}

	return sb.String()
}

// renderPart renders a single part based on its type
func renderPart(part agent.Part, width int) string {
	switch {
	case part.IsText():
		return renderTextPart(part, width)
	case part.IsReasoning():
		return renderReasoningPart(part, width)
	case part.IsTool():
		return renderToolPart(part, width)
	case part.IsFile():
		return renderFilePart(part, width)
	default:
		return ""
	}
}

// renderTextPart renders text content with markdown
func renderTextPart(part agent.Part, width int) string {
	content := part.Text
	if content == "" {
		return ""
	}

	// Render markdown
	rendered, err := renderMarkdown(content, width)
	if err == nil {
		content = strings.TrimSpace(rendered)
	}

	return styles.AssistantMessage.Width(width).Render(content)
}

// renderReasoningPart renders thinking/reasoning content
func renderReasoningPart(part agent.Part, width int) string {
	if part.Text == "" {
		return ""
	}

	// Style for reasoning - dimmed and italic
	reasoningStyle := lipgloss.NewStyle().
		Foreground(styles.Muted).
		Italic(true).
		PaddingLeft(2).
		Border(lipgloss.NormalBorder(), false, false, false, true).
		BorderForeground(styles.Muted)

	header := styles.MutedBold.Render("Thinking...")
	content := reasoningStyle.Width(width - 4).Render(part.Text)

	return header + "\n" + content
}

// renderToolPart renders tool invocation and results
func renderToolPart(part agent.Part, width int) string {
	if part.State == nil {
		return ""
	}

	state := part.State
	var status string
	var statusStyle lipgloss.Style

	switch state.Status {
	case "pending":
		status = "⏳"
		statusStyle = styles.MutedText
	case "running":
		status = "⚡"
		statusStyle = styles.StatusBarStreaming
	case "completed":
		status = "✓"
		statusStyle = styles.ToolStatus
	default:
		status = "?"
		statusStyle = styles.MutedText
	}

	// Format tool name and input
	toolName := styles.ToolName.Render(part.Tool)
	inputStr := formatToolInput(part.Tool, state.Input)

	// Use title if available
	if state.Title != nil && *state.Title != "" {
		inputStr = *state.Title
	}

	header := fmt.Sprintf("%s %s %s", statusStyle.Render(status), toolName, inputStr)

	// Show output if completed and has output
	if state.Status == "completed" && state.Output != "" {
		outputStyle := lipgloss.NewStyle().
			Foreground(styles.Muted).
			PaddingLeft(4)

		output := state.Output
		if len(output) > 200 {
			output = output[:200] + "..."
		}
		// Replace newlines for compact display
		output = strings.ReplaceAll(output, "\n", " ")
		output = truncate(output, width-8)

		return styles.ToolEvent.Render(header) + "\n" + outputStyle.Render(output)
	}

	return styles.ToolEvent.Render(header)
}

// renderFilePart renders file attachments
func renderFilePart(part agent.Part, width int) string {
	fileStyle := lipgloss.NewStyle().
		Foreground(styles.Secondary).
		Bold(true)

	name := "File"
	if part.Filename != nil {
		name = *part.Filename
	}

	return fileStyle.Render(fmt.Sprintf("📎 %s (%s)", name, part.Mime))
}

// formatToolInput formats tool input for display
func formatToolInput(tool string, input map[string]interface{}) string {
	if input == nil {
		return ""
	}

	switch tool {
	case "Read":
		if path, ok := input["file_path"].(string); ok {
			return truncate(path, 50)
		}
	case "Bash":
		if cmd, ok := input["command"].(string); ok {
			return truncate(cmd, 50)
		}
	case "Glob", "Grep":
		if pattern, ok := input["pattern"].(string); ok {
			return truncate(pattern, 50)
		}
	case "Edit", "Write":
		if path, ok := input["file_path"].(string); ok {
			return truncate(path, 50)
		}
	case "WebFetch":
		if url, ok := input["url"].(string); ok {
			return truncate(url, 50)
		}
	case "WebSearch":
		if query, ok := input["query"].(string); ok {
			return truncate(query, 50)
		}
	case "Task":
		if desc, ok := input["description"].(string); ok {
			return truncate(desc, 50)
		}
	}

	// Fallback
	return truncate(fmt.Sprintf("%v", input), 50)
}

// renderMarkdown renders markdown content for the terminal
func renderMarkdown(content string, width int) (string, error) {
	r, err := glamour.NewTermRenderer(
		glamour.WithAutoStyle(),
		glamour.WithWordWrap(width),
	)
	if err != nil {
		return content, err
	}
	return r.Render(content)
}

// truncate truncates a string to the given length
func truncate(s string, maxLen int) string {
	// Replace newlines with spaces for display
	s = strings.ReplaceAll(s, "\n", " ")
	if len(s) <= maxLen {
		return s
	}
	return s[:maxLen-3] + "..."
}

// ChatItem represents a renderable item in the chat
type ChatItem interface {
	Render(width int) string
}

// Ensure Message implements ChatItem
var _ ChatItem = Message{}

// HelpText returns the help text shown at the bottom
func HelpText() string {
	return lipgloss.NewStyle().
		Foreground(styles.Muted).
		Render("Enter: send • Ctrl+C: quit • Ctrl+N: new session")
}
