package dialog

import (
	"sort"
	"strings"

	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"tui/internal/keybind"
	"tui/internal/styles"
)

// Command represents a command in the palette
type Command struct {
	ID          string         // Unique identifier
	Title       string         // Display title
	Description string         // Command description
	Category    string         // Category for grouping
	Action      keybind.Action // Associated action
	Keybind     string         // Keybind display string
}

// CommandSelectedMsg is sent when a command is selected
type CommandSelectedMsg struct {
	Command Command
}

// CommandDialog displays a searchable command palette
type CommandDialog struct {
	commands      []Command
	filtered      []Command
	selectedIndex int
	searchInput   textinput.Model
	visible       bool
	width         int
	height        int
}

// NewCommandDialog creates a new command palette dialog
func NewCommandDialog(keyMap *keybind.KeyMap) *CommandDialog {
	ti := textinput.New()
	ti.Placeholder = "Search commands..."
	ti.Focus()
	ti.CharLimit = 50
	ti.Width = 40

	commands := buildCommandList(keyMap)

	return &CommandDialog{
		commands:      commands,
		filtered:      commands,
		selectedIndex: 0,
		searchInput:   ti,
		visible:       true,
		width:         60,
		height:        20,
	}
}

// buildCommandList creates the list of available commands
func buildCommandList(keyMap *keybind.KeyMap) []Command {
	// Build a map of action -> keybind
	actionKeybinds := make(map[keybind.Action]string)
	for _, binding := range keyMap.All() {
		if _, exists := actionKeybinds[binding.Action]; !exists {
			actionKeybinds[binding.Action] = binding.Key
		}
	}

	commands := []Command{
		// Session commands
		{ID: "session.new", Title: "New Session", Description: "Create a new chat session", Category: "Session", Action: keybind.ActionNewSession, Keybind: actionKeybinds[keybind.ActionNewSession]},
		{ID: "session.list", Title: "Switch Session", Description: "Switch to another session", Category: "Session", Action: keybind.ActionSessionList, Keybind: actionKeybinds[keybind.ActionSessionList]},
		{ID: "session.fork", Title: "Fork Session", Description: "Create a branch from current session", Category: "Session", Action: keybind.ActionForkSession, Keybind: actionKeybinds[keybind.ActionForkSession]},
		{ID: "session.revert", Title: "Revert Session", Description: "Undo recent changes", Category: "Session", Action: keybind.ActionRevertSession, Keybind: actionKeybinds[keybind.ActionRevertSession]},
		{ID: "session.diff", Title: "Show Diff", Description: "View file changes in session", Category: "Session", Action: keybind.ActionShowDiff, Keybind: actionKeybinds[keybind.ActionShowDiff]},
		{ID: "session.undo", Title: "Undo Message", Description: "Undo the last message", Category: "Session", Action: keybind.ActionUndoMessage, Keybind: actionKeybinds[keybind.ActionUndoMessage]},
		{ID: "session.clear", Title: "Clear Chat", Description: "Clear chat history", Category: "Session", Action: keybind.ActionClearChat, Keybind: actionKeybinds[keybind.ActionClearChat]},

		// View commands
		{ID: "view.sidebar", Title: "Toggle Sidebar", Description: "Show/hide the session sidebar", Category: "View", Action: keybind.ActionToggleSidebar, Keybind: actionKeybinds[keybind.ActionToggleSidebar]},
		{ID: "view.thinking", Title: "Toggle Thinking", Description: "Show/hide AI thinking process", Category: "View", Action: keybind.ActionToggleThinking, Keybind: actionKeybinds[keybind.ActionToggleThinking]},
		{ID: "view.markdown", Title: "Toggle Markdown", Description: "Toggle markdown rendering", Category: "View", Action: keybind.ActionToggleMarkdown, Keybind: actionKeybinds[keybind.ActionToggleMarkdown]},
		{ID: "view.help", Title: "Show Help", Description: "Display keyboard shortcuts", Category: "View", Action: keybind.ActionShowHelp, Keybind: actionKeybinds[keybind.ActionShowHelp]},

		// Agent commands
		{ID: "agent.select", Title: "Select Agent", Description: "Choose a different agent", Category: "Agent", Action: keybind.ActionShowAgents, Keybind: actionKeybinds[keybind.ActionShowAgents]},
		{ID: "agent.model", Title: "Select Model", Description: "Choose a different AI model", Category: "Agent", Action: keybind.ActionShowModels, Keybind: actionKeybinds[keybind.ActionShowModels]},

		// Input commands
		{ID: "input.editor", Title: "Open Editor", Description: "Edit in external editor", Category: "Input", Action: keybind.ActionOpenEditor, Keybind: actionKeybinds[keybind.ActionOpenEditor]},
		{ID: "input.focus", Title: "Focus Input", Description: "Focus the input field", Category: "Input", Action: keybind.ActionFocusInput, Keybind: actionKeybinds[keybind.ActionFocusInput]},

		// Navigation
		{ID: "nav.top", Title: "Go to Top", Description: "Scroll to first message", Category: "Navigation", Action: keybind.ActionScrollToTop, Keybind: actionKeybinds[keybind.ActionScrollToTop]},
		{ID: "nav.bottom", Title: "Go to Bottom", Description: "Scroll to last message", Category: "Navigation", Action: keybind.ActionScrollToBottom, Keybind: actionKeybinds[keybind.ActionScrollToBottom]},

		// System
		{ID: "app.quit", Title: "Quit", Description: "Exit the application", Category: "System", Action: keybind.ActionQuit, Keybind: actionKeybinds[keybind.ActionQuit]},
	}

	// Sort by category, then by title
	sort.Slice(commands, func(i, j int) bool {
		if commands[i].Category != commands[j].Category {
			return commands[i].Category < commands[j].Category
		}
		return commands[i].Title < commands[j].Title
	})

	return commands
}

// Update handles messages for the command dialog
func (d *CommandDialog) Update(msg tea.Msg) (Dialog, tea.Cmd) {
	var cmd tea.Cmd

	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "esc":
			d.visible = false
			return d, nil
		case "enter":
			if len(d.filtered) > 0 && d.selectedIndex < len(d.filtered) {
				d.visible = false
				return d, func() tea.Msg {
					return CommandSelectedMsg{Command: d.filtered[d.selectedIndex]}
				}
			}
		case "up", "ctrl+k", "ctrl+p":
			if d.selectedIndex > 0 {
				d.selectedIndex--
			}
			return d, nil
		case "down", "ctrl+j", "ctrl+n":
			if d.selectedIndex < len(d.filtered)-1 {
				d.selectedIndex++
			}
			return d, nil
		}
	}

	// Update search input
	d.searchInput, cmd = d.searchInput.Update(msg)

	// Filter commands based on search
	d.filterCommands()

	return d, cmd
}

// filterCommands filters the command list based on search input
func (d *CommandDialog) filterCommands() {
	query := strings.ToLower(d.searchInput.Value())
	if query == "" {
		d.filtered = d.commands
		d.selectedIndex = 0
		return
	}

	var filtered []Command
	for _, cmd := range d.commands {
		titleMatch := strings.Contains(strings.ToLower(cmd.Title), query)
		descMatch := strings.Contains(strings.ToLower(cmd.Description), query)
		catMatch := strings.Contains(strings.ToLower(cmd.Category), query)
		if titleMatch || descMatch || catMatch {
			filtered = append(filtered, cmd)
		}
	}
	d.filtered = filtered

	// Reset selection if out of bounds
	if d.selectedIndex >= len(d.filtered) {
		if len(d.filtered) > 0 {
			d.selectedIndex = len(d.filtered) - 1
		} else {
			d.selectedIndex = 0
		}
	}
}

// GetTitle returns the dialog title
func (d *CommandDialog) GetTitle() string {
	return "Command Palette"
}

// IsVisible returns whether the dialog is visible
func (d *CommandDialog) IsVisible() bool {
	return d.visible
}

// SetVisible sets the visibility
func (d *CommandDialog) SetVisible(visible bool) {
	d.visible = visible
}

// Render renders the command palette dialog
func (d *CommandDialog) Render(termWidth, termHeight int) string {
	if !d.visible {
		return ""
	}

	theme := styles.GetCurrentTheme()

	// Calculate dimensions
	dialogWidth := d.width
	if dialogWidth > termWidth-4 {
		dialogWidth = termWidth - 4
	}

	// Title
	titleStyle := lipgloss.NewStyle().
		Foreground(theme.Primary).
		Bold(true).
		Padding(0, 1).
		Width(dialogWidth - 4).
		Align(lipgloss.Center)

	title := titleStyle.Render("Command Palette")

	// Search input
	inputStyle := lipgloss.NewStyle().
		Foreground(theme.TextPrimary).
		Padding(0, 1).
		Width(dialogWidth - 6)

	searchView := inputStyle.Render(d.searchInput.View())

	// Command list
	var listLines []string
	maxVisible := 10
	startIdx := 0
	if d.selectedIndex >= maxVisible {
		startIdx = d.selectedIndex - maxVisible + 1
	}

	currentCategory := ""
	visibleCount := 0

	for i := startIdx; i < len(d.filtered) && visibleCount < maxVisible; i++ {
		cmd := d.filtered[i]

		// Category header
		if cmd.Category != currentCategory {
			currentCategory = cmd.Category
			catStyle := lipgloss.NewStyle().
				Foreground(theme.Muted).
				Bold(true).
				PaddingLeft(1)
			listLines = append(listLines, catStyle.Render(currentCategory))
		}

		// Command line
		isSelected := i == d.selectedIndex
		cmdTitle := cmd.Title
		cmdKeybind := cmd.Keybind

		var lineStyle lipgloss.Style
		if isSelected {
			lineStyle = lipgloss.NewStyle().
				Foreground(theme.TextPrimary).
				Background(theme.Primary).
				Width(dialogWidth - 6).
				PaddingLeft(2)
		} else {
			lineStyle = lipgloss.NewStyle().
				Foreground(theme.TextPrimary).
				Width(dialogWidth - 6).
				PaddingLeft(2)
		}

		// Build the line with keybind on right
		keybindWidth := len(cmdKeybind)
		titleWidth := dialogWidth - 10 - keybindWidth
		if titleWidth < 10 {
			titleWidth = 10
		}

		// Truncate title if needed
		if len(cmdTitle) > titleWidth {
			cmdTitle = cmdTitle[:titleWidth-3] + "..."
		}

		// Pad title to align keybind
		padding := titleWidth - len(cmdTitle)
		if padding < 1 {
			padding = 1
		}

		var line string
		if cmdKeybind != "" {
			keybindStyle := lipgloss.NewStyle().Foreground(theme.Accent)
			if isSelected {
				keybindStyle = keybindStyle.Background(theme.Primary)
			}
			line = cmdTitle + strings.Repeat(" ", padding) + keybindStyle.Render(cmdKeybind)
		} else {
			line = cmdTitle
		}

		listLines = append(listLines, lineStyle.Render(line))
		visibleCount++
	}

	listContent := strings.Join(listLines, "\n")

	// Help text
	helpStyle := lipgloss.NewStyle().
		Foreground(theme.Muted).
		Italic(true).
		Align(lipgloss.Center).
		Width(dialogWidth - 4)

	help := helpStyle.Render("↑↓ navigate • Enter select • Esc close")

	// Border
	borderStyle := lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(theme.Primary).
		Padding(1, 1).
		Width(dialogWidth).
		MaxWidth(dialogWidth)

	dialogContent := lipgloss.JoinVertical(lipgloss.Left, title, searchView, listContent, help)
	dialog := borderStyle.Render(dialogContent)

	return centerDialog(dialog, termWidth, termHeight)
}
