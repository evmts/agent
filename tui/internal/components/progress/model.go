package progress

import (
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"tui/internal/styles"
)

// Variant defines the progress display style
type Variant int

const (
	VariantBar Variant = iota // Traditional progress bar
	VariantRing               // Circular progress (ASCII)
	VariantTokens             // Token-specific display
	VariantCompact            // Compact inline display
)

// Model represents the progress component
type Model struct {
	variant     Variant
	current     int
	max         int
	label       string
	showPercent bool
	showNumbers bool
	width       int
	warningAt   float64 // Warning threshold (0-1)
	dangerAt    float64 // Danger threshold (0-1)
}

// New creates a new progress model
func New(variant Variant, max int) Model {
	return Model{
		variant:     variant,
		current:     0,
		max:         max,
		showPercent: true,
		showNumbers: false,
		width:       20,
		warningAt:   0.75,
		dangerAt:    0.90,
	}
}

// NewTokenProgress creates a progress model for token tracking
func NewTokenProgress(inputTokens, outputTokens, maxContext int) Model {
	m := New(VariantTokens, maxContext)
	m.current = inputTokens + outputTokens
	m.showNumbers = true
	return m
}

// Init initializes the progress
func (m Model) Init() tea.Cmd {
	return nil
}

// Update handles progress messages
func (m Model) Update(msg tea.Msg) (Model, tea.Cmd) {
	return m, nil
}

// View renders the progress component
func (m Model) View() string {
	switch m.variant {
	case VariantRing:
		return m.renderRing()
	case VariantTokens:
		return m.renderTokens()
	case VariantCompact:
		return m.renderCompact()
	default:
		return m.renderBar()
	}
}

// renderBar renders a traditional progress bar
func (m Model) renderBar() string {
	theme := styles.GetCurrentTheme()

	percent := m.Percent()
	filledWidth := int(float64(m.width) * percent)
	if filledWidth > m.width {
		filledWidth = m.width
	}

	// Determine color based on thresholds
	color := theme.Success
	if percent >= m.dangerAt {
		color = theme.Error
	} else if percent >= m.warningAt {
		color = theme.Warning
	}

	// Build the bar
	filled := strings.Repeat("█", filledWidth)
	empty := strings.Repeat("░", m.width-filledWidth)

	filledStyle := lipgloss.NewStyle().Foreground(color)
	emptyStyle := lipgloss.NewStyle().Foreground(theme.Muted)

	bar := filledStyle.Render(filled) + emptyStyle.Render(empty)

	// Add label and percentage
	var result strings.Builder
	if m.label != "" {
		result.WriteString(m.label)
		result.WriteString(" ")
	}
	result.WriteString("[")
	result.WriteString(bar)
	result.WriteString("]")

	if m.showPercent {
		result.WriteString(" ")
		percentStyle := lipgloss.NewStyle().Foreground(color)
		result.WriteString(percentStyle.Render(fmt.Sprintf("%d%%", int(percent*100))))
	}

	if m.showNumbers {
		result.WriteString(" ")
		numberStyle := lipgloss.NewStyle().Foreground(theme.Muted)
		result.WriteString(numberStyle.Render(fmt.Sprintf("(%s/%s)", formatNumber(m.current), formatNumber(m.max))))
	}

	return result.String()
}

// renderRing renders a circular ASCII progress indicator
func (m Model) renderRing() string {
	theme := styles.GetCurrentTheme()
	percent := m.Percent()

	// ASCII ring characters (8 segments)
	segments := []string{"◯", "◔", "◑", "◕", "●"}
	idx := int(percent * float64(len(segments)-1))
	if idx >= len(segments) {
		idx = len(segments) - 1
	}

	// Determine color
	color := theme.Success
	if percent >= m.dangerAt {
		color = theme.Error
	} else if percent >= m.warningAt {
		color = theme.Warning
	}

	ringStyle := lipgloss.NewStyle().Foreground(color)
	ring := ringStyle.Render(segments[idx])

	var result strings.Builder
	result.WriteString(ring)

	if m.showPercent {
		result.WriteString(" ")
		percentStyle := lipgloss.NewStyle().Foreground(theme.TextSecondary)
		result.WriteString(percentStyle.Render(fmt.Sprintf("%d%%", int(percent*100))))
	}

	return result.String()
}

// renderTokens renders token-specific progress
func (m Model) renderTokens() string {
	theme := styles.GetCurrentTheme()
	percent := m.Percent()

	// Determine color
	color := theme.Success
	if percent >= m.dangerAt {
		color = theme.Error
	} else if percent >= m.warningAt {
		color = theme.Warning
	}

	// Mini bar (5 chars)
	barWidth := 5
	filledWidth := int(float64(barWidth) * percent)
	if filledWidth > barWidth {
		filledWidth = barWidth
	}

	filled := strings.Repeat("▰", filledWidth)
	empty := strings.Repeat("▱", barWidth-filledWidth)

	filledStyle := lipgloss.NewStyle().Foreground(color)
	emptyStyle := lipgloss.NewStyle().Foreground(theme.Muted)

	bar := filledStyle.Render(filled) + emptyStyle.Render(empty)

	// Token count
	tokenStyle := lipgloss.NewStyle().Foreground(theme.TextSecondary)
	tokens := tokenStyle.Render(formatNumber(m.current))

	return fmt.Sprintf("%s %s", bar, tokens)
}

// renderCompact renders a compact inline progress
func (m Model) renderCompact() string {
	theme := styles.GetCurrentTheme()
	percent := m.Percent()

	// Determine color
	color := theme.Success
	if percent >= m.dangerAt {
		color = theme.Error
	} else if percent >= m.warningAt {
		color = theme.Warning
	}

	percentStyle := lipgloss.NewStyle().Foreground(color)
	return percentStyle.Render(fmt.Sprintf("%d%%", int(percent*100)))
}

// Percent returns the current progress as a percentage (0-1)
func (m Model) Percent() float64 {
	if m.max == 0 {
		return 0
	}
	p := float64(m.current) / float64(m.max)
	if p > 1 {
		p = 1
	}
	if p < 0 {
		p = 0
	}
	return p
}

// SetProgress sets the current progress value
func (m *Model) SetProgress(current int) {
	m.current = current
}

// SetMax sets the maximum value
func (m *Model) SetMax(max int) {
	m.max = max
}

// SetTokens sets both current and max for token progress
func (m *Model) SetTokens(current, max int) {
	m.current = current
	m.max = max
}

// Increment increases the current value
func (m *Model) Increment(delta int) {
	m.current += delta
	if m.current > m.max {
		m.current = m.max
	}
}

// SetWidth sets the bar width
func (m *Model) SetWidth(width int) {
	m.width = width
}

// SetLabel sets the progress label
func (m *Model) SetLabel(label string) {
	m.label = label
}

// SetShowPercent enables/disables percentage display
func (m *Model) SetShowPercent(show bool) {
	m.showPercent = show
}

// SetShowNumbers enables/disables number display
func (m *Model) SetShowNumbers(show bool) {
	m.showNumbers = show
}

// SetThresholds sets warning and danger thresholds
func (m *Model) SetThresholds(warning, danger float64) {
	m.warningAt = warning
	m.dangerAt = danger
}

// SetVariant changes the progress variant
func (m *Model) SetVariant(variant Variant) {
	m.variant = variant
}

// GetCurrent returns the current value
func (m Model) GetCurrent() int {
	return m.current
}

// GetMax returns the max value
func (m Model) GetMax() int {
	return m.max
}

// IsComplete returns true if progress is at 100%
func (m Model) IsComplete() bool {
	return m.current >= m.max
}

// IsWarning returns true if progress is in warning zone
func (m Model) IsWarning() bool {
	return m.Percent() >= m.warningAt && m.Percent() < m.dangerAt
}

// IsDanger returns true if progress is in danger zone
func (m Model) IsDanger() bool {
	return m.Percent() >= m.dangerAt
}

// formatNumber formats a number for display (k for thousands, M for millions)
func formatNumber(n int) string {
	if n < 1000 {
		return fmt.Sprintf("%d", n)
	}
	if n < 1000000 {
		return fmt.Sprintf("%.1fk", float64(n)/1000)
	}
	return fmt.Sprintf("%.1fM", float64(n)/1000000)
}
