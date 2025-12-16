package app

import (
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/williamcory/agent/tui/internal/components/dialog"
	"github.com/williamcory/agent/tui/internal/components/toast"
	"github.com/williamcory/agent/tui/internal/keybind"
)

// Common duration constant
const secondDuration = time.Second

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
		return m, m.ShowToast("Thinking content "+status, toast.ToastInfo, 2*secondDuration)
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
		return m, m.ShowToast("No active session", toast.ToastWarning, 2*secondDuration)
	case keybind.ActionRevertSession:
		if m.session != nil {
			return m, m.revertSession(m.session.ID)
		}
		return m, m.ShowToast("No active session", toast.ToastWarning, 2*secondDuration)
	case keybind.ActionShowDiff:
		if m.session != nil {
			return m, m.loadSessionDiff(m.session.ID)
		}
		return m, m.ShowToast("No active session", toast.ToastWarning, 2*secondDuration)
	case keybind.ActionUndoMessage:
		if m.session != nil {
			return m, m.revertSession(m.session.ID)
		}
		return m, m.ShowToast("No active session", toast.ToastWarning, 2*secondDuration)
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

// handleContextMenuAction handles actions from the context menu
func (m Model) handleContextMenuAction(msg dialog.ContextMenuSelectedMsg) (tea.Model, tea.Cmd) {
	switch msg.Action {
	case dialog.ActionCopyMessage:
		// Copy message text to clipboard
		text := m.chat.GetLastMessageText()
		if text == "" {
			return m, m.ShowToast("No text to copy", toast.ToastWarning, 2*secondDuration)
		}
		if err := copyToClipboard(text); err != nil {
			return m, m.ShowToast("Failed to copy: "+err.Error(), toast.ToastError, 2*secondDuration)
		}
		return m, m.ShowToast("Message copied to clipboard", toast.ToastSuccess, 2*secondDuration)

	case dialog.ActionCopyCode:
		// Copy code blocks to clipboard
		text := m.chat.GetLastMessageText()
		code := extractCodeBlocks(text)
		if code == "" {
			return m, m.ShowToast("No code blocks found", toast.ToastWarning, 2*secondDuration)
		}
		if err := copyToClipboard(code); err != nil {
			return m, m.ShowToast("Failed to copy: "+err.Error(), toast.ToastError, 2*secondDuration)
		}
		return m, m.ShowToast("Code blocks copied to clipboard", toast.ToastSuccess, 2*secondDuration)

	case dialog.ActionRevertTo:
		if m.session != nil && msg.MessageID != "" {
			return m, m.revertToMessage(m.session.ID, msg.MessageID)
		}
		return m, m.ShowToast("No active session", toast.ToastWarning, 2*secondDuration)

	case dialog.ActionForkFrom:
		if m.session != nil && msg.MessageID != "" {
			return m, m.forkFromMessage(m.session.ID, msg.MessageID)
		}
		return m, m.ShowToast("No active session", toast.ToastWarning, 2*secondDuration)

	case dialog.ActionRetry:
		// Retry would regenerate the last response
		return m, m.ShowToast("Retry not yet implemented", toast.ToastInfo, 2*secondDuration)

	case dialog.ActionEditMessage:
		// Edit and resend a message
		return m, m.ShowToast("Edit not yet implemented", toast.ToastInfo, 2*secondDuration)
	}

	return m, nil
}
