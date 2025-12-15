package app

import (
	"context"
	"fmt"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/williamcory/agent/sdk/agent"
	"tui/internal/components/dialog"
	"tui/internal/components/sidebar"
	"tui/internal/keybind"
	"tui/internal/messages"
)

// Update handles all application messages
func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmds []tea.Cmd

	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		m.ready = true

		// Calculate component sizes
		// Reserve space for: header (2), input (5), status bar (2), padding (2)
		chatHeight := msg.Height - 11
		if chatHeight < 5 {
			chatHeight = 5
		}

		// Adjust widths based on sidebar visibility
		sidebarWidth := 32 // sidebar width + border
		chatWidth := msg.Width
		if m.sidebar.IsVisible() {
			chatWidth = msg.Width - sidebarWidth
		}

		m.chat.SetSize(chatWidth, chatHeight)
		m.input.SetWidth(chatWidth)
		m.sidebar.SetSize(sidebarWidth, msg.Height)
		return m, nil

	case healthCheckMsg:
		if msg.healthy {
			// Create a new session on startup
			return m, m.createSession()
		} else {
			m.state = StateError
			m.err = msg.err
			return m, nil
		}

	case sessionCreatedMsg:
		m.session = msg.session
		m.state = StateIdle
		m.inputFocused = true
		return m, m.input.Focus()

	case messagesLoadedMsg:
		m.chat.LoadMessages(msg.messages)
		m.state = StateIdle
		return m, nil

	case sidebar.SessionSelectedMsg:
		// Load the selected session
		if m.state == StateIdle {
			m.chat.Clear()
			m.session = &msg.Session
			return m, m.loadSessionMessages(msg.Session.ID)
		}
		return m, nil

	case sessionsLoadedMsg:
		m.sidebar.SetSessions(msg.sessions)
		return m, nil

	case tea.KeyMsg:
		// If there's an active dialog, handle it first
		if m.HasActiveDialog() {
			switch d := m.activeDialog.(type) {
			case *dialog.HelpDialog:
				var cmd tea.Cmd
				m.activeDialog, cmd = d.Update(msg)
				if !m.activeDialog.IsVisible() {
					m.CloseDialog()
				}
				return m, cmd
			case *dialog.ConfirmDialog:
				var cmd tea.Cmd
				m.activeDialog, cmd = d.Update(msg)
				if !m.activeDialog.IsVisible() {
					m.CloseDialog()
				}
				return m, cmd
			}
		}

		action := m.keyMap.Get(msg.String())

		// Handle help action
		if action == keybind.ActionShowHelp {
			m.ShowHelp()
			return m, nil
		}

		// Handle cancel/escape - always check streaming state first
		if action == keybind.ActionCancel {
			if m.state == StateStreaming && m.cancel != nil {
				m.cancel()
				m.state = StateIdle
				m.chat.EndAssistantMessage()
				m.inputFocused = true
				return m, m.input.Focus()
			}
			// If input is focused, unfocus it
			if m.inputFocused {
				m.input.Blur()
				m.inputFocused = false
				return m, nil
			}
		}

		// Handle quit
		if action == keybind.ActionQuit {
			// If streaming, cancel first
			if m.state == StateStreaming && m.cancel != nil {
				m.cancel()
				m.state = StateIdle
				m.chat.EndAssistantMessage()
			}
			return m, tea.Quit
		}

		// Handle submit
		if action == keybind.ActionSubmit && m.inputFocused {
			if m.state == StateIdle && m.session != nil && m.input.Value() != "" {
				return m.sendMessage()
			}
		}

		// Handle actions that require idle state
		if m.state == StateIdle {
			switch action {
			case keybind.ActionNewSession:
				m.chat.Clear()
				m.session = nil
				m.state = StateLoading
				return m, m.createSession()

			case keybind.ActionClearChat:
				m.chat.Clear()
				return m, nil

			case keybind.ActionFocusInput:
				if !m.inputFocused {
					m.inputFocused = true
					return m, m.input.Focus()
				}

			case keybind.ActionToggleSidebar:
				m.sidebar.Toggle()
				// Load sessions when opening sidebar
				if m.sidebar.IsVisible() {
					return m, m.loadSessions()
				}
				// Recalculate sizes when toggling
				return m, func() tea.Msg {
					return tea.WindowSizeMsg{Width: m.width, Height: m.height}
				}
			}
		}

		// Navigation actions - only when input is not focused
		if !m.inputFocused {
			switch action {
			case keybind.ActionScrollUp:
				m.chat.ScrollUp()
				return m, nil
			case keybind.ActionScrollDown:
				m.chat.ScrollDown()
				return m, nil
			case keybind.ActionPageUp:
				m.chat.PageUp()
				return m, nil
			case keybind.ActionPageDown:
				m.chat.PageDown()
				return m, nil
			case keybind.ActionScrollToTop:
				m.chat.ScrollToTop()
				return m, nil
			case keybind.ActionScrollToBottom:
				m.chat.ScrollToBottom()
				return m, nil
			}
		}

	// SDK Stream Events
	case messages.StreamEventMsg:
		if msg.Event != nil {
			m.chat.HandleStreamEvent(msg.Event)

			// Update token tracking
			if msg.Event.Message != nil {
				if msg.Event.Message.Tokens != nil {
					tokens := msg.Event.Message.Tokens
					m.totalInputTokens = tokens.Input
					m.totalOutputTokens = tokens.Output + tokens.Reasoning
				}
				if msg.Event.Message.Cost > 0 {
					m.totalCost = msg.Event.Message.Cost
				}
				// Track model info
				if msg.Event.Message.ModelID != "" {
					m.currentModel = msg.Event.Message.ModelID
				}
				if msg.Event.Message.Agent != "" {
					m.currentAgent = msg.Event.Message.Agent
				}
			}
		}
		return m, nil

	case messages.StreamStartMsg:
		m.state = StateStreaming
		m.chat.StartAssistantMessage()
		return m, nil

	case messages.StreamEndMsg:
		if m.state == StateStreaming {
			m.chat.EndAssistantMessage()
		}
		m.state = StateIdle
		m.inputFocused = true
		return m, m.input.Focus()

	case messages.ErrorMsg:
		m.err = fmt.Errorf("%s", msg.Message)
		m.state = StateError
		m.chat.EndAssistantMessage()
		m.inputFocused = true
		return m, m.input.Focus()
	}

	// Update child components when idle and focused
	if m.state == StateIdle && m.inputFocused {
		var cmd tea.Cmd
		m.input, cmd = m.input.Update(msg)
		cmds = append(cmds, cmd)
	}

	// Update sidebar if visible
	if m.sidebar.IsVisible() {
		var cmd tea.Cmd
		m.sidebar, cmd = m.sidebar.Update(msg)
		cmds = append(cmds, cmd)
	}

	// Always allow chat scrolling (viewport handles its own key events)
	var cmd tea.Cmd
	m.chat, cmd = m.chat.Update(msg)
	cmds = append(cmds, cmd)

	return m, tea.Batch(cmds...)
}

// Internal message types
type sessionCreatedMsg struct {
	session *agent.Session
}

type messagesLoadedMsg struct {
	messages []agent.MessageWithParts
}

type sessionsLoadedMsg struct {
	sessions []agent.Session
}

// createSession creates a new session
func (m Model) createSession() tea.Cmd {
	return func() tea.Msg {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()

		session, err := m.client.CreateSession(ctx, &agent.CreateSessionRequest{
			Title: agent.String("Claude TUI Session"),
		})
		if err != nil {
			return messages.ErrorMsg{Message: fmt.Sprintf("Failed to create session: %v", err)}
		}
		return sessionCreatedMsg{session: session}
	}
}

// sendMessage sends the current input to the backend
func (m Model) sendMessage() (tea.Model, tea.Cmd) {
	content := m.input.Value()

	// Add user message to chat
	m.chat.AddUserMessage(content)

	// Clear input and unfocus
	m.input.Clear()
	m.input.Blur()
	m.inputFocused = false

	// Create cancellable context
	m.ctx, m.cancel = context.WithCancel(context.Background())

	// Get program from shared state
	p := m.shared.GetProgram()

	// Start streaming
	return m, m.streamMessage(m.ctx, m.session.ID, content, p)
}

// streamMessage streams a message using the SDK
func (m Model) streamMessage(ctx context.Context, sessionID, content string, p *tea.Program) tea.Cmd {
	return func() tea.Msg {
		// Prepare the request
		req := &agent.PromptRequest{
			Parts: []interface{}{
				agent.TextPartInput{Type: "text", Text: content},
			},
		}

		// Start streaming
		eventCh, errCh, err := m.client.SendMessage(ctx, sessionID, req)
		if err != nil {
			return messages.ErrorMsg{Message: fmt.Sprintf("Failed to send message: %v", err)}
		}

		// Signal stream start
		p.Send(messages.StreamStartMsg{})

		// Process events
		for {
			select {
			case <-ctx.Done():
				return messages.StreamEndMsg{}
			case err := <-errCh:
				if err != nil {
					return messages.ErrorMsg{Message: fmt.Sprintf("Stream error: %v", err)}
				}
				return messages.StreamEndMsg{}
			case event, ok := <-eventCh:
				if !ok {
					return messages.StreamEndMsg{}
				}
				// Send event to the program
				p.Send(messages.StreamEventMsg{Event: event})
			}
		}
	}
}

// loadSessions loads all sessions from the backend
func (m Model) loadSessions() tea.Cmd {
	return func() tea.Msg {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()

		sessions, err := m.client.ListSessions(ctx)
		if err != nil {
			return messages.ErrorMsg{Message: fmt.Sprintf("Failed to load sessions: %v", err)}
		}
		return sessionsLoadedMsg{sessions: sessions}
	}
}

// loadSessionMessages loads messages for a specific session
func (m Model) loadSessionMessages(sessionID string) tea.Cmd {
	return func() tea.Msg {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()

		msgs, err := m.client.ListMessages(ctx, sessionID, nil)
		if err != nil {
			return messages.ErrorMsg{Message: fmt.Sprintf("Failed to load messages: %v", err)}
		}
		return messagesLoadedMsg{messages: msgs}
	}
}
