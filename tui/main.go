package main

import (
	"context"
	"flag"
	"fmt"
	"io"
	"os"
	"os/signal"
	"path/filepath"
	"regexp"
	"strings"
	"syscall"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/williamcory/agent/sdk/agent"
	"github.com/williamcory/agent/tui/internal/embedded"
)

var Version = "dev"

// Spinner frames for animation
var spinnerFrames = []string{"⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"}

// Styles
var (
	promptStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("12"))

	responseStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("10"))

	autocompleteSelectedStyle = lipgloss.NewStyle().
					Foreground(lipgloss.Color("0")).
					Background(lipgloss.Color("12"))

	statusStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("240"))

	availableCommands = []string{"/model", "/new", "/sessions", "/clear", "/help"}
)

// Message types
type message struct {
	role         string
	content      string
	toolName     string
	toolID       string
	isToolUse    bool
	isToolResult bool
	err          error
}

type modelOption struct {
	name        string
	description string
	providerID  string
	modelID     string
}

type mode string

const (
	normalMode mode = "normal"
	planMode   mode = "plan"
	bypassMode mode = "bypass"
)

var modes = []mode{normalMode, planMode, bypassMode}

// Main model
type model struct {
	messages              []message
	input                 string
	client                *agent.Client
	session               *agent.Session
	waiting               bool
	err                   error
	width                 int
	height                int
	showAutocomplete      bool
	autocompleteOptions   []string
	autocompleteSelection int
	showModelMenu         bool
	modelMenuSelection    int
	modelOptions          []modelOption
	currentModel          *agent.ModelInfo
	currentMode           mode
	project               *agent.Project
	cwd                   string
	version               string
	ctx                   context.Context
	cancel                context.CancelFunc
	streamingText         string
	spinnerFrame          int
	program               *tea.Program
	seenToolIDs           map[string]bool // Track tools we've displayed
}

// Bubbletea message types
type responseMsg string
type streamChunkMsg struct {
	text string
}
type streamDoneMsg struct{}
type spinnerTickMsg struct{}
type toolUseMsg struct {
	toolName string
	toolID   string
	status   string
}
type toolResultMsg struct {
	toolName string
	toolID   string
	output   string
	err      error
}
type sessionCreatedMsg struct {
	session *agent.Session
}
type errMsg error
type modelsLoadedMsg struct {
	options []modelOption
}
type messageStartedMsg struct{}
type setProgramMsg struct {
	program *tea.Program
}

func initialModel(client *agent.Client, project *agent.Project, cwd, version string, initialPrompt *string) model {
	ctx, cancel := context.WithCancel(context.Background())

	m := model{
		messages:              []message{},
		input:                 "",
		client:                client,
		waiting:               false,
		showAutocomplete:      false,
		autocompleteOptions:   []string{},
		autocompleteSelection: 0,
		showModelMenu:         false,
		modelMenuSelection:    0,
		modelOptions:          []modelOption{},
		currentMode:           normalMode,
		project:               project,
		cwd:                   cwd,
		version:               version,
		ctx:                   ctx,
		cancel:                cancel,
		seenToolIDs:           make(map[string]bool),
	}

	if initialPrompt != nil && *initialPrompt != "" {
		m.input = *initialPrompt
	}

	return m
}

func filterCommands(input string) []string {
	if !strings.HasPrefix(input, "/") {
		return []string{}
	}

	var matches []string
	for _, cmd := range availableCommands {
		if strings.HasPrefix(cmd, input) {
			matches = append(matches, cmd)
		}
	}
	return matches
}

func (m *model) updateAutocomplete() {
	m.autocompleteOptions = filterCommands(m.input)
	m.showAutocomplete = len(m.autocompleteOptions) > 0
	if m.autocompleteSelection >= len(m.autocompleteOptions) {
		m.autocompleteSelection = 0
	}
}

func (m model) Init() tea.Cmd {
	// Create session and load models on startup
	return tea.Batch(
		m.createSession(),
		m.loadModels(),
	)
}

func (m model) createSession() tea.Cmd {
	return func() tea.Msg {
		session, err := m.client.CreateSession(m.ctx, nil)
		if err != nil {
			return errMsg(err)
		}
		return sessionCreatedMsg{session: session}
	}
}

func (m model) loadModels() tea.Cmd {
	return func() tea.Msg {
		providers, err := m.client.ListProviders(m.ctx)
		if err != nil {
			return errMsg(err)
		}

		var options []modelOption
		for _, provider := range providers.Providers {
			for _, model := range provider.Models {
				options = append(options, modelOption{
					name:        model.Name,
					description: fmt.Sprintf("%s · %s", provider.Name, model.ID),
					providerID:  provider.ID,
					modelID:     model.ID,
				})
			}
		}
		return modelsLoadedMsg{options: options}
	}
}

func spinnerTick() tea.Cmd {
	return tea.Tick(80*time.Millisecond, func(t time.Time) tea.Msg {
		return spinnerTickMsg{}
	})
}

// Timeout for waiting - reset if no activity for this duration
const streamTimeout = 5 * time.Minute

func timeoutTick() tea.Cmd {
	return tea.Tick(streamTimeout, func(t time.Time) tea.Msg {
		return streamTimeoutMsg{}
	})
}

type streamTimeoutMsg struct{}

// streamTextMsg is sent when streaming text is updated
type streamTextUpdateMsg struct {
	text string
}

// streamToolMsg is sent when a tool event occurs
type streamToolStartMsg struct {
	toolName string
	toolID   string
}

type streamToolCompleteMsg struct {
	toolName string
	toolID   string
	output   string
}

// streamCompleteMsg is sent when the stream is done
type streamCompleteMsg struct{}

// fileAttachment represents a file to include in context
type fileAttachment struct {
	path     string
	content  string
	err      error
	skipped  bool   // true if file was skipped due to size
	fileSize int64  // size of file in bytes
}

// Maximum file size to auto-include (100KB)
const maxFileSize = 100 * 1024

// parseFileReferences extracts @filename patterns from text
// Returns the cleaned text and list of file paths
func parseFileReferences(text string, cwd string) (string, []string) {
	// Match @path patterns (handles @file.go, @./file.go, @../file.go, @/absolute/path)
	// Stop at whitespace, quotes, or common punctuation
	re := regexp.MustCompile(`@([^\s"'<>|*?]+)`)
	matches := re.FindAllStringSubmatch(text, -1)

	var files []string
	seen := make(map[string]bool)

	for _, match := range matches {
		if len(match) >= 2 {
			path := match[1]
			// Resolve relative paths
			if !filepath.IsAbs(path) {
				path = filepath.Join(cwd, path)
			}
			path = filepath.Clean(path)

			if !seen[path] {
				seen[path] = true
				files = append(files, path)
			}
		}
	}

	// Remove @mentions from text for cleaner display
	cleanedText := re.ReplaceAllString(text, "")
	cleanedText = strings.TrimSpace(cleanedText)

	return cleanedText, files
}

// readFileAttachments reads files and returns their contents
// Files larger than maxFileSize are skipped
func readFileAttachments(paths []string) []fileAttachment {
	var attachments []fileAttachment
	for _, path := range paths {
		// Check file size first
		info, err := os.Stat(path)
		if err != nil {
			attachments = append(attachments, fileAttachment{
				path: path,
				err:  err,
			})
			continue
		}

		fileSize := info.Size()

		// Skip files that are too large
		if fileSize > maxFileSize {
			attachments = append(attachments, fileAttachment{
				path:     path,
				skipped:  true,
				fileSize: fileSize,
			})
			continue
		}

		// Read the file
		content, err := os.ReadFile(path)
		attachments = append(attachments, fileAttachment{
			path:     path,
			content:  string(content),
			err:      err,
			fileSize: fileSize,
		})
	}
	return attachments
}

// formatFileSize returns a human-readable file size
func formatFileSize(bytes int64) string {
	const unit = 1024
	if bytes < unit {
		return fmt.Sprintf("%d B", bytes)
	}
	div, exp := int64(unit), 0
	for n := bytes / unit; n >= unit; n /= unit {
		div *= unit
		exp++
	}
	return fmt.Sprintf("%.1f %cB", float64(bytes)/float64(div), "KMGTPE"[exp])
}

// buildMessageWithFiles constructs a message with file contents prepended
func buildMessageWithFiles(text string, attachments []fileAttachment) string {
	var sb strings.Builder

	// Add file contents first
	for _, att := range attachments {
		if att.err != nil {
			sb.WriteString(fmt.Sprintf("<!-- Error reading %s: %v -->\n\n", att.path, att.err))
		} else if att.skipped {
			// For large files, tell the LLM about it but don't include contents
			sb.WriteString(fmt.Sprintf("File: %s (LARGE FILE - %s)\n", att.path, formatFileSize(att.fileSize)))
			sb.WriteString("This file is too large to include in full. Use grep/search tools to find specific content. Be frugal with tokens.\n\n")
		} else {
			// Format like Claude Code does
			sb.WriteString(fmt.Sprintf("File: %s\n```\n%s\n```\n\n", att.path, att.content))
		}
	}

	// Add the user's message
	if text != "" {
		sb.WriteString(text)
	}

	return sb.String()
}

func (m model) sendMessage(text string, p *tea.Program) tea.Cmd {
	return func() tea.Msg {
		if m.session == nil {
			return errMsg(fmt.Errorf("no active session"))
		}

		// Parse @file references and read their contents
		cleanedText, filePaths := parseFileReferences(text, m.cwd)
		attachments := readFileAttachments(filePaths)

		// Build the full message with file contents
		fullMessage := buildMessageWithFiles(cleanedText, attachments)

		req := &agent.PromptRequest{
			Parts: []interface{}{
				agent.TextPartInput{Type: "text", Text: fullMessage},
			},
		}

		if m.currentModel != nil {
			req.Model = m.currentModel
		}

		// Get the per-message event stream
		eventCh, errCh, err := m.client.SendMessage(m.ctx, m.session.ID, req)
		if err != nil {
			return errMsg(err)
		}

		// Process events in a goroutine and send updates to the TUI
		go func() {
			var currentText strings.Builder
			seenTools := make(map[string]bool)

			for {
				select {
				case event, ok := <-eventCh:
					if !ok {
						// Channel closed - stream complete
						p.Send(streamCompleteMsg{})
						return
					}

					if event.Part != nil {
						switch event.Part.Type {
						case "text":
							currentText.Reset()
							currentText.WriteString(event.Part.Text)
							p.Send(streamTextUpdateMsg{text: currentText.String()})

						case "tool":
							if event.Part.State != nil {
								toolKey := event.Part.ID + ":" + event.Part.State.Status
								if !seenTools[toolKey] {
									seenTools[toolKey] = true

									switch event.Part.State.Status {
									case "pending", "running":
										p.Send(streamToolStartMsg{
											toolName: event.Part.Tool,
											toolID:   event.Part.ID,
										})
									case "completed":
										p.Send(streamToolCompleteMsg{
											toolName: event.Part.Tool,
											toolID:   event.Part.ID,
											output:   event.Part.State.Output,
										})
									}
								}
							}
						}
					}

				case err, ok := <-errCh:
					if ok && err != nil {
						p.Send(errMsg(err))
					}
					p.Send(streamCompleteMsg{})
					return

				case <-m.ctx.Done():
					p.Send(errMsg(m.ctx.Err()))
					return
				}
			}
		}()

		// Return immediately - the goroutine handles streaming
		return messageStartedMsg{}
	}
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		// Always allow Ctrl+C to quit
		if msg.Type == tea.KeyCtrlC {
			m.cancel()
			return m, tea.Quit
		}

		if m.waiting {
			return m, nil
		}

		// Alt+Enter for multiline
		if msg.Type == tea.KeyEnter && msg.Alt {
			m.input += "\n"
			return m, nil
		}

		// Handle model menu
		if m.showModelMenu {
			switch msg.Type {
			case tea.KeyEsc:
				m.showModelMenu = false
				return m, nil
			case tea.KeyEnter:
				if len(m.modelOptions) > 0 {
					selected := m.modelOptions[m.modelMenuSelection]
					m.currentModel = &agent.ModelInfo{
						ProviderID: selected.providerID,
						ModelID:    selected.modelID,
					}
					m.showModelMenu = false
					m.messages = append(m.messages, message{
						role:    "system",
						content: fmt.Sprintf("Switched to %s", selected.name),
					})
				}
				return m, nil
			case tea.KeyUp:
				m.modelMenuSelection--
				if m.modelMenuSelection < 0 {
					m.modelMenuSelection = len(m.modelOptions) - 1
				}
			case tea.KeyDown:
				m.modelMenuSelection++
				if m.modelMenuSelection >= len(m.modelOptions) {
					m.modelMenuSelection = 0
				}
			}
			return m, nil
		}

		switch msg.Type {
		case tea.KeyEsc:
			if m.showAutocomplete {
				m.showAutocomplete = false
				return m, nil
			}
			m.cancel()
			return m, tea.Quit

		case tea.KeyEnter:
			if m.showAutocomplete && len(m.autocompleteOptions) > 0 {
				m.input = m.autocompleteOptions[m.autocompleteSelection]
				m.showAutocomplete = false
				m.autocompleteSelection = 0
				return m, nil
			}

			if strings.TrimSpace(m.input) == "" {
				return m, nil
			}

			// Handle slash commands
			switch m.input {
			case "/model":
				m.showModelMenu = true
				m.input = ""
				return m, nil
			case "/new":
				m.messages = []message{}
				m.input = ""
				return m, m.createSession()
			case "/clear":
				m.messages = []message{}
				m.input = ""
				return m, nil
			case "/help":
				m.messages = append(m.messages, message{
					role:    "system",
					content: "Commands: /model (switch model), /new (new session), /clear (clear messages), /help",
				})
				m.input = ""
				return m, nil
			}

			if strings.HasPrefix(m.input, "/") {
				m.messages = append(m.messages, message{
					role:    "system",
					content: "Unknown command: " + m.input,
				})
				m.input = ""
				return m, nil
			}

			// Send message
			userMsg := message{role: "user", content: m.input}
			m.messages = append(m.messages, userMsg)
			input := m.input
			m.input = ""
			m.waiting = true
			m.streamingText = ""
			m.spinnerFrame = 0
			m.seenToolIDs = make(map[string]bool)
			m.err = nil // Clear previous errors

			if m.program == nil {
				m.err = fmt.Errorf("program not initialized")
				m.waiting = false
				return m, nil
			}

			return m, tea.Batch(m.sendMessage(input, m.program), spinnerTick(), timeoutTick())

		case tea.KeyTab:
			if m.showAutocomplete && len(m.autocompleteOptions) > 0 {
				m.input = m.autocompleteOptions[m.autocompleteSelection]
				m.showAutocomplete = false
				m.autocompleteSelection = 0
			}

		case tea.KeyShiftTab:
			currentIndex := 0
			for i, mode := range modes {
				if mode == m.currentMode {
					currentIndex = i
					break
				}
			}
			nextIndex := (currentIndex + 1) % len(modes)
			m.currentMode = modes[nextIndex]

		case tea.KeyUp:
			if m.showAutocomplete && len(m.autocompleteOptions) > 0 {
				m.autocompleteSelection--
				if m.autocompleteSelection < 0 {
					m.autocompleteSelection = len(m.autocompleteOptions) - 1
				}
			}

		case tea.KeyDown:
			if m.showAutocomplete && len(m.autocompleteOptions) > 0 {
				m.autocompleteSelection++
				if m.autocompleteSelection >= len(m.autocompleteOptions) {
					m.autocompleteSelection = 0
				}
			}

		case tea.KeyBackspace:
			if len(m.input) > 0 {
				m.input = m.input[:len(m.input)-1]
				m.updateAutocomplete()
			}

		case tea.KeySpace:
			m.input += " "
			m.showAutocomplete = false

		case tea.KeyRunes:
			m.input += string(msg.Runes)
			m.updateAutocomplete()
		}

	case spinnerTickMsg:
		if m.waiting {
			m.spinnerFrame = (m.spinnerFrame + 1) % len(spinnerFrames)
			return m, spinnerTick()
		}

	case messageStartedMsg:
		// Message send initiated, spinner already running
		return m, nil

	case setProgramMsg:
		m.program = msg.program
		return m, nil

	case sessionCreatedMsg:
		m.session = msg.session
		if m.input != "" && m.program != nil {
			// Auto-send initial prompt if provided
			userMsg := message{role: "user", content: m.input}
			m.messages = append(m.messages, userMsg)
			input := m.input
			m.input = ""
			m.waiting = true
			m.spinnerFrame = 0
			m.seenToolIDs = make(map[string]bool)
			return m, tea.Batch(m.sendMessage(input, m.program), spinnerTick(), timeoutTick())
		}

	case modelsLoadedMsg:
		m.modelOptions = msg.options
		if len(m.modelOptions) > 0 {
			// Set default model
			m.currentModel = &agent.ModelInfo{
				ProviderID: m.modelOptions[0].providerID,
				ModelID:    m.modelOptions[0].modelID,
			}
		}

	case responseMsg:
		m.waiting = false
		m.messages = append(m.messages, message{role: "assistant", content: string(msg)})

	case streamDoneMsg:
		m.waiting = false
		if m.streamingText != "" {
			m.messages = append(m.messages, message{role: "assistant", content: m.streamingText})
			m.streamingText = ""
		}

	case toolUseMsg:
		m.messages = append(m.messages, message{
			role:      "assistant",
			content:   fmt.Sprintf("Using tool: %s", msg.toolName),
			isToolUse: true,
			toolName:  msg.toolName,
			toolID:    msg.toolID,
		})
		// Continue waiting for the tool result

	case toolResultMsg:
		m.messages = append(m.messages, message{
			role:         "tool_result",
			content:      msg.output,
			isToolResult: true,
			toolName:     msg.toolName,
			toolID:       msg.toolID,
			err:          msg.err,
		})
		// Continue the conversation - server handles tool loop

	case errMsg:
		m.waiting = false
		m.err = msg

	case streamTextUpdateMsg:
		// Update streaming text as it arrives
		m.streamingText = msg.text

	case streamToolStartMsg:
		// Tool execution started
		toolKey := msg.toolID + ":start"
		if !m.seenToolIDs[toolKey] {
			m.seenToolIDs[toolKey] = true
			m.messages = append(m.messages, message{
				role:      "assistant",
				content:   fmt.Sprintf("Using tool: %s", msg.toolName),
				isToolUse: true,
				toolName:  msg.toolName,
				toolID:    msg.toolID,
			})
		}

	case streamToolCompleteMsg:
		// Tool execution completed
		toolKey := msg.toolID + ":complete"
		if !m.seenToolIDs[toolKey] {
			m.seenToolIDs[toolKey] = true
			m.messages = append(m.messages, message{
				role:         "tool_result",
				content:      msg.output,
				isToolResult: true,
				toolName:     msg.toolName,
				toolID:       msg.toolID,
			})
		}

	case streamCompleteMsg:
		// Stream completed
		m.waiting = false
		if m.streamingText != "" {
			m.messages = append(m.messages, message{role: "assistant", content: m.streamingText})
			m.streamingText = ""
		}
		m.seenToolIDs = make(map[string]bool)

	case streamTimeoutMsg:
		// Timeout while waiting - reset state
		if m.waiting {
			m.waiting = false
			m.err = fmt.Errorf("request timed out after %v", streamTimeout)
			m.streamingText = ""
		}

	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height

	// Handle global events from SSE stream
	case *agent.GlobalEvent:
		if msg.Part != nil {
			switch msg.Part.Type {
			case "text":
				// Update streaming text
				m.streamingText = msg.Part.Text
			case "tool":
				if msg.Part.State != nil {
					toolKey := msg.Part.ID + ":" + msg.Part.State.Status
					if !m.seenToolIDs[toolKey] {
						m.seenToolIDs[toolKey] = true
						if msg.Part.State.Status == "completed" {
							m.messages = append(m.messages, message{
								role:         "tool_result",
								content:      msg.Part.State.Output,
								isToolResult: true,
								toolName:     msg.Part.Tool,
								toolID:       msg.Part.ID,
							})
						} else if msg.Part.State.Status == "pending" || msg.Part.State.Status == "running" {
							// Show tool being used
							m.messages = append(m.messages, message{
								role:      "assistant",
								content:   fmt.Sprintf("Using tool: %s", msg.Part.Tool),
								isToolUse: true,
								toolName:  msg.Part.Tool,
								toolID:    msg.Part.ID,
							})
						}
					}
				}
			}
		}
		if msg.Type == "session.idle" {
			m.waiting = false
			if m.streamingText != "" {
				m.messages = append(m.messages, message{role: "assistant", content: m.streamingText})
				m.streamingText = ""
			}
			// Reset seen tools for next message
			m.seenToolIDs = make(map[string]bool)
		}
	}

	return m, nil
}

func (m model) getModelName() string {
	if m.currentModel != nil {
		for _, opt := range m.modelOptions {
			if opt.modelID == m.currentModel.ModelID {
				return opt.name
			}
		}
		return m.currentModel.ModelID
	}
	return "Loading..."
}

func (m model) View() string {
	var s strings.Builder

	// Display logo header when no messages
	if len(m.messages) == 0 && !m.showModelMenu {
		logoStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("12"))
		versionStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("240"))

		version := m.version
		if version == "" {
			version = "dev"
		}

		s.WriteString(logoStyle.Render(" ▐▛███▜▌") + "   " + lipgloss.NewStyle().Bold(true).Render("Agent "+version) + "\n")
		s.WriteString(logoStyle.Render("▝▜█████▛▘") + "  " + m.getModelName() + "\n")
		s.WriteString(logoStyle.Render("  ▘▘ ▝▝") + "    " + versionStyle.Render(m.cwd) + "\n\n")
	}

	// Model menu
	if m.showModelMenu {
		s.WriteString(lipgloss.NewStyle().Bold(true).Render("Switch between models") + "\n\n")
		for i, opt := range m.modelOptions {
			prefix := "   "
			if i == m.modelMenuSelection {
				prefix = " > "
			}

			checkmark := ""
			if m.currentModel != nil && opt.modelID == m.currentModel.ModelID {
				checkmark = " [current]"
			}

			line := fmt.Sprintf("%s%d. %-25s %s%s", prefix, i+1, opt.name, opt.description, checkmark)
			if i == m.modelMenuSelection {
				s.WriteString(autocompleteSelectedStyle.Render(line) + "\n")
			} else {
				s.WriteString(line + "\n")
			}
		}
		s.WriteString("\n")
		s.WriteString(statusStyle.Render("Press Enter to select, Esc to cancel") + "\n")
		return s.String()
	}

	// Chat history
	for _, msg := range m.messages {
		if msg.role == "user" {
			s.WriteString(promptStyle.Render("> ") + msg.content + "\n\n")
		} else if msg.role == "system" {
			s.WriteString(lipgloss.NewStyle().Foreground(lipgloss.Color("11")).Render(msg.content) + "\n\n")
		} else if msg.isToolUse {
			toolStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("14"))
			s.WriteString(toolStyle.Render("🔧 ") + msg.content + "\n")
		} else if msg.isToolResult {
			resultStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("8"))
			content := msg.content
			if len(content) > 200 {
				content = content[:200] + "..."
			}
			s.WriteString(resultStyle.Render("  └─ ") + content + "\n\n")
		} else {
			s.WriteString(responseStyle.Render("⏺ ") + msg.content + "\n\n")
		}
	}

	// Streaming text with spinner
	if m.streamingText != "" {
		spinner := spinnerFrames[m.spinnerFrame]
		s.WriteString(responseStyle.Render(spinner+" ") + m.streamingText + "\n\n")
	}

	// Waiting indicator with animated spinner
	if m.waiting && m.streamingText == "" {
		spinner := spinnerFrames[m.spinnerFrame]
		s.WriteString(responseStyle.Render(spinner+" Thinking...") + "\n\n")
	}

	// Error display
	if m.err != nil {
		s.WriteString(lipgloss.NewStyle().Foreground(lipgloss.Color("9")).Render(fmt.Sprintf("✗ %v", m.err)) + "\n\n")
	}

	// Input area
	borderLine := strings.Repeat("─", m.width)
	if m.width == 0 {
		borderLine = strings.Repeat("─", 80)
	}
	s.WriteString(borderLine + "\n")

	// Display input
	inputLines := strings.Split(m.input, "\n")
	for i, line := range inputLines {
		if i == 0 {
			s.WriteString("> " + line + "\n")
		} else {
			s.WriteString("  " + line + "\n")
		}
	}

	s.WriteString(borderLine + "\n")

	// Status line with colored mode indicator
	modeText := ""
	var modeStyle lipgloss.Style
	switch m.currentMode {
	case planMode:
		modeText = "plan mode"
		modeStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("10")) // Green
	case bypassMode:
		modeText = "bypass permissions"
		modeStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("9")) // Red
	default:
		modeStyle = statusStyle
		if m.showAutocomplete && len(m.autocompleteOptions) > 0 {
			modeText = m.autocompleteOptions[m.autocompleteSelection]
		}
	}

	s.WriteString(statusStyle.Render("  ⏵⏵ ") + modeStyle.Render(modeText) + "\n")
	s.WriteString(statusStyle.Render("  (shift+tab to cycle modes)") + "\n")

	return s.String()
}

func main() {
	version := Version
	if version != "dev" && !strings.HasPrefix(version, "v") {
		version = "v" + version
	}

	// Parse flags
	prompt := flag.String("prompt", "", "Initial prompt to send")
	backendURL := flag.String("backend", "", "Backend URL (overrides embedded server)")
	useEmbedded := flag.Bool("embedded", true, "Use embedded server (default: true)")
	flag.Parse()

	// Determine backend URL
	url := *backendURL
	if url == "" {
		url = os.Getenv("OPENCODE_SERVER")
	}

	// Check for piped stdin
	stat, err := os.Stdin.Stat()
	if err == nil && (stat.Mode()&os.ModeCharDevice) == 0 {
		stdin, err := io.ReadAll(os.Stdin)
		if err == nil {
			stdinContent := strings.TrimSpace(string(stdin))
			if stdinContent != "" {
				if prompt == nil || *prompt == "" {
					prompt = &stdinContent
				} else {
					combined := *prompt + "\n" + stdinContent
					prompt = &combined
				}
			}
		}
	}

	var serverProcess *embedded.ServerProcess
	var cleanup func()

	// Start embedded server if needed
	if url == "" && *useEmbedded {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()

		fmt.Println("Starting embedded server...")
		var err error
		serverProcess, url, err = embedded.StartServer(ctx)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error starting embedded server: %v\n", err)
			fmt.Fprintf(os.Stderr, "Tip: Use --backend=URL to connect to an external server\n")
			os.Exit(1)
		}

		cleanup = func() {
			if serverProcess != nil {
				serverProcess.Stop()
			}
		}

		// Signal handling
		sigChan := make(chan os.Signal, 1)
		signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
		go func() {
			<-sigChan
			cleanup()
			os.Exit(0)
		}()

		fmt.Printf("Server running at %s\n", url)
	} else if url == "" {
		url = "http://localhost:8000"
	}

	// Get working directory
	cwd, err := os.Getwd()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error getting working directory: %v\n", err)
		if cleanup != nil {
			cleanup()
		}
		os.Exit(1)
	}

	// Create SDK client
	client := agent.NewClient(url,
		agent.WithDirectory(cwd),
		agent.WithTimeout(60*time.Second),
	)

	// Get project info
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	project, err := client.GetProject(ctx)
	cancel()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error getting project: %v\n", err)
		if cleanup != nil {
			cleanup()
		}
		os.Exit(1)
	}

	// Create model
	m := initialModel(client, project, cwd, version, prompt)

	// Create program
	p := tea.NewProgram(m, tea.WithAltScreen())

	// Send program pointer to model immediately after creation
	go func() {
		// Small delay to ensure program is ready
		time.Sleep(10 * time.Millisecond)
		p.Send(setProgramMsg{program: p})
	}()

	// Subscribe to global events (for session.idle fallback)
	go func() {
		eventCh, errCh, err := client.SubscribeToEvents(m.ctx)
		if err != nil {
			return
		}

		for {
			select {
			case event := <-eventCh:
				if event != nil {
					p.Send(event)
				}
			case <-errCh:
				return
			case <-m.ctx.Done():
				return
			}
		}
	}()

	// Run
	if _, err := p.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
	}

	// Cleanup
	if cleanup != nil {
		cleanup()
	}
}
