package styles

import "github.com/charmbracelet/lipgloss"

// Helper functions to get current theme colors
func getCurrentPrimary() lipgloss.Color {
	return GetCurrentTheme().Primary
}

func getCurrentSecondary() lipgloss.Color {
	return GetCurrentTheme().Secondary
}

func getCurrentError() lipgloss.Color {
	return GetCurrentTheme().Error
}

func getCurrentMuted() lipgloss.Color {
	return GetCurrentTheme().Muted
}

func getCurrentTextPrimary() lipgloss.Color {
	return GetCurrentTheme().TextPrimary
}

func getCurrentTextSecondary() lipgloss.Color {
	return GetCurrentTheme().TextSecondary
}

func getCurrentSuccess() lipgloss.Color {
	return GetCurrentTheme().Success
}

func getCurrentWarning() lipgloss.Color {
	return GetCurrentTheme().Warning
}

func getCurrentInfo() lipgloss.Color {
	return GetCurrentTheme().Info
}

func getCurrentBorder() lipgloss.Color {
	return GetCurrentTheme().Border
}

func getCurrentAccent() lipgloss.Color {
	return GetCurrentTheme().Accent
}

// Style helper functions that use current theme
func PrimaryStyle() lipgloss.Style {
	return lipgloss.NewStyle().Foreground(getCurrentPrimary())
}

func SecondaryStyle() lipgloss.Style {
	return lipgloss.NewStyle().Foreground(getCurrentSecondary())
}

func ErrorStyle() lipgloss.Style {
	return lipgloss.NewStyle().Foreground(getCurrentError())
}

func SuccessStyle() lipgloss.Style {
	return lipgloss.NewStyle().Foreground(getCurrentSuccess())
}

func WarningStyle() lipgloss.Style {
	return lipgloss.NewStyle().Foreground(getCurrentWarning())
}

func InfoStyle() lipgloss.Style {
	return lipgloss.NewStyle().Foreground(getCurrentInfo())
}

func MutedStyle() lipgloss.Style {
	return lipgloss.NewStyle().Foreground(getCurrentMuted())
}

func AccentStyle() lipgloss.Style {
	return lipgloss.NewStyle().Foreground(getCurrentAccent())
}

// Message Styles - using functions to ensure theme updates are reflected
func UserMessage() lipgloss.Style {
	return lipgloss.NewStyle().
		Padding(0, 1).
		Foreground(getCurrentTextPrimary()).
		Bold(true)
}

func UserLabel() lipgloss.Style {
	return lipgloss.NewStyle().
		Foreground(getCurrentPrimary()).
		Bold(true)
}

func AssistantMessage() lipgloss.Style {
	return lipgloss.NewStyle().
		Padding(0, 1).
		Foreground(getCurrentTextSecondary())
}

func AssistantLabel() lipgloss.Style {
	return lipgloss.NewStyle().
		Foreground(getCurrentSecondary()).
		Bold(true)
}

// Tool Event Styles
func ToolEvent() lipgloss.Style {
	return lipgloss.NewStyle().
		Foreground(getCurrentMuted()).
		Italic(true).
		PaddingLeft(2)
}

func ToolName() lipgloss.Style {
	return lipgloss.NewStyle().
		Foreground(getCurrentPrimary()).
		Bold(true)
}

func ToolStatus() lipgloss.Style {
	return lipgloss.NewStyle().
		Foreground(getCurrentSecondary())
}

// Input Styles
func InputBorder() lipgloss.Style {
	return lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(getCurrentPrimary()).
		Padding(0, 1)
}

// Status Bar Styles
func StatusBar() lipgloss.Style {
	return lipgloss.NewStyle().
		Foreground(getCurrentMuted()).
		Padding(0, 1)
}

func StatusBarStreaming() lipgloss.Style {
	return lipgloss.NewStyle().
		Foreground(getCurrentPrimary()).
		Padding(0, 1)
}

func StatusBarError() lipgloss.Style {
	return lipgloss.NewStyle().
		Foreground(getCurrentError()).
		Padding(0, 1)
}

// Header
func Header() lipgloss.Style {
	return lipgloss.NewStyle().
		Foreground(getCurrentPrimary()).
		Bold(true).
		Padding(0, 1)
}

// Cursor for streaming
func StreamingCursor() lipgloss.Style {
	return lipgloss.NewStyle().
		Foreground(getCurrentPrimary()).
		Bold(true)
}

// Muted text style
func MutedText() lipgloss.Style {
	return lipgloss.NewStyle().
		Foreground(getCurrentMuted())
}

// Muted bold text
func MutedBold() lipgloss.Style {
	return lipgloss.NewStyle().
		Foreground(getCurrentMuted()).
		Bold(true)
}
