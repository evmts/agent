package keybind

// Action represents a keybinding action
type Action string

// Available actions
const (
	// Application control
	ActionQuit            Action = "quit"
	ActionNewSession      Action = "new_session"
	ActionClearChat       Action = "clear_chat"
	ActionToggleSidebar   Action = "toggle_sidebar"
	ActionShowHelp        Action = "show_help"
	ActionShowModels      Action = "show_models"
	ActionCycleTheme      Action = "cycle_theme"
	ActionShowAgents      Action = "show_agents"
	ActionToggleMarkdown  Action = "toggle_markdown"
	ActionToggleThinking  Action = "toggle_thinking"
	ActionToggleMouse     Action = "toggle_mouse"
	ActionShowCommands    Action = "show_commands"
	ActionToggleTimestamp Action = "toggle_timestamps"
	ActionToggleToolInfo  Action = "toggle_tool_info"
	ActionShowThemes      Action = "show_themes"
	ActionShowStatus      Action = "show_status"
	ActionShowSettings    Action = "show_settings"

	// Session actions
	ActionForkSession     Action = "fork_session"
	ActionRevertSession   Action = "revert_session"
	ActionShowDiff        Action = "show_diff"
	ActionRenameSession   Action = "rename_session"
	ActionShareSession    Action = "share_session"
	ActionCopyMessage     Action = "copy_message"
	ActionCopyTranscript  Action = "copy_transcript"
	ActionUndoMessage     Action = "undo_message"
	ActionRedoMessage     Action = "redo_message"
	ActionSessionList     Action = "session_list"
	ActionShowContextMenu Action = "show_context_menu"

	// Navigation
	ActionScrollUp       Action = "scroll_up"
	ActionScrollDown     Action = "scroll_down"
	ActionPageUp         Action = "page_up"
	ActionPageDown       Action = "page_down"
	ActionScrollToTop    Action = "scroll_to_top"
	ActionScrollToBottom Action = "scroll_to_bottom"

	// Input control
	ActionSubmit     Action = "submit"
	ActionCancel     Action = "cancel"
	ActionFocusInput Action = "focus_input"
	ActionOpenEditor Action = "open_editor"

	// Permissions mode
	ActionCyclePermissions Action = "cycle_permissions"

	// None for unknown/unbound keys
	ActionNone Action = ""
)
