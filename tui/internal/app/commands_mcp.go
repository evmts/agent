package app

import (
	"context"
	"time"

	tea "github.com/charmbracelet/bubbletea"
)

// Constants
const mcpLoadTimeout = 10 * time.Second

// mcpServersLoadedMsg is sent when MCP servers are loaded
type mcpServersLoadedMsg struct {
	servers interface{} // Will be []agent.MCPServer
	err     error
}

// showMCPDialogMsg triggers the MCP dialog to be shown
type showMCPDialogMsg struct{}

// loadMCPServers loads the list of MCP servers from the backend
func (m Model) loadMCPServers() tea.Cmd {
	return func() tea.Msg {
		ctx, cancel := context.WithTimeout(context.Background(), mcpLoadTimeout)
		defer cancel()

		servers, err := m.client.GetMCPServers(ctx)
		if err != nil {
			return mcpServersLoadedMsg{err: err}
		}

		return mcpServersLoadedMsg{servers: servers.Servers}
	}
}

// ShowMCPDialog shows the MCP browser dialog
func (m *Model) ShowMCPDialog() {
	if m.mcpDialog == nil {
		return
	}
	m.mcpDialog.SetVisible(true)
	m.activeDialog = m.mcpDialog
}
