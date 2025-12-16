package styles

// Example usage of the theme system:
//
// 1. Get the current theme:
//    theme := styles.GetCurrentTheme()
//    primaryColor := theme.Primary
//
// 2. Change the theme:
//    styles.SetTheme("dracula")  // Returns true if theme exists
//    styles.SetTheme("nord")
//    styles.SetTheme("tokyonight")
//
// 3. List available themes:
//    themes := styles.ListThemes()
//    // Returns: ["default", "light", "dracula", "nord", "monokai", "catppuccin", "tokyonight", "gruvbox"]
//
// 4. Use theme-aware style functions:
//    userLabel := styles.UserLabel()  // Returns a lipgloss.Style
//    errorMsg := styles.ErrorStyle().Render("An error occurred")
//    successMsg := styles.SuccessStyle().Render("Success!")
//
// 5. Use theme colors directly:
//    theme := styles.GetCurrentTheme()
//    customStyle := lipgloss.NewStyle().
//        Foreground(theme.Primary).
//        Background(theme.Background).
//        Border(lipgloss.RoundedBorder()).
//        BorderForeground(theme.Border)
//
// Available themes:
// - default: Dark theme with violet and emerald accents
// - light: Light theme for bright environments
// - dracula: Popular dark theme with vibrant colors
// - nord: Arctic, north-bluish color palette
// - monokai: Classic code editor theme
// - catppuccin: Soothing pastel theme (Mocha variant)
// - tokyonight: Clean, dark theme inspired by Tokyo's neon nights
// - gruvbox: Retro groove color scheme
//
// Theme struct contains:
// - Primary: Main accent color
// - Secondary: Secondary accent color
// - Background: Base background color
// - Foreground: Base text color
// - Border: Border color
// - Success: Success state color
// - Error: Error state color
// - Warning: Warning state color
// - Info: Info state color
// - Muted: Muted/disabled text color
// - Accent: Additional accent color
// - TextPrimary: Primary text color (high contrast)
// - TextSecondary: Secondary text color (medium contrast)
// - CodeBackground: Background for code blocks
// - DiffAdd: Color for added lines in diffs
// - DiffRemove: Color for removed lines in diffs
