package dialog

import (
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/williamcory/agent/tui/internal/styles"
)

// AgentInfo represents information about an available agent
type AgentInfo struct {
	Name        string
	Description string
	Mode        string // "primary" or "subagent"
	Color       string // hex color for UI
}

// AgentDialog displays the agent selection interface
type AgentDialog struct {
	BaseDialog
	agents        []AgentInfo
	selectedIndex int
}

// NewAgentDialog creates a new agent selection dialog
func NewAgentDialog() *AgentDialog {
	// Pre-define available agents (matching Python registry)
	agents := []AgentInfo{
		{
			Name:        "build",
			Description: "Default agent for development tasks",
			Mode:        "primary",
			Color:       "#7C3AED", // purple
		},
		{
			Name:        "general",
			Description: "Multi-step parallel task execution",
			Mode:        "subagent",
			Color:       "#3B82F6", // blue
		},
		{
			Name:        "plan",
			Description: "Read-only analysis and planning",
			Mode:        "primary",
			Color:       "#10B981", // green
		},
		{
			Name:        "explore",
			Description: "Fast codebase exploration",
			Mode:        "subagent",
			Color:       "#F59E0B", // amber
		},
	}

	content := buildAgentContent(agents, 0)
	return &AgentDialog{
		BaseDialog:    NewBaseDialog("Select Agent", content, 70, 16),
		agents:        agents,
		selectedIndex: 0,
	}
}

// buildAgentContent builds the content for the agent selection dialog
func buildAgentContent(agents []AgentInfo, selectedIndex int) string {
	var lines []string
	lines = append(lines, "")

	theme := styles.GetCurrentTheme()

	for i, agent := range agents {
		// Style for agent name
		nameStyle := lipgloss.NewStyle().
			Foreground(lipgloss.Color(agent.Color)).
			Bold(true)

		// Mode badge style
		badgeStyle := lipgloss.NewStyle().
			Foreground(theme.TextPrimary).
			Background(lipgloss.Color(agent.Color)).
			Padding(0, 1).
			Bold(true)

		// Description style
		descStyle := lipgloss.NewStyle().
			Foreground(theme.TextSecondary)

		// Selection indicator
		indicator := "  "
		if i == selectedIndex {
			indicator = "> "
			// Highlight selected item
			nameStyle = nameStyle.Underline(true)
		}

		// Build the line
		name := nameStyle.Render(agent.Name)
		badge := badgeStyle.Render(agent.Mode)
		desc := descStyle.Render(agent.Description)

		line := indicator + name + "  " + badge
		lines = append(lines, "  "+line)
		lines = append(lines, "    "+desc)
		lines = append(lines, "")
	}

	lines = append(lines, styles.MutedText().Render("  Use ↑/↓ or j/k to navigate, Enter to select, Esc to cancel"))
	lines = append(lines, "")

	return strings.Join(lines, "\n")
}

// Update handles messages for the agent dialog
func (d *AgentDialog) Update(msg tea.Msg) (*AgentDialog, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "esc", "q":
			d.SetVisible(false)
			return d, nil

		case "enter":
			// Return the selected agent
			d.SetVisible(false)
			return d, func() tea.Msg {
				return AgentSelectedMsg{Agent: d.agents[d.selectedIndex]}
			}

		case "up", "k":
			if d.selectedIndex > 0 {
				d.selectedIndex--
				d.Content = buildAgentContent(d.agents, d.selectedIndex)
			}
			return d, nil

		case "down", "j":
			if d.selectedIndex < len(d.agents)-1 {
				d.selectedIndex++
				d.Content = buildAgentContent(d.agents, d.selectedIndex)
			}
			return d, nil
		}
	}
	return d, nil
}

// GetSelected returns the currently selected agent
func (d *AgentDialog) GetSelected() AgentInfo {
	return d.agents[d.selectedIndex]
}

// Render renders the agent dialog
func (d *AgentDialog) Render(termWidth, termHeight int) string {
	return d.BaseDialog.Render(termWidth, termHeight)
}

// AgentSelectedMsg is sent when an agent is selected
type AgentSelectedMsg struct {
	Agent AgentInfo
}
