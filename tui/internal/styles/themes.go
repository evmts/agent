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
		"onedark": {
			Name:           "One Dark",
			Primary:        lipgloss.Color("#61AFEF"), // Blue
			Secondary:      lipgloss.Color("#98C379"), // Green
			Background:     lipgloss.Color("#282C34"), // Background
			Foreground:     lipgloss.Color("#ABB2BF"), // Foreground
			Border:         lipgloss.Color("#3E4451"), // Border
			Success:        lipgloss.Color("#98C379"), // Green
			Error:          lipgloss.Color("#E06C75"), // Red
			Warning:        lipgloss.Color("#E5C07B"), // Yellow
			Info:           lipgloss.Color("#56B6C2"), // Cyan
			Muted:          lipgloss.Color("#5C6370"), // Comment
			Accent:         lipgloss.Color("#C678DD"), // Purple
			TextPrimary:    lipgloss.Color("#ABB2BF"), // Foreground
			TextSecondary:  lipgloss.Color("#ABB2BF"), // Foreground
			CodeBackground: lipgloss.Color("#21252B"), // Background Dark
			DiffAdd:        lipgloss.Color("#98C379"), // Green
			DiffRemove:     lipgloss.Color("#E06C75"), // Red
		},
		"solarized": {
			Name:           "Solarized Dark",
			Primary:        lipgloss.Color("#268BD2"), // Blue
			Secondary:      lipgloss.Color("#859900"), // Green
			Background:     lipgloss.Color("#002B36"), // Base03
			Foreground:     lipgloss.Color("#839496"), // Base0
			Border:         lipgloss.Color("#073642"), // Base02
			Success:        lipgloss.Color("#859900"), // Green
			Error:          lipgloss.Color("#DC322F"), // Red
			Warning:        lipgloss.Color("#B58900"), // Yellow
			Info:           lipgloss.Color("#2AA198"), // Cyan
			Muted:          lipgloss.Color("#586E75"), // Base01
			Accent:         lipgloss.Color("#D33682"), // Magenta
			TextPrimary:    lipgloss.Color("#839496"), // Base0
			TextSecondary:  lipgloss.Color("#657B83"), // Base00
			CodeBackground: lipgloss.Color("#073642"), // Base02
			DiffAdd:        lipgloss.Color("#859900"), // Green
			DiffRemove:     lipgloss.Color("#DC322F"), // Red
		},
		"github": {
			Name:           "GitHub Dark",
			Primary:        lipgloss.Color("#58A6FF"), // Blue
			Secondary:      lipgloss.Color("#3FB950"), // Green
			Background:     lipgloss.Color("#0D1117"), // Background
			Foreground:     lipgloss.Color("#C9D1D9"), // Foreground
			Border:         lipgloss.Color("#30363D"), // Border
			Success:        lipgloss.Color("#3FB950"), // Green
			Error:          lipgloss.Color("#F85149"), // Red
			Warning:        lipgloss.Color("#D29922"), // Yellow
			Info:           lipgloss.Color("#58A6FF"), // Blue
			Muted:          lipgloss.Color("#8B949E"), // Muted
			Accent:         lipgloss.Color("#A371F7"), // Purple
			TextPrimary:    lipgloss.Color("#C9D1D9"), // Foreground
			TextSecondary:  lipgloss.Color("#8B949E"), // Muted
			CodeBackground: lipgloss.Color("#161B22"), // Background Secondary
			DiffAdd:        lipgloss.Color("#238636"), // Green
			DiffRemove:     lipgloss.Color("#DA3633"), // Red
		},
		"rosepine": {
			Name:           "Rose Pine",
			Primary:        lipgloss.Color("#C4A7E7"), // Iris
			Secondary:      lipgloss.Color("#9CCFD8"), // Foam
			Background:     lipgloss.Color("#191724"), // Base
			Foreground:     lipgloss.Color("#E0DEF4"), // Text
			Border:         lipgloss.Color("#26233A"), // Overlay
			Success:        lipgloss.Color("#9CCFD8"), // Foam
			Error:          lipgloss.Color("#EB6F92"), // Love
			Warning:        lipgloss.Color("#F6C177"), // Gold
			Info:           lipgloss.Color("#31748F"), // Pine
			Muted:          lipgloss.Color("#6E6A86"), // Muted
			Accent:         lipgloss.Color("#EBBCBA"), // Rose
			TextPrimary:    lipgloss.Color("#E0DEF4"), // Text
			TextSecondary:  lipgloss.Color("#908CAA"), // Subtle
			CodeBackground: lipgloss.Color("#1F1D2E"), // Surface
			DiffAdd:        lipgloss.Color("#9CCFD8"), // Foam
			DiffRemove:     lipgloss.Color("#EB6F92"), // Love
		},
		"nightowl": {
			Name:           "Night Owl",
			Primary:        lipgloss.Color("#82AAFF"), // Blue
			Secondary:      lipgloss.Color("#ADDB67"), // Green
			Background:     lipgloss.Color("#011627"), // Background
			Foreground:     lipgloss.Color("#D6DEEB"), // Foreground
			Border:         lipgloss.Color("#1D3B53"), // Border
			Success:        lipgloss.Color("#ADDB67"), // Green
			Error:          lipgloss.Color("#EF5350"), // Red
			Warning:        lipgloss.Color("#FFCB6B"), // Yellow
			Info:           lipgloss.Color("#7FDBCA"), // Cyan
			Muted:          lipgloss.Color("#637777"), // Comment
			Accent:         lipgloss.Color("#C792EA"), // Purple
			TextPrimary:    lipgloss.Color("#D6DEEB"), // Foreground
			TextSecondary:  lipgloss.Color("#7FDBCA"), // Cyan
			CodeBackground: lipgloss.Color("#0B2942"), // Background Light
			DiffAdd:        lipgloss.Color("#ADDB67"), // Green
			DiffRemove:     lipgloss.Color("#EF5350"), // Red
		},
		"material": {
			Name:           "Material",
			Primary:        lipgloss.Color("#82AAFF"), // Blue
			Secondary:      lipgloss.Color("#C3E88D"), // Green
			Background:     lipgloss.Color("#263238"), // Background
			Foreground:     lipgloss.Color("#EEFFFF"), // Foreground
			Border:         lipgloss.Color("#37474F"), // Border
			Success:        lipgloss.Color("#C3E88D"), // Green
			Error:          lipgloss.Color("#F07178"), // Red
			Warning:        lipgloss.Color("#FFCB6B"), // Yellow
			Info:           lipgloss.Color("#89DDFF"), // Cyan
			Muted:          lipgloss.Color("#546E7A"), // Comment
			Accent:         lipgloss.Color("#C792EA"), // Purple
			TextPrimary:    lipgloss.Color("#EEFFFF"), // Foreground
			TextSecondary:  lipgloss.Color("#B0BEC5"), // Foreground Light
			CodeBackground: lipgloss.Color("#1E272C"), // Background Dark
			DiffAdd:        lipgloss.Color("#C3E88D"), // Green
			DiffRemove:     lipgloss.Color("#F07178"), // Red
		},
		"ayu": {
			Name:           "Ayu (Mirage)",
			Primary:        lipgloss.Color("#FFCC66"), // Yellow
			Secondary:      lipgloss.Color("#87D96C"), // Green
			Background:     lipgloss.Color("#1F2430"), // Background
			Foreground:     lipgloss.Color("#CBCCC6"), // Foreground
			Border:         lipgloss.Color("#33415E"), // Border
			Success:        lipgloss.Color("#87D96C"), // Green
			Error:          lipgloss.Color("#F27983"), // Red
			Warning:        lipgloss.Color("#FFCC66"), // Yellow
			Info:           lipgloss.Color("#5CCFE6"), // Cyan
			Muted:          lipgloss.Color("#5C6773"), // Comment
			Accent:         lipgloss.Color("#D4BFFF"), // Purple
			TextPrimary:    lipgloss.Color("#CBCCC6"), // Foreground
			TextSecondary:  lipgloss.Color("#707A8C"), // Foreground Dim
			CodeBackground: lipgloss.Color("#242936"), // Background Dark
			DiffAdd:        lipgloss.Color("#87D96C"), // Green
			DiffRemove:     lipgloss.Color("#F27983"), // Red
		},
		"everforest": {
			Name:           "Everforest",
			Primary:        lipgloss.Color("#A7C080"), // Green
			Secondary:      lipgloss.Color("#83C092"), // Aqua
			Background:     lipgloss.Color("#2D353B"), // Background
			Foreground:     lipgloss.Color("#D3C6AA"), // Foreground
			Border:         lipgloss.Color("#475258"), // Border
			Success:        lipgloss.Color("#A7C080"), // Green
			Error:          lipgloss.Color("#E67E80"), // Red
			Warning:        lipgloss.Color("#DBBC7F"), // Yellow
			Info:           lipgloss.Color("#7FBBB3"), // Blue
			Muted:          lipgloss.Color("#859289"), // Comment
			Accent:         lipgloss.Color("#D699B6"), // Purple
			TextPrimary:    lipgloss.Color("#D3C6AA"), // Foreground
			TextSecondary:  lipgloss.Color("#9DA9A0"), // Foreground Dim
			CodeBackground: lipgloss.Color("#343F44"), // Background Light
			DiffAdd:        lipgloss.Color("#A7C080"), // Green
			DiffRemove:     lipgloss.Color("#E67E80"), // Red
		},
		"kanagawa": {
			Name:           "Kanagawa",
			Primary:        lipgloss.Color("#7E9CD8"), // Blue
			Secondary:      lipgloss.Color("#76946A"), // Green
			Background:     lipgloss.Color("#1F1F28"), // Background
			Foreground:     lipgloss.Color("#DCD7BA"), // Foreground
			Border:         lipgloss.Color("#363646"), // Border
			Success:        lipgloss.Color("#76946A"), // Green
			Error:          lipgloss.Color("#C34043"), // Red
			Warning:        lipgloss.Color("#C0A36E"), // Yellow
			Info:           lipgloss.Color("#7FB4CA"), // Cyan
			Muted:          lipgloss.Color("#727169"), // Comment
			Accent:         lipgloss.Color("#957FB8"), // Purple
			TextPrimary:    lipgloss.Color("#DCD7BA"), // Foreground
			TextSecondary:  lipgloss.Color("#C8C093"), // Foreground Dim
			CodeBackground: lipgloss.Color("#2A2A37"), // Background Light
			DiffAdd:        lipgloss.Color("#76946A"), // Green
			DiffRemove:     lipgloss.Color("#C34043"), // Red
		},
		"synthwave": {
			Name:           "Synthwave '84",
			Primary:        lipgloss.Color("#FF7EDB"), // Pink
			Secondary:      lipgloss.Color("#72F1B8"), // Green
			Background:     lipgloss.Color("#262335"), // Background
			Foreground:     lipgloss.Color("#FFFFFF"), // Foreground
			Border:         lipgloss.Color("#495495"), // Border
			Success:        lipgloss.Color("#72F1B8"), // Green
			Error:          lipgloss.Color("#FE4450"), // Red
			Warning:        lipgloss.Color("#FEDE5D"), // Yellow
			Info:           lipgloss.Color("#36F9F6"), // Cyan
			Muted:          lipgloss.Color("#848BBD"), // Comment
			Accent:         lipgloss.Color("#FF7EDB"), // Pink
			TextPrimary:    lipgloss.Color("#FFFFFF"), // Foreground
			TextSecondary:  lipgloss.Color("#B6B1B1"), // Foreground Dim
			CodeBackground: lipgloss.Color("#34294F"), // Background Light
			DiffAdd:        lipgloss.Color("#72F1B8"), // Green
			DiffRemove:     lipgloss.Color("#FE4450"), // Red
		},
		"palenight": {
			Name:           "Palenight",
			Primary:        lipgloss.Color("#82AAFF"), // Blue
			Secondary:      lipgloss.Color("#C3E88D"), // Green
			Background:     lipgloss.Color("#292D3E"), // Background
			Foreground:     lipgloss.Color("#A6ACCD"), // Foreground
			Border:         lipgloss.Color("#444267"), // Border
			Success:        lipgloss.Color("#C3E88D"), // Green
			Error:          lipgloss.Color("#F07178"), // Red
			Warning:        lipgloss.Color("#FFCB6B"), // Yellow
			Info:           lipgloss.Color("#89DDFF"), // Cyan
			Muted:          lipgloss.Color("#676E95"), // Comment
			Accent:         lipgloss.Color("#C792EA"), // Purple
			TextPrimary:    lipgloss.Color("#A6ACCD"), // Foreground
			TextSecondary:  lipgloss.Color("#959DCB"), // Foreground Dim
			CodeBackground: lipgloss.Color("#32374D"), // Background Light
			DiffAdd:        lipgloss.Color("#C3E88D"), // Green
			DiffRemove:     lipgloss.Color("#F07178"), // Red
		},
		"vercel": {
			Name:           "Vercel",
			Primary:        lipgloss.Color("#FFFFFF"), // White
			Secondary:      lipgloss.Color("#50E3C2"), // Cyan
			Background:     lipgloss.Color("#000000"), // Black
			Foreground:     lipgloss.Color("#FFFFFF"), // White
			Border:         lipgloss.Color("#333333"), // Dark Gray
			Success:        lipgloss.Color("#50E3C2"), // Cyan
			Error:          lipgloss.Color("#FF0080"), // Pink
			Warning:        lipgloss.Color("#F5A623"), // Orange
			Info:           lipgloss.Color("#0070F3"), // Blue
			Muted:          lipgloss.Color("#666666"), // Gray
			Accent:         lipgloss.Color("#7928CA"), // Purple
			TextPrimary:    lipgloss.Color("#FFFFFF"), // White
			TextSecondary:  lipgloss.Color("#888888"), // Light Gray
			CodeBackground: lipgloss.Color("#111111"), // Almost Black
			DiffAdd:        lipgloss.Color("#50E3C2"), // Cyan
			DiffRemove:     lipgloss.Color("#FF0080"), // Pink
		},
		"matrix": {
			Name:           "Matrix",
			Primary:        lipgloss.Color("#00FF41"), // Green
			Secondary:      lipgloss.Color("#00FF41"), // Green
			Background:     lipgloss.Color("#0D0208"), // Black
			Foreground:     lipgloss.Color("#00FF41"), // Green
			Border:         lipgloss.Color("#003B00"), // Dark Green
			Success:        lipgloss.Color("#00FF41"), // Green
			Error:          lipgloss.Color("#FF0000"), // Red
			Warning:        lipgloss.Color("#FFFF00"), // Yellow
			Info:           lipgloss.Color("#008F11"), // Light Green
			Muted:          lipgloss.Color("#003B00"), // Dark Green
			Accent:         lipgloss.Color("#008F11"), // Light Green
			TextPrimary:    lipgloss.Color("#00FF41"), // Green
			TextSecondary:  lipgloss.Color("#008F11"), // Light Green
			CodeBackground: lipgloss.Color("#0D0208"), // Black
			DiffAdd:        lipgloss.Color("#00FF41"), // Green
			DiffRemove:     lipgloss.Color("#FF0000"), // Red
		},
		"zenburn": {
			Name:           "Zenburn",
			Primary:        lipgloss.Color("#8CD0D3"), // Cyan
			Secondary:      lipgloss.Color("#7F9F7F"), // Green
			Background:     lipgloss.Color("#3F3F3F"), // Background
			Foreground:     lipgloss.Color("#DCDCCC"), // Foreground
			Border:         lipgloss.Color("#636363"), // Border
			Success:        lipgloss.Color("#7F9F7F"), // Green
			Error:          lipgloss.Color("#CC9393"), // Red
			Warning:        lipgloss.Color("#DFAF8F"), // Orange
			Info:           lipgloss.Color("#8CD0D3"), // Cyan
			Muted:          lipgloss.Color("#7F9F7F"), // Green
			Accent:         lipgloss.Color("#DC8CC3"), // Purple
			TextPrimary:    lipgloss.Color("#DCDCCC"), // Foreground
			TextSecondary:  lipgloss.Color("#989890"), // Foreground Dim
			CodeBackground: lipgloss.Color("#4F4F4F"), // Background Light
			DiffAdd:        lipgloss.Color("#7F9F7F"), // Green
			DiffRemove:     lipgloss.Color("#CC9393"), // Red
		},
		"cobalt2": {
			Name:           "Cobalt2",
			Primary:        lipgloss.Color("#FFC600"), // Yellow
			Secondary:      lipgloss.Color("#3AD900"), // Green
			Background:     lipgloss.Color("#193549"), // Background
			Foreground:     lipgloss.Color("#FFFFFF"), // Foreground
			Border:         lipgloss.Color("#0D3A58"), // Border
			Success:        lipgloss.Color("#3AD900"), // Green
			Error:          lipgloss.Color("#FF0000"), // Red
			Warning:        lipgloss.Color("#FFC600"), // Yellow
			Info:           lipgloss.Color("#0088FF"), // Blue
			Muted:          lipgloss.Color("#0D3A58"), // Border
			Accent:         lipgloss.Color("#FF9D00"), // Orange
			TextPrimary:    lipgloss.Color("#FFFFFF"), // Foreground
			TextSecondary:  lipgloss.Color("#E1EFFF"), // Foreground Light
			CodeBackground: lipgloss.Color("#122738"), // Background Dark
			DiffAdd:        lipgloss.Color("#3AD900"), // Green
			DiffRemove:     lipgloss.Color("#FF0000"), // Red
		},
		"horizon": {
			Name:           "Horizon",
			Primary:        lipgloss.Color("#E95678"), // Red
			Secondary:      lipgloss.Color("#29D398"), // Green
			Background:     lipgloss.Color("#1C1E26"), // Background
			Foreground:     lipgloss.Color("#D5D8DA"), // Foreground
			Border:         lipgloss.Color("#2E303E"), // Border
			Success:        lipgloss.Color("#29D398"), // Green
			Error:          lipgloss.Color("#E95678"), // Red
			Warning:        lipgloss.Color("#FAB795"), // Orange
			Info:           lipgloss.Color("#26BBD9"), // Cyan
			Muted:          lipgloss.Color("#6C6F93"), // Comment
			Accent:         lipgloss.Color("#EE64AC"), // Pink
			TextPrimary:    lipgloss.Color("#D5D8DA"), // Foreground
			TextSecondary:  lipgloss.Color("#CBCED0"), // Foreground Dim
			CodeBackground: lipgloss.Color("#232530"), // Background Light
			DiffAdd:        lipgloss.Color("#29D398"), // Green
			DiffRemove:     lipgloss.Color("#E95678"), // Red
		},
		"oceanic": {
			Name:           "Oceanic Next",
			Primary:        lipgloss.Color("#6699CC"), // Blue
			Secondary:      lipgloss.Color("#99C794"), // Green
			Background:     lipgloss.Color("#1B2B34"), // Background
			Foreground:     lipgloss.Color("#D8DEE9"), // Foreground
			Border:         lipgloss.Color("#343D46"), // Border
			Success:        lipgloss.Color("#99C794"), // Green
			Error:          lipgloss.Color("#EC5F67"), // Red
			Warning:        lipgloss.Color("#FAC863"), // Yellow
			Info:           lipgloss.Color("#5FB3B3"), // Cyan
			Muted:          lipgloss.Color("#65737E"), // Comment
			Accent:         lipgloss.Color("#C594C5"), // Purple
			TextPrimary:    lipgloss.Color("#D8DEE9"), // Foreground
			TextSecondary:  lipgloss.Color("#A7ADBA"), // Foreground Dim
			CodeBackground: lipgloss.Color("#22333E"), // Background Light
			DiffAdd:        lipgloss.Color("#99C794"), // Green
			DiffRemove:     lipgloss.Color("#EC5F67"), // Red
		},
		"atom": {
			Name:           "Atom One Dark",
			Primary:        lipgloss.Color("#528BFF"), // Blue
			Secondary:      lipgloss.Color("#98C379"), // Green
			Background:     lipgloss.Color("#21252B"), // Background
			Foreground:     lipgloss.Color("#ABB2BF"), // Foreground
			Border:         lipgloss.Color("#181A1F"), // Border
			Success:        lipgloss.Color("#98C379"), // Green
			Error:          lipgloss.Color("#E06C75"), // Red
			Warning:        lipgloss.Color("#E5C07B"), // Yellow
			Info:           lipgloss.Color("#56B6C2"), // Cyan
			Muted:          lipgloss.Color("#5C6370"), // Comment
			Accent:         lipgloss.Color("#C678DD"), // Purple
			TextPrimary:    lipgloss.Color("#ABB2BF"), // Foreground
			TextSecondary:  lipgloss.Color("#828997"), // Foreground Dim
			CodeBackground: lipgloss.Color("#282C34"), // Background Light
			DiffAdd:        lipgloss.Color("#98C379"), // Green
			DiffRemove:     lipgloss.Color("#E06C75"), // Red
		},
		"iceberg": {
			Name:           "Iceberg",
			Primary:        lipgloss.Color("#84A0C6"), // Blue
			Secondary:      lipgloss.Color("#B4BE82"), // Green
			Background:     lipgloss.Color("#161821"), // Background
			Foreground:     lipgloss.Color("#C6C8D1"), // Foreground
			Border:         lipgloss.Color("#1E2132"), // Border
			Success:        lipgloss.Color("#B4BE82"), // Green
			Error:          lipgloss.Color("#E27878"), // Red
			Warning:        lipgloss.Color("#E2A478"), // Orange
			Info:           lipgloss.Color("#89B8C2"), // Cyan
			Muted:          lipgloss.Color("#6B7089"), // Comment
			Accent:         lipgloss.Color("#A093C7"), // Purple
			TextPrimary:    lipgloss.Color("#C6C8D1"), // Foreground
			TextSecondary:  lipgloss.Color("#9A9CA5"), // Foreground Dim
			CodeBackground: lipgloss.Color("#1E2132"), // Background Light
			DiffAdd:        lipgloss.Color("#B4BE82"), // Green
			DiffRemove:     lipgloss.Color("#E27878"), // Red
		},
		"panda": {
			Name:           "Panda",
			Primary:        lipgloss.Color("#19F9D8"), // Cyan
			Secondary:      lipgloss.Color("#6FC1FF"), // Blue
			Background:     lipgloss.Color("#292A2B"), // Background
			Foreground:     lipgloss.Color("#E6E6E6"), // Foreground
			Border:         lipgloss.Color("#3F4042"), // Border
			Success:        lipgloss.Color("#19F9D8"), // Cyan
			Error:          lipgloss.Color("#FF4B82"), // Red
			Warning:        lipgloss.Color("#FFCC95"), // Orange
			Info:           lipgloss.Color("#6FC1FF"), // Blue
			Muted:          lipgloss.Color("#757575"), // Comment
			Accent:         lipgloss.Color("#FF75B5"), // Pink
			TextPrimary:    lipgloss.Color("#E6E6E6"), // Foreground
			TextSecondary:  lipgloss.Color("#CCCCCC"), // Foreground Dim
			CodeBackground: lipgloss.Color("#31353A"), // Background Light
			DiffAdd:        lipgloss.Color("#19F9D8"), // Cyan
			DiffRemove:     lipgloss.Color("#FF4B82"), // Red
		},
		"shadesofpurple": {
			Name:           "Shades of Purple",
			Primary:        lipgloss.Color("#FAD000"), // Yellow
			Secondary:      lipgloss.Color("#A599E9"), // Purple
			Background:     lipgloss.Color("#2D2B55"), // Background
			Foreground:     lipgloss.Color("#FFFFFF"), // Foreground
			Border:         lipgloss.Color("#1E1E3F"), // Border
			Success:        lipgloss.Color("#9EFFFF"), // Cyan
			Error:          lipgloss.Color("#EC3A37"), // Red
			Warning:        lipgloss.Color("#FAD000"), // Yellow
			Info:           lipgloss.Color("#9EFFFF"), // Cyan
			Muted:          lipgloss.Color("#B362FF"), // Purple Light
			Accent:         lipgloss.Color("#FF628C"), // Pink
			TextPrimary:    lipgloss.Color("#FFFFFF"), // Foreground
			TextSecondary:  lipgloss.Color("#A599E9"), // Purple
			CodeBackground: lipgloss.Color("#1E1E3F"), // Background Dark
			DiffAdd:        lipgloss.Color("#9EFFFF"), // Cyan
			DiffRemove:     lipgloss.Color("#EC3A37"), // Red
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

// GetThemeNames returns a sorted list of available theme names
func GetThemeNames() []string {
	names := ListThemes()
	// Sort alphabetically
	for i := 0; i < len(names)-1; i++ {
		for j := i + 1; j < len(names); j++ {
			if names[i] > names[j] {
				names[i], names[j] = names[j], names[i]
			}
		}
	}
	return names
}

// GetCurrentThemeName returns the name of the currently active theme
func GetCurrentThemeName() string {
	if currentTheme == nil {
		return "default"
	}
	// Find the key for the current theme
	for name, theme := range themes {
		if theme == currentTheme {
			return name
		}
	}
	return "default"
}

// GetThemeByName returns a theme by name, or nil if not found
func GetThemeByName(name string) *Theme {
	if theme, ok := themes[name]; ok {
		return theme
	}
	return nil
}
