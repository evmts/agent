package tabs

import (
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"tui/internal/styles"
)

// Variant defines the tab style variant
type Variant int

const (
	VariantDefault Variant = iota
	VariantPills
	VariantUnderline
)

// Tab represents a single tab
type Tab struct {
	ID        string
	Title     string
	Icon      string
	Badge     string // Optional badge text (e.g., count)
	Closeable bool
}

// TabSelectedMsg is sent when a tab is selected
type TabSelectedMsg struct {
	Tab   Tab
	Index int
}

// TabClosedMsg is sent when a tab is closed
type TabClosedMsg struct {
	Tab   Tab
	Index int
}

// Model represents the tabs component
type Model struct {
	tabs        []Tab
	activeIndex int
	variant     Variant
	width       int
	focused     bool
}

// New creates a new tabs model
func New(tabs []Tab) Model {
	return Model{
		tabs:        tabs,
		activeIndex: 0,
		variant:     VariantDefault,
		focused:     false,
	}
}

// NewWithVariant creates tabs with a specific variant
func NewWithVariant(tabs []Tab, variant Variant) Model {
	m := New(tabs)
	m.variant = variant
	return m
}

// Init initializes the tabs
func (m Model) Init() tea.Cmd {
	return nil
}

// Update handles tab messages
func (m Model) Update(msg tea.Msg) (Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		if !m.focused {
			return m, nil
		}
		switch msg.String() {
		case "left", "h":
			return m.PrevTab()
		case "right", "l":
			return m.NextTab()
		case "1", "2", "3", "4", "5", "6", "7", "8", "9":
			idx := int(msg.String()[0] - '1')
			if idx < len(m.tabs) {
				return m.SelectTab(idx)
			}
		case "x", "ctrl+w":
			if len(m.tabs) > 0 && m.tabs[m.activeIndex].Closeable {
				return m.CloseTab(m.activeIndex)
			}
		case "enter", " ":
			if len(m.tabs) > 0 {
				tab := m.tabs[m.activeIndex]
				return m, func() tea.Msg {
					return TabSelectedMsg{Tab: tab, Index: m.activeIndex}
				}
			}
		}
	}
	return m, nil
}

// View renders the tabs
func (m Model) View() string {
	if len(m.tabs) == 0 {
		return ""
	}

	switch m.variant {
	case VariantPills:
		return m.renderPills()
	case VariantUnderline:
		return m.renderUnderline()
	default:
		return m.renderDefault()
	}
}

// renderDefault renders default style tabs
func (m Model) renderDefault() string {
	theme := styles.GetCurrentTheme()

	var tabs []string
	for i, tab := range m.tabs {
		isActive := i == m.activeIndex

		var style lipgloss.Style
		if isActive {
			style = lipgloss.NewStyle().
				Foreground(theme.TextPrimary).
				Background(theme.Primary).
				Padding(0, 2).
				Bold(true)
		} else {
			style = lipgloss.NewStyle().
				Foreground(theme.TextSecondary).
				Background(theme.Background).
				Padding(0, 2)
		}

		content := tab.Title
		if tab.Icon != "" {
			content = tab.Icon + " " + content
		}
		if tab.Badge != "" {
			badgeStyle := lipgloss.NewStyle().
				Foreground(theme.Accent).
				Bold(true)
			content = content + " " + badgeStyle.Render(tab.Badge)
		}

		tabs = append(tabs, style.Render(content))
	}

	return lipgloss.JoinHorizontal(lipgloss.Top, tabs...)
}

// renderPills renders pill-style tabs
func (m Model) renderPills() string {
	theme := styles.GetCurrentTheme()

	var tabs []string
	for i, tab := range m.tabs {
		isActive := i == m.activeIndex

		var style lipgloss.Style
		if isActive {
			style = lipgloss.NewStyle().
				Foreground(theme.TextPrimary).
				Background(theme.Primary).
				Padding(0, 2).
				MarginRight(1).
				Bold(true)
		} else {
			style = lipgloss.NewStyle().
				Foreground(theme.TextSecondary).
				Background(theme.Border).
				Padding(0, 2).
				MarginRight(1)
		}

		content := tab.Title
		if tab.Icon != "" {
			content = tab.Icon + " " + content
		}
		if tab.Badge != "" {
			badgeStyle := lipgloss.NewStyle().Foreground(theme.Accent)
			content = content + " " + badgeStyle.Render(tab.Badge)
		}

		tabs = append(tabs, style.Render(content))
	}

	return lipgloss.JoinHorizontal(lipgloss.Top, tabs...)
}

// renderUnderline renders underline-style tabs
func (m Model) renderUnderline() string {
	theme := styles.GetCurrentTheme()

	var tabs []string
	for i, tab := range m.tabs {
		isActive := i == m.activeIndex

		var style lipgloss.Style
		if isActive {
			style = lipgloss.NewStyle().
				Foreground(theme.Primary).
				BorderBottom(true).
				BorderStyle(lipgloss.NormalBorder()).
				BorderForeground(theme.Primary).
				Padding(0, 2).
				Bold(true)
		} else {
			style = lipgloss.NewStyle().
				Foreground(theme.TextSecondary).
				Padding(0, 2)
		}

		content := tab.Title
		if tab.Icon != "" {
			content = tab.Icon + " " + content
		}
		if tab.Badge != "" {
			badgeStyle := lipgloss.NewStyle().Foreground(theme.Muted)
			content = content + " " + badgeStyle.Render(tab.Badge)
		}

		tabs = append(tabs, style.Render(content))
	}

	return lipgloss.JoinHorizontal(lipgloss.Top, tabs...)
}

// SelectTab selects a tab by index
func (m Model) SelectTab(index int) (Model, tea.Cmd) {
	if index >= 0 && index < len(m.tabs) {
		m.activeIndex = index
		tab := m.tabs[index]
		return m, func() tea.Msg {
			return TabSelectedMsg{Tab: tab, Index: index}
		}
	}
	return m, nil
}

// SelectTabByID selects a tab by its ID
func (m Model) SelectTabByID(id string) (Model, tea.Cmd) {
	for i, tab := range m.tabs {
		if tab.ID == id {
			return m.SelectTab(i)
		}
	}
	return m, nil
}

// NextTab moves to the next tab
func (m Model) NextTab() (Model, tea.Cmd) {
	if len(m.tabs) == 0 {
		return m, nil
	}
	newIndex := (m.activeIndex + 1) % len(m.tabs)
	return m.SelectTab(newIndex)
}

// PrevTab moves to the previous tab
func (m Model) PrevTab() (Model, tea.Cmd) {
	if len(m.tabs) == 0 {
		return m, nil
	}
	newIndex := m.activeIndex - 1
	if newIndex < 0 {
		newIndex = len(m.tabs) - 1
	}
	return m.SelectTab(newIndex)
}

// CloseTab closes a tab at the specified index
func (m Model) CloseTab(index int) (Model, tea.Cmd) {
	if index < 0 || index >= len(m.tabs) {
		return m, nil
	}

	closedTab := m.tabs[index]

	// Remove the tab
	m.tabs = append(m.tabs[:index], m.tabs[index+1:]...)

	// Adjust active index if needed
	if len(m.tabs) == 0 {
		m.activeIndex = 0
	} else if m.activeIndex >= len(m.tabs) {
		m.activeIndex = len(m.tabs) - 1
	} else if m.activeIndex > index {
		m.activeIndex--
	}

	return m, func() tea.Msg {
		return TabClosedMsg{Tab: closedTab, Index: index}
	}
}

// AddTab adds a new tab
func (m *Model) AddTab(tab Tab) {
	m.tabs = append(m.tabs, tab)
}

// InsertTab inserts a tab at a specific index
func (m *Model) InsertTab(index int, tab Tab) {
	if index < 0 {
		index = 0
	}
	if index > len(m.tabs) {
		index = len(m.tabs)
	}
	m.tabs = append(m.tabs[:index], append([]Tab{tab}, m.tabs[index:]...)...)
}

// SetTabs replaces all tabs
func (m *Model) SetTabs(tabs []Tab) {
	m.tabs = tabs
	if m.activeIndex >= len(m.tabs) && len(m.tabs) > 0 {
		m.activeIndex = len(m.tabs) - 1
	}
}

// GetActiveTab returns the currently active tab
func (m Model) GetActiveTab() *Tab {
	if len(m.tabs) == 0 || m.activeIndex >= len(m.tabs) {
		return nil
	}
	return &m.tabs[m.activeIndex]
}

// GetActiveIndex returns the active tab index
func (m Model) GetActiveIndex() int {
	return m.activeIndex
}

// GetActiveID returns the active tab's ID
func (m Model) GetActiveID() string {
	if tab := m.GetActiveTab(); tab != nil {
		return tab.ID
	}
	return ""
}

// SetWidth sets the component width
func (m *Model) SetWidth(width int) {
	m.width = width
}

// SetVariant sets the tab variant
func (m *Model) SetVariant(variant Variant) {
	m.variant = variant
}

// Focus sets focus on the tabs
func (m *Model) Focus() {
	m.focused = true
}

// Blur removes focus from the tabs
func (m *Model) Blur() {
	m.focused = false
}

// IsFocused returns whether tabs are focused
func (m Model) IsFocused() bool {
	return m.focused
}

// Count returns the number of tabs
func (m Model) Count() int {
	return len(m.tabs)
}

// UpdateBadge updates the badge for a specific tab
func (m *Model) UpdateBadge(id string, badge string) {
	for i := range m.tabs {
		if m.tabs[i].ID == id {
			m.tabs[i].Badge = badge
			break
		}
	}
}

// GetTabs returns all tabs
func (m Model) GetTabs() []Tab {
	return m.tabs
}
