package keybind

import (
	"strings"
)

// KeyBinding represents a single keybinding
type KeyBinding struct {
	Key         string // The key combination (e.g., "ctrl+c", "enter")
	Description string // Human-readable description
	Action      Action // The action to perform
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
	km.Add("?", "Show help", ActionShowHelp)
	km.Add("ctrl+t", "Cycle theme", ActionCycleTheme)
	km.Add("ctrl+a", "Select agent", ActionShowAgents)

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
