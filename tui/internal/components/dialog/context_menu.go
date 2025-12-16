package dialog

import (
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"tui/internal/styles"
)

// ContextAction represents an action from the context menu
type ContextAction string

const (
	ActionCopyMessage   ContextAction = "copy_message"
	ActionCopyCode      ContextAction = "copy_code"
	ActionRevertTo      ContextAction = "revert_to"
	ActionForkFrom      ContextAction = "fork_from"
	ActionRetry         ContextAction = "retry"
	ActionEditMessage   ContextAction = "edit_message"
)

// ContextMenuItem represents a menu item
type ContextMenuItem struct {
	Action      ContextAction
	Label       string
	Description string
	Keybind     string
}

// ContextMenuSelectedMsg is sent when an action is selected from the context menu
type ContextMenuSelectedMsg struct {
	Action    ContextAction
	MessageID string
}

// ContextMenuDialog displays a context menu for messages
type ContextMenuDialog struct {
	items         []ContextMenuItem
	selectedIndex int
	visible       bool
	width         int
	height        int
	messageID     string
	messageRole   string // "user" or "assistant"
}

// NewContextMenuDialog creates a new context menu dialog
func NewContextMenuDialog(messageID string, isUserMessage bool) *ContextMenuDialog {
	var items []ContextMenuItem

	if isUserMessage {
		// User message options
		items = []ContextMenuItem{
			{Action: ActionCopyMessage, Label: "Copy message", Description: "Copy message text to clipboard", Keybind: "c"},
			{Action: ActionEditMessage, Label: "Edit message", Description: "Edit and resend this message", Keybind: "e"},
			{Action: ActionRevertTo, Label: "Revert to here", Description: "Revert conversation to this point", Keybind: "r"},
			{Action: ActionForkFrom, Label: "Fork from here", Description: "Create new branch from this message", Keybind: "f"},
		}
	} else {
		// Assistant message options
		items = []ContextMenuItem{
			{Action: ActionCopyMessage, Label: "Copy message", Description: "Copy full response to clipboard", Keybind: "c"},
			{Action: ActionCopyCode, Label: "Copy code blocks", Description: "Copy only code blocks to clipboard", Keybind: "C"},
			{Action: ActionRetry, Label: "Retry", Description: "Regenerate this response", Keybind: "R"},
			{Action: ActionRevertTo, Label: "Revert to here", Description: "Revert conversation to this point", Keybind: "r"},
			{Action: ActionForkFrom, Label: "Fork from here", Description: "Create new branch from this message", Keybind: "f"},
		}
	}

	role := "assistant"
	if isUserMessage {
		role = "user"
	}

	return &ContextMenuDialog{
		items:         items,
		selectedIndex: 0,
		visible:       true,
		width:         50,
		height:        len(items) + 6,
		messageID:     messageID,
		messageRole:   role,
	}
}

// Update handles messages for the context menu dialog
func (d *ContextMenuDialog) Update(msg tea.Msg) (Dialog, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "esc", "q":
			d.visible = false
			return d, nil
		case "enter":
			if d.selectedIndex < len(d.items) {
				d.visible = false
				action := d.items[d.selectedIndex].Action
				msgID := d.messageID
				return d, func() tea.Msg {
					return ContextMenuSelectedMsg{Action: action, MessageID: msgID}
				}
			}
		case "up", "k":
			if d.selectedIndex > 0 {
				d.selectedIndex--
			}
			return d, nil
		case "down", "j":
			if d.selectedIndex < len(d.items)-1 {
				d.selectedIndex++
			}
			return d, nil
		default:
			// Check for keybind shortcuts
			for i, item := range d.items {
				if msg.String() == item.Keybind {
					d.visible = false
					action := item.Action
					msgID := d.messageID
					_ = i // avoid unused variable
					return d, func() tea.Msg {
						return ContextMenuSelectedMsg{Action: action, MessageID: msgID}
					}
				}
			}
		}
	}

	return d, nil
}

// GetTitle returns the dialog title
func (d *ContextMenuDialog) GetTitle() string {
	return "Message Actions"
}

// IsVisible returns whether the dialog is visible
func (d *ContextMenuDialog) IsVisible() bool {
	return d.visible
}

// SetVisible sets the visibility
func (d *ContextMenuDialog) SetVisible(visible bool) {
	d.visible = visible
}

// Render renders the context menu dialog
func (d *ContextMenuDialog) Render(termWidth, termHeight int) string {
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
	roleLabel := "Assistant"
	if d.messageRole == "user" {
		roleLabel = "User"
	}
	titleStyle := lipgloss.NewStyle().
		Foreground(theme.Primary).
		Bold(true).
		Padding(0, 1).
		Width(dialogWidth - 4).
		Align(lipgloss.Center)

	title := titleStyle.Render(fmt.Sprintf("%s Message Actions", roleLabel))

	// Menu items
	var listLines []string
	for i, item := range d.items {
		isSelected := i == d.selectedIndex

		var lineStyle lipgloss.Style
		if isSelected {
			lineStyle = lipgloss.NewStyle().
				Foreground(theme.TextPrimary).
				Background(theme.Primary).
				Width(dialogWidth - 6).
				PaddingLeft(1)
		} else {
			lineStyle = lipgloss.NewStyle().
				Foreground(theme.TextPrimary).
				Width(dialogWidth - 6).
				PaddingLeft(1)
		}

		// Format keybind
		keybindStyle := lipgloss.NewStyle().Foreground(theme.Muted)
		if isSelected {
			keybindStyle = keybindStyle.Background(theme.Primary)
		}

		// Build the line
		keybindText := keybindStyle.Render(fmt.Sprintf("[%s]", item.Keybind))
		line := fmt.Sprintf("%s %s", keybindText, item.Label)
		listLines = append(listLines, lineStyle.Render(line))

		// Show description for selected item
		if isSelected {
			descStyle := lipgloss.NewStyle().
				Foreground(theme.Muted).
				Italic(true).
				PaddingLeft(5)
			listLines = append(listLines, descStyle.Render(item.Description))
		}
	}

	listContent := strings.Join(listLines, "\n")

	// Help text
	helpStyle := lipgloss.NewStyle().
		Foreground(theme.Muted).
		Italic(true).
		Align(lipgloss.Center).
		Width(dialogWidth - 4)

	help := helpStyle.Render("j/k navigate | Enter select | Esc close")

	// Border
	borderStyle := lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(theme.Primary).
		Padding(1, 1).
		Width(dialogWidth).
		MaxWidth(dialogWidth)

	dialogContent := lipgloss.JoinVertical(lipgloss.Left, title, listContent, "", help)
	dialog := borderStyle.Render(dialogContent)

	return centerDialog(dialog, termWidth, termHeight)
}
