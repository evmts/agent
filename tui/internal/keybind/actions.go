package keybind

// Action represents a keybinding action
type Action string

// Available actions
const (
	// Application control
	ActionQuit          Action = "quit"
	ActionNewSession    Action = "new_session"
	ActionClearChat     Action = "clear_chat"
	ActionToggleSidebar Action = "toggle_sidebar"
	ActionShowHelp      Action = "show_help"
	ActionCycleTheme    Action = "cycle_theme"
	ActionShowAgents    Action = "show_agents"

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

	// None for unknown/unbound keys
	ActionNone Action = ""
)
