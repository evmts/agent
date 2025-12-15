package styles

import "github.com/charmbracelet/lipgloss"

// Theme defines a complete color scheme for the TUI
type Theme struct {
	Name           string
	Primary        lipgloss.Color
	Secondary      lipgloss.Color
	Background     lipgloss.Color
	Foreground     lipgloss.Color
	Border         lipgloss.Color
	Success        lipgloss.Color
	Error          lipgloss.Color
	Warning        lipgloss.Color
	Info           lipgloss.Color
	Muted          lipgloss.Color
	Accent         lipgloss.Color
	TextPrimary    lipgloss.Color
	TextSecondary  lipgloss.Color
	CodeBackground lipgloss.Color
	DiffAdd        lipgloss.Color
	DiffRemove     lipgloss.Color
}

var (
	// currentTheme holds the active theme
	currentTheme *Theme

	// Predefined themes
	themes = map[string]*Theme{
		"default": {
			Name:           "Default (Dark)",
			Primary:        lipgloss.Color("#7C3AED"), // Violet
			Secondary:      lipgloss.Color("#10B981"), // Emerald
			Background:     lipgloss.Color("#0F172A"), // Slate 900
			Foreground:     lipgloss.Color("#F1F5F9"), // Slate 100
			Border:         lipgloss.Color("#334155"), // Slate 700
			Success:        lipgloss.Color("#10B981"), // Emerald
			Error:          lipgloss.Color("#EF4444"), // Red
			Warning:        lipgloss.Color("#F59E0B"), // Amber
			Info:           lipgloss.Color("#3B82F6"), // Blue
			Muted:          lipgloss.Color("#6B7280"), // Gray 500
			Accent:         lipgloss.Color("#EC4899"), // Pink
			TextPrimary:    lipgloss.Color("#FFFFFF"), // White
			TextSecondary:  lipgloss.Color("#E5E7EB"), // Gray 200
			CodeBackground: lipgloss.Color("#1E293B"), // Slate 800
			DiffAdd:        lipgloss.Color("#059669"), // Emerald 600
			DiffRemove:     lipgloss.Color("#DC2626"), // Red 600
		},
		"light": {
			Name:           "Light",
			Primary:        lipgloss.Color("#7C3AED"), // Violet
			Secondary:      lipgloss.Color("#059669"), // Emerald 600
			Background:     lipgloss.Color("#FFFFFF"), // White
			Foreground:     lipgloss.Color("#0F172A"), // Slate 900
			Border:         lipgloss.Color("#CBD5E1"), // Slate 300
			Success:        lipgloss.Color("#059669"), // Emerald 600
			Error:          lipgloss.Color("#DC2626"), // Red 600
			Warning:        lipgloss.Color("#D97706"), // Amber 600
			Info:           lipgloss.Color("#2563EB"), // Blue 600
			Muted:          lipgloss.Color("#64748B"), // Slate 500
			Accent:         lipgloss.Color("#DB2777"), // Pink 600
			TextPrimary:    lipgloss.Color("#0F172A"), // Slate 900
			TextSecondary:  lipgloss.Color("#475569"), // Slate 600
			CodeBackground: lipgloss.Color("#F1F5F9"), // Slate 100
			DiffAdd:        lipgloss.Color("#10B981"), // Emerald 500
			DiffRemove:     lipgloss.Color("#EF4444"), // Red 500
		},
		"dracula": {
			Name:           "Dracula",
			Primary:        lipgloss.Color("#BD93F9"), // Purple
			Secondary:      lipgloss.Color("#50FA7B"), // Green
			Background:     lipgloss.Color("#282A36"), // Background
			Foreground:     lipgloss.Color("#F8F8F2"), // Foreground
			Border:         lipgloss.Color("#6272A4"), // Comment
			Success:        lipgloss.Color("#50FA7B"), // Green
			Error:          lipgloss.Color("#FF5555"), // Red
			Warning:        lipgloss.Color("#FFB86C"), // Orange
			Info:           lipgloss.Color("#8BE9FD"), // Cyan
			Muted:          lipgloss.Color("#6272A4"), // Comment
			Accent:         lipgloss.Color("#FF79C6"), // Pink
			TextPrimary:    lipgloss.Color("#F8F8F2"), // Foreground
			TextSecondary:  lipgloss.Color("#F8F8F2"), // Foreground
			CodeBackground: lipgloss.Color("#44475A"), // Current Line
			DiffAdd:        lipgloss.Color("#50FA7B"), // Green
			DiffRemove:     lipgloss.Color("#FF5555"), // Red
		},
		"nord": {
			Name:           "Nord",
			Primary:        lipgloss.Color("#88C0D0"), // Frost 2
			Secondary:      lipgloss.Color("#A3BE8C"), // Aurora Green
			Background:     lipgloss.Color("#2E3440"), // Polar Night 0
			Foreground:     lipgloss.Color("#ECEFF4"), // Snow Storm 3
			Border:         lipgloss.Color("#4C566A"), // Polar Night 3
			Success:        lipgloss.Color("#A3BE8C"), // Aurora Green
			Error:          lipgloss.Color("#BF616A"), // Aurora Red
			Warning:        lipgloss.Color("#EBCB8B"), // Aurora Yellow
			Info:           lipgloss.Color("#81A1C1"), // Frost 1
			Muted:          lipgloss.Color("#4C566A"), // Polar Night 3
			Accent:         lipgloss.Color("#B48EAD"), // Aurora Purple
			TextPrimary:    lipgloss.Color("#ECEFF4"), // Snow Storm 3
			TextSecondary:  lipgloss.Color("#D8DEE9"), // Snow Storm 1
			CodeBackground: lipgloss.Color("#3B4252"), // Polar Night 1
			DiffAdd:        lipgloss.Color("#A3BE8C"), // Aurora Green
			DiffRemove:     lipgloss.Color("#BF616A"), // Aurora Red
		},
		"monokai": {
			Name:           "Monokai",
			Primary:        lipgloss.Color("#F92672"), // Magenta
			Secondary:      lipgloss.Color("#A6E22E"), // Green
			Background:     lipgloss.Color("#272822"), // Background
			Foreground:     lipgloss.Color("#F8F8F2"), // Foreground
			Border:         lipgloss.Color("#49483E"), // Gray
			Success:        lipgloss.Color("#A6E22E"), // Green
			Error:          lipgloss.Color("#F92672"), // Magenta
			Warning:        lipgloss.Color("#E6DB74"), // Yellow
			Info:           lipgloss.Color("#66D9EF"), // Cyan
			Muted:          lipgloss.Color("#75715E"), // Comment
			Accent:         lipgloss.Color("#AE81FF"), // Purple
			TextPrimary:    lipgloss.Color("#F8F8F2"), // Foreground
			TextSecondary:  lipgloss.Color("#F8F8F2"), // Foreground
			CodeBackground: lipgloss.Color("#3E3D32"), // Selection
			DiffAdd:        lipgloss.Color("#A6E22E"), // Green
			DiffRemove:     lipgloss.Color("#F92672"), // Magenta
		},
		"catppuccin": {
			Name:           "Catppuccin (Mocha)",
			Primary:        lipgloss.Color("#CBA6F7"), // Mauve
			Secondary:      lipgloss.Color("#A6E3A1"), // Green
			Background:     lipgloss.Color("#1E1E2E"), // Base
			Foreground:     lipgloss.Color("#CDD6F4"), // Text
			Border:         lipgloss.Color("#585B70"), // Surface 2
			Success:        lipgloss.Color("#A6E3A1"), // Green
			Error:          lipgloss.Color("#F38BA8"), // Red
			Warning:        lipgloss.Color("#FAB387"), // Peach
			Info:           lipgloss.Color("#89B4FA"), // Blue
			Muted:          lipgloss.Color("#6C7086"), // Overlay 0
			Accent:         lipgloss.Color("#F5C2E7"), // Pink
			TextPrimary:    lipgloss.Color("#CDD6F4"), // Text
			TextSecondary:  lipgloss.Color("#BAC2DE"), // Subtext 1
			CodeBackground: lipgloss.Color("#313244"), // Surface 0
			DiffAdd:        lipgloss.Color("#A6E3A1"), // Green
			DiffRemove:     lipgloss.Color("#F38BA8"), // Red
		},
		"tokyonight": {
			Name:           "Tokyo Night",
			Primary:        lipgloss.Color("#7AA2F7"), // Blue
			Secondary:      lipgloss.Color("#9ECE6A"), // Green
			Background:     lipgloss.Color("#1A1B26"), // Background
			Foreground:     lipgloss.Color("#C0CAF5"), // Foreground
			Border:         lipgloss.Color("#3B4261"), // Border
			Success:        lipgloss.Color("#9ECE6A"), // Green
			Error:          lipgloss.Color("#F7768E"), // Red
			Warning:        lipgloss.Color("#E0AF68"), // Yellow
			Info:           lipgloss.Color("#7DCFFF"), // Cyan
			Muted:          lipgloss.Color("#565F89"), // Comment
			Accent:         lipgloss.Color("#BB9AF7"), // Purple
			TextPrimary:    lipgloss.Color("#C0CAF5"), // Foreground
			TextSecondary:  lipgloss.Color("#A9B1D6"), // Foreground Dark
			CodeBackground: lipgloss.Color("#24283B"), // Background Dark
			DiffAdd:        lipgloss.Color("#9ECE6A"), // Green
			DiffRemove:     lipgloss.Color("#F7768E"), // Red
		},
		"gruvbox": {
			Name:           "Gruvbox (Dark)",
			Primary:        lipgloss.Color("#D3869B"), // Purple
			Secondary:      lipgloss.Color("#B8BB26"), // Green
			Background:     lipgloss.Color("#282828"), // Background
			Foreground:     lipgloss.Color("#EBDBB2"), // Foreground
			Border:         lipgloss.Color("#504945"), // Gray
			Success:        lipgloss.Color("#B8BB26"), // Green
			Error:          lipgloss.Color("#FB4934"), // Red
			Warning:        lipgloss.Color("#FABD2F"), // Yellow
			Info:           lipgloss.Color("#83A598"), // Blue
			Muted:          lipgloss.Color("#928374"), // Gray
			Accent:         lipgloss.Color("#FE8019"), // Orange
			TextPrimary:    lipgloss.Color("#EBDBB2"), // Foreground
			TextSecondary:  lipgloss.Color("#D5C4A1"), // Foreground Light
			CodeBackground: lipgloss.Color("#3C3836"), // Background Light
			DiffAdd:        lipgloss.Color("#B8BB26"), // Green
			DiffRemove:     lipgloss.Color("#FB4934"), // Red
		},
	}
)

// init sets the default theme
func init() {
	currentTheme = themes["default"]
}

// GetTheme returns a theme by name, or the default theme if not found
func GetTheme(name string) *Theme {
	if theme, ok := themes[name]; ok {
		return theme
	}
	return themes["default"]
}

// ListThemes returns a list of available theme names
func ListThemes() []string {
	names := make([]string, 0, len(themes))
	for name := range themes {
		names = append(names, name)
	}
	return names
}

// GetCurrentTheme returns the currently active theme
func GetCurrentTheme() *Theme {
	return currentTheme
}

// SetTheme sets the active theme by name
func SetTheme(name string) bool {
	if theme, ok := themes[name]; ok {
		currentTheme = theme
		return true
	}
	return false
}

// SetThemeObj sets the active theme directly
func SetThemeObj(theme *Theme) {
	currentTheme = theme
}
