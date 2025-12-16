package dialog

import (
	"fmt"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/williamcory/agent/sdk/agent"
	"tui/internal/styles"
)

// MCPDialog displays MCP servers and their tools
type MCPDialog struct {
	servers       []agent.MCPServer
	selectedIndex int
	expandedMap   map[int]bool // Track which servers are expanded
	visible       bool
	width         int
	height        int
	scrollOffset  int
}

// NewMCPDialog creates a new MCP dialog
func NewMCPDialog() *MCPDialog {
	return &MCPDialog{
		servers:       []agent.MCPServer{},
		selectedIndex: 0,
		expandedMap:   make(map[int]bool),
		visible:       true,
		width:         80,
		height:        25,
		scrollOffset:  0,
	}
}

// SetServers updates the server list
func (d *MCPDialog) SetServers(servers []agent.MCPServer) {
	d.servers = servers
	// Reset selection if out of bounds
	if d.selectedIndex >= len(d.servers) {
		if len(d.servers) > 0 {
			d.selectedIndex = len(d.servers) - 1
		} else {
			d.selectedIndex = 0
		}
	}
}

// Update handles messages for the MCP dialog
func (d *MCPDialog) Update(msg tea.Msg) (Dialog, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "esc", "ctrl+shift+m":
			d.visible = false
			return d, nil
		case "up", "k":
			if d.selectedIndex > 0 {
				d.selectedIndex--
			}
			return d, nil
		case "down", "j":
			if d.selectedIndex < len(d.servers)-1 {
				d.selectedIndex++
			}
			return d, nil
		case "enter", "space", "tab":
			// Toggle expansion for the selected server
			if d.selectedIndex < len(d.servers) {
				d.expandedMap[d.selectedIndex] = !d.expandedMap[d.selectedIndex]
			}
			return d, nil
		case "r":
			// Reconnect action - not implemented yet
			return d, nil
		}
	}

	return d, nil
}

// GetTitle returns the dialog title
func (d *MCPDialog) GetTitle() string {
	return "MCP Servers"
}

// IsVisible returns whether the dialog is visible
func (d *MCPDialog) IsVisible() bool {
	return d.visible
}

// SetVisible sets the visibility
func (d *MCPDialog) SetVisible(visible bool) {
	d.visible = visible
}

// formatMCPTimeAgo formats a timestamp as a relative time string
func formatMCPTimeAgo(unixTime float64) string {
	if unixTime == 0 {
		return ""
	}

	t := time.Unix(int64(unixTime), 0)
	now := time.Now()
	diff := now.Sub(t)

	switch {
	case diff < time.Minute:
		return "just now"
	case diff < time.Hour:
		mins := int(diff.Minutes())
		if mins == 1 {
			return "1 min ago"
		}
		return fmt.Sprintf("%d mins ago", mins)
	case diff < 24*time.Hour:
		hours := int(diff.Hours())
		if hours == 1 {
			return "1 hour ago"
		}
		return fmt.Sprintf("%d hours ago", hours)
	default:
		return t.Format("Jan 2 15:04")
	}
}

// renderStatusIndicator returns a status indicator string
func renderStatusIndicator(status agent.MCPServerStatus, theme styles.Theme) string {
	var indicator string
	var color lipgloss.Color

	switch status {
	case agent.MCPStatusConnected:
		indicator = "●"
		color = theme.Success
	case agent.MCPStatusDisconnected:
		indicator = "○"
		color = theme.Muted
	case agent.MCPStatusError:
		indicator = "✗"
		color = theme.Error
	case agent.MCPStatusConnecting:
		indicator = "◐"
		color = theme.Warning
	default:
		indicator = "?"
		color = theme.Muted
	}

	return lipgloss.NewStyle().Foreground(color).Render(indicator)
}

// Render renders the MCP dialog
func (d *MCPDialog) Render(termWidth, termHeight int) string {
	if !d.visible {
		return ""
	}

	theme := styles.GetCurrentTheme()

	// Calculate dimensions
	dialogWidth := d.width
	if dialogWidth > termWidth-4 {
		dialogWidth = termWidth - 4
	}

	// Title
	titleStyle := lipgloss.NewStyle().
		Foreground(theme.Primary).
		Bold(true).
		Padding(0, 1).
		Width(dialogWidth - 4).
		Align(lipgloss.Center)

	var title string
	if len(d.servers) == 0 {
		title = titleStyle.Render("MCP Servers")
	} else {
		toolCount := 0
		for _, srv := range d.servers {
			toolCount += len(srv.Tools)
		}
		title = titleStyle.Render(fmt.Sprintf("MCP Servers (%d servers • %d tools)", len(d.servers), toolCount))
	}

	// Content
	var content string
	if len(d.servers) == 0 {
		content = d.renderEmptyState(dialogWidth, *theme)
	} else {
		content = d.renderServerList(dialogWidth, *theme)
	}

	// Help text
	helpStyle := lipgloss.NewStyle().
		Foreground(theme.Muted).
		Italic(true).
		Align(lipgloss.Center).
		Width(dialogWidth - 4)

	help := helpStyle.Render("↑↓ navigate • Enter expand/collapse • R reconnect • Esc close")

	// Border
	borderStyle := lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(theme.Primary).
		Padding(1, 1).
		Width(dialogWidth).
		MaxWidth(dialogWidth)

	dialogContent := lipgloss.JoinVertical(lipgloss.Left, title, content, help)
	dialog := borderStyle.Render(dialogContent)

	return centerDialog(dialog, termWidth, termHeight)
}

// renderEmptyState renders the empty state when no MCP servers are configured
func (d *MCPDialog) renderEmptyState(dialogWidth int, theme styles.Theme) string {
	emptyStyle := lipgloss.NewStyle().
		Foreground(theme.Muted).
		Italic(true).
		Padding(2, 2).
		Width(dialogWidth - 8).
		Align(lipgloss.Center)

	message := `No MCP servers configured

MCP servers provide tools and resources to the agent.
Configure them in your agent settings or environment.`

	return emptyStyle.Render(message)
}

// renderServerList renders the list of MCP servers
func (d *MCPDialog) renderServerList(dialogWidth int, theme styles.Theme) string {
	var lines []string
	maxVisible := 15

	for i, srv := range d.servers {
		isSelected := i == d.selectedIndex
		isExpanded := d.expandedMap[i]

		// Server line
		serverLine := d.renderServerLine(srv, isSelected, dialogWidth, theme)
		lines = append(lines, serverLine)

		// Tool lines (if expanded)
		if isExpanded {
			toolLines := d.renderToolLines(srv, isSelected, dialogWidth, theme)
			lines = append(lines, toolLines...)
		}
	}

	// Limit visible lines
	if len(lines) > maxVisible {
		start := d.scrollOffset
		end := start + maxVisible
		if end > len(lines) {
			end = len(lines)
		}
		if start >= len(lines) {
			start = len(lines) - maxVisible
			if start < 0 {
				start = 0
			}
		}
		lines = lines[start:end]
	}

	contentStyle := lipgloss.NewStyle().
		Padding(1, 2).
		Width(dialogWidth - 4)

	return contentStyle.Render(strings.Join(lines, "\n"))
}

// renderServerLine renders a single server line
func (d *MCPDialog) renderServerLine(srv agent.MCPServer, isSelected bool, dialogWidth int, theme styles.Theme) string {
	// Status indicator
	statusInd := renderStatusIndicator(srv.Status, theme)

	// Server name and description
	serverName := srv.Name
	if srv.Description != "" {
		serverName += " - " + srv.Description
	}

	// Tool count
	toolCount := fmt.Sprintf("(%d tools)", len(srv.Tools))

	// Connection time or error
	var statusText string
	if srv.Status == agent.MCPStatusConnected && srv.ConnectedAt != nil {
		statusText = formatMCPTimeAgo(*srv.ConnectedAt)
	} else if srv.Status == agent.MCPStatusError && srv.LastError != "" {
		statusText = "Error: " + srv.LastError
		if len(statusText) > 40 {
			statusText = statusText[:37] + "..."
		}
	}

	// Expand/collapse indicator
	expandInd := "▶"
	if d.expandedMap[d.selectedIndex] && isSelected {
		expandInd = "▼"
	}

	// Build the line
	var lineStyle lipgloss.Style
	if isSelected {
		lineStyle = lipgloss.NewStyle().
			Foreground(theme.TextPrimary).
			Background(theme.Primary).
			Width(dialogWidth - 10).
			PaddingLeft(1)
	} else {
		lineStyle = lipgloss.NewStyle().
			Foreground(theme.TextPrimary).
			Width(dialogWidth - 10).
			PaddingLeft(1)
	}

	// Format: [status] [expand] name (X tools) [status text]
	leftPart := fmt.Sprintf("%s %s %s %s", statusInd, expandInd, serverName, toolCount)
	maxLeftLen := dialogWidth - 20 - len(statusText)
	if len(leftPart) > maxLeftLen {
		leftPart = leftPart[:maxLeftLen-3] + "..."
	}

	padding := dialogWidth - 14 - len(leftPart) - len(statusText)
	if padding < 1 {
		padding = 1
	}

	line := leftPart + strings.Repeat(" ", padding) + statusText

	return lineStyle.Render(line)
}

// renderToolLines renders the tool list for an expanded server
func (d *MCPDialog) renderToolLines(srv agent.MCPServer, isParentSelected bool, dialogWidth int, theme styles.Theme) []string {
	var lines []string

	if len(srv.Tools) == 0 {
		emptyStyle := lipgloss.NewStyle().
			Foreground(theme.Muted).
			Italic(true).
			PaddingLeft(6)
		lines = append(lines, emptyStyle.Render("No tools available"))
		return lines
	}

	toolStyle := lipgloss.NewStyle().
		Foreground(theme.TextSecondary).
		PaddingLeft(4)

	for _, tool := range srv.Tools {
		toolLine := fmt.Sprintf("  ├─ %s", tool.Name)
		if tool.Description != "" {
			desc := tool.Description
			maxDescLen := dialogWidth - 20 - len(tool.Name)
			if len(desc) > maxDescLen {
				desc = desc[:maxDescLen-3] + "..."
			}
			toolLine += " - " + desc
		}
		lines = append(lines, toolStyle.Render(toolLine))
	}

	return lines
}
