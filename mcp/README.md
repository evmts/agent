# Plue MCP Server

The Plue MCP (Model Context Protocol) server allows AI assistants like Claude to directly control and interact with the Plue application through a standardized protocol.

## Features

The Plue MCP server provides the following tools:

### Application Control
- **plue_launch** - Launch the Plue application
- **plue_quit** - Quit the Plue application
- **plue_get_state** - Get the current application state

### Terminal Operations
- **plue_terminal_command** - Execute commands in Plue's terminal
- **plue_terminal_output** - Get the current terminal output

### Chat/Agent Operations
- **plue_send_message** - Send messages to the chat/agent interface
- **plue_get_messages** - Retrieve conversation messages

### Navigation
- **plue_switch_tab** - Switch between tabs (prompt, farcaster, agent, terminal, web, editor, diff, worktree)

### File Operations
- **plue_open_file** - Open files in the editor
- **plue_save_file** - Save the current file

### Prompt Engineering
- **plue_set_prompt** - Set prompt content
- **plue_get_prompt** - Get current prompt content

### Git Worktree Operations
- **plue_list_worktrees** - List all git worktrees
- **plue_create_worktree** - Create a new git worktree

### Farcaster Operations
- **plue_farcaster_post** - Post to Farcaster

## Building

To build the Plue MCP server:

```bash
zig build plue-mcp
```

## Running

To run the MCP server:

```bash
zig build plue-mcp
```

Or run the compiled binary directly:

```bash
./zig-out/bin/plue-mcp
```

## Integration with Claude Desktop

1. Copy the configuration to Claude Desktop's config directory:

```bash
# macOS
cp mcp/claude_desktop_config.json ~/Library/Application\ Support/Claude/claude_desktop_config.json

# Merge with existing config if needed
```

2. Restart Claude Desktop

3. The Plue MCP server will now be available to Claude

## Usage Examples

Once integrated, you can ask Claude to:

- "Launch Plue and switch to the terminal tab"
- "Run `ls -la` in Plue's terminal"
- "Send a message to the agent asking for help with code"
- "Open the file /path/to/myfile.zig in Plue"
- "Get the current state of the Plue application"
- "Post 'Hello from MCP!' to Farcaster"

## Development

The MCP server is implemented in Zig and uses AppleScript to communicate with the Plue application. The server:

1. Listens for JSON-RPC requests on stdin
2. Processes tool calls
3. Executes corresponding AppleScript commands
4. Returns results via JSON-RPC on stdout

## Extending

To add new tools:

1. Add the tool definition in `handleListTools`
2. Create a handler function for the tool
3. Add the handler to the routing in `handleCallTool`
4. Update the AppleScript support in the Plue app if needed

## Architecture

```
Claude Desktop <-> MCP Protocol <-> Plue MCP Server <-> AppleScript <-> Plue App
```

The MCP server acts as a bridge between Claude's standardized tool-calling interface and Plue's AppleScript API.