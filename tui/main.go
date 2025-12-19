package main

import (
	"context"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"regexp"
	"strings"
	"syscall"
	"time"

	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/williamcory/agent/sdk/agent"
	"github.com/williamcory/agent/tui/internal/clipboard"
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

	availableCommands = []string{"/model", "/new", "/sessions", "/clear", "/help", "/diff", "/script"}
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

type imageAttachment struct {
	path     string // Path to temp file
	filename string // Display name
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
	streamingReasoning    string
	spinnerFrame          int
	program               *tea.Program
	seenToolIDs           map[string]bool // Track tools we've displayed
	viewport              viewport.Model  // Scrollable viewport for messages
	viewportReady         bool            // Whether viewport has been initialized
	autoScroll            bool            // Auto-scroll to bottom on new content
	lastContentLen        int             // Track content length to detect changes
	manualScrollOffset    int             // Manual scroll offset when not auto-scrolling
	// File search fields
	showFileSearch      bool
	fileSearchStartPos  int
	fileSearchQuery     string
	fileSearchResults   []FileMatch
	fileSearchSelection int
	fileIndex           *FileIndex
	imageAttachments    []imageAttachment // Images to send with message
	// Input history
	inputHistory      []string // History of sent messages
	historyIndex      int      // Current position in history (-1 = not browsing)
	savedInput        string   // Saved current input when browsing history
	// Mouse mode
	mouseEnabled      bool     // Whether mouse capture is enabled (for text selection toggle)
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
type imagePastedMsg struct {
	path     string
	filename string
}
type scriptExpandedMsg struct {
	prompt string
	err    error
}
type sessionAbortedMsg struct {
	err error
}

func initialModel(client *agent.Client, project *agent.Project, cwd, version string, initialPrompt *string) model {
	ctx, cancel := context.WithCancel(context.Background())

	// Initialize file index
	fileIndex := &FileIndex{}
	// Scan files in the background - don't block startup
	go fileIndex.Scan(cwd)

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
		autoScroll:            true, // Auto-scroll to bottom by default
		fileIndex:             fileIndex,
		showFileSearch:        false,
		fileSearchResults:     []FileMatch{},
		fileSearchSelection:   0,
		inputHistory:          []string{},
		historyIndex:          -1,
		savedInput:            "",
		mouseEnabled:          false, // Mouse disabled by default for native text selection
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

		// Build parts array with text and images
		parts := []interface{}{
			agent.TextPartInput{Type: "text", Text: fullMessage},
		}

		// Add image attachments
		for _, img := range m.imageAttachments {
			// Determine MIME type from extension
			mime := "image/png"
			ext := strings.ToLower(filepath.Ext(img.path))
			switch ext {
			case ".jpg", ".jpeg":
				mime = "image/jpeg"
			case ".gif":
				mime = "image/gif"
			case ".webp":
				mime = "image/webp"
			}

			// Convert local path to file:// URL
			fileURL := "file://" + img.path

			parts = append(parts, agent.FilePartInput{
				Type:     "file",
				Mime:     mime,
				URL:      fileURL,
				Filename: &img.filename,
			})
		}

		req := &agent.PromptRequest{
			Parts: parts,
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

// cleanupImageAttachments removes temp files and clears attachments
func (m *model) cleanupImageAttachments() {
	for _, img := range m.imageAttachments {
		// Only delete files in temp directory
		if strings.HasPrefix(img.path, os.TempDir()) {
			os.Remove(img.path)
		}
	}
	m.imageAttachments = nil
}

// handleImagePaste attempts to paste an image from clipboard
func (m model) handleImagePaste() tea.Cmd {
	return func() tea.Msg {
		// Try to get image from clipboard
		img, err := clipboard.GetImage()
		if err != nil || img == nil {
			// No image in clipboard, not an error - just ignore
			return nil
		}

		// Save to temp file
		path, err := img.SaveToTemp()
		if err != nil {
			return errMsg(fmt.Errorf("failed to save image: %w", err))
		}

		// Generate a nice filename
		filename := filepath.Base(path)

		return imagePastedMsg{
			path:     path,
			filename: filename,
		}
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
			// Allow Escape to abort the running agent
			if msg.Type == tea.KeyEsc {
				return m, m.abortSession()
			}
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
		case tea.KeyCtrlV:
			// Handle Ctrl+V for image paste
			return m, m.handleImagePaste()

		case tea.KeyCtrlS:
			// Toggle mouse mode for text selection
			m.mouseEnabled = !m.mouseEnabled
			if m.mouseEnabled {
				return m, tea.EnableMouseCellMotion
			}
			return m, tea.DisableMouse

		case tea.KeyEsc:
			if m.showFileSearch {
				m.showFileSearch = false
				return m, nil
			}
			if m.showAutocomplete {
				m.showAutocomplete = false
				return m, nil
			}
			m.cancel()
			return m, tea.Quit

		case tea.KeyEnter:
			if m.showFileSearch && len(m.fileSearchResults) > 0 {
				m.insertSelectedFile()
				return m, nil
			}
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
					content: "Commands: /model (switch model), /new (new session), /clear (clear messages), /diff (show changes), /script (create plugin), /help\n\nModes: normal, plan, bypass (shift+tab to cycle)\n\nKeybindings: esc (abort running agent), ctrl+s (toggle text selection), ctrl+v (paste image), shift+tab (cycle modes)",
				})
				m.input = ""
				return m, nil
			case "/script":
				// Expand the script command and send as a message
				return m, m.handleScriptCommand()
			}

			// Handle /diff command
			if strings.HasPrefix(m.input, "/diff") {
				diffOutput, err := m.handleDiffCommand(m.input)
				if err != nil {
					m.messages = append(m.messages, message{
						role:    "system",
						content: fmt.Sprintf("Error: %v", err),
					})
				} else {
					m.messages = append(m.messages, message{
						role:    "system",
						content: diffOutput,
					})
				}
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
			// Add to history (avoid duplicates of last entry)
			if len(m.inputHistory) == 0 || m.inputHistory[len(m.inputHistory)-1] != input {
				m.inputHistory = append(m.inputHistory, input)
			}
			m.historyIndex = -1 // Reset history navigation
			m.savedInput = ""
			m.input = ""
			m.waiting = true
			m.streamingText = ""
			m.streamingReasoning = ""
			m.spinnerFrame = 0
			m.seenToolIDs = make(map[string]bool)
			m.err = nil // Clear previous errors

			if m.program == nil {
				m.err = fmt.Errorf("program not initialized")
				m.waiting = false
				return m, nil
			}

			// Note: Image attachments will be cleared after the message completes
			// to allow the sendMessage goroutine to access them
			return m, tea.Batch(m.sendMessage(input, m.program), spinnerTick(), timeoutTick())

		case tea.KeyTab:
			if m.showFileSearch && len(m.fileSearchResults) > 0 {
				m.insertSelectedFile()
				return m, nil
			}
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
			if m.showFileSearch && len(m.fileSearchResults) > 0 {
				m.fileSearchSelection--
				if m.fileSearchSelection < 0 {
					m.fileSearchSelection = len(m.fileSearchResults) - 1
				}
			} else if m.showAutocomplete && len(m.autocompleteOptions) > 0 {
				m.autocompleteSelection--
				if m.autocompleteSelection < 0 {
					m.autocompleteSelection = len(m.autocompleteOptions) - 1
				}
			} else if len(m.inputHistory) > 0 {
				// Navigate input history
				if m.historyIndex == -1 {
					// Starting to browse history - save current input
					m.savedInput = m.input
					m.historyIndex = len(m.inputHistory) - 1
				} else if m.historyIndex > 0 {
					m.historyIndex--
				}
				m.input = m.inputHistory[m.historyIndex]
			} else if m.viewportReady {
				// Scroll up
				m.viewport.LineUp(1)
				m.autoScroll = false // User scrolled, disable auto-scroll
			}

		case tea.KeyDown:
			if m.showFileSearch && len(m.fileSearchResults) > 0 {
				m.fileSearchSelection++
				if m.fileSearchSelection >= len(m.fileSearchResults) {
					m.fileSearchSelection = 0
				}
			} else if m.showAutocomplete && len(m.autocompleteOptions) > 0 {
				m.autocompleteSelection++
				if m.autocompleteSelection >= len(m.autocompleteOptions) {
					m.autocompleteSelection = 0
				}
			} else if m.historyIndex >= 0 {
				// Navigate input history forward
				if m.historyIndex < len(m.inputHistory)-1 {
					m.historyIndex++
					m.input = m.inputHistory[m.historyIndex]
				} else {
					// Reached end of history - restore saved input
					m.historyIndex = -1
					m.input = m.savedInput
				}
			} else if m.viewportReady {
				// Scroll down
				m.viewport.LineDown(1)
				// Re-enable auto-scroll if we're at the bottom
				if m.viewport.AtBottom() {
					m.autoScroll = true
				}
			}

		case tea.KeyPgUp:
			if m.viewportReady {
				m.viewport.HalfViewUp()
				m.autoScroll = false
			}

		case tea.KeyPgDown:
			if m.viewportReady {
				m.viewport.HalfViewDown()
				if m.viewport.AtBottom() {
					m.autoScroll = true
				}
			}

		case tea.KeyHome:
			if m.viewportReady {
				m.viewport.GotoTop()
				m.autoScroll = false
			}

		case tea.KeyEnd:
			if m.viewportReady {
				m.viewport.GotoBottom()
				m.autoScroll = true
			}

		case tea.KeyBackspace:
			if len(m.input) > 0 {
				m.input = m.input[:len(m.input)-1]
				m.updateAutocomplete()
				m.detectFileSearch()
				m.historyIndex = -1 // Reset history navigation on edit
			}

		case tea.KeySpace:
			m.input += " "
			m.showAutocomplete = false
			m.detectFileSearch()
			m.historyIndex = -1 // Reset history navigation on edit

		case tea.KeyRunes:
			m.input += string(msg.Runes)
			m.updateAutocomplete()
			m.detectFileSearch()
			m.historyIndex = -1 // Reset history navigation on edit
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

	case imagePastedMsg:
		// Add image attachment
		m.imageAttachments = append(m.imageAttachments, imageAttachment{
			path:     msg.path,
			filename: msg.filename,
		})
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
		m.streamingReasoning = ""

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
		m.streamingReasoning = ""
		m.seenToolIDs = make(map[string]bool)
		// Clean up temp image files
		m.cleanupImageAttachments()

	case streamTimeoutMsg:
		// Timeout while waiting - reset state
		if m.waiting {
			m.waiting = false
			m.err = fmt.Errorf("request timed out after %v", streamTimeout)
			m.streamingText = ""
			m.streamingReasoning = ""
		}

	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height

		// Calculate viewport height (total height minus input area)
		// Input area: 1 border + input lines + 1 border + 2 status lines = ~5-6 lines minimum
		inputAreaHeight := 6
		viewportHeight := m.height - inputAreaHeight
		if viewportHeight < 1 {
			viewportHeight = 1
		}

		if !m.viewportReady {
			// Initialize viewport
			m.viewport = viewport.New(m.width, viewportHeight)
			m.viewport.YPosition = 0
			m.viewportReady = true
		} else {
			// Update viewport dimensions
			m.viewport.Width = m.width
			m.viewport.Height = viewportHeight
		}

	case tea.MouseMsg:
		// Handle mouse wheel scrolling
		if m.viewportReady {
			switch msg.Button {
			case tea.MouseButtonWheelUp:
				m.viewport.LineUp(3)
				m.autoScroll = false
			case tea.MouseButtonWheelDown:
				m.viewport.LineDown(3)
				if m.viewport.AtBottom() {
					m.autoScroll = true
				}
			}
		}

	// Handle global events from SSE stream
	case *agent.GlobalEvent:
		if msg.Part != nil {
			switch msg.Part.Type {
			case "reasoning":
				// Update streaming reasoning/thinking text
				m.streamingReasoning = msg.Part.Text
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
			// Clear reasoning when done (we don't persist it in messages)
			m.streamingReasoning = ""
			// Reset seen tools for next message
			m.seenToolIDs = make(map[string]bool)
		}

	case scriptExpandedMsg:
		if msg.err != nil {
			m.messages = append(m.messages, message{
				role:    "system",
				content: fmt.Sprintf("Error expanding /script command: %v", msg.err),
			})
			return m, nil
		}
		// Send the expanded prompt as a message
		userMsg := message{role: "user", content: msg.prompt}
		m.messages = append(m.messages, userMsg)
		m.input = ""
		m.waiting = true
		m.streamingText = ""
		m.streamingReasoning = ""
		m.spinnerFrame = 0
		m.seenToolIDs = make(map[string]bool)
		m.err = nil
		if m.program != nil {
			return m, tea.Batch(m.sendMessage(msg.prompt, m.program), spinnerTick(), timeoutTick())
		}

	case sessionAbortedMsg:
		m.waiting = false
		m.streamingText = ""
		m.streamingReasoning = ""
		m.seenToolIDs = make(map[string]bool)
		if msg.err != nil {
			m.messages = append(m.messages, message{
				role:    "system",
				content: fmt.Sprintf("Failed to abort: %v", msg.err),
			})
		} else {
			m.messages = append(m.messages, message{
				role:    "system",
				content: "Aborted",
			})
		}
		return m, nil
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

// wrapText wraps text to fit within the given width
func wrapText(text string, width int) string {
	if width <= 0 {
		width = 80
	}
	return lipgloss.NewStyle().Width(width).Render(text)
}

// buildMessageContent builds the chat content for the viewport
func (m model) buildMessageContent() string {
	var s strings.Builder

	// Add top margin
	s.WriteString("\n")

	// Display logo header when no messages
	if len(m.messages) == 0 {
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

	// Chat history
	// Calculate wrap width (leave some margin for prefixes)
	wrapWidth := m.width - 4
	if wrapWidth <= 0 {
		wrapWidth = 76
	}

	for _, msg := range m.messages {
		if msg.role == "user" {
			s.WriteString(promptStyle.Render("> ") + wrapText(msg.content, wrapWidth-2) + "\n\n")
		} else if msg.role == "system" {
			s.WriteString(lipgloss.NewStyle().Foreground(lipgloss.Color("11")).Render(wrapText(msg.content, wrapWidth)) + "\n\n")
		} else if msg.isToolUse {
			toolStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("14"))
			s.WriteString(toolStyle.Render("🔧 ") + wrapText(msg.content, wrapWidth-3) + "\n")
		} else if msg.isToolResult {
			resultStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("8"))
			content := msg.content
			if len(content) > 200 {
				content = content[:200] + "..."
			}
			s.WriteString(resultStyle.Render("  └─ ") + wrapText(content, wrapWidth-5) + "\n\n")
		} else {
			s.WriteString(responseStyle.Render("⏺ ") + wrapText(msg.content, wrapWidth-2) + "\n\n")
		}
	}

	// Streaming reasoning (thinking) with gray text
	if m.streamingReasoning != "" {
		thinkingStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("8")) // Gray
		spinner := spinnerFrames[m.spinnerFrame]
		s.WriteString(thinkingStyle.Render(spinner+" Thinking...\n") + thinkingStyle.Render(wrapText(m.streamingReasoning, wrapWidth-2)) + "\n\n")
	}

	// Streaming text with spinner
	if m.streamingText != "" {
		spinner := spinnerFrames[m.spinnerFrame]
		s.WriteString(responseStyle.Render(spinner+" ") + wrapText(m.streamingText, wrapWidth-2) + "\n\n")
	}

	// Waiting indicator with animated spinner (only when not showing reasoning or text)
	if m.waiting && m.streamingText == "" && m.streamingReasoning == "" {
		spinner := spinnerFrames[m.spinnerFrame]
		s.WriteString(responseStyle.Render(spinner+" Thinking...") + "\n\n")
	}

	// Error display
	if m.err != nil {
		s.WriteString(lipgloss.NewStyle().Foreground(lipgloss.Color("9")).Render(fmt.Sprintf("✗ %v", m.err)) + "\n\n")
	}

	return s.String()
}

func (m model) View() string {
	var s strings.Builder

	// Model menu (rendered without viewport)
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

	// Build message content
	content := m.buildMessageContent()
	contentLines := strings.Count(content, "\n")

	// Calculate available space for content (total height minus input area)
	inputAreaHeight := 6
	availableHeight := m.height - inputAreaHeight
	if availableHeight < 1 {
		availableHeight = 1
	}

	// Use viewport only when content exceeds available space
	if m.viewportReady && contentLines > availableHeight {
		m.viewport.SetContent(content)
		if m.autoScroll {
			m.viewport.GotoBottom()
		}
		s.WriteString(m.viewport.View())
		s.WriteString("\n")
	} else {
		// Content fits - render directly without viewport padding
		s.WriteString(content)
	}

	// Input area
	borderLine := strings.Repeat("─", m.width)
	if m.width == 0 {
		borderLine = strings.Repeat("─", 80)
	}
	s.WriteString(borderLine + "\n")

	// Display image attachments
	if len(m.imageAttachments) > 0 {
		attachStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("14"))
		for _, img := range m.imageAttachments {
			s.WriteString(attachStyle.Render("📎 " + img.filename) + "\n")
		}
	}

	// Display input
	inputLines := strings.Split(m.input, "\n")
	for i, line := range inputLines {
		if i == 0 {
			s.WriteString("> " + line + "\n")
		} else {
			s.WriteString("  " + line + "\n")
		}
	}

	// File search overlay
	if m.showFileSearch {
		s.WriteString("\n")
		searchHeaderStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("12")).Bold(true)
		s.WriteString(searchHeaderStyle.Render("🔍 File Search: ") + m.fileSearchQuery + "\n")
		s.WriteString(strings.Repeat("─", minInt(m.width, 80)) + "\n")

		if len(m.fileSearchResults) == 0 {
			s.WriteString(statusStyle.Render("  No files found\n"))
		} else {
			// Show up to 10 results
			maxResults := minInt(10, len(m.fileSearchResults))
			for i := 0; i < maxResults; i++ {
				result := m.fileSearchResults[i]
				prefix := "  "
				if i == m.fileSearchSelection {
					prefix = "> "
				}

				// Split path to show directory
				dir := filepath.Dir(result.Path)
				base := filepath.Base(result.Path)

				line := fmt.Sprintf("%s%-30s  %s", prefix, base, statusStyle.Render(dir))
				if i == m.fileSearchSelection {
					s.WriteString(autocompleteSelectedStyle.Render(line) + "\n")
				} else {
					s.WriteString(line + "\n")
				}
			}

			if len(m.fileSearchResults) > maxResults {
				s.WriteString(statusStyle.Render(fmt.Sprintf("  ... and %d more\n", len(m.fileSearchResults)-maxResults)))
			}
		}

		s.WriteString(statusStyle.Render("  [↑↓: Navigate] [Tab/Enter: Select] [Esc: Cancel]\n"))
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

	// Scroll indicator
	scrollInfo := ""
	if m.viewportReady && !m.viewport.AtBottom() {
		scrollInfo = " (↑↓ to scroll)"
	}

	// Mouse mode indicator
	mouseInfo := ""
	if m.mouseEnabled {
		mouseInfo = " · ctrl+s: select text"
	} else {
		mouseInfo = " · " + lipgloss.NewStyle().Foreground(lipgloss.Color("11")).Render("SELECT MODE") + " (ctrl+s to exit)"
	}

	s.WriteString(statusStyle.Render("  ⏵⏵ ") + modeStyle.Render(modeText) + statusStyle.Render(scrollInfo) + statusStyle.Render(mouseInfo) + "\n")
	s.WriteString(statusStyle.Render("  (shift+tab to cycle modes)") + "\n")

	return s.String()
}

// handleDiffCommand handles the /diff slash command
func (m model) handleDiffCommand(input string) (string, error) {
	// Parse arguments
	args := strings.Fields(input)
	args = args[1:] // Skip "/diff"

	stagedOnly := false
	statOnly := false
	var fileFilter string

	for _, arg := range args {
		switch arg {
		case "--staged":
			stagedOnly = true
		case "--stat":
			statOnly = true
		default:
			if !strings.HasPrefix(arg, "-") {
				fileFilter = arg
			}
		}
	}

	// Run git diff command
	diff, err := m.runGitDiff(stagedOnly, statOnly, fileFilter)
	if err != nil {
		return "", fmt.Errorf("failed to get diff: %w", err)
	}

	// If no diff output, check for untracked files
	if diff == "" {
		untracked, err := m.getUntrackedFiles()
		if err == nil && untracked != "" {
			return formatUntrackedFiles(untracked), nil
		}
		return "No changes", nil
	}

	// Format the diff output
	return formatDiff(diff), nil
}

// runGitDiff executes git diff and returns the output
func (m model) runGitDiff(stagedOnly, statOnly bool, fileFilter string) (string, error) {
	gitArgs := []string{"diff"}

	// Add color for better display
	if !statOnly {
		gitArgs = append(gitArgs, "--color=always")
	}

	if stagedOnly {
		gitArgs = append(gitArgs, "--staged")
	}

	if statOnly {
		gitArgs = append(gitArgs, "--stat")
	}

	// Add file filter if specified
	if fileFilter != "" {
		gitArgs = append(gitArgs, "--", fileFilter)
	}

	cmd := exec.Command("git", gitArgs...)
	cmd.Dir = m.cwd
	output, err := cmd.Output()
	if err != nil {
		// Check if it's because we're not in a git repo
		if exitErr, ok := err.(*exec.ExitError); ok {
			return "", fmt.Errorf("git command failed: %s", string(exitErr.Stderr))
		}
		return "", err
	}

	return string(output), nil
}

// getUntrackedFiles returns a list of untracked files
func (m model) getUntrackedFiles() (string, error) {
	cmd := exec.Command("git", "ls-files", "--others", "--exclude-standard")
	cmd.Dir = m.cwd
	output, err := cmd.Output()
	if err != nil {
		return "", err
	}
	return string(output), nil
}

// formatUntrackedFiles formats untracked files for display
func formatUntrackedFiles(files string) string {
	var sb strings.Builder
	sb.WriteString("Untracked files:\n\n")

	fileList := strings.Split(strings.TrimSpace(files), "\n")
	for _, file := range fileList {
		if file == "" {
			continue
		}
		// Use green color for new files
		fileStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("10"))
		sb.WriteString("  " + fileStyle.Render("+ "+file) + " (new file)\n")
	}

	return sb.String()
}

// formatDiff formats git diff output with enhanced styling
func formatDiff(raw string) string {
	// Git already provides colored output with --color=always,
	// so we can mostly pass it through, but we'll add some headers
	var sb strings.Builder
	lines := strings.Split(raw, "\n")

	for _, line := range lines {
		switch {
		case strings.HasPrefix(line, "diff --git"):
			// Extract file name and add a nice header
			parts := strings.Fields(line)
			if len(parts) >= 4 {
				file := strings.TrimPrefix(parts[2], "a/")
				headerStyle := lipgloss.NewStyle().
					Foreground(lipgloss.Color("12")).
					Bold(true)
				sb.WriteString("\n")
				sb.WriteString(headerStyle.Render("═══ " + file + " ═══"))
				sb.WriteString("\n")
			}
		case strings.HasPrefix(line, "index") || strings.HasPrefix(line, "new file") || strings.HasPrefix(line, "deleted file"):
			// Skip index lines for cleaner output
			continue
		case strings.HasPrefix(line, "---") || strings.HasPrefix(line, "+++"):
			// Skip the file marker lines as we have our own header
			continue
		default:
			// Pass through all other lines (including colored ones from git)
			sb.WriteString(line)
			sb.WriteString("\n")
		}
	}

	return sb.String()
}

// handleScriptCommand expands the /script command and returns a tea.Cmd
func (m model) handleScriptCommand() tea.Cmd {
	return func() tea.Msg {
		ctx, cancel := context.WithTimeout(m.ctx, 10*time.Second)
		defer cancel()

		resp, err := m.client.ExpandCommand(ctx, &agent.ExpandCommandRequest{
			Name: "script",
		})
		if err != nil {
			return scriptExpandedMsg{err: err}
		}
		return scriptExpandedMsg{prompt: resp.Expanded}
	}
}

// abortSession aborts the current running session
func (m model) abortSession() tea.Cmd {
	return func() tea.Msg {
		if m.session == nil {
			return sessionAbortedMsg{err: fmt.Errorf("no active session")}
		}

		ctx, cancel := context.WithTimeout(m.ctx, 5*time.Second)
		defer cancel()

		err := m.client.AbortSession(ctx, m.session.ID)
		return sessionAbortedMsg{err: err}
	}
}

func printUsage() {
	fmt.Fprintf(os.Stderr, `agent - AI agent CLI

Usage:
  agent [OPTIONS]                Start interactive TUI
  agent exec [OPTIONS] [PROMPT]  Run agent non-interactively
  agent e [OPTIONS] [PROMPT]     Alias for exec
  agent apply [OPTIONS]          Apply latest session diff to working tree
  agent a [OPTIONS]              Alias for apply
  agent help                     Show this help
  agent version                  Show version

Interactive Mode Options:
  --prompt TEXT      Initial prompt to send
  --backend URL      Backend URL (overrides embedded server)
  --embedded         Use embedded server (default: true)

Exec Command Options:
  -f, --file FILE    Read prompt from file
  -m, --model MODEL  Model to use
  -C, --cd DIR       Working directory
  --timeout SECONDS  Timeout in seconds (0 = no timeout)
  --full             Include all messages in output
  --json             Output in JSON format
  --stream           Stream output in real-time
  --no-tools         Disable tool execution
  -q, --quiet        Suppress status messages

Apply Command Options:
  --session ID       Apply diff from specific session (default: latest)
  --dry-run          Show what would be applied without changes
  --reverse          Reverse the diff (unapply changes)
  --check            Check if diff applies cleanly
  --3way             Use 3-way merge for conflicts
  -q, --quiet        Suppress output except errors

Examples:
  agent                                    Start interactive TUI
  agent exec "List all files"              Run non-interactively
  echo "List files" | agent exec           Read from stdin
  agent exec -f prompt.txt --json          Read from file, JSON output
  agent exec --timeout 300 --stream "task" With timeout and streaming
  agent apply                              Apply latest session diff
  agent apply --dry-run                    Preview what would be applied
  agent apply --session ses_abc123         Apply specific session diff
  agent apply --reverse                    Reverse (unapply) the diff

Environment Variables:
  ANTHROPIC_API_KEY  Required - Claude API key
  OPENCODE_SERVER    Backend server URL
  LOG_LEVEL          Logging level (debug, info, warn, error)
`)
}

func main() {
	version := Version
	if version != "dev" && !strings.HasPrefix(version, "v") {
		version = "v" + version
	}

	// Check for subcommands before parsing flags
	args := os.Args[1:]
	if len(args) > 0 {
		switch args[0] {
		case "exec", "e":
			// Run non-interactive exec command
			os.Exit(execCommand(args[1:]))
		case "apply", "a":
			// Apply session diff
			cmd, err := NewApplyCommand(args[1:])
			if err != nil {
				fmt.Fprintf(os.Stderr, "Error parsing apply command: %v\n", err)
				os.Exit(1)
			}
			if err := cmd.Run(); err != nil {
				fmt.Fprintf(os.Stderr, "Error: %v\n", err)
				os.Exit(1)
			}
			os.Exit(0)
		case "help", "--help", "-h":
			printUsage()
			os.Exit(0)
		case "version", "--version", "-v":
			fmt.Println("agent", version)
			os.Exit(0)
		}
	}

	// Parse flags for interactive TUI mode
	prompt := flag.String("prompt", "", "Initial prompt to send")
	backendURL := flag.String("backend", "", "Backend URL (overrides embedded server)")
	useEmbedded := flag.Bool("embedded", true, "Use embedded server (default: true)")
	flag.Parse()

	// Initialize logging from LOG_LEVEL env var
	logger := agent.NewLoggerFromEnv()
	agent.SetLogger(logger)
	logger.Info("TUI starting", "version", version)

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

		logger.Info("Starting embedded server...")
		var err error
		serverProcess, url, err = embedded.StartServerWithLogger(ctx, logger)
		if err != nil {
			logger.Error("Failed to start embedded server", "error", err.Error())
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
			logger.Info("Received shutdown signal")
			cleanup()
			os.Exit(0)
		}()

		logger.Info("Server running", "url", url)
	} else if url == "" {
		url = "http://localhost:8000"
		logger.Debug("Using default backend URL", "url", url)
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
		agent.WithLogger(logger),
	)
	logger.Debug("SDK client created", "url", url, "cwd", cwd)

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

	// Create program without mouse capture to allow native text selection
	// Use arrow keys, Page Up/Down, Home/End to scroll
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
