package accordion

import (
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/bubbles/viewport"
	"github.com/charmbracelet/lipgloss"
	"tui/internal/styles"
)

// SelectMode defines how sections can be expanded
type SelectMode int

const (
	SelectSingle SelectMode = iota // Only one section open at a time
	SelectMulti                    // Multiple sections can be open
)

// Section represents a collapsible section
type Section struct {
	ID       string
	Title    string
	Content  string
	Icon     string // Optional icon
	Badge    string // Optional badge (e.g., count)
	Expanded bool
}

// SectionToggleMsg is sent when a section is toggled
type SectionToggleMsg struct {
	ID       string
	Index    int
	Expanded bool
}

// Model represents the accordion component
type Model struct {
	sections      []Section
	selectedIndex int
	mode          SelectMode
	width         int
	height        int
	viewport      viewport.Model
	focused       bool
	stickyHeaders bool
}

// New creates a new accordion model
func New(sections []Section, mode SelectMode) Model {
	vp := viewport.New(80, 10)
	return Model{
		sections:      sections,
		selectedIndex: 0,
		mode:          mode,
		viewport:      vp,
		focused:       false,
		stickyHeaders: false,
	}
}

// Init initializes the accordion
func (m Model) Init() tea.Cmd {
	return nil
}

// Update handles accordion messages
func (m Model) Update(msg tea.Msg) (Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		if !m.focused {
			return m, nil
		}
		switch msg.String() {
		case "up", "k":
			if m.selectedIndex > 0 {
				m.selectedIndex--
			}
			return m, nil
		case "down", "j":
			if m.selectedIndex < len(m.sections)-1 {
				m.selectedIndex++
			}
			return m, nil
		case "enter", " ", "tab":
			return m.Toggle(m.selectedIndex)
		case "e":
			m.ExpandAll()
			return m, nil
		case "c":
			m.CollapseAll()
			return m, nil
		}
	}

	// Update viewport for scrolling
	var cmd tea.Cmd
	m.viewport, cmd = m.viewport.Update(msg)
	return m, cmd
}

// View renders the accordion
func (m Model) View() string {
	if len(m.sections) == 0 {
		return ""
	}

	theme := styles.GetCurrentTheme()
	var parts []string

	for i, section := range m.sections {
		isSelected := i == m.selectedIndex

		// Header
		header := m.renderHeader(section, isSelected)
		parts = append(parts, header)

		// Content (if expanded)
		if section.Expanded {
			content := m.renderContent(section)
			parts = append(parts, content)
		}
	}

	result := strings.Join(parts, "\n")

	// Apply container style
	containerStyle := lipgloss.NewStyle().
		Width(m.width).
		BorderStyle(lipgloss.RoundedBorder()).
		BorderForeground(theme.Border)

	return containerStyle.Render(result)
}

// renderHeader renders a section header
func (m Model) renderHeader(section Section, isSelected bool) string {
	theme := styles.GetCurrentTheme()

	// Expand/collapse indicator
	indicator := "▶"
	if section.Expanded {
		indicator = "▼"
	}

	// Build header content
	var content strings.Builder
	content.WriteString(indicator)
	content.WriteString(" ")
	if section.Icon != "" {
		content.WriteString(section.Icon)
		content.WriteString(" ")
	}
	content.WriteString(section.Title)
	if section.Badge != "" {
		content.WriteString(" ")
		badgeStyle := lipgloss.NewStyle().
			Foreground(theme.Accent).
			Bold(true)
		content.WriteString(badgeStyle.Render(section.Badge))
	}

	// Style based on selection
	var style lipgloss.Style
	if isSelected {
		style = lipgloss.NewStyle().
			Foreground(theme.TextPrimary).
			Background(theme.Primary).
			Width(m.width - 2).
			Padding(0, 1).
			Bold(true)
	} else {
		style = lipgloss.NewStyle().
			Foreground(theme.TextPrimary).
			Background(theme.CodeBackground).
			Width(m.width - 2).
			Padding(0, 1)
	}

	return style.Render(content.String())
}

// renderContent renders section content
func (m Model) renderContent(section Section) string {
	theme := styles.GetCurrentTheme()

	contentStyle := lipgloss.NewStyle().
		Foreground(theme.TextSecondary).
		Width(m.width - 4).
		Padding(0, 2).
		MarginLeft(2)

	// Truncate content if too long
	content := section.Content
	lines := strings.Split(content, "\n")
	maxLines := 20 // Max lines to show
	if len(lines) > maxLines {
		lines = lines[:maxLines]
		lines = append(lines, "...")
		content = strings.Join(lines, "\n")
	}

	return contentStyle.Render(content)
}

// Toggle toggles a section's expanded state
func (m Model) Toggle(index int) (Model, tea.Cmd) {
	if index < 0 || index >= len(m.sections) {
		return m, nil
	}

	section := &m.sections[index]

	if m.mode == SelectSingle {
		// Collapse all others
		for i := range m.sections {
			if i != index {
				m.sections[i].Expanded = false
			}
		}
	}

	section.Expanded = !section.Expanded

	return m, func() tea.Msg {
		return SectionToggleMsg{
			ID:       section.ID,
			Index:    index,
			Expanded: section.Expanded,
		}
	}
}

// ToggleByID toggles a section by its ID
func (m Model) ToggleByID(id string) (Model, tea.Cmd) {
	for i, section := range m.sections {
		if section.ID == id {
			return m.Toggle(i)
		}
	}
	return m, nil
}

// ExpandAll expands all sections
func (m *Model) ExpandAll() {
	for i := range m.sections {
		m.sections[i].Expanded = true
	}
}

// CollapseAll collapses all sections
func (m *Model) CollapseAll() {
	for i := range m.sections {
		m.sections[i].Expanded = false
	}
}

// SetSections replaces all sections
func (m *Model) SetSections(sections []Section) {
	m.sections = sections
	if m.selectedIndex >= len(m.sections) && len(m.sections) > 0 {
		m.selectedIndex = len(m.sections) - 1
	}
}

// AddSection adds a new section
func (m *Model) AddSection(section Section) {
	m.sections = append(m.sections, section)
}

// RemoveSection removes a section by ID
func (m *Model) RemoveSection(id string) {
	for i, section := range m.sections {
		if section.ID == id {
			m.sections = append(m.sections[:i], m.sections[i+1:]...)
			if m.selectedIndex >= len(m.sections) && len(m.sections) > 0 {
				m.selectedIndex = len(m.sections) - 1
			}
			break
		}
	}
}

// UpdateSection updates a section's content
func (m *Model) UpdateSection(id string, content string) {
	for i := range m.sections {
		if m.sections[i].ID == id {
			m.sections[i].Content = content
			break
		}
	}
}

// UpdateSectionBadge updates a section's badge
func (m *Model) UpdateSectionBadge(id string, badge string) {
	for i := range m.sections {
		if m.sections[i].ID == id {
			m.sections[i].Badge = badge
			break
		}
	}
}

// SetSize sets the accordion dimensions
func (m *Model) SetSize(width, height int) {
	m.width = width
	m.height = height
	m.viewport.Width = width
	m.viewport.Height = height
}

// SetWidth sets the accordion width
func (m *Model) SetWidth(width int) {
	m.width = width
	m.viewport.Width = width
}

// SetHeight sets the accordion height
func (m *Model) SetHeight(height int) {
	m.height = height
	m.viewport.Height = height
}

// Focus sets focus on the accordion
func (m *Model) Focus() {
	m.focused = true
}

// Blur removes focus from the accordion
func (m *Model) Blur() {
	m.focused = false
}

// IsFocused returns whether the accordion is focused
func (m Model) IsFocused() bool {
	return m.focused
}

// SetMode sets the selection mode
func (m *Model) SetMode(mode SelectMode) {
	m.mode = mode
}

// SetStickyHeaders enables/disables sticky headers
func (m *Model) SetStickyHeaders(sticky bool) {
	m.stickyHeaders = sticky
}

// GetSelectedIndex returns the selected section index
func (m Model) GetSelectedIndex() int {
	return m.selectedIndex
}

// GetSelectedSection returns the selected section
func (m Model) GetSelectedSection() *Section {
	if m.selectedIndex >= 0 && m.selectedIndex < len(m.sections) {
		return &m.sections[m.selectedIndex]
	}
	return nil
}

// Count returns the number of sections
func (m Model) Count() int {
	return len(m.sections)
}

// GetExpandedCount returns the number of expanded sections
func (m Model) GetExpandedCount() int {
	count := 0
	for _, section := range m.sections {
		if section.Expanded {
			count++
		}
	}
	return count
}

// IsExpanded checks if a section is expanded by ID
func (m Model) IsExpanded(id string) bool {
	for _, section := range m.sections {
		if section.ID == id {
			return section.Expanded
		}
	}
	return false
}

// GetSections returns all sections
func (m Model) GetSections() []Section {
	return m.sections
}
