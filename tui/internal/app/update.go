package app

import (
	"fmt"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/williamcory/agent/sdk/agent"
	"tui/internal/components/dialog"
	"tui/internal/components/sidebar"
	"tui/internal/components/spinner"
	"tui/internal/components/toast"
	"tui/internal/config"
	"tui/internal/messages"
	"tui/internal/notification"
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
			// Mark as connected but don't create session yet - wait for resume check
			m.connected = true
			return m, m.detectGitBranch()
		} else {
			m.state = StateError
			m.connected = false
			m.spinner.Stop()
			m.err = msg.err
			return m, nil
		}

	case resumeCheckMsg:
		// Handle resume session check result
		if !msg.hasSession || msg.info == nil {
			// No session to resume, create a new one
			return m, m.createSession()
		}

		// We have a session to potentially resume
		switch msg.preference {
		case config.ResumeAlwaysContinue:
			// Auto-resume the session
			m.state = StateLoading
			return m, m.loadExistingSession(msg.info.SessionID)
		case config.ResumeAlwaysNew:
			// Auto-create new session
			return m, m.createSession()
		default:
			// Show resume dialog to ask user
			m.ShowResumeDialog(msg.info)
			return m, nil
		}

	case dialog.ResumeSelectedMsg:
		// Handle user's resume choice
		if msg.RememberPreference {
			// Save the preference (async, ignore errors)
			go func() {
				_ = config.SetResumePreference(msg.Preference)
			}()
		}

		switch msg.Action {
		case dialog.ResumeContinue:
			// Load the previous session
			m.state = StateLoading
			return m, m.loadExistingSession(msg.SessionID)
		case dialog.ResumeNew:
			// Create a new session
			return m, m.createSession()
		case dialog.ResumeSelect:
			// Show session list
			return m, tea.Batch(
				m.loadSessions(),
				func() tea.Msg {
					return showSessionListMsg{}
				},
			)
		default:
			// Cancel - just create a new session
			return m, m.createSession()
		}

	case resumeLoadSessionMsg:
		m.state = StateLoading
		return m, m.loadExistingSession(msg.sessionID)

	case resumeCreateNewSessionMsg:
		return m, m.createSession()

	case resumeShowSessionListMsg:
		return m, tea.Batch(
			m.loadSessions(),
			func() tea.Msg {
				return showSessionListMsg{}
			},
		)

	case gitBranchMsg:
		m.gitBranch = msg.branch
		// Also refresh git status when we detect the branch
		return m, m.refreshGitStatus()

	case sessionCreatedMsg:
		m.session = msg.session
		m.state = StateIdle
		m.spinner.Stop()
		m.inputFocused = true
		m.sidebar.SetCurrentSession(msg.session)

		// If there are messages in this session (i.e., we resumed), load them
		// Otherwise, just focus input for a new session
		if msg.session != nil {
			// Check if this is a resumed session by seeing if we have message data
			// For resumed sessions, we need to load the messages
			return m, tea.Batch(
				m.loadSessionMessages(msg.session.ID),
				m.input.Focus(),
			)
		}
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

	case sidebar.GitStatusUpdatedMsg:
		// Update git status in sidebar
		m.sidebar.SetGitStatus(msg.Status)
		return m, nil

	case sidebar.GitRefreshMsg:
		// Refresh git status
		return m, m.refreshGitStatus()

	case sidebar.GitStageToggleMsg:
		// Stage/unstage a file
		return m, m.handleGitStageToggle(msg)

	case sidebar.GitStageAllMsg:
		// Stage all files
		return m, m.handleGitStageAll()

	case sidebar.GitDiffMsg:
		// View diff for a file
		return m, m.handleGitDiff(msg)

	case sidebar.GitCommitMsg:
		// Show commit dialog
		return m, m.handleGitCommit()

	case gitErrorMsg:
		// Handle git operation errors
		return m, m.ShowToast(msg.err.Error(), toast.ToastError, 3*time.Second)

	case gitDiffViewMsg:
		// Show diff view (for now, just show a toast)
		// TODO: Implement a proper diff view dialog
		return m, m.ShowToast(fmt.Sprintf("Viewing diff for %s", msg.file), toast.ToastInfo, 2*time.Second)

	case gitCommitDialogMsg:
		// TODO: Show commit dialog to get message
		// For now, just show a toast
		return m, m.ShowToast("Commit dialog not yet implemented", toast.ToastInfo, 2*time.Second)

	case gitCommitSuccessMsg:
		// Commit successful, refresh git status
		return m, tea.Batch(
			m.ShowToast(fmt.Sprintf("Committed: %s", msg.message), toast.ToastSuccess, 3*time.Second),
			m.refreshGitStatus(),
		)

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

	case dialog.ThemeSelectedMsg:
		// Theme was changed
		return m, m.ShowToast("Theme changed to "+msg.ThemeName, toast.ToastSuccess, 2*time.Second)

	case dialog.SettingChangedMsg:
		// Handle setting changes
		switch msg.Key {
		case "show_thinking":
			if msg.Value != m.IsShowingThinking() {
				m.ToggleThinking()
			}
		case "render_markdown":
			if msg.Value != m.chat.IsMarkdownEnabled() {
				m.chat.ToggleMarkdown()
			}
		case "mouse_mode":
			if msg.Value != m.mouseEnabled {
				m.mouseEnabled = msg.Value
			}
		}
		return m, nil

	case dialog.RenameConfirmedMsg:
		// Rename the session
		return m, m.renameSession(msg.SessionID, msg.NewTitle)

	case dialog.RenameCancelledMsg:
		// Just closed, nothing to do
		return m, nil

	case mcpServersLoadedMsg:
		if msg.err != nil {
			return m, m.ShowToast("Failed to load MCP servers: "+msg.err.Error(), toast.ToastError, 3*time.Second)
		}
		// Update the MCP dialog with loaded servers
		if servers, ok := msg.servers.([]agent.MCPServer); ok {
			m.mcpDialog.SetServers(servers)
			m.ShowMCPDialog()
		}
		return m, nil

	case sessionRenamedMsg:
		m.session = msg.session
		m.sidebar.SetCurrentSession(msg.session)
		return m, m.ShowToast("Session renamed", toast.ToastSuccess, 2*time.Second)

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
		return m.handleKeyMsg(msg)

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

		// Save current session info after message completes
		m.saveCurrentSessionInfo()

		// Play completion notification
		go notification.NotifyComplete(m.notificationConfig)

		return m, m.input.Focus()

	case messages.ErrorMsg:
		m.err = fmt.Errorf("%s", msg.Message)
		m.state = StateError
		m.spinner.Stop()
		m.chat.EndAssistantMessage()
		m.inputFocused = true

		// Play error notification
		go notification.NotifyError(m.notificationConfig)

		return m, m.input.Focus()
	}

	// Update child components when idle and focused
	if m.state == StateIdle && m.inputFocused {
		var cmd tea.Cmd
		prevValue := m.input.Value()
		m.input, cmd = m.input.Update(msg)
		cmds = append(cmds, cmd)

		// If search is active and input changed, update search
		if m.chat.IsSearchActive() && m.input.Value() != prevValue {
			m.chat.UpdateSearchQuery(m.input.Value())
		}
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
