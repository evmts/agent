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

// renderToolPartEnhanced renders tool with Claude Code style formatting
// Uses tree structure with └ character for child results
func renderToolPartEnhanced(part agent.Part, width int, opts MessageOptions, index int) string {
	if part.State == nil {
		return ""
	}

	theme := styles.GetCurrentTheme()
	state := part.State

	// Status indicator - Claude Code style
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
		status = "●"
		statusStyle = lipgloss.NewStyle().Foreground(theme.Success)
	case "failed":
		status = "✗"
		statusStyle = lipgloss.NewStyle().Foreground(theme.Error)
	default:
		status = "○"
		statusStyle = lipgloss.NewStyle().Foreground(theme.Muted)
	}

	// Format tool name with parentheses - Claude Code style: ToolName(argument)
	toolNameStyle := lipgloss.NewStyle().
		Foreground(theme.Success).
		Bold(true)

	inputStr := formatToolInputForHeader(part.Tool, state.Input)
	if state.Title != nil && *state.Title != "" {
		inputStr = *state.Title
	}

	// Format as: ● ToolName(argument)
	header := fmt.Sprintf("%s %s", statusStyle.Render(status), toolNameStyle.Render(part.Tool+"("+inputStr+")"))

	var result strings.Builder
	result.WriteString(header)

	// Tree branch character for child items (└)
	treeChar := "└"
	treeStyle := lipgloss.NewStyle().Foreground(theme.Muted)

	// Show output summary in tree format
	if state.Status == "completed" && state.Output != "" {
		output := state.Output
		lines := strings.Split(strings.TrimSpace(output), "\n")

		// Format output summary based on tool type
		summary := formatToolOutputSummary(part.Tool, state.Input, output, lines)
		if summary != "" {
			summaryStyle := lipgloss.NewStyle().Foreground(theme.TextSecondary)
			result.WriteString("\n")
			result.WriteString(treeStyle.Render(treeChar + " "))
			result.WriteString(summaryStyle.Render(summary))
		}

		// For tools that list files (Glob, Grep), show file paths
		if (part.Tool == "Glob" || part.Tool == "Grep" || part.Tool == "Search") && len(lines) > 0 {
			maxFiles := 10
			fileStyle := lipgloss.NewStyle().Foreground(theme.Success)
			for i, line := range lines {
				if i >= maxFiles {
					result.WriteString("\n")
					moreStyle := lipgloss.NewStyle().Foreground(theme.Muted).Italic(true)
					result.WriteString(moreStyle.Render(fmt.Sprintf("  ... and %d more files", len(lines)-maxFiles)))
					break
				}
				if strings.TrimSpace(line) != "" {
					result.WriteString("\n")
					result.WriteString("  ")
					result.WriteString(fileStyle.Render(strings.TrimSpace(line)))
				}
			}
		}
	} else if state.Status == "running" {
		// Show running state summary
		summaryStyle := lipgloss.NewStyle().Foreground(theme.Muted).Italic(true)
		result.WriteString("\n")
		result.WriteString(treeStyle.Render(treeChar + " "))
		result.WriteString(summaryStyle.Render("Running..."))
	}

	return result.String()
}

// formatToolInputForHeader formats tool input for the header display
func formatToolInputForHeader(tool string, input map[string]interface{}) string {
	if input == nil {
		return ""
	}

	switch tool {
	case "Read":
		if path, ok := input["file_path"].(string); ok {
			return truncate(path, 60)
		}
	case "Bash":
		if cmd, ok := input["command"].(string); ok {
			// Show first line only for bash commands
			lines := strings.Split(cmd, "\n")
			return truncate(lines[0], 50)
		}
	case "Glob":
		if pattern, ok := input["pattern"].(string); ok {
			return fmt.Sprintf("pattern: %q", truncate(pattern, 40))
		}
	case "Grep", "Search":
		if pattern, ok := input["pattern"].(string); ok {
			return fmt.Sprintf("pattern: %q", truncate(pattern, 40))
		}
	case "Edit":
		if path, ok := input["file_path"].(string); ok {
			return truncate(path, 60)
		}
	case "Write":
		if path, ok := input["file_path"].(string); ok {
			return truncate(path, 60)
		}
	case "WebFetch":
		if url, ok := input["url"].(string); ok {
			return truncate(url, 50)
		}
	case "WebSearch":
		if query, ok := input["query"].(string); ok {
			return fmt.Sprintf("query: %q", truncate(query, 40))
		}
	case "Task":
		if desc, ok := input["description"].(string); ok {
			return truncate(desc, 50)
		}
	}

	return ""
}

// formatToolOutputSummary creates a summary line for tool output
func formatToolOutputSummary(tool string, input map[string]interface{}, output string, lines []string) string {
	switch tool {
	case "Read":
		lineCount := len(lines)
		return fmt.Sprintf("Read %d lines", lineCount)
	case "Glob":
		return fmt.Sprintf("Found %d files", len(lines))
	case "Grep", "Search":
		return fmt.Sprintf("Found %d files", len(lines))
	case "Bash":
		if len(output) == 0 {
			return "Command completed"
		}
		return fmt.Sprintf("%d lines of output", len(lines))
	case "Edit":
		return "Edit applied"
	case "Write":
		return "File written"
	case "WebFetch":
		return fmt.Sprintf("Fetched %d bytes", len(output))
	case "WebSearch":
		return fmt.Sprintf("Found %d results", len(lines))
	default:
		if len(output) > 0 {
			return fmt.Sprintf("%d lines of output", len(lines))
		}
		return "Completed"
	}
}

// renderReasoningPart renders thinking/reasoning content - Claude Code style
func renderReasoningPart(part agent.Part, width int, showThinking bool) string {
	if part.Text == "" {
		return ""
	}

	theme := styles.GetCurrentTheme()

	// If showThinking is false, show collapsed indicator - Claude Code style
	if !showThinking {
		// Claude Code style: ∴ Thought for Xs (ctrl+o to show thinking)
		collapsedStyle := lipgloss.NewStyle().
			Foreground(theme.Muted).
			Italic(true)
		symbolStyle := lipgloss.NewStyle().
			Foreground(theme.Muted)
		hintStyle := lipgloss.NewStyle().
			Foreground(theme.Muted)

		return symbolStyle.Render("∴ ") + collapsedStyle.Render("Thought ") + hintStyle.Render("(ctrl+o to show thinking)")
	}

	// Show expanded thinking - Claude Code style
	symbolStyle := lipgloss.NewStyle().
		Foreground(theme.Muted)
	headerStyle := lipgloss.NewStyle().
		Foreground(theme.Muted).
		Italic(true)
	header := symbolStyle.Render("∴ ") + headerStyle.Render("Thinking...")

	// Content style - dimmed and italic
	contentStyle := lipgloss.NewStyle().
		Foreground(theme.Muted).
		Italic(true).
		PaddingLeft(2).
		Width(width - 4)
	content := contentStyle.Render(part.Text)

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
