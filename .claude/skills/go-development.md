# Go Development

This skill covers the Go SDK client library and the Bubbletea TUI application for the Claude Agent platform.

## Overview

The Go components consist of an SDK client library implementing the OpenCode API and a terminal UI application built with Bubbletea. The TUI can run standalone connecting to an external server or embed the Python server directly.

## Key Files

| File | Purpose |
|------|---------|
| `sdk/agent/client.go` | HTTP client with SSE support |
| `sdk/agent/types.go` | OpenCode type definitions |
| `tui/main.go` | Bubbletea TUI application |
| `tui/internal/embedded/process.go` | Embedded server management |

## SDK Architecture

```
agent.NewClient(baseURL)
    │
    ├── ClientOption funcs
    │   ├── WithHTTPClient(c)
    │   ├── WithDirectory(dir)
    │   └── WithTimeout(d)
    │
    ├── doRequest() - JSON requests
    │   └── Response decoding
    │
    └── doSSERequest() - SSE streaming
        └── Event channel + Error channel
```

## SDK Client

### Creating the Client

```go
import "github.com/williamcory/agent/sdk/agent"

// Basic client
client := agent.NewClient("http://localhost:8000")

// With options
client := agent.NewClient(baseURL,
    agent.WithDirectory("/path/to/project"),
    agent.WithTimeout(60*time.Second),
    agent.WithHTTPClient(customClient),
)
```

### ClientOption Pattern

```go
// WithHTTPClient sets a custom HTTP client.
func WithHTTPClient(c *http.Client) ClientOption {
    return func(client *Client) {
        client.httpClient = c
    }
}

// WithDirectory sets the directory query parameter.
func WithDirectory(dir string) ClientOption {
    return func(client *Client) {
        client.directory = &dir
    }
}

// WithTimeout sets the HTTP client timeout.
func WithTimeout(d time.Duration) ClientOption {
    return func(client *Client) {
        client.httpClient.Timeout = d
    }
}
```

### Helper Functions

```go
// Create pointers for optional fields
title := agent.String("My Session")
limit := agent.Int(10)
archived := agent.Bool(true)
```

## API Methods

### Health Check

```go
health, err := client.Health(ctx)
if err != nil {
    log.Fatal(err)
}
fmt.Printf("Status: %s, Agent: %v\n", health.Status, health.AgentConfigured)
```

### Sessions

```go
// List all sessions
sessions, err := client.ListSessions(ctx)

// Create a session
session, err := client.CreateSession(ctx, &agent.CreateSessionRequest{
    Title: agent.String("My Session"),
})

// Get session by ID
session, err := client.GetSession(ctx, sessionID)

// Update session
session, err := client.UpdateSession(ctx, sessionID, &agent.UpdateSessionRequest{
    Title: agent.String("New Title"),
})

// Delete session
err := client.DeleteSession(ctx, sessionID)
```

### Messages - Streaming

```go
// Send message with streaming
eventCh, errCh, err := client.SendMessage(ctx, sessionID, &agent.PromptRequest{
    Parts: []interface{}{
        agent.TextPartInput{Type: "text", Text: "Hello!"},
    },
    Model: &agent.ModelInfo{
        ProviderID: "anthropic",
        ModelID:    "claude-sonnet-4-20250514",
    },
})
if err != nil {
    return err
}

// Process stream events
for {
    select {
    case event, ok := <-eventCh:
        if !ok {
            return nil // Stream complete
        }
        switch event.Type {
        case "message.updated":
            if event.Message != nil {
                fmt.Printf("Message: %+v\n", event.Message)
            }
        case "part.updated":
            if event.Part != nil {
                if event.Part.Type == "text" {
                    fmt.Print(event.Part.Text)
                }
            }
        }
    case err := <-errCh:
        return err
    case <-ctx.Done():
        return ctx.Err()
    }
}
```

### Messages - Synchronous

```go
// Send and wait for complete response
result, err := client.SendMessageSync(ctx, sessionID, &agent.PromptRequest{
    Parts: []interface{}{
        agent.TextPartInput{Type: "text", Text: "Hello!"},
    },
})
if err != nil {
    return err
}

// Access response
fmt.Printf("Message: %+v\n", result.Info)
for _, part := range result.Parts {
    if part.IsText() {
        fmt.Println(part.Text)
    }
}
```

### Session Actions

```go
// Abort running session
err := client.AbortSession(ctx, sessionID)

// Get file diffs
diffs, err := client.GetSessionDiff(ctx, sessionID, nil)
for _, diff := range diffs {
    fmt.Printf("%s: +%d -%d\n", diff.File, diff.Additions, diff.Deletions)
}

// Fork session
newSession, err := client.ForkSession(ctx, sessionID, &agent.ForkRequest{
    MessageID: agent.String("msg_123"),
})

// Revert to message
session, err := client.RevertSession(ctx, sessionID, &agent.RevertRequest{
    MessageID: "msg_123",
})

// Undo revert
session, err := client.UnrevertSession(ctx, sessionID)
```

### Global Events

```go
// Subscribe to all events
eventCh, errCh, err := client.SubscribeToEvents(ctx)
if err != nil {
    return err
}

for {
    select {
    case event := <-eventCh:
        switch {
        case strings.HasPrefix(event.Type, "session."):
            fmt.Printf("Session event: %s\n", event.Type)
        case strings.HasPrefix(event.Type, "message."):
            fmt.Printf("Message event: %s\n", event.Type)
        case event.Type == "part.updated":
            fmt.Printf("Part updated: %s\n", event.Part.Type)
        }
    case err := <-errCh:
        return err
    case <-ctx.Done():
        return nil
    }
}
```

### Other Endpoints

```go
// Get MCP servers
mcpServers, err := client.GetMCPServers(ctx)

// Get project info
project, err := client.GetProject(ctx)

// List agents
agents, err := client.ListAgents(ctx)

// Get config
config, err := client.GetConfig(ctx)

// List providers
providers, err := client.ListProviders(ctx)

// List commands
commands, err := client.ListCommands(ctx)
```

## Type Definitions

### Session

```go
type Session struct {
    ID        string          `json:"id"`
    ProjectID string          `json:"projectID"`
    Directory string          `json:"directory"`
    Title     string          `json:"title"`
    Version   string          `json:"version"`
    Time      SessionTime     `json:"time"`
    ParentID  *string         `json:"parentID,omitempty"`
    Summary   *SessionSummary `json:"summary,omitempty"`
    Revert    *RevertInfo     `json:"revert,omitempty"`
}
```

### Message

```go
type Message struct {
    ID        string      `json:"id"`
    SessionID string      `json:"sessionID"`
    Role      string      `json:"role"` // "user" or "assistant"
    Time      MessageTime `json:"time"`

    // User message fields
    Agent  string          `json:"agent,omitempty"`
    Model  *ModelInfo      `json:"model,omitempty"`
    System *string         `json:"system,omitempty"`
    Tools  map[string]bool `json:"tools,omitempty"`

    // Assistant message fields
    ParentID   string     `json:"parentID,omitempty"`
    ModelID    string     `json:"modelID,omitempty"`
    ProviderID string     `json:"providerID,omitempty"`
    Cost       float64    `json:"cost,omitempty"`
    Tokens     *TokenInfo `json:"tokens,omitempty"`
    Finish     *string    `json:"finish,omitempty"`
}

// Helper methods
func (m *Message) IsUser() bool      { return m.Role == "user" }
func (m *Message) IsAssistant() bool { return m.Role == "assistant" }
```

### Part Types

```go
type Part struct {
    ID        string `json:"id"`
    SessionID string `json:"sessionID"`
    MessageID string `json:"messageID"`
    Type      string `json:"type"` // "text", "reasoning", "tool", "file"

    // TextPart / ReasoningPart
    Text string    `json:"text,omitempty"`
    Time *PartTime `json:"time,omitempty"`

    // ToolPart
    Tool  string     `json:"tool,omitempty"`
    State *ToolState `json:"state,omitempty"`

    // FilePart
    Mime     string  `json:"mime,omitempty"`
    URL      string  `json:"url,omitempty"`
    Filename *string `json:"filename,omitempty"`
}

// Helper methods
func (p *Part) IsText() bool      { return p.Type == "text" }
func (p *Part) IsReasoning() bool { return p.Type == "reasoning" }
func (p *Part) IsTool() bool      { return p.Type == "tool" }
func (p *Part) IsFile() bool      { return p.Type == "file" }
```

### ToolState with Progress

```go
type ToolState struct {
    Status   string                 `json:"status"` // "pending", "running", "completed"
    Input    map[string]interface{} `json:"input"`
    Output   string                 `json:"output,omitempty"`
    Title    *string                `json:"title,omitempty"`
    Metadata map[string]interface{} `json:"metadata,omitempty"`
    Progress *ToolProgress          `json:"progress,omitempty"`
}

type ToolProgress struct {
    Type        ProgressType `json:"type"`
    Current     int64        `json:"current"`
    Total       int64        `json:"total"`
    Unit        string       `json:"unit"`
    BytesPerSec float64      `json:"bytesPerSec"`
}

// Progress types
const (
    ProgressNone          ProgressType = "none"
    ProgressCount         ProgressType = "count"
    ProgressBytes         ProgressType = "bytes"
    ProgressTime          ProgressType = "time"
    ProgressIndeterminate ProgressType = "indeterminate"
)

// Helper methods
func (p ToolProgress) Percentage() float64  // 0-100
func (p ToolProgress) ETA() float64         // Seconds remaining
func (p ToolProgress) ElapsedSeconds() float64
```

## TUI Application

### Architecture

```
main()
    │
    ├── Flag parsing (--prompt, --backend, --embedded)
    │
    ├── Embedded server start (if needed)
    │   └── embedded.StartServer(ctx)
    │
    ├── SDK client creation
    │
    └── Bubbletea program
        ├── Init() - Create session, load models
        ├── Update() - Handle messages/events
        └── View() - Render UI
```

### Main Model

```go
type model struct {
    messages              []message
    input                 string
    client                *agent.Client
    session               *agent.Session
    waiting               bool
    err                   error
    width, height         int
    showAutocomplete      bool
    autocompleteOptions   []string
    autocompleteSelection int
    showModelMenu         bool
    modelOptions          []modelOption
    currentModel          *agent.ModelInfo
    currentMode           mode
    project               *agent.Project
    cwd                   string
    streamingText         string
    spinnerFrame          int
    seenToolIDs           map[string]bool
}
```

### Modes

```go
type mode string

const (
    normalMode mode = "normal"
    planMode   mode = "plan"
    bypassMode mode = "bypass"
)
```

### Message Types

```go
// Bubbletea messages for async operations
type streamTextUpdateMsg struct{ text string }
type streamToolStartMsg struct{ toolName, toolID string }
type streamToolCompleteMsg struct{ toolName, toolID, output string }
type streamCompleteMsg struct{}
type sessionCreatedMsg struct{ session *agent.Session }
type modelsLoadedMsg struct{ options []modelOption }
type errMsg error
```

### File References

The TUI supports `@filename` syntax for including file contents:

```go
// Parse @file references
cleanedText, filePaths := parseFileReferences(text, cwd)
attachments := readFileAttachments(filePaths)
fullMessage := buildMessageWithFiles(cleanedText, attachments)
```

Files larger than 100KB are included as references only.

### Commands

| Command | Description |
|---------|-------------|
| `/model` | Open model selection menu |
| `/new` | Create new session |
| `/clear` | Clear message history |
| `/help` | Show help |

### Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `Enter` | Send message / Select |
| `Alt+Enter` | Newline in input |
| `Tab` | Accept autocomplete |
| `Shift+Tab` | Cycle modes |
| `Esc` | Quit / Cancel |
| `Ctrl+C` | Force quit |
| `Up/Down` | Navigate menus |

## Embedded Server

### ServerProcess

```go
type ServerProcess struct {
    cmd    *exec.Cmd
    port   int
    cancel context.CancelFunc
}

// Start embedded Python server
serverProcess, url, err := embedded.StartServer(ctx)
if err != nil {
    log.Fatal(err)
}
defer serverProcess.Stop()

// Use the URL
client := agent.NewClient(url)
```

### Server Discovery

The embedded server:
1. Finds a free port automatically
2. Locates `main.py` relative to executable or working directory
3. Starts via `uv run python main.py`
4. Waits for `/health` endpoint to respond

## Build and Run

### Using Go Directly

```bash
# Build TUI
cd tui && go build -o agent-tui .

# Run with external server
./agent-tui --backend=http://localhost:8000

# Run with embedded server
./agent-tui --embedded

# Run with initial prompt
./agent-tui --prompt="Hello, world!"
```

### Using Zig Build System

```bash
# Build and run TUI
zig build run

# Build standalone
zig build

# Output at zig-out/bin/tui
```

### Environment Variables

| Variable | Description |
|----------|-------------|
| `OPENCODE_SERVER` | Default server URL |

## SSE Implementation

### Request Setup

```go
req.Header.Set("Accept", "text/event-stream")
req.Header.Set("Cache-Control", "no-cache")
req.Header.Set("Connection", "keep-alive")

// Use client without timeout for SSE
sseClient := &http.Client{}
```

### Event Parsing

```go
// Parse SSE format:
// event: message.updated
// data: {"type": "message.updated", ...}

for {
    line, err := reader.ReadString('\n')
    if strings.HasPrefix(line, "event:") {
        eventType = strings.TrimSpace(strings.TrimPrefix(line, "event:"))
    } else if strings.HasPrefix(line, "data:") {
        data := strings.TrimSpace(strings.TrimPrefix(line, "data:"))
        dataLines = append(dataLines, data)
    } else if line == "" {
        // Empty line = end of event, emit
    }
}
```

## Testing

```go
import (
    "testing"
    "github.com/williamcory/agent/sdk/agent"
)

func TestClient(t *testing.T) {
    client := agent.NewClient("http://localhost:8000")

    ctx := context.Background()
    health, err := client.Health(ctx)
    if err != nil {
        t.Fatalf("Health check failed: %v", err)
    }

    if health.Status != "ok" {
        t.Errorf("Expected status 'ok', got '%s'", health.Status)
    }
}

func TestSendMessage(t *testing.T) {
    client := agent.NewClient("http://localhost:8000")
    ctx := context.Background()

    session, err := client.CreateSession(ctx, nil)
    if err != nil {
        t.Fatalf("Create session failed: %v", err)
    }

    result, err := client.SendMessageSync(ctx, session.ID, &agent.PromptRequest{
        Parts: []interface{}{
            agent.TextPartInput{Type: "text", Text: "Say hello"},
        },
    })
    if err != nil {
        t.Fatalf("Send message failed: %v", err)
    }

    if len(result.Parts) == 0 {
        t.Error("Expected at least one part in response")
    }
}
```

## Best Practices

1. **Context usage**: Always pass context for cancellation
2. **Error handling**: Check both channel errors and HTTP errors
3. **Stream cleanup**: Ensure goroutines exit when context cancels
4. **Timeout handling**: Set appropriate timeouts for different operations
5. **Directory param**: Use `WithDirectory` for project-scoped requests

## Related Skills

- [api-development.md](./api-development.md) - OpenCode API specification
- [python-backend.md](./python-backend.md) - Server being connected to
- [testing.md](./testing.md) - E2E testing patterns
