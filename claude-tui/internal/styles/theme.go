package styles

import "github.com/charmbracelet/lipgloss"

var (
	// Colors
	Primary     = lipgloss.Color("#7C3AED")
	Secondary   = lipgloss.Color("#10B981")
	Error       = lipgloss.Color("#EF4444")
	Muted       = lipgloss.Color("#6B7280")
	UserBg      = lipgloss.Color("#1E3A5F")
	AssistantBg = lipgloss.Color("#1F2937")
	ToolBg      = lipgloss.Color("#374151")
	White       = lipgloss.Color("#FFFFFF")
	LightGray   = lipgloss.Color("#E5E7EB")

	// Message Styles
	UserMessage = lipgloss.NewStyle().
			Padding(0, 1).
			Foreground(White).
			Bold(true)

	UserLabel = lipgloss.NewStyle().
			Foreground(Primary).
			Bold(true)

	AssistantMessage = lipgloss.NewStyle().
				Padding(0, 1).
				Foreground(LightGray)

	AssistantLabel = lipgloss.NewStyle().
			Foreground(Secondary).
			Bold(true)

	// Tool Event Styles
	ToolEvent = lipgloss.NewStyle().
			Foreground(Muted).
			Italic(true).
			PaddingLeft(2)

	ToolName = lipgloss.NewStyle().
			Foreground(Primary).
			Bold(true)

	ToolStatus = lipgloss.NewStyle().
			Foreground(Secondary)

	// Input Styles
	InputBorder = lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(Primary).
			Padding(0, 1)

	// Status Bar Styles
	StatusBar = lipgloss.NewStyle().
			Foreground(Muted).
			Padding(0, 1)

	StatusBarStreaming = lipgloss.NewStyle().
				Foreground(Primary).
				Padding(0, 1)

	StatusBarError = lipgloss.NewStyle().
			Foreground(Error).
			Padding(0, 1)

	// Header
	Header = lipgloss.NewStyle().
		Foreground(Primary).
		Bold(true).
		Padding(0, 1)

	// Cursor for streaming
	StreamingCursor = lipgloss.NewStyle().
			Foreground(Primary).
			Bold(true)
)
