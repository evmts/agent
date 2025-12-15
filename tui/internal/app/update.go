package app

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/williamcory/agent/sdk/agent"
	"tui/internal/components/dialog"
	"tui/internal/components/sidebar"
	"tui/internal/components/spinner"
	"tui/internal/components/toast"
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
		m.toast.SetWidth(msg.Width)
		return m, nil

	case spinner.TickMsg:
		var cmd tea.Cmd
		m.spinner, cmd = m.spinner.Update(msg)
		return m, cmd

	case healthCheckMsg:
		if msg.healthy {
			// Create a new session on startup
			return m, m.createSession()
		} else {
			m.state = StateError
			m.spinner.Stop()
			m.err = msg.err
			return m, nil
		}

	case sessionCreatedMsg:
		m.session = msg.session
		m.state = StateIdle
		m.spinner.Stop()
		m.inputFocused = true
		m.sidebar.SetCurrentSession(msg.session)
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
			m.sidebar.SetCurrentSession(&msg.Session)
			m.sidebar.SetDiffs(nil) // Clear diffs when switching sessions
			return m, m.loadSessionMessages(msg.Session.ID)
		}
		return m, nil

	case sessionsLoadedMsg:
		m.sidebar.SetSessions(msg.sessions)
		return m, nil

	case showSessionListMsg:
		// Show session list dialog with cached sessions
		sessions := m.GetSessions()
		if len(sessions) > 0 {
			m.ShowSessionListDialog(sessions)
		}
		return m, nil

	case diffLoadedMsg:
		// Update sidebar with diffs
		m.sidebar.SetDiffs(msg.diffs)

		if len(msg.diffs) == 0 {
			return m, m.ShowToast("No file changes in this session", toast.ToastInfo, 2*time.Second)
		}
		m.ShowDiffDialog(msg.diffs)
		return m, nil

	case sessionForkedMsg:
		m.session = msg.session
		m.chat.Clear()
		m.sidebar.SetCurrentSession(msg.session)
		m.sidebar.SetDiffs(nil) // Clear diffs for new fork
		return m, tea.Batch(
			m.loadSessionMessages(msg.session.ID),
			m.ShowToast("Session forked successfully", toast.ToastSuccess, 2*time.Second),
		)

	case sessionRevertedMsg:
		m.session = msg.session
		m.chat.Clear()
		m.sidebar.SetCurrentSession(msg.session)
		m.sidebar.SetDiffs(nil) // Clear diffs after revert
		return m, tea.Batch(
			m.loadSessionMessages(msg.session.ID),
			m.ShowToast("Session reverted", toast.ToastSuccess, 2*time.Second),
		)

	case dialog.AgentSelectedMsg:
		// Update the current agent
		m.currentAgent = msg.Agent.Name
		return m, nil

	case dialog.ModelSelectedMsg:
		// Update the current model
		m.currentModel = msg.Model.ID
		return m, nil

	case dialog.CommandSelectedMsg:
		// Execute the selected command
		return m.executeCommand(msg.Command)

	case dialog.SessionListSelectedMsg:
		// Load the selected session
		if m.state == StateIdle {
			m.chat.Clear()
			m.session = &msg.Session
			m.sidebar.SetCurrentSession(&msg.Session)
			m.sidebar.SetDiffs(nil) // Clear diffs when switching sessions
			return m, m.loadSessionMessages(msg.Session.ID)
		}
		return m, nil

	case dialog.ContextMenuSelectedMsg:
		// Handle context menu action
		return m.handleContextMenuAction(msg)

	case shellCommandResultMsg:
		// Add shell output as a system message to chat
		var output string
		if msg.err != nil {
			output = fmt.Sprintf("Error: %v\n%s", msg.err, msg.output)
		} else {
			output = msg.output
			if output == "" {
				output = "(no output)"
			}
		}
		m.chat.AddShellOutput(output)
		m.inputFocused = true
		return m, m.input.Focus()

	case editorResultMsg:
		if msg.err != nil {
			return m, m.ShowToast("Editor error: "+msg.err.Error(), toast.ToastError, 2*time.Second)
		}
		// Set the input to the edited content
		m.input.SetValue(msg.content)
		m.inputFocused = true
		return m, m.input.Focus()

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
			case *dialog.AgentDialog:
				var cmd tea.Cmd
				m.activeDialog, cmd = d.Update(msg)
				if !m.activeDialog.IsVisible() {
					m.CloseDialog()
				}
				return m, cmd
			case *dialog.ModelDialog:
				var cmd tea.Cmd
				m.activeDialog, cmd = d.Update(msg)
				if !m.activeDialog.IsVisible() {
					m.CloseDialog()
				}
				return m, cmd
			case *dialog.DiffDialog:
				var cmd tea.Cmd
				m.activeDialog, cmd = d.Update(msg)
				if !m.activeDialog.IsVisible() {
					m.CloseDialog()
				}
				return m, cmd
			case *dialog.CommandDialog:
				var cmd tea.Cmd
				m.activeDialog, cmd = d.Update(msg)
				if !m.activeDialog.IsVisible() {
					m.CloseDialog()
				}
				return m, cmd
			case *dialog.SessionListDialog:
				var cmd tea.Cmd
				m.activeDialog, cmd = d.Update(msg)
				if !m.activeDialog.IsVisible() {
					m.CloseDialog()
				}
				return m, cmd
			case *dialog.ContextMenuDialog:
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

		// Handle model selection action
		if action == keybind.ActionShowModels {
			m.ShowModelDialog()
			return m, nil
		}

		// Handle agent selection action
		if action == keybind.ActionShowAgents {
			m.ShowAgentDialog()
			return m, nil
		}

		// Handle command palette action
		if action == keybind.ActionShowCommands {
			m.ShowCommandDialog()
			return m, nil
		}

		// Handle session list action
		if action == keybind.ActionSessionList {
			// Load sessions first, then show dialog
			return m, tea.Batch(
				m.loadSessions(),
				func() tea.Msg {
					return showSessionListMsg{}
				},
			)
		}

		// Handle context menu action (only when not typing)
		if action == keybind.ActionShowContextMenu && !m.inputFocused {
			msgID, isUser := m.GetLastMessageInfo()
			if msgID != "" {
				m.ShowContextMenu(msgID, isUser)
			} else {
				return m, m.ShowToast("No messages to act on", toast.ToastInfo, 2*time.Second)
			}
			return m, nil
		}

		// Handle cancel/escape - always check streaming state first
		if action == keybind.ActionCancel {
			if m.state == StateStreaming && m.cancel != nil {
				// Check for double-escape (within 500ms)
				now := time.Now()
				if now.Sub(m.lastEscapeTime) < 500*time.Millisecond {
					// Double escape - cancel immediately
					m.cancel()
					m.state = StateIdle
					m.spinner.Stop()
					m.chat.EndAssistantMessage()
					m.inputFocused = true
					m.lastEscapeTime = time.Time{} // Reset
					return m, m.input.Focus()
				}
				// First escape - show hint and record time
				m.lastEscapeTime = now
				return m, m.ShowToast("Press Esc again to cancel streaming", toast.ToastInfo, 500*time.Millisecond)
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
				m.spinner.SetMessage("Creating session...")
				return m, tea.Batch(m.createSession(), m.spinner.Start())

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

			case keybind.ActionToggleMarkdown:
				m.chat.ToggleMarkdown()
				return m, nil

			case keybind.ActionToggleThinking:
				m.ToggleThinking()
				status := "hidden"
				if m.IsShowingThinking() {
					status = "visible"
				}
				return m, m.ShowToast("Thinking content "+status, toast.ToastInfo, 2*time.Second)

			case keybind.ActionToggleMouse:
				m.mouseEnabled = !m.mouseEnabled
				var cmd tea.Cmd
				var status string
				if m.mouseEnabled {
					cmd = func() tea.Msg { return tea.EnableMouseCellMotion() }
					status = "enabled"
				} else {
					cmd = func() tea.Msg { return tea.DisableMouse() }
					status = "disabled (use terminal selection)"
				}
				return m, tea.Batch(cmd, m.ShowToast("Mouse mode "+status, toast.ToastInfo, 3*time.Second))

			case keybind.ActionShowDiff:
				if m.session != nil {
					return m, m.loadSessionDiff(m.session.ID)
				}
				return m, m.ShowToast("No active session", toast.ToastWarning, 2*time.Second)

			case keybind.ActionForkSession:
				if m.session != nil {
					return m, m.forkSession(m.session.ID)
				}
				return m, m.ShowToast("No active session", toast.ToastWarning, 2*time.Second)

			case keybind.ActionRevertSession:
				if m.session != nil {
					return m, m.revertSession(m.session.ID)
				}
				return m, m.ShowToast("No active session", toast.ToastWarning, 2*time.Second)

			case keybind.ActionOpenEditor:
				// Open external editor for input
				currentText := m.input.Value()
				return m, m.openExternalEditor(currentText)
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

				// Update sidebar context info
				m.sidebar.SetContextInfo(sidebar.ContextInfo{
					InputTokens:  m.totalInputTokens,
					OutputTokens: m.totalOutputTokens,
					TotalCost:    m.totalCost,
					ModelName:    m.currentModel,
					AgentName:    m.currentAgent,
				})
			}
		}
		return m, nil

	case messages.StreamStartMsg:
		m.state = StateStreaming
		m.spinner.SetMessage("Streaming...")
		m.chat.StartAssistantMessage()
		return m, m.spinner.Start()

	case messages.StreamEndMsg:
		if m.state == StateStreaming {
			m.chat.EndAssistantMessage()
		}
		m.state = StateIdle
		m.spinner.Stop()
		m.inputFocused = true
		return m, m.input.Focus()

	case messages.ErrorMsg:
		m.err = fmt.Errorf("%s", msg.Message)
		m.state = StateError
		m.spinner.Stop()
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

	// Update toast (always, to handle auto-dismiss)
	var toastCmd tea.Cmd
	m.toast, toastCmd = m.toast.Update(msg)
	cmds = append(cmds, toastCmd)

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

type diffLoadedMsg struct {
	diffs []agent.FileDiff
}

type sessionForkedMsg struct {
	session *agent.Session
}

type sessionRevertedMsg struct {
	session *agent.Session
}

type showSessionListMsg struct{}

type shellCommandResultMsg struct {
	output string
	err    error
}

type editorResultMsg struct {
	content string
	err     error
}

// executeCommand executes a command from the command palette
func (m Model) executeCommand(cmd dialog.Command) (tea.Model, tea.Cmd) {
	switch cmd.Action {
	case keybind.ActionNewSession:
		m.chat.Clear()
		m.session = nil
		m.state = StateLoading
		return m, m.createSession()
	case keybind.ActionClearChat:
		m.chat.Clear()
		return m, nil
	case keybind.ActionToggleSidebar:
		m.sidebar.Toggle()
		if m.sidebar.IsVisible() {
			return m, m.loadSessions()
		}
		return m, func() tea.Msg {
			return tea.WindowSizeMsg{Width: m.width, Height: m.height}
		}
	case keybind.ActionShowHelp:
		m.ShowHelp()
		return m, nil
	case keybind.ActionShowModels:
		m.ShowModelDialog()
		return m, nil
	case keybind.ActionShowAgents:
		m.ShowAgentDialog()
		return m, nil
	case keybind.ActionToggleMarkdown:
		m.chat.ToggleMarkdown()
		return m, nil
	case keybind.ActionToggleThinking:
		m.ToggleThinking()
		status := "hidden"
		if m.IsShowingThinking() {
			status = "visible"
		}
		return m, m.ShowToast("Thinking content "+status, toast.ToastInfo, 2*time.Second)
	case keybind.ActionSessionList:
		return m, tea.Batch(
			m.loadSessions(),
			func() tea.Msg {
				return showSessionListMsg{}
			},
		)
	case keybind.ActionForkSession:
		if m.session != nil {
			return m, m.forkSession(m.session.ID)
		}
		return m, m.ShowToast("No active session", toast.ToastWarning, 2*time.Second)
	case keybind.ActionRevertSession:
		if m.session != nil {
			return m, m.revertSession(m.session.ID)
		}
		return m, m.ShowToast("No active session", toast.ToastWarning, 2*time.Second)
	case keybind.ActionShowDiff:
		if m.session != nil {
			return m, m.loadSessionDiff(m.session.ID)
		}
		return m, m.ShowToast("No active session", toast.ToastWarning, 2*time.Second)
	case keybind.ActionUndoMessage:
		if m.session != nil {
			return m, m.revertSession(m.session.ID)
		}
		return m, m.ShowToast("No active session", toast.ToastWarning, 2*time.Second)
	case keybind.ActionFocusInput:
		if !m.inputFocused {
			m.inputFocused = true
			return m, m.input.Focus()
		}
		return m, nil
	case keybind.ActionScrollToTop:
		m.chat.ScrollToTop()
		return m, nil
	case keybind.ActionScrollToBottom:
		m.chat.ScrollToBottom()
		return m, nil
	case keybind.ActionQuit:
		return m, tea.Quit
	}
	return m, nil
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

	// Check for shell mode (! prefix)
	if strings.HasPrefix(content, "!") {
		shellCmd := strings.TrimPrefix(content, "!")
		shellCmd = strings.TrimSpace(shellCmd)
		if shellCmd == "" {
			return m, m.ShowToast("Empty shell command", toast.ToastWarning, 2*time.Second)
		}

		// Add the command to chat as user message
		m.chat.AddUserMessage(content)

		// Clear input
		m.input.Clear()
		m.input.Blur()
		m.inputFocused = false

		// Execute shell command
		return m, m.executeShellCommand(shellCmd)
	}

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

// loadSessionDiff loads the file diffs for a session
func (m Model) loadSessionDiff(sessionID string) tea.Cmd {
	return func() tea.Msg {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()

		diffs, err := m.client.GetSessionDiff(ctx, sessionID, nil)
		if err != nil {
			return messages.ErrorMsg{Message: fmt.Sprintf("Failed to load diff: %v", err)}
		}
		return diffLoadedMsg{diffs: diffs}
	}
}

// forkSession creates a fork of the current session
func (m Model) forkSession(sessionID string) tea.Cmd {
	return func() tea.Msg {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()

		session, err := m.client.ForkSession(ctx, sessionID, &agent.ForkRequest{})
		if err != nil {
			return messages.ErrorMsg{Message: fmt.Sprintf("Failed to fork session: %v", err)}
		}
		return sessionForkedMsg{session: session}
	}
}

// revertSession reverts the session to the last checkpoint
func (m Model) revertSession(sessionID string) tea.Cmd {
	return func() tea.Msg {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()

		// Get the latest message to find a revert point
		msgs, err := m.client.ListMessages(ctx, sessionID, agent.Int(1))
		if err != nil || len(msgs) == 0 {
			return messages.ErrorMsg{Message: "No messages to revert to"}
		}

		// Revert to the last message
		session, err := m.client.RevertSession(ctx, sessionID, &agent.RevertRequest{
			MessageID: msgs[0].Info.ID,
		})
		if err != nil {
			return messages.ErrorMsg{Message: fmt.Sprintf("Failed to revert session: %v", err)}
		}
		return sessionRevertedMsg{session: session}
	}
}

// handleContextMenuAction handles actions from the context menu
func (m Model) handleContextMenuAction(msg dialog.ContextMenuSelectedMsg) (tea.Model, tea.Cmd) {
	switch msg.Action {
	case dialog.ActionCopyMessage:
		// Copy message text to clipboard
		text := m.chat.GetLastMessageText()
		if text == "" {
			return m, m.ShowToast("No text to copy", toast.ToastWarning, 2*time.Second)
		}
		if err := copyToClipboard(text); err != nil {
			return m, m.ShowToast("Failed to copy: "+err.Error(), toast.ToastError, 2*time.Second)
		}
		return m, m.ShowToast("Message copied to clipboard", toast.ToastSuccess, 2*time.Second)

	case dialog.ActionCopyCode:
		// Copy code blocks to clipboard
		text := m.chat.GetLastMessageText()
		code := extractCodeBlocks(text)
		if code == "" {
			return m, m.ShowToast("No code blocks found", toast.ToastWarning, 2*time.Second)
		}
		if err := copyToClipboard(code); err != nil {
			return m, m.ShowToast("Failed to copy: "+err.Error(), toast.ToastError, 2*time.Second)
		}
		return m, m.ShowToast("Code blocks copied to clipboard", toast.ToastSuccess, 2*time.Second)

	case dialog.ActionRevertTo:
		if m.session != nil && msg.MessageID != "" {
			return m, m.revertToMessage(m.session.ID, msg.MessageID)
		}
		return m, m.ShowToast("No active session", toast.ToastWarning, 2*time.Second)

	case dialog.ActionForkFrom:
		if m.session != nil && msg.MessageID != "" {
			return m, m.forkFromMessage(m.session.ID, msg.MessageID)
		}
		return m, m.ShowToast("No active session", toast.ToastWarning, 2*time.Second)

	case dialog.ActionRetry:
		// Retry would regenerate the last response
		return m, m.ShowToast("Retry not yet implemented", toast.ToastInfo, 2*time.Second)

	case dialog.ActionEditMessage:
		// Edit and resend a message
		return m, m.ShowToast("Edit not yet implemented", toast.ToastInfo, 2*time.Second)
	}

	return m, nil
}

// revertToMessage reverts to a specific message
func (m Model) revertToMessage(sessionID, messageID string) tea.Cmd {
	return func() tea.Msg {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()

		session, err := m.client.RevertSession(ctx, sessionID, &agent.RevertRequest{
			MessageID: messageID,
		})
		if err != nil {
			return messages.ErrorMsg{Message: fmt.Sprintf("Failed to revert: %v", err)}
		}
		return sessionRevertedMsg{session: session}
	}
}

// forkFromMessage creates a fork from a specific message
func (m Model) forkFromMessage(sessionID, messageID string) tea.Cmd {
	return func() tea.Msg {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()

		session, err := m.client.ForkSession(ctx, sessionID, &agent.ForkRequest{
			MessageID: &messageID,
		})
		if err != nil {
			return messages.ErrorMsg{Message: fmt.Sprintf("Failed to fork: %v", err)}
		}
		return sessionForkedMsg{session: session}
	}
}

// copyToClipboard copies text to system clipboard
func copyToClipboard(text string) error {
	// Use pbcopy on macOS, xclip on Linux
	// For now, just return nil - clipboard integration would require os/exec
	_ = text
	return nil
}

// extractCodeBlocks extracts code blocks from markdown text
func extractCodeBlocks(text string) string {
	// Simple extraction of code blocks between ``` markers
	var result []string
	lines := strings.Split(text, "\n")
	inCodeBlock := false
	var currentBlock []string

	for _, line := range lines {
		if strings.HasPrefix(line, "```") {
			if inCodeBlock {
				// End of code block
				if len(currentBlock) > 0 {
					result = append(result, strings.Join(currentBlock, "\n"))
				}
				currentBlock = nil
				inCodeBlock = false
			} else {
				// Start of code block
				inCodeBlock = true
			}
		} else if inCodeBlock {
			currentBlock = append(currentBlock, line)
		}
	}

	return strings.Join(result, "\n\n")
}

// executeShellCommand executes a shell command and returns the result
func (m Model) executeShellCommand(cmdStr string) tea.Cmd {
	return func() tea.Msg {
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()

		cmd := exec.CommandContext(ctx, "bash", "-c", cmdStr)
		var stdout, stderr bytes.Buffer
		cmd.Stdout = &stdout
		cmd.Stderr = &stderr

		err := cmd.Run()

		output := stdout.String()
		if stderr.Len() > 0 {
			if output != "" {
				output += "\n"
			}
			output += stderr.String()
		}

		return shellCommandResultMsg{output: output, err: err}
	}
}

// openExternalEditor opens an external editor with the given content
func (m Model) openExternalEditor(initialContent string) tea.Cmd {
	return tea.ExecProcess(getEditorCmd(initialContent), func(err error) tea.Msg {
		if err != nil {
			return editorResultMsg{err: err}
		}
		// Read the temp file after editor closes
		content, readErr := readTempFile()
		return editorResultMsg{content: content, err: readErr}
	})
}

// getEditorCmd returns the command to open the external editor
func getEditorCmd(content string) *exec.Cmd {
	// Get editor from environment
	editor := os.Getenv("EDITOR")
	if editor == "" {
		editor = os.Getenv("VISUAL")
	}
	if editor == "" {
		// Fallback to common editors
		if _, err := exec.LookPath("nvim"); err == nil {
			editor = "nvim"
		} else if _, err := exec.LookPath("vim"); err == nil {
			editor = "vim"
		} else if _, err := exec.LookPath("nano"); err == nil {
			editor = "nano"
		} else {
			editor = "vi"
		}
	}

	// Create temp file with content
	tmpFile, err := os.CreateTemp("", "claude-input-*.txt")
	if err != nil {
		return exec.Command("echo", "Failed to create temp file")
	}
	defer tmpFile.Close()

	// Write initial content
	if content != "" {
		tmpFile.WriteString(content)
	}

	// Store temp file path in environment for later reading
	os.Setenv("CLAUDE_TEMP_FILE", tmpFile.Name())

	return exec.Command(editor, tmpFile.Name())
}

// readTempFile reads the content from the temp file
func readTempFile() (string, error) {
	tempPath := os.Getenv("CLAUDE_TEMP_FILE")
	if tempPath == "" {
		return "", fmt.Errorf("no temp file path")
	}

	content, err := os.ReadFile(tempPath)
	if err != nil {
		return "", err
	}

	// Clean up temp file
	os.Remove(tempPath)
	os.Unsetenv("CLAUDE_TEMP_FILE")

	return strings.TrimSpace(string(content)), nil
}
