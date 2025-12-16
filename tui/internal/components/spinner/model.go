package spinner

import (
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/williamcory/agent/tui/internal/styles"
)

// Style defines the spinner animation style
type Style int

const (
	StyleDots Style = iota
	StyleBraille
	StyleLine
	StylePulse
	StyleGrow
	StyleBounce
	StyleMeter
)

// Frames for each spinner style
var frames = map[Style][]string{
	StyleDots:    {"⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"},
	StyleBraille: {"⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷"},
	StyleLine:    {"─", "\\", "│", "/"},
	StylePulse:   {"◐", "◓", "◑", "◒"},
	StyleGrow:    {"▁", "▂", "▃", "▄", "▅", "▆", "▇", "█", "▇", "▆", "▅", "▄", "▃", "▂"},
	StyleBounce:  {"⠁", "⠂", "⠄", "⠂"},
	StyleMeter:   {"▱▱▱", "▰▱▱", "▰▰▱", "▰▰▰", "▱▰▰", "▱▱▰"},
}

// Default intervals for each style
var intervals = map[Style]time.Duration{
	StyleDots:    80 * time.Millisecond,
	StyleBraille: 80 * time.Millisecond,
	StyleLine:    100 * time.Millisecond,
	StylePulse:   100 * time.Millisecond,
	StyleGrow:    80 * time.Millisecond,
	StyleBounce:  120 * time.Millisecond,
	StyleMeter:   150 * time.Millisecond,
}

// TickMsg is sent when the spinner should advance
type TickMsg struct {
	ID int
}

// Model represents a spinner component
type Model struct {
	id       int
	style    Style
	frame    int
	active   bool
	message  string
	interval time.Duration
}

var spinnerID int

// New creates a new spinner with the specified style
func New(style Style) Model {
	spinnerID++
	return Model{
		id:       spinnerID,
		style:    style,
		frame:    0,
		active:   false,
		interval: intervals[style],
	}
}

// NewWithMessage creates a spinner with a message
func NewWithMessage(style Style, message string) Model {
	m := New(style)
	m.message = message
	return m
}

// Init initializes the spinner (no-op, call Start to begin)
func (m Model) Init() tea.Cmd {
	return nil
}

// Update handles spinner messages
func (m Model) Update(msg tea.Msg) (Model, tea.Cmd) {
	switch msg := msg.(type) {
	case TickMsg:
		if msg.ID != m.id || !m.active {
			return m, nil
		}
		f := frames[m.style]
		m.frame = (m.frame + 1) % len(f)
		return m, m.tick()
	}
	return m, nil
}

// View renders the spinner
func (m Model) View() string {
	if !m.active {
		return ""
	}

	theme := styles.GetCurrentTheme()
	spinnerStyle := lipgloss.NewStyle().Foreground(theme.Accent)

	f := frames[m.style]
	spinner := spinnerStyle.Render(f[m.frame])

	if m.message != "" {
		msgStyle := lipgloss.NewStyle().Foreground(theme.TextSecondary)
		return spinner + " " + msgStyle.Render(m.message)
	}

	return spinner
}

// ViewWithStyle renders the spinner with a custom style
func (m Model) ViewWithStyle(style lipgloss.Style) string {
	if !m.active {
		return ""
	}

	f := frames[m.style]
	spinner := style.Render(f[m.frame])

	if m.message != "" {
		theme := styles.GetCurrentTheme()
		msgStyle := lipgloss.NewStyle().Foreground(theme.TextSecondary)
		return spinner + " " + msgStyle.Render(m.message)
	}

	return spinner
}

// Start begins the spinner animation
func (m *Model) Start() tea.Cmd {
	m.active = true
	m.frame = 0
	return m.tick()
}

// Stop stops the spinner animation
func (m *Model) Stop() {
	m.active = false
}

// IsActive returns whether the spinner is running
func (m Model) IsActive() bool {
	return m.active
}

// SetMessage sets the spinner message
func (m *Model) SetMessage(msg string) {
	m.message = msg
}

// SetStyle changes the spinner style
func (m *Model) SetStyle(style Style) {
	m.style = style
	m.interval = intervals[style]
	m.frame = 0
}

// SetInterval sets a custom animation interval
func (m *Model) SetInterval(d time.Duration) {
	m.interval = d
}

// tick returns a command that sends a tick after the interval
func (m Model) tick() tea.Cmd {
	return tea.Tick(m.interval, func(t time.Time) tea.Msg {
		return TickMsg{ID: m.id}
	})
}

// Frame returns the current frame string
func (m Model) Frame() string {
	f := frames[m.style]
	return f[m.frame]
}

// GetID returns the spinner's unique ID
func (m Model) GetID() int {
	return m.id
}
