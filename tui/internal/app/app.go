package app

import (
	"context"
	"strings"
	"time"

	"github.com/williamcory/agent/sdk/agent"
	"github.com/charmbracelet/bubbles/textarea"
	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/glamour"
	"github.com/charmbracelet/lipgloss"
)

// Styles - Claude Code inspired
var (
	userStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("5")). // Magenta
			Bold(true)

	assistantStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("4")). // Blue
			Bold(true)

	dimStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("241"))

	errorStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("1")) // Red
)

// Message represents a chat message
type Message struct {
	Role    string
	Content string
}

// Model is the main application model
type Model struct {
	client    *agent.Client
	sessionID string

	messages []Message
	viewport viewport.Model
	textarea textarea.Model
	renderer *glamour.TermRenderer

	width  int
	height int

	streaming      bool
	currentContent string
	err            error
	initialized    bool

	// For streaming
	streamCtx    context.Context
	streamCancel context.CancelFunc
	eventCh      <-chan *agent.StreamEvent
	errCh        <-chan error
}

// New creates a new Model
func New(backendURL string) Model {
	ta := textarea.New()
	ta.Placeholder = "Type a message... (Enter to send, Esc to quit)"
	ta.Focus()
	ta.CharLimit = 0
	ta.SetWidth(80)
	ta.SetHeight(3)
	ta.ShowLineNumbers = false
	ta.KeyMap.InsertNewline.SetEnabled(false)

	renderer, _ := glamour.NewTermRenderer(
		glamour.WithAutoStyle(),
		glamour.WithWordWrap(80),
	)

	client := agent.NewClient(backendURL)

	return Model{
		client:   client,
		textarea: ta,
		renderer: renderer,
		messages: []Message{},
	}
}

// Init initializes the model
func (m Model) Init() tea.Cmd {
	return tea.Batch(
		textarea.Blink,
		m.createSession(),
	)
}

// Update handles messages
func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmds []tea.Cmd

	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.Type {
		case tea.KeyCtrlC, tea.KeyEsc:
			if m.streamCancel != nil {
				m.streamCancel()
			}
			return m, tea.Quit

		case tea.KeyEnter:
			if m.streaming {
				return m, nil
			}
			content := strings.TrimSpace(m.textarea.Value())
			if content == "" {
				return m, nil
			}

			// Add user message
			m.messages = append(m.messages, Message{Role: "user", Content: content})
			m.textarea.Reset()
			m.streaming = true
			m.currentContent = ""

			// Update viewport with new message
			m.updateViewportContent()
			m.viewport.GotoBottom()

			return m, m.startStream(content)
		}

	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height

		inputHeight := 5
		helpHeight := 1
		viewportHeight := m.height - inputHeight - helpHeight - 1

		if !m.initialized {
			m.viewport = viewport.New(m.width, viewportHeight)
			m.viewport.SetContent("")
			m.initialized = true
		} else {
			m.viewport.Width = m.width
			m.viewport.Height = viewportHeight
		}

		m.textarea.SetWidth(m.width - 2)
		if m.renderer != nil {
			m.renderer, _ = glamour.NewTermRenderer(
				glamour.WithAutoStyle(),
				glamour.WithWordWrap(m.width-4),
			)
		}
		m.updateViewportContent()

	case sessionCreatedMsg:
		m.sessionID = msg.sessionID

	case streamStartedMsg:
		m.eventCh = msg.eventCh
		m.errCh = msg.errCh
		return m, m.waitForStreamEvent()

	case streamUpdateMsg:
		m.currentContent = msg.content
		m.updateStreamingContent()
		m.viewport.GotoBottom()
		return m, m.waitForStreamEvent()

	case streamDoneMsg:
		m.streaming = false
		if m.currentContent != "" {
			m.messages = append(m.messages, Message{Role: "assistant", Content: m.currentContent})
		}
		m.currentContent = ""
		m.updateViewportContent()
		m.viewport.GotoBottom()

	case streamErrorMsg:
		m.streaming = false
		m.err = msg.err
		m.messages = append(m.messages, Message{Role: "error", Content: msg.err.Error()})
		m.currentContent = ""
		m.updateViewportContent()

	case errMsg:
		m.err = msg.err
	}

	// Update textarea
	var cmd tea.Cmd
	m.textarea, cmd = m.textarea.Update(msg)
	cmds = append(cmds, cmd)

	// Update viewport
	m.viewport, cmd = m.viewport.Update(msg)
	cmds = append(cmds, cmd)

	return m, tea.Batch(cmds...)
}

func (m *Model) updateViewportContent() {
	var content strings.Builder

	for _, msg := range m.messages {
		switch msg.Role {
		case "user":
			content.WriteString(userStyle.Render("> You") + "\n")
			content.WriteString(msg.Content + "\n\n")
		case "assistant":
			content.WriteString(assistantStyle.Render("Claude") + "\n")
			rendered, err := m.renderer.Render(msg.Content)
			if err != nil {
				content.WriteString(msg.Content)
			} else {
				content.WriteString(strings.TrimSpace(rendered))
			}
			content.WriteString("\n\n")
		case "error":
			content.WriteString(errorStyle.Render("Error: "+msg.Content) + "\n\n")
		}
	}

	m.viewport.SetContent(content.String())
}

func (m *Model) updateStreamingContent() {
	var content strings.Builder

	for _, msg := range m.messages {
		switch msg.Role {
		case "user":
			content.WriteString(userStyle.Render("> You") + "\n")
			content.WriteString(msg.Content + "\n\n")
		case "assistant":
			content.WriteString(assistantStyle.Render("Claude") + "\n")
			rendered, err := m.renderer.Render(msg.Content)
			if err != nil {
				content.WriteString(msg.Content)
			} else {
				content.WriteString(strings.TrimSpace(rendered))
			}
			content.WriteString("\n\n")
		case "error":
			content.WriteString(errorStyle.Render("Error: "+msg.Content) + "\n\n")
		}
	}

	// Add streaming content
	if m.currentContent != "" {
		content.WriteString(assistantStyle.Render("Claude") + "\n")
		rendered, err := m.renderer.Render(m.currentContent)
		if err != nil {
			content.WriteString(m.currentContent)
		} else {
			content.WriteString(strings.TrimSpace(rendered))
		}
		content.WriteString(dimStyle.Render(" █") + "\n\n")
	}

	m.viewport.SetContent(content.String())
}

// View renders the UI
func (m Model) View() string {
	if !m.initialized {
		return "Connecting to server..."
	}

	// Chat viewport
	chatView := m.viewport.View()

	// Input
	inputView := m.textarea.View()

	// Help
	var help string
	if m.streaming {
		help = dimStyle.Render("  Thinking...")
	} else {
		help = dimStyle.Render("  Enter to send | Esc to quit")
	}

	return lipgloss.JoinVertical(
		lipgloss.Left,
		chatView,
		inputView,
		help,
	)
}

// Messages for tea.Cmd

type sessionCreatedMsg struct {
	sessionID string
}

type streamStartedMsg struct {
	eventCh <-chan *agent.StreamEvent
	errCh   <-chan error
}

type streamUpdateMsg struct {
	content string
}

type streamDoneMsg struct{}

type streamErrorMsg struct {
	err error
}

type errMsg struct {
	err error
}

// Commands

func (m *Model) createSession() tea.Cmd {
	return func() tea.Msg {
		ctx := context.Background()
		session, err := m.client.CreateSession(ctx, &agent.CreateSessionRequest{})
		if err != nil {
			return errMsg{err: err}
		}
		return sessionCreatedMsg{sessionID: session.ID}
	}
}

func (m *Model) startStream(content string) tea.Cmd {
	return func() tea.Msg {
		ctx, cancel := context.WithCancel(context.Background())
		m.streamCtx = ctx
		m.streamCancel = cancel

		req := &agent.PromptRequest{
			Parts: []interface{}{
				agent.TextPartInput{Type: "text", Text: content},
			},
		}

		eventCh, errCh, err := m.client.SendMessage(ctx, m.sessionID, req)
		if err != nil {
			return streamErrorMsg{err: err}
		}

		return streamStartedMsg{eventCh: eventCh, errCh: errCh}
	}
}

func (m *Model) waitForStreamEvent() tea.Cmd {
	return func() tea.Msg {
		if m.eventCh == nil {
			return streamDoneMsg{}
		}

		// Use a short timeout to keep UI responsive
		timeout := time.After(100 * time.Millisecond)

		select {
		case event, ok := <-m.eventCh:
			if !ok {
				return streamDoneMsg{}
			}
			// Extract text from part updates
			if event.Part != nil && event.Part.Type == "text" {
				return streamUpdateMsg{content: event.Part.Text}
			}
			// Continue waiting for more events
			return streamUpdateMsg{content: m.currentContent}

		case err, ok := <-m.errCh:
			if ok && err != nil {
				return streamErrorMsg{err: err}
			}
			return streamDoneMsg{}

		case <-timeout:
			// Keep polling
			return streamUpdateMsg{content: m.currentContent}
		}
	}
}
