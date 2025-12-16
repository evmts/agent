# MCP Server Browser

<metadata>
  <priority>medium</priority>
  <category>feature</category>
  <estimated-complexity>high</estimated-complexity>
  <affects>tui/internal/components/dialog/, tui/internal/app/</affects>
</metadata>

## Objective

Create a browser interface for viewing and managing connected MCP (Model Context Protocol) servers, displaying their available tools and resources.

<context>
Claude Code supports MCP servers that extend the agent's capabilities with custom tools. Users need visibility into:
- Which MCP servers are connected
- What tools each server provides
- Server health status
- Ability to enable/disable servers

The Python backend already supports MCP - this task exposes that functionality in the TUI.
</context>

## Requirements

<functional-requirements>
1. Add MCP browser accessible via `/mcp` command or `ctrl+shift+m`
2. Display list of configured MCP servers with status:
   - Server name and description
   - Connection status (connected, disconnected, error)
   - Number of tools provided
3. Expandable view showing tools for each server:
   - Tool name and description
   - Input schema (parameters)
   - Example usage
4. Actions:
   - Reconnect to server
   - Enable/disable server
   - View server logs
5. Show "No MCP servers configured" with setup instructions when empty
</functional-requirements>

<technical-requirements>
1. Create `MCPDialog` component
2. Add API endpoint integration to fetch MCP server status
3. Implement tool schema display
4. Add accordion/tree view for server -> tools hierarchy
5. Handle real-time status updates
</technical-requirements>

## Implementation Guide

<files-to-modify>
- `tui/internal/components/dialog/mcp.go` - New MCP browser dialog
- `tui/internal/app/commands_mcp.go` - MCP action handlers
- `sdk/agent/client.go` - Add MCP status API calls
- `sdk/agent/types.go` - MCP server/tool types
- `tui/internal/keybind/actions.go` - Add ActionShowMCP
</files-to-modify>

<mcp-types>
```go
type MCPServer struct {
    Name        string
    Description string
    Status      MCPServerStatus
    URL         string
    Tools       []MCPTool
    LastError   string
    ConnectedAt time.Time
}

type MCPServerStatus string

const (
    MCPStatusConnected    MCPServerStatus = "connected"
    MCPStatusDisconnected MCPServerStatus = "disconnected"
    MCPStatusError        MCPServerStatus = "error"
    MCPStatusConnecting   MCPServerStatus = "connecting"
)

type MCPTool struct {
    Name        string
    Description string
    InputSchema map[string]interface{}
    Examples    []string
}
```
</mcp-types>

<example-ui>
```
┌─ MCP Servers ───────────────────────────────────────┐
│                                                     │
│ ● filesystem (connected)                            │
│   Local filesystem access                           │
│   ├─ read_file      Read contents of a file        │
│   ├─ write_file     Write contents to a file       │
│   ├─ list_directory List directory contents        │
│   └─ search_files   Search for files by pattern    │
│                                                     │
│ ● github (connected)                                │
│   GitHub API integration                            │
│   ├─ get_issue      Fetch issue details            │
│   ├─ create_pr      Create pull request            │
│   └─ list_repos     List repositories              │
│                                                     │
│ ○ slack (disconnected)                              │
│   Slack workspace integration                       │
│   Last error: Connection timeout                    │
│   [R] Reconnect                                     │
│                                                     │
│ ──────────────────────────────────────────────────  │
│ 3 servers · 11 tools available                      │
│ [Tab] Navigate [Enter] Expand [R] Reconnect [Esc]   │
└─────────────────────────────────────────────────────┘
```
</example-ui>

<empty-state-ui>
```
┌─ MCP Servers ───────────────────────────────────────┐
│                                                     │
│           No MCP servers configured                 │
│                                                     │
│  MCP servers extend the agent with custom tools.    │
│                                                     │
│  To add a server, create a config file:            │
│                                                     │
│    ~/.claude/mcp.json                               │
│                                                     │
│  Example configuration:                             │
│  {                                                  │
│    "servers": [{                                    │
│      "name": "filesystem",                          │
│      "command": "npx",                              │
│      "args": ["-y", "@anthropic/mcp-filesystem"]   │
│    }]                                               │
│  }                                                  │
│                                                     │
│  Learn more: https://docs.anthropic.com/mcp        │
│                                                     │
└─────────────────────────────────────────────────────┘
```
</empty-state-ui>

## Acceptance Criteria

<criteria>
- [ ] MCP browser accessible via command and keybinding
- [ ] Connected servers shown with green indicator
- [ ] Disconnected/error servers shown with status
- [ ] Tools expandable under each server
- [ ] Tool descriptions and parameters visible
- [ ] Reconnect action works for failed servers
- [ ] Empty state shows setup instructions
- [ ] Status updates in real-time
</criteria>

## Completion Instructions

<completion>
When this task is fully implemented and tested:
1. Verify all acceptance criteria are met
2. Run `zig build build-go` to ensure compilation succeeds
3. Test with mock MCP server data
4. Rename this file from `07-mcp-server-browser.md` to `07-mcp-server-browser.complete.md`
</completion>
