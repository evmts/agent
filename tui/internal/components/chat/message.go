package chat

import (
	"fmt"
	"strings"
	"time"

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

// MessageOptions contains rendering options
type MessageOptions struct {
	ShowThinking   bool
	ShowTimestamps bool
	ExpandedTools  map[string]bool // Track which tools are expanded
}

// Message represents a chat message with its parts
type Message struct {
	Role        Role
	Parts       []agent.Part
	IsStreaming bool
	Info        *agent.Message // Original message info
	Timestamp   time.Time      // When the message was created
}

// Render renders a message with the given width
func (m Message) Render(width int) string {
	return m.RenderWithOptions(width, false)
}

// RenderWithOptions renders a message with the given width and options
func (m Message) RenderWithOptions(width int, showThinking bool) string {
	opts := MessageOptions{
		ShowThinking:   showThinking,
		ShowTimestamps: false, // Default off
		ExpandedTools:  make(map[string]bool),
	}
	return m.RenderWithFullOptions(width, opts)
}

// RenderWithFullOptions renders a message with full options control
func (m Message) RenderWithFullOptions(width int, opts MessageOptions) string {
	var sb strings.Builder
	theme := styles.GetCurrentTheme()

	// Build header line with role + optional timestamp
	var headerParts []string

	switch m.Role {
	case RoleUser:
		headerParts = append(headerParts, styles.UserLabel().Render("You"))
	case RoleAssistant:
		headerParts = append(headerParts, styles.AssistantLabel().Render("Assistant"))
		// Add model info if available
		if m.Info != nil && m.Info.ModelID != "" {
			modelStyle := lipgloss.NewStyle().Foreground(theme.Muted).Italic(true)
			headerParts = append(headerParts, modelStyle.Render(fmt.Sprintf("(%s)", m.Info.ModelID)))
		}
	}

	// Add timestamp if enabled
	if opts.ShowTimestamps && !m.Timestamp.IsZero() {
		timestampStyle := lipgloss.NewStyle().Foreground(theme.Muted)
		headerParts = append(headerParts, timestampStyle.Render(formatMessageTime(m.Timestamp)))
	}

	sb.WriteString(strings.Join(headerParts, " "))
	sb.WriteString("\n")

	// Count tool parts for collapsible display
	toolCount := 0
	for _, part := range m.Parts {
		if part.IsTool() {
			toolCount++
		}
	}

	// Render all parts
	for i, part := range m.Parts {
		partView := renderPartWithOptions(part, width-4, opts, i)
		if partView != "" {
			sb.WriteString(partView)
			sb.WriteString("\n")
		}
	}

	// Add streaming cursor
	if m.IsStreaming {
		sb.WriteString(styles.StreamingCursor().Render("▊"))
	}

	return sb.String()
}

// formatMessageTime formats a timestamp for display
func formatMessageTime(t time.Time) string {
	now := time.Now()
	diff := now.Sub(t)

	switch {
	case diff < time.Minute:
		return "just now"
	case diff < time.Hour:
		return fmt.Sprintf("%dm ago", int(diff.Minutes()))
	case diff < 24*time.Hour:
		return t.Format("3:04 PM")
	default:
		return t.Format("Jan 2, 3:04 PM")
	}
}

// renderPartWithOptions renders a part with full options
func renderPartWithOptions(part agent.Part, width int, opts MessageOptions, index int) string {
	switch {
	case part.IsText():
		return renderTextPartEnhanced(part, width)
	case part.IsReasoning():
		return renderReasoningPart(part, width, opts.ShowThinking)
	case part.IsTool():
		return renderToolPartEnhanced(part, width, opts, index)
	case part.IsFile():
		return renderFilePart(part, width)
	default:
		return ""
	}
}

// renderPart renders a single part based on its type
func renderPart(part agent.Part, width int, showThinking bool) string {
	switch {
	case part.IsText():
		return renderTextPart(part, width)
	case part.IsReasoning():
		return renderReasoningPart(part, width, showThinking)
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

	// Render markdown using shared renderer
	rendered := RenderMarkdown(content)
	content = strings.TrimSpace(rendered)

	return styles.AssistantMessage().Width(width).Render(content)
}

// renderTextPartEnhanced renders text with code block indicators
func renderTextPartEnhanced(part agent.Part, width int) string {
	content := part.Text
	if content == "" {
		return ""
	}

	theme := styles.GetCurrentTheme()

	// Check for code blocks and add copy indicator
	hasCodeBlock := strings.Contains(content, "```")

	// Render markdown using shared renderer
	rendered := RenderMarkdown(content)
	content = strings.TrimSpace(rendered)

	// Add code block indicator if present
	if hasCodeBlock {
		copyHint := lipgloss.NewStyle().
			Foreground(theme.Muted).
			Italic(true).
			Render("  [Code block - select to copy]")
		content = content + "\n" + copyHint
	}

	return styles.AssistantMessage().Width(width).Render(content)
}

// renderToolPartEnhanced renders tool with better formatting
func renderToolPartEnhanced(part agent.Part, width int, opts MessageOptions, index int) string {
	if part.State == nil {
		return ""
	}

	theme := styles.GetCurrentTheme()
	state := part.State

	// Status indicator with better icons
	var status string
	var statusStyle lipgloss.Style

	switch state.Status {
	case "pending":
		status = "○"
		statusStyle = lipgloss.NewStyle().Foreground(theme.Muted)
	case "running":
		status = "●"
		statusStyle = lipgloss.NewStyle().Foreground(theme.Warning)
	case "completed":
		status = "✓"
		statusStyle = lipgloss.NewStyle().Foreground(theme.Success)
	case "failed":
		status = "✗"
		statusStyle = lipgloss.NewStyle().Foreground(theme.Error)
	default:
		status = "?"
		statusStyle = lipgloss.NewStyle().Foreground(theme.Muted)
	}

	// Format tool name with better styling
	toolNameStyle := lipgloss.NewStyle().
		Foreground(theme.Accent).
		Bold(true)
	toolName := toolNameStyle.Render(part.Tool)

	// Input description
	inputStr := formatToolInput(part.Tool, state.Input)
	if state.Title != nil && *state.Title != "" {
		inputStr = *state.Title
	}
	inputStyle := lipgloss.NewStyle().Foreground(theme.TextSecondary)
	inputDisplay := inputStyle.Render(inputStr)

	// Build header
	header := fmt.Sprintf("%s %s %s", statusStyle.Render(status), toolName, inputDisplay)

	// Tool container style
	toolContainerStyle := lipgloss.NewStyle().
		BorderStyle(lipgloss.RoundedBorder()).
		BorderForeground(theme.Border).
		BorderLeft(true).
		BorderRight(false).
		BorderTop(false).
		BorderBottom(false).
		PaddingLeft(1).
		Width(width - 2)

	// Show output if completed
	if state.Status == "completed" && state.Output != "" {
		output := state.Output

		// Truncate long output with "Show more" indicator
		maxLines := 5
		lines := strings.Split(output, "\n")
		truncated := false
		if len(lines) > maxLines {
			lines = lines[:maxLines]
			truncated = true
		}
		output = strings.Join(lines, "\n")

		// Limit total length
		if len(output) > 500 {
			output = output[:500]
			truncated = true
		}

		outputStyle := lipgloss.NewStyle().
			Foreground(theme.Muted).
			Width(width - 8)

		outputView := outputStyle.Render(output)

		if truncated {
			moreStyle := lipgloss.NewStyle().
				Foreground(theme.Accent).
				Italic(true)
			outputView += "\n" + moreStyle.Render("  ... (output truncated)")
		}

		content := header + "\n" + outputView
		return toolContainerStyle.Render(content)
	}

	return toolContainerStyle.Render(header)
}

// renderReasoningPart renders thinking/reasoning content
func renderReasoningPart(part agent.Part, width int, showThinking bool) string {
	if part.Text == "" {
		return ""
	}

	// If showThinking is false, show collapsed indicator
	if !showThinking {
		return ThinkingCollapsed().Render("[Thinking hidden - press Ctrl+T to show]")
	}

	// Style for reasoning - dimmed and italic
	reasoningStyle := ThinkingContainer()
	header := ThinkingHeader().Render("Thinking...")
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
		statusStyle = styles.MutedText()
	case "running":
		status = "⚡"
		statusStyle = styles.StatusBarStreaming()
	case "completed":
		status = "✓"
		statusStyle = styles.ToolStatus()
	default:
		status = "?"
		statusStyle = styles.MutedText()
	}

	// Format tool name and input
	toolName := styles.ToolName().Render(part.Tool)
	inputStr := formatToolInput(part.Tool, state.Input)

	// Use title if available
	if state.Title != nil && *state.Title != "" {
		inputStr = *state.Title
	}

	header := fmt.Sprintf("%s %s %s", statusStyle.Render(status), toolName, inputStr)

	// Show output if completed and has output
	if state.Status == "completed" && state.Output != "" {
		outputStyle := lipgloss.NewStyle().
			Foreground(styles.GetCurrentTheme().Muted).
			PaddingLeft(4)

		output := state.Output
		if len(output) > 200 {
			output = output[:200] + "..."
		}
		// Replace newlines for compact display
		output = strings.ReplaceAll(output, "\n", " ")
		output = truncate(output, width-8)

		return styles.ToolEvent().Render(header) + "\n" + outputStyle.Render(output)
	}

	return styles.ToolEvent().Render(header)
}

// renderFilePart renders file attachments
func renderFilePart(part agent.Part, width int) string {
	fileStyle := lipgloss.NewStyle().
		Foreground(styles.GetCurrentTheme().Secondary).
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
		Foreground(styles.GetCurrentTheme().Muted).
		Render("Enter: send • Ctrl+C: quit • Ctrl+N: new session")
}
