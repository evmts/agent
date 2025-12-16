package keybind

import (
	"strings"
)

// ShortcutCategory represents a category for grouping shortcuts
type ShortcutCategory string

const (
	CategoryNavigation ShortcutCategory = "Navigation"
	CategorySession    ShortcutCategory = "Session"
	CategoryView       ShortcutCategory = "View"
	CategoryActions    ShortcutCategory = "Actions"
	CategoryInput      ShortcutCategory = "Input"
	CategoryDialogs    ShortcutCategory = "Dialogs"
)

// KeyBinding represents a single keybinding
type KeyBinding struct {
	Key         string           // The key combination (e.g., "ctrl+c", "enter")
	Description string           // Human-readable description
	Action      Action           // The action to perform
	Category    ShortcutCategory // Category for shortcuts overlay
}

// KeyMap contains all keybindings
type KeyMap struct {
	bindings map[string]KeyBinding
}

// NewKeyMap creates a new empty keymap
func NewKeyMap() *KeyMap {
	return &KeyMap{
		bindings: make(map[string]KeyBinding),
	}
}

// Add adds a keybinding to the map
func (km *KeyMap) Add(key string, description string, action Action) {
	km.bindings[key] = KeyBinding{
		Key:         key,
		Description: description,
		Action:      action,
		Category:    categorizeAction(action),
	}
}

// AddWithCategory adds a keybinding with explicit category
func (km *KeyMap) AddWithCategory(key string, description string, action Action, category ShortcutCategory) {
	km.bindings[key] = KeyBinding{
		Key:         key,
		Description: description,
		Action:      action,
		Category:    category,
	}
}

// categorizeAction automatically categorizes an action
func categorizeAction(action Action) ShortcutCategory {
	switch action {
	case ActionScrollUp, ActionScrollDown, ActionPageUp, ActionPageDown,
		ActionScrollToTop, ActionScrollToBottom:
		return CategoryNavigation
	case ActionNewSession, ActionForkSession, ActionRevertSession,
		ActionRenameSession, ActionSessionList, ActionShowDiff:
		return CategorySession
	case ActionToggleSidebar, ActionToggleMarkdown, ActionToggleThinking,
		ActionToggleMouse, ActionToggleCompact, ActionCycleTheme:
		return CategoryView
	case ActionCopyMessage, ActionCopyTranscript, ActionUndoMessage,
		ActionShowContextMenu, ActionCyclePermissions:
		return CategoryActions
	case ActionSubmit, ActionCancel, ActionFocusInput, ActionOpenEditor,
		ActionSearch, ActionSearchNext, ActionSearchPrev:
		return CategoryInput
	case ActionShowHelp, ActionShowModels, ActionShowAgents, ActionShowCommands,
		ActionShowThemes, ActionShowStatus, ActionShowSettings, ActionShowShortcuts, ActionShowMCP:
		return CategoryDialogs
	default:
		return CategoryActions
	}
}

// Get returns the action for a key, or ActionNone if not found
func (km *KeyMap) Get(key string) Action {
	if binding, ok := km.bindings[key]; ok {
		return binding.Action
	}
	return ActionNone
}

// GetBinding returns the full keybinding for a key
func (km *KeyMap) GetBinding(key string) (KeyBinding, bool) {
	binding, ok := km.bindings[key]
	return binding, ok
}

// All returns all keybindings
func (km *KeyMap) All() []KeyBinding {
	bindings := make([]KeyBinding, 0, len(km.bindings))
	for _, binding := range km.bindings {
		bindings = append(bindings, binding)
	}
	return bindings
}

// DefaultKeyMap returns the default keybindings
func DefaultKeyMap() *KeyMap {
	km := NewKeyMap()

	// Application control
	km.Add("ctrl+c", "Quit application", ActionQuit)
	km.Add("q", "Quit application (when not typing)", ActionQuit)
	km.Add("ctrl+n", "Create new session", ActionNewSession)
	km.Add("ctrl+l", "Clear chat (keep session)", ActionClearChat)
	km.Add("ctrl+/", "Toggle sidebar", ActionToggleSidebar)
	km.Add("?", "Show keyboard shortcuts", ActionShowShortcuts)
	km.Add("ctrl+h", "Show help", ActionShowHelp)
	km.Add("ctrl+m", "Select AI model", ActionShowModels)
	km.Add("ctrl+t", "Toggle thinking display", ActionToggleThinking)
	km.Add("ctrl+a", "Select agent", ActionShowAgents)
	km.Add("ctrl+r", "Toggle markdown rendering", ActionToggleMarkdown)
	km.Add("ctrl+y", "Toggle mouse mode (for text selection)", ActionToggleMouse)
	km.Add("ctrl+shift+c", "Toggle compact view", ActionToggleCompact)
	km.Add("ctrl+p", "Open command palette", ActionShowCommands)
	km.Add("ctrl+s", "Switch session", ActionSessionList)
	km.Add("ctrl+e", "Open external editor", ActionOpenEditor)

	// New dialogs
	km.Add("ctrl+k", "Open command palette", ActionShowCommands)
	km.Add("T", "Select theme", ActionShowThemes)
	km.Add("ctrl+,", "Open settings", ActionShowSettings)
	km.Add("ctrl+i", "Show status", ActionShowStatus)
	km.Add("F2", "Rename session", ActionRenameSession)

	// Session actions
	km.Add("ctrl+shift+f", "Fork current session", ActionForkSession)
	km.Add("ctrl+z", "Revert session changes", ActionRevertSession)
	km.Add("ctrl+d", "Show file changes diff", ActionShowDiff)
	km.Add("ctrl+u", "Undo last message", ActionUndoMessage)
	km.Add("m", "Message actions menu", ActionShowContextMenu)

	// Search actions
	km.Add("ctrl+f", "Search in chat history", ActionSearch)
	km.Add("n", "Next search match", ActionSearchNext)
	km.Add("N", "Previous search match", ActionSearchPrev)

	// Navigation
	km.Add("pgup", "Scroll up one page", ActionPageUp)
	km.Add("pgdown", "Scroll down one page", ActionPageDown)
	km.Add("home", "Jump to first message", ActionScrollToTop)
	km.Add("end", "Jump to last message", ActionScrollToBottom)

	// Vim-like navigation (when not in input mode)
	km.Add("j", "Scroll down", ActionScrollDown)
	km.Add("k", "Scroll up", ActionScrollUp)
	km.Add("g", "Jump to first message", ActionScrollToTop)
	km.Add("G", "Jump to last message", ActionScrollToBottom)
	km.Add("/", "Focus input (search)", ActionFocusInput)

	// Input control
	km.Add("enter", "Submit message", ActionSubmit)
	km.Add("esc", "Cancel/close", ActionCancel)

	// Permissions mode
	km.Add("shift+tab", "Cycle permissions mode", ActionCyclePermissions)

	// Interrupt handling
	km.Add("r", "Resume interrupted operation", ActionResume)

	return km
}

// ParseKey normalizes a key string for consistent lookup
func ParseKey(key string) string {
	// Normalize the key string
	key = strings.ToLower(key)
	key = strings.TrimSpace(key)

	// Handle special cases
	switch key {
	case "ctrl+slash":
		return "ctrl+/"
	case "shift+/":
		return "?"
	case "shift+g":
		return "G"
	}

	return key
}
