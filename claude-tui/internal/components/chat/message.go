package chat

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/glamour"
	"github.com/charmbracelet/lipgloss"
	"claude-tui/internal/styles"
)

// Role represents who sent the message
type Role string

const (
	RoleUser      Role = "user"
	RoleAssistant Role = "assistant"
)

// Message represents a chat message
type Message struct {
	Role        Role
	Content     string
	IsStreaming bool
}

// ToolEvent represents a tool being used by the assistant
type ToolEvent struct {
	Tool      string
	Input     map[string]any
	Output    string
	Completed bool
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
		sb.WriteString("\n")
	}

	// Render content
	content := m.Content
	if m.Role == RoleAssistant && content != "" {
		// Use glamour for markdown rendering
		rendered, err := renderMarkdown(content, width-4)
		if err == nil {
			content = strings.TrimSpace(rendered)
		}
	}

	// Add streaming cursor
	if m.IsStreaming {
		content += styles.StreamingCursor.Render("▊")
	}

	// Apply message style
	switch m.Role {
	case RoleUser:
		sb.WriteString(styles.UserMessage.Width(width - 2).Render(content))
	case RoleAssistant:
		sb.WriteString(styles.AssistantMessage.Width(width - 2).Render(content))
	}

	return sb.String()
}

// Render renders a tool event
func (t ToolEvent) Render(width int) string {
	var status string
	if t.Completed {
		status = styles.ToolStatus.Render("✓")
	} else {
		status = styles.ToolStatus.Render("...")
	}

	// Format input based on tool type
	var inputStr string
	switch t.Tool {
	case "Read":
		if path, ok := t.Input["file_path"].(string); ok {
			inputStr = truncate(path, 50)
		}
	case "Bash":
		if cmd, ok := t.Input["command"].(string); ok {
			inputStr = truncate(cmd, 50)
		}
	case "Glob", "Grep":
		if pattern, ok := t.Input["pattern"].(string); ok {
			inputStr = truncate(pattern, 50)
		}
	case "Edit":
		if path, ok := t.Input["file_path"].(string); ok {
			inputStr = truncate(path, 50)
		}
	case "Write":
		if path, ok := t.Input["file_path"].(string); ok {
			inputStr = truncate(path, 50)
		}
	default:
		inputStr = fmt.Sprintf("%v", t.Input)
		inputStr = truncate(inputStr, 50)
	}

	toolName := styles.ToolName.Render(t.Tool)
	return styles.ToolEvent.Render(fmt.Sprintf("%s %s %s", status, toolName, inputStr))
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

// ChatItem represents either a message or tool event in the chat
type ChatItem interface {
	Render(width int) string
}

// Ensure Message and ToolEvent implement ChatItem
var _ ChatItem = Message{}
var _ ChatItem = ToolEvent{}

// HelpText returns the help text shown at the bottom
func HelpText() string {
	return lipgloss.NewStyle().
		Foreground(styles.Muted).
		Render("Enter: send • Ctrl+C: quit • Shift+Enter: newline")
}
