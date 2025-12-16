package app

import (
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"tui/internal/components/dialog"
	"tui/internal/components/toast"
	"tui/internal/keybind"
)

// handleKeyMsg handles all keyboard input
func (m Model) handleKeyMsg(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	// If there's an active dialog, handle it first
	if m.HasActiveDialog() {
		return m.handleDialogKeyMsg(msg)
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

	// Handle theme dialog action
	if action == keybind.ActionShowThemes {
		m.ShowThemeDialog()
		return m, nil
	}

	// Handle status dialog action
	if action == keybind.ActionShowStatus {
		m.ShowStatusDialog()
		return m, nil
	}

	// Handle settings dialog action
	if action == keybind.ActionShowSettings {
		m.ShowSettingsDialog()
		return m, nil
	}

	// Handle rename session action
	if action == keybind.ActionRenameSession {
		if m.session != nil {
			m.ShowRenameDialog()
		} else {
			return m, m.ShowToast("No active session to rename", toast.ToastWarning, 2*time.Second)
		}
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

	return m, nil
}

// handleDialogKeyMsg handles keyboard input when a dialog is active
func (m Model) handleDialogKeyMsg(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
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
	case *dialog.ThemeDialog:
		var cmd tea.Cmd
		m.activeDialog, cmd = d.Update(msg)
		if !m.activeDialog.IsVisible() {
			m.CloseDialog()
		}
		return m, cmd
	case *dialog.StatusDialog:
		var cmd tea.Cmd
		m.activeDialog, cmd = d.Update(msg)
		if !m.activeDialog.IsVisible() {
			m.CloseDialog()
		}
		return m, cmd
	case *dialog.SettingsDialog:
		var cmd tea.Cmd
		m.activeDialog, cmd = d.Update(msg)
		if !m.activeDialog.IsVisible() {
			m.CloseDialog()
		}
		return m, cmd
	case *dialog.RenameDialog:
		var cmd tea.Cmd
		m.activeDialog, cmd = d.Update(msg)
		if !m.activeDialog.IsVisible() {
			m.CloseDialog()
		}
		return m, cmd
	}
	return m, nil
}
