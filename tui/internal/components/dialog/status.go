package dialog

import (
	"fmt"
	"runtime"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/williamcory/agent/tui/internal/styles"
)

// StatusInfo contains system status information
type StatusInfo struct {
	Version      string
	GoVersion    string
	OS           string
	Arch         string
	Connected    bool
	Provider     string
	Model        string
	Agent        string
	SessionID    string
	InputTokens  int
	OutputTokens int
	TotalCost    float64
	GitBranch    string
}

// StatusDialog displays system status information
type StatusDialog struct {
	BaseDialog
	info StatusInfo
}

// NewStatusDialog creates a new status dialog
func NewStatusDialog(info StatusInfo) *StatusDialog {
	d := &StatusDialog{
		BaseDialog: NewBaseDialog("System Status", "", 60, 22),
		info:       info,
	}
	d.BaseDialog.Content = d.buildContent()
	return d
}

// buildContent builds the status content
func (d *StatusDialog) buildContent() string {
	var lines []string
	theme := styles.GetCurrentTheme()

	// Section header style
	sectionStyle := lipgloss.NewStyle().
		Foreground(theme.Primary).
		Bold(true)

	labelStyle := lipgloss.NewStyle().
		Foreground(theme.Muted).
		Width(18)

	valueStyle := lipgloss.NewStyle().
		Foreground(theme.TextPrimary)

	successStyle := lipgloss.NewStyle().
		Foreground(theme.Success)

	errorStyle := lipgloss.NewStyle().
		Foreground(theme.Error)

	// System section
	lines = append(lines, "")
	lines = append(lines, sectionStyle.Render("  System"))
	lines = append(lines, "  "+strings.Repeat("─", 50))

	version := d.info.Version
	if version == "" {
		version = "dev"
	}
	lines = append(lines, "  "+labelStyle.Render("Version:")+valueStyle.Render(version))
	lines = append(lines, "  "+labelStyle.Render("Go Version:")+valueStyle.Render(runtime.Version()))
	lines = append(lines, "  "+labelStyle.Render("Platform:")+valueStyle.Render(fmt.Sprintf("%s/%s", runtime.GOOS, runtime.GOARCH)))
	lines = append(lines, "  "+labelStyle.Render("Theme:")+valueStyle.Render(styles.GetCurrentThemeName()))

	// Connection section
	lines = append(lines, "")
	lines = append(lines, sectionStyle.Render("  Connection"))
	lines = append(lines, "  "+strings.Repeat("─", 50))

	var connStatus string
	if d.info.Connected {
		connStatus = successStyle.Render("● Connected")
	} else {
		connStatus = errorStyle.Render("○ Disconnected")
	}
	lines = append(lines, "  "+labelStyle.Render("Status:")+connStatus)

	if d.info.Provider != "" {
		lines = append(lines, "  "+labelStyle.Render("Provider:")+valueStyle.Render(d.info.Provider))
	}
	if d.info.Model != "" {
		lines = append(lines, "  "+labelStyle.Render("Model:")+valueStyle.Render(d.info.Model))
	}
	if d.info.Agent != "" {
		lines = append(lines, "  "+labelStyle.Render("Agent:")+valueStyle.Render(d.info.Agent))
	}

	// Session section
	if d.info.SessionID != "" {
		lines = append(lines, "")
		lines = append(lines, sectionStyle.Render("  Session"))
		lines = append(lines, "  "+strings.Repeat("─", 50))

		sessionID := d.info.SessionID
		if len(sessionID) > 30 {
			sessionID = sessionID[:27] + "..."
		}
		lines = append(lines, "  "+labelStyle.Render("Session ID:")+valueStyle.Render(sessionID))

		totalTokens := d.info.InputTokens + d.info.OutputTokens
		if totalTokens > 0 {
			tokenStr := fmt.Sprintf("%d in / %d out", d.info.InputTokens, d.info.OutputTokens)
			lines = append(lines, "  "+labelStyle.Render("Tokens:")+valueStyle.Render(tokenStr))
		}

		if d.info.TotalCost > 0 {
			costStr := fmt.Sprintf("$%.4f", d.info.TotalCost)
			lines = append(lines, "  "+labelStyle.Render("Cost:")+valueStyle.Render(costStr))
		}
	}

	// Git section
	if d.info.GitBranch != "" {
		lines = append(lines, "")
		lines = append(lines, sectionStyle.Render("  Git"))
		lines = append(lines, "  "+strings.Repeat("─", 50))
		lines = append(lines, "  "+labelStyle.Render("Branch:")+valueStyle.Render(d.info.GitBranch))
	}

	// Footer
	lines = append(lines, "")
	footerStyle := lipgloss.NewStyle().Foreground(theme.Muted)
	lines = append(lines, footerStyle.Render("  Press Esc to close"))

	return strings.Join(lines, "\n")
}

// Update handles messages for the status dialog
func (d *StatusDialog) Update(msg tea.Msg) (*StatusDialog, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "esc", "enter", "q":
			d.SetVisible(false)
			return d, nil
		}
	}
	return d, nil
}

// Render renders the status dialog
func (d *StatusDialog) Render(termWidth, termHeight int) string {
	return d.BaseDialog.Render(termWidth, termHeight)
}

// UpdateInfo updates the status information
func (d *StatusDialog) UpdateInfo(info StatusInfo) {
	d.info = info
	d.BaseDialog.Content = d.buildContent()
}
