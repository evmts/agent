package dialog

import (
	"sort"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/williamcory/agent/tui/internal/keybind"
	"github.com/williamcory/agent/tui/internal/styles"
)

// ShortcutsOverlay displays a quick-reference keyboard shortcuts overlay
type ShortcutsOverlay struct {
	BaseDialog
	keyMap          *keybind.KeyMap
	categorized     map[keybind.ShortcutCategory][]keybind.KeyBinding
	inputFocused    bool
	hasActiveDialog bool
}

// NewShortcutsOverlay creates a new shortcuts overlay
func NewShortcutsOverlay(km *keybind.KeyMap, inputFocused bool, hasActiveDialog bool) *ShortcutsOverlay {
	overlay := &ShortcutsOverlay{
		keyMap:          km,
		categorized:     make(map[keybind.ShortcutCategory][]keybind.KeyBinding),
		inputFocused:    inputFocused,
		hasActiveDialog: hasActiveDialog,
		BaseDialog: BaseDialog{
			Title:   "",
			Content: "",
			Visible: true,
			Width:   90,
			Height:  30,
		},
	}
	overlay.categorizeBindings()
	return overlay
}

// categorizeBindings organizes all keybindings by category
func (s *ShortcutsOverlay) categorizeBindings() {
	allBindings := s.keyMap.All()

	// Group by category
	for _, binding := range allBindings {
		// Skip duplicate bindings (e.g., ctrl+c and q both for quit)
		if s.isDuplicate(binding) {
			continue
		}
		s.categorized[binding.Category] = append(s.categorized[binding.Category], binding)
	}

	// Sort bindings within each category by key
	for category := range s.categorized {
		sort.Slice(s.categorized[category], func(i, j int) bool {
			return s.categorized[category][i].Key < s.categorized[category][j].Key
		})
	}
}

// isDuplicate checks if this is a duplicate binding we should skip
func (s *ShortcutsOverlay) isDuplicate(binding keybind.KeyBinding) bool {
	// Skip "q" (we show ctrl+c instead)
	if binding.Key == "q" {
		return true
	}
	// Skip ctrl+p (duplicate of ctrl+k for commands)
	if binding.Key == "ctrl+p" {
		return true
	}
	return false
}

// isBindingAvailable checks if a binding is available in the current state
func (s *ShortcutsOverlay) isBindingAvailable(binding keybind.KeyBinding) bool {
	// Navigation keys are disabled when input is focused
	if s.inputFocused && binding.Category == keybind.CategoryNavigation {
		// Except for page up/down, home/end which work in input
		if binding.Key != "pgup" && binding.Key != "pgdown" &&
			binding.Key != "home" && binding.Key != "end" {
			return false
		}
	}

	// Some actions are disabled when a dialog is active
	if s.hasActiveDialog {
		return binding.Category == keybind.CategoryInput ||
			binding.Action == keybind.ActionShowShortcuts
	}

	return true
}

// buildContent builds the shortcuts overlay content
func (s *ShortcutsOverlay) buildContent() string {
	theme := styles.GetCurrentTheme()

	// Styles
	titleStyle := lipgloss.NewStyle().
		Foreground(theme.Primary).
		Bold(true).
		Align(lipgloss.Center).
		Width(s.Width - 4)

	categoryStyle := lipgloss.NewStyle().
		Foreground(theme.Accent).
		Bold(true).
		Underline(true)

	keyStyle := lipgloss.NewStyle().
		Foreground(theme.Primary).
		Bold(true).
		Width(12)

	descStyle := lipgloss.NewStyle().
		Foreground(theme.TextPrimary)

	disabledKeyStyle := lipgloss.NewStyle().
		Foreground(theme.Muted).
		Width(12)

	disabledDescStyle := lipgloss.NewStyle().
		Foreground(theme.Muted)

	hintStyle := lipgloss.NewStyle().
		Foreground(theme.Muted).
		Align(lipgloss.Center).
		Width(s.Width - 4)

	// Build content
	var lines []string
	lines = append(lines, titleStyle.Render("⌨  Keyboard Shortcuts"))
	lines = append(lines, "")

	// Define category order and column layout
	leftCategories := []keybind.ShortcutCategory{
		keybind.CategoryNavigation,
		keybind.CategoryActions,
	}
	middleCategories := []keybind.ShortcutCategory{
		keybind.CategorySession,
		keybind.CategoryDialogs,
	}
	rightCategories := []keybind.ShortcutCategory{
		keybind.CategoryView,
		keybind.CategoryInput,
	}

	// Build three columns
	leftCol := s.buildColumn(leftCategories, categoryStyle, keyStyle, descStyle, disabledKeyStyle, disabledDescStyle)
	middleCol := s.buildColumn(middleCategories, categoryStyle, keyStyle, descStyle, disabledKeyStyle, disabledDescStyle)
	rightCol := s.buildColumn(rightCategories, categoryStyle, keyStyle, descStyle, disabledKeyStyle, disabledDescStyle)

	// Calculate max height
	maxHeight := max(len(leftCol), max(len(middleCol), len(rightCol)))

	// Pad columns to same height
	for len(leftCol) < maxHeight {
		leftCol = append(leftCol, "")
	}
	for len(middleCol) < maxHeight {
		middleCol = append(middleCol, "")
	}
	for len(rightCol) < maxHeight {
		rightCol = append(rightCol, "")
	}

	// Join columns side by side
	colWidth := 28
	for i := 0; i < maxHeight; i++ {
		left := leftCol[i]
		middle := middleCol[i]
		right := rightCol[i]

		// Pad to column width
		if lipgloss.Width(left) < colWidth {
			left += strings.Repeat(" ", colWidth-lipgloss.Width(left))
		}
		if lipgloss.Width(middle) < colWidth {
			middle += strings.Repeat(" ", colWidth-lipgloss.Width(middle))
		}

		line := "  " + left + " " + middle + " " + right
		lines = append(lines, line)
	}

	lines = append(lines, "")
	lines = append(lines, hintStyle.Render("Press any key to close"))

	return strings.Join(lines, "\n")
}

// buildColumn builds a column of categories
func (s *ShortcutsOverlay) buildColumn(
	categories []keybind.ShortcutCategory,
	categoryStyle, keyStyle, descStyle, disabledKeyStyle, disabledDescStyle lipgloss.Style,
) []string {
	var lines []string

	for _, category := range categories {
		bindings := s.categorized[category]
		if len(bindings) == 0 {
			continue
		}

		// Category header
		lines = append(lines, categoryStyle.Render(string(category)))

		// Bindings
		for _, binding := range bindings {
			available := s.isBindingAvailable(binding)
			var key, desc string

			if available {
				key = keyStyle.Render(formatKey(binding.Key))
				desc = descStyle.Render(binding.Description)
			} else {
				key = disabledKeyStyle.Render(formatKey(binding.Key))
				desc = disabledDescStyle.Render(binding.Description)
			}

			lines = append(lines, key+" "+desc)
		}

		lines = append(lines, "") // Spacing between categories
	}

	return lines
}

// formatKey formats a key for display (makes it more readable)
func formatKey(key string) string {
	// Replace ctrl+ with ^
	key = strings.ReplaceAll(key, "ctrl+", "^")
	// Capitalize single letters (except for special combos)
	if len(key) == 1 && key >= "a" && key <= "z" {
		return strings.ToUpper(key)
	}
	return key
}

// max returns the maximum of two integers
func max(a, b int) int {
	if a > b {
		return a
	}
	return b
}

// Update handles messages for the shortcuts overlay
func (s *ShortcutsOverlay) Update(msg tea.Msg) (*ShortcutsOverlay, tea.Cmd) {
	switch msg.(type) {
	case tea.KeyMsg:
		// Any key press closes the overlay
		s.SetVisible(false)
		return s, nil
	}
	return s, nil
}

// Render renders the shortcuts overlay
func (s *ShortcutsOverlay) Render(termWidth, termHeight int) string {
	if !s.Visible {
		return ""
	}

	// Build fresh content (in case state changed)
	s.Content = s.buildContent()

	// Use BaseDialog's rendering with semi-transparent background
	return s.renderWithOverlay(termWidth, termHeight)
}

// renderWithOverlay renders the overlay with semi-transparent effect
func (s *ShortcutsOverlay) renderWithOverlay(termWidth, termHeight int) string {
	theme := styles.GetCurrentTheme()

	// Dialog dimensions
	dialogWidth := s.Width
	dialogHeight := s.Height

	// Ensure dialog fits on screen
	if dialogWidth > termWidth-4 {
		dialogWidth = termWidth - 4
	}
	if dialogHeight > termHeight-4 {
		dialogHeight = termHeight - 4
	}

	// Content style
	contentStyle := lipgloss.NewStyle().
		Foreground(theme.TextPrimary).
		Padding(1, 2).
		Width(dialogWidth - 4)

	content := contentStyle.Render(s.Content)

	// Border style - semi-transparent look
	borderStyle := lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(theme.Primary).
		Background(theme.Background).
		Padding(1, 1).
		Width(dialogWidth).
		MaxWidth(dialogWidth)

	dialog := borderStyle.Render(content)

	// Center the dialog on screen
	return centerDialog(dialog, termWidth, termHeight)
}
