package chat

import (
	"fmt"
	"strings"
	"time"

	"github.com/charmbracelet/lipgloss"
	"github.com/williamcory/agent/sdk/agent"
	"github.com/williamcory/agent/tui/internal/components/progress"
	"github.com/williamcory/agent/tui/internal/styles"
)

// Role represents who sent the message
type Role string

const (
	RoleUser      Role = "user"
	RoleAssistant Role = "assistant"
)

// Token threshold constants for color coding
const (
	TOKEN_THRESHOLD_WARNING = 100000 // Yellow warning at 100k tokens
	TOKEN_THRESHOLD_ERROR   = 180000 // Red error at 180k tokens
)

// formatTokenCount formats token count with k suffix for thousands
func formatTokenCount(count int) string {
	if count < 1000 {
		return fmt.Sprintf("%d", count)
	}
	if count < 1000000 {
		return fmt.Sprintf("%.1fk", float64(count)/1000.0)
	}
	return fmt.Sprintf("%.1fM", float64(count)/1000000.0)
}

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

// RenderWithSearch renders a message with search highlighting
func (m Message) RenderWithSearch(width int, showThinking bool, searchQuery string, isCurrentMatch bool) string {
	opts := MessageOptions{
		ShowThinking:   showThinking,
		ShowTimestamps: false,
		ExpandedTools:  make(map[string]bool),
	}
	return m.renderWithSearchInternal(width, opts, searchQuery, isCurrentMatch)
}

// renderWithSearchInternal renders a message with search highlighting
func (m Message) renderWithSearchInternal(width int, opts MessageOptions, searchQuery string, isCurrentMatch bool) string {
	var sb strings.Builder
	theme := styles.GetCurrentTheme()

	// Build header line with role + optional timestamp + token info
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

	// Join the basic header parts
	sb.WriteString(strings.Join(headerParts, " "))

	// Add token info for assistant messages on the same line (right-aligned)
	if m.Role == RoleAssistant && m.Info != nil {
		tokenInfo := formatTokenInfo(m.Info.Tokens, m.Info.Cost, theme)
		if tokenInfo != "" {
			// Calculate space needed to right-align token info
			headerText := strings.Join(headerParts, " ")
			// Remove ANSI codes for accurate length calculation
			headerLen := lipgloss.Width(headerText)
			tokenInfoLen := lipgloss.Width(tokenInfo)

			// Add padding to push token info to the right
			// Leave some margin from the right edge
			padding := width - headerLen - tokenInfoLen - 2
			if padding > 0 {
				sb.WriteString(strings.Repeat(" ", padding))
			}
			sb.WriteString(tokenInfo)
		}
	}

	sb.WriteString("\n")

	// Render all parts with search highlighting
	for i, part := range m.Parts {
		partView := renderPartWithSearch(part, width-4, opts, i, searchQuery, isCurrentMatch)
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

// RenderWithFullOptions renders a message with full options control
func (m Message) RenderWithFullOptions(width int, opts MessageOptions) string {
	var sb strings.Builder
	theme := styles.GetCurrentTheme()

	// Build header line with role + optional timestamp + token info
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

	// Join the basic header parts
	sb.WriteString(strings.Join(headerParts, " "))

	// Add token info for assistant messages on the same line (right-aligned)
	if m.Role == RoleAssistant && m.Info != nil {
		tokenInfo := formatTokenInfo(m.Info.Tokens, m.Info.Cost, theme)
		if tokenInfo != "" {
			// Calculate space needed to right-align token info
			headerText := strings.Join(headerParts, " ")
			// Remove ANSI codes for accurate length calculation
			headerLen := lipgloss.Width(headerText)
			tokenInfoLen := lipgloss.Width(tokenInfo)

			// Add padding to push token info to the right
			// Leave some margin from the right edge
			padding := width - headerLen - tokenInfoLen - 2
			if padding > 0 {
				sb.WriteString(strings.Repeat(" ", padding))
			}
			sb.WriteString(tokenInfo)
		}
	}

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

// renderPartWithSearch renders a part with search highlighting
func renderPartWithSearch(part agent.Part, width int, opts MessageOptions, index int, searchQuery string, isCurrentMatch bool) string {
	switch {
	case part.IsText():
		return renderTextPartWithSearch(part, width, searchQuery, isCurrentMatch)
	case part.IsReasoning():
		return renderReasoningPartWithSearch(part, width, opts.ShowThinking, searchQuery, isCurrentMatch)
	case part.IsTool():
		return renderToolPartWithSearch(part, width, opts, index, searchQuery, isCurrentMatch)
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
		// Show progress if available
		if state.Progress != nil && state.Progress.Type != agent.ProgressNone {
			result.WriteString("\n")
			result.WriteString(treeStyle.Render(treeChar + " "))
			progressBar := progress.RenderToolProgress(*state.Progress, width)
			result.WriteString(progressBar)
		} else {
			// Show generic running state
			summaryStyle := lipgloss.NewStyle().Foreground(theme.Muted).Italic(true)
			result.WriteString("\n")
			result.WriteString(treeStyle.Render(treeChar + " "))
			result.WriteString(summaryStyle.Render("Running..."))
		}
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
	name := "File"
	if part.Filename != nil {
		name = *part.Filename
	}

	// Check if this is an image file
	if IsImageMimeType(part.Mime) {
		// Try to render image inline
		return RenderImage(part.URL, part.Mime, name, width)
	}

	// For non-image files, show as attachment
	fileStyle := lipgloss.NewStyle().
		Foreground(styles.GetCurrentTheme().Secondary).
		Bold(true)

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

// formatTokensWithColor formats token count with color based on threshold
func formatTokensWithColor(count int, theme *styles.Theme) string {
	formatted := formatTokenCount(count)
	style := lipgloss.NewStyle()

	switch {
	case count > 50000: // Error threshold
		style = style.Foreground(theme.Error)
	case count > 10000: // Warning threshold
		style = style.Foreground(theme.Warning)
	default:
		style = style.Foreground(theme.Muted)
	}

	return style.Render("↑ " + formatted + " tokens")
}

// formatCost formats a cost value with appropriate precision
func formatCost(cost float64) string {
	if cost < 0.01 {
		return fmt.Sprintf("$%.4f", cost)
	}
	return fmt.Sprintf("$%.3f", cost)
}

// formatTokenInfo creates a formatted token info string for message header
func formatTokenInfo(tokens *agent.TokenInfo, cost float64, theme *styles.Theme) string {
	if tokens == nil {
		return ""
	}

	var parts []string

	// Calculate total tokens
	totalTokens := tokens.Input + tokens.Output + tokens.Reasoning

	if totalTokens > 0 {
		// Add token count with color
		tokenStr := formatTokensWithColor(totalTokens, theme)
		parts = append(parts, tokenStr)
	}

	// Add cost if non-zero
	if cost > 0 {
		costStyle := lipgloss.NewStyle().Foreground(theme.Muted)
		costStr := costStyle.Render(formatCost(cost))
		parts = append(parts, costStr)
	}

	if len(parts) == 0 {
		return ""
	}

	// Join with middle dot separator
	separator := lipgloss.NewStyle().Foreground(theme.Muted).Render(" · ")
	return separator + strings.Join(parts, separator)
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

// renderCompactHeader renders the collapsed messages header
func renderCompactHeader(hiddenCount int, width int, expanded bool) string {
	theme := styles.GetCurrentTheme()

	// Arrow indicator (▶ when collapsed, ▼ when expanded)
	var arrow string
	if expanded {
		arrow = "▼"
	} else {
		arrow = "▶"
	}

	arrowStyle := lipgloss.NewStyle().
		Foreground(theme.Accent).
		Bold(true)

	// Message text
	messageStyle := lipgloss.NewStyle().
		Foreground(theme.TextSecondary).
		Italic(true)

	var messageText string
	if hiddenCount == 1 {
		messageText = "1 earlier message"
	} else {
		messageText = fmt.Sprintf("%d earlier messages", hiddenCount)
	}

	// Hint text
	hintStyle := lipgloss.NewStyle().
		Foreground(theme.Muted)

	var hintText string
	if expanded {
		hintText = "(press E to collapse)"
	} else {
		hintText = "(press E to expand)"
	}

	// Build the header line
	header := arrowStyle.Render(arrow+" ") +
		messageStyle.Render(messageText+" ") +
		hintStyle.Render(hintText)

	// Add border
	borderStyle := lipgloss.NewStyle().
		Foreground(theme.Border).
		Width(width)

	borderLine := borderStyle.Render(strings.Repeat("─", width))

	return header + "\n" + borderLine + "\n"
}

// renderTextPartWithSearch renders text with search highlighting
func renderTextPartWithSearch(part agent.Part, width int, searchQuery string, isCurrentMatch bool) string {
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

	// Apply search highlighting
	if searchQuery != "" {
		content = HighlightMatches(content, searchQuery, isCurrentMatch)
	}

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

// renderReasoningPartWithSearch renders thinking/reasoning content with search highlighting
func renderReasoningPartWithSearch(part agent.Part, width int, showThinking bool, searchQuery string, isCurrentMatch bool) string {
	if part.Text == "" {
		return ""
	}

	theme := styles.GetCurrentTheme()

	// If showThinking is false, show collapsed indicator
	if !showThinking {
		collapsedStyle := lipgloss.NewStyle().
			Foreground(theme.Muted).
			Italic(true)
		symbolStyle := lipgloss.NewStyle().
			Foreground(theme.Muted)
		hintStyle := lipgloss.NewStyle().
			Foreground(theme.Muted)

		return symbolStyle.Render("∴ ") + collapsedStyle.Render("Thought ") + hintStyle.Render("(ctrl+o to show thinking)")
	}

	// Show expanded thinking with search highlighting
	symbolStyle := lipgloss.NewStyle().
		Foreground(theme.Muted)
	headerStyle := lipgloss.NewStyle().
		Foreground(theme.Muted).
		Italic(true)
	header := symbolStyle.Render("∴ ") + headerStyle.Render("Thinking...")

	// Apply search highlighting to content
	thinkingText := part.Text
	if searchQuery != "" {
		thinkingText = HighlightMatches(thinkingText, searchQuery, isCurrentMatch)
	}

	// Content style - dimmed and italic
	contentStyle := lipgloss.NewStyle().
		Foreground(theme.Muted).
		Italic(true).
		PaddingLeft(2).
		Width(width - 4)
	content := contentStyle.Render(thinkingText)

	return header + "\n" + content
}

// renderToolPartWithSearch renders tool with search highlighting
func renderToolPartWithSearch(part agent.Part, width int, opts MessageOptions, index int, searchQuery string, isCurrentMatch bool) string {
	if part.State == nil {
		return ""
	}

	theme := styles.GetCurrentTheme()
	state := part.State

	// Status indicator
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

	// Format tool name with parentheses
	toolNameStyle := lipgloss.NewStyle().
		Foreground(theme.Success).
		Bold(true)

	inputStr := formatToolInputForHeader(part.Tool, state.Input)
	if state.Title != nil && *state.Title != "" {
		inputStr = *state.Title
	}

	// Apply search highlighting to tool name and input
	toolDisplay := part.Tool + "(" + inputStr + ")"
	if searchQuery != "" {
		toolDisplay = HighlightMatches(toolDisplay, searchQuery, isCurrentMatch)
	}

	header := fmt.Sprintf("%s %s", statusStyle.Render(status), toolNameStyle.Render(toolDisplay))

	var result strings.Builder
	result.WriteString(header)

	// Tree branch character for child items
	treeChar := "└"
	treeStyle := lipgloss.NewStyle().Foreground(theme.Muted)

	// Show output summary with search highlighting
	if state.Status == "completed" && state.Output != "" {
		output := state.Output
		lines := strings.Split(strings.TrimSpace(output), "\n")

		// Format output summary
		summary := formatToolOutputSummary(part.Tool, state.Input, output, lines)
		if summary != "" {
			summaryStyle := lipgloss.NewStyle().Foreground(theme.TextSecondary)
			result.WriteString("\n")
			result.WriteString(treeStyle.Render(treeChar + " "))
			result.WriteString(summaryStyle.Render(summary))
		}

		// For tools that list files, show file paths with highlighting
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
					lineText := strings.TrimSpace(line)
					if searchQuery != "" {
						lineText = HighlightMatches(lineText, searchQuery, isCurrentMatch)
					}
					result.WriteString(fileStyle.Render(lineText))
				}
			}
		}
	} else if state.Status == "running" {
		// Show progress if available
		if state.Progress != nil && state.Progress.Type != agent.ProgressNone {
			result.WriteString("\n")
			result.WriteString(treeStyle.Render(treeChar + " "))
			progressBar := progress.RenderToolProgress(*state.Progress, width)
			result.WriteString(progressBar)
		} else {
			// Show generic running state
			summaryStyle := lipgloss.NewStyle().Foreground(theme.Muted).Italic(true)
			result.WriteString("\n")
			result.WriteString(treeStyle.Render(treeChar + " "))
			result.WriteString(summaryStyle.Render("Running..."))
		}
	}

	return result.String()
}
