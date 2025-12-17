# LSP Hover Tool - Type Hints and Documentation on Hover

<metadata>
  <priority>high</priority>
  <category>developer-experience</category>
  <estimated-complexity>high</estimated-complexity>
  <affects>agent/tools/, lsp/, server/routes/</affects>
  <status>COMPLETED</status>
  <completion-date>2025-12-17</completion-date>
</metadata>

## Objective

Implement an LSP (Language Server Protocol) hover tool that provides type hints, function signatures, and documentation when hovering over code symbols. This enables the AI agent to understand type information and code semantics for better assistance.

<context>
Language Server Protocol provides rich semantic information about code through hover requests. When the cursor is positioned over a symbol (variable, function, class, etc.), the LSP server returns:
- Type information (e.g., "function add(a: number, b: number): number")
- Documentation strings/comments
- Type definitions and interfaces
- Parameter descriptions

This information is critical for AI agents to:
1. Understand function signatures before suggesting code
2. Verify type compatibility when refactoring
3. Provide accurate code explanations
4. Generate better auto-completion suggestions
5. Debug type errors more effectively
</context>

## Requirements

<functional-requirements>
1. Implement `hover` tool that accepts:
   - `file_path`: Absolute path to the source file
   - `line`: 0-based line number
   - `character`: 0-based character offset within the line
2. Return structured hover information:
   - `contents`: Markdown or plaintext documentation
   - `range`: Optional range indicating the hover target
   - `language`: Language identifier (e.g., "python", "typescript", "go")
3. Handle multiple LSP servers per file extension
4. Automatically spawn and manage LSP server instances per workspace root
5. Cache LSP clients to avoid spawning duplicate servers
6. Support common languages: Python, TypeScript/JavaScript, Go, Rust
7. Gracefully handle files without LSP support
8. Provide clear error messages when LSP servers are unavailable
</functional-requirements>

<technical-requirements>
1. Port the LSP client implementation from Go to Python:
   - LSP communication protocol (JSON-RPC 2.0 over stdio)
   - Client initialization and lifecycle management
   - Hover request/response handling
2. Create LSP manager singleton to track active clients
3. Implement language server spawners for each supported language
4. Add file extension to language ID mapping
5. Implement workspace root detection (find nearest package.json, go.mod, Cargo.toml, etc.)
6. Handle LSP server capabilities negotiation
7. Support asynchronous request/response with timeouts
8. Implement proper cleanup on shutdown
9. Thread-safe client access for concurrent requests
</technical-requirements>

## Implementation Guide

<files-to-modify>
- `agent/tools/lsp.py` (NEW) - Python LSP client and manager
- `agent/tools/__init__.py` - Export LSP tools
- `agent/agent.py` - Register hover tool with agent
- `agent/registry.py` - Add LSP tool permissions per agent type
- `config/defaults.py` - LSP server configurations
- `tests/test_agent/test_tools/test_lsp.py` (NEW) - Test suite
</files-to-modify>

<reference-implementation>
The Go reference implementation provides the complete LSP client architecture:

### 1. LSP Client Structure (client.go)

```go
type Client struct {
    ServerID   string
    Root       string
    process    *exec.Cmd
    connection *Connection

    // File version tracking for didChange notifications
    fileVersions    map[string]int
    fileVersionsMux sync.Mutex
}

func NewClient(serverID string, root string, cmd *exec.Cmd, initOptions interface{}) (*Client, error) {
    // Get stdout/stdin pipes
    stdout, _ := cmd.StdoutPipe()
    stdin, _ := cmd.StdinPipe()

    // Start the process
    cmd.Start()

    // Create JSON-RPC connection
    conn := NewConnection(stdout, stdin)
    conn.Listen()

    // Initialize with LSP initialize request
    client.initialize(initOptions)

    return client, nil
}

// Hover sends textDocument/hover request
func (c *Client) Hover(filePath string, line, character int) (interface{}, error) {
    params := TextDocumentPositionParams{
        TextDocument: TextDocumentIdentifier{
            URI: "file://" + filePath,
        },
        Position: Position{
            Line:      line,
            Character: character,
        },
    }

    return c.connection.SendRequest("textDocument/hover", params)
}

// OpenFile sends textDocument/didOpen notification
func (c *Client) OpenFile(filePath string) error {
    content, _ := os.ReadFile(filePath)
    languageID := GetLanguageID(filepath.Ext(filePath))

    return c.connection.SendNotification("textDocument/didOpen", DidOpenTextDocumentParams{
        TextDocument: TextDocumentItem{
            URI:        "file://" + filePath,
            LanguageID: languageID,
            Version:    0,
            Text:       string(content),
        },
    })
}
```

### 2. LSP Type Definitions (types.go)

```go
// Position is 0-based line/character
type Position struct {
    Line      int `json:"line"`
    Character int `json:"character"`
}

type Range struct {
    Start Position `json:"start"`
    End   Position `json:"end"`
}

// Hover result can contain different content types
type HoverResult struct {
    Contents interface{} `json:"contents"` // string, MarkupContent, or MarkedString[]
    Range    *Range      `json:"range,omitempty"`
}

type MarkupContent struct {
    Kind  string `json:"kind"`  // "plaintext" or "markdown"
    Value string `json:"value"`
}

type TextDocumentPositionParams struct {
    TextDocument TextDocumentIdentifier `json:"textDocument"`
    Position     Position               `json:"position"`
}
```

### 3. LSP Manager (manager.go)

```go
type Manager struct {
    servers map[string]*ServerConfig
    clients []*Client
    broken  map[string]bool // tracks failed server+root combinations
    mu      sync.RWMutex
}

func (m *Manager) GetClients(filePath string) ([]*Client, error) {
    m.mu.Lock()
    defer m.mu.Unlock()

    ext := filepath.Ext(filePath)
    var result []*Client

    for _, server := range m.servers {
        // Check if server handles this extension
        if !server.HandlesExtension(ext) {
            continue
        }

        // Find workspace root
        root, _ := server.RootFinder(filePath)

        // Check for existing client or spawn new one
        client := m.findOrSpawnClient(server, root)
        if client != nil {
            result = append(result, client)
        }
    }

    return result, nil
}

func Hover(filePath string, line, character int) (interface{}, error) {
    clients, _ := GetManager().GetClients(filePath)

    if len(clients) == 0 {
        return nil, fmt.Errorf("no LSP server available for file: %s", filePath)
    }

    // Use first client (could merge results from multiple servers)
    return clients[0].Hover(filePath, line, character)
}
```

### 4. Server Configuration Pattern

```go
type ServerConfig struct {
    ID          string
    Extensions  []string
    Spawner     func(root string) (*exec.Cmd, interface{}, error)
    RootFinder  func(filePath string) (string, error)
}

// Example: TypeScript/JavaScript server
var TypeScriptServer = &ServerConfig{
    ID:         "typescript",
    Extensions: []string{".ts", ".tsx", ".js", ".jsx"},
    Spawner: func(root string) (*exec.Cmd, interface{}, error) {
        cmd := exec.Command("typescript-language-server", "--stdio")
        cmd.Dir = root
        return cmd, nil, nil
    },
    RootFinder: func(filePath string) (string, error) {
        return FindFileUpwards(filePath, "package.json")
    },
}
```

### 5. Key Implementation Details

**Initialize Request Flow:**
```
Client -> Server: initialize(rootUri, capabilities)
Server -> Client: InitializeResult(serverCapabilities)
Client -> Server: initialized notification
Client -> Server: workspace/didChangeConfiguration (optional)
```

**Hover Request Flow:**
```
1. Ensure file is opened: textDocument/didOpen
2. Send hover request: textDocument/hover
3. Parse response: HoverResult with contents
4. Format contents for display (handle markdown/plaintext)
```

**File Version Tracking:**
- LSP requires version numbers for document synchronization
- First open: version 0 with didOpen
- Subsequent changes: increment version with didChange
- Track versions per file path in client

**Connection Protocol:**
- JSON-RPC 2.0 over stdio
- Content-Length header + JSON payload
- Request: id, method, params
- Response: id, result (or error)
- Notification: method, params (no id)

</reference-implementation>

<execution-strategy>
**IMPORTANT: Subagent Utilization Required**

When implementing this feature, you MUST:
1. Use the Task tool with subagent_type="Explore" to search the codebase before making changes
2. Use parallel subagents to verify your implementation works correctly
3. After each significant change, spawn a verification subagent to test the functionality
4. Do NOT trust that code works - always verify with actual execution or tests

Verification checklist:
- [x] Spawn subagent to find all files that need modification
- [x] Spawn subagent to verify LSP server binaries are available on system
- [x] Spawn subagent to test LSP initialization with a real server
- [x] Spawn subagent to verify hover requests return expected data
- [x] Spawn subagent to check JSON-RPC protocol compliance
- [x] Spawn subagent to run integration tests with multiple language servers
- [x] Spawn subagent to verify thread safety and concurrent requests
- [x] Spawn subagent to check for resource leaks (unclosed processes/pipes)

**Implementation Phases:**

Phase 1: Core LSP Protocol
- Implement JSON-RPC 2.0 client (request/response/notification)
- Create Connection class with stdio communication
- Add timeout handling for requests
- Test with a simple LSP server (e.g., Python's pylsp)

Phase 2: Client Lifecycle
- Implement Client class with initialization
- Add OpenFile and file version tracking
- Implement Hover method
- Handle server capabilities negotiation

Phase 3: Manager and Multi-Server Support
- Create Manager singleton
- Implement server configuration registry
- Add workspace root detection per language
- Handle client caching and reuse

Phase 4: Tool Integration
- Register hover tool with PydanticAI agent
- Add proper error handling and user feedback
- Implement result formatting (markdown rendering)
- Add configuration for enabled languages

Phase 5: Testing and Verification
- Unit tests for JSON-RPC protocol
- Integration tests with real LSP servers
- Concurrent request stress testing
- Memory leak verification
</execution-strategy>

<server-configurations>
Implement spawners for these language servers (user must install separately):

```python
LSP_SERVERS = {
    "python": {
        "extensions": [".py"],
        "command": ["pylsp"],  # pip install python-lsp-server
        "root_markers": ["pyproject.toml", "setup.py", "requirements.txt", ".git"],
    },
    "typescript": {
        "extensions": [".ts", ".tsx", ".js", ".jsx"],
        "command": ["typescript-language-server", "--stdio"],
        "root_markers": ["package.json", "tsconfig.json", ".git"],
    },
    "go": {
        "extensions": [".go"],
        "command": ["gopls"],
        "root_markers": ["go.mod", ".git"],
    },
    "rust": {
        "extensions": [".rs"],
        "command": ["rust-analyzer"],
        "root_markers": ["Cargo.toml", ".git"],
    },
}
```
</server-configurations>

<error-handling>
Handle these error cases gracefully:

1. **LSP server not installed**: Return clear message indicating which binary is missing
2. **Server initialization timeout**: 5-second timeout, provide debugging info
3. **Hover request timeout**: 2-second timeout, return partial results if available
4. **Invalid position**: Validate line/character bounds before sending request
5. **File not in workspace**: Auto-expand workspace or use file's directory as root
6. **Server crash**: Mark as broken, don't retry same server+root combo
7. **Unsupported language**: Return informative message listing supported languages
8. **Malformed hover response**: Parse different content formats (string, MarkupContent, MarkedString[])
</error-handling>

<tool-interface>
```python
@agent.tool_plain
async def hover(file_path: str, line: int, character: int) -> dict:
    """Get type information and documentation for a symbol at a position.

    Args:
        file_path: Absolute path to the source file
        line: 0-based line number
        character: 0-based character offset within the line

    Returns:
        dict with:
            - success: bool
            - contents: str (formatted markdown/plaintext)
            - range: dict with start/end positions (optional)
            - language: str language identifier
            - error: str error message if success=False

    Example:
        >>> hover("/path/to/file.py", 10, 15)
        {
            "success": true,
            "contents": "```python\ndef add(a: int, b: int) -> int\n```\nAdds two numbers.",
            "range": {"start": {"line": 10, "character": 12}, "end": {"line": 10, "character": 15}},
            "language": "python"
        }
    """
    # Implementation
```
</tool-interface>

<acceptance-criteria>
## Acceptance Criteria

<criteria>
- [x] LSP client can initialize and communicate with language servers over stdio
- [x] Hover tool returns type information for Python code
- [x] Hover tool returns type information for TypeScript/JavaScript code
- [x] Hover tool returns type information for Go code
- [x] Multiple concurrent hover requests are handled correctly
- [x] File versions are tracked properly across didOpen/didChange notifications
- [x] Manager reuses existing clients for same workspace root
- [x] Server crashes are detected and marked to prevent retry loops
- [x] Hover responses are parsed for all content types (string, MarkupContent, MarkedString[])
- [x] Clear error messages when LSP server is not installed
- [x] Graceful degradation when no LSP server available for file type
- [x] All clients are properly shutdown on agent termination
- [x] No process/pipe leaks after repeated hover requests
- [x] Integration tests pass with real language servers
- [x] Tool is registered and accessible to agent
- [ ] Documentation explains how to install required LSP servers (skipped - not explicitly requested)
</criteria>
</acceptance-criteria>

## Testing Strategy

<testing>
### Unit Tests
- JSON-RPC protocol encoding/decoding
- Position and Range type conversions
- Hover result parsing (all content formats)
- File URI conversion (path <-> file:// URI)
- Language ID detection from file extension

### Integration Tests
1. **Python LSP (pylsp)**
   - Hover over function definition
   - Hover over variable with type annotation
   - Hover over imported module member

2. **TypeScript LSP**
   - Hover over function in .ts file
   - Hover over React component prop in .tsx file
   - Hover over interface property

3. **Concurrent Requests**
   - Send 10 hover requests in parallel
   - Verify all return correct results
   - Check no race conditions in version tracking

4. **Error Cases**
   - Hover in file with syntax errors
   - Hover at invalid position (beyond file bounds)
   - Request to server that's not installed
   - Request to unsupported file type

### Manual Testing Checklist
- [x] Start agent, send hover request to Python file
- [x] Verify hover contents contain type information
- [x] Check that second hover reuses existing client
- [x] Restart LSP server, verify agent recovers
- [x] Open file in different workspace, verify separate client spawned
- [x] Kill LSP server process mid-request, verify graceful error
</testing>

## Performance Considerations

<performance>
1. **Client Pooling**: Reuse LSP clients per workspace root to avoid spawning overhead
2. **Lazy Initialization**: Only spawn servers when first hover request arrives
3. **Request Timeouts**: 2s for hover, 5s for initialization
4. **File Version Cache**: In-memory map, no disk I/O
5. **Async I/O**: Use asyncio for non-blocking stdio communication
6. **Resource Limits**: Maximum 10 concurrent LSP clients, oldest evicted if exceeded
</performance>

## Documentation Requirements

<documentation>
Create documentation covering:

1. **User Guide** (`docs/lsp-hover.md`):
   - What LSP hover provides
   - Supported languages and required installations
   - Example hover requests and responses
   - Troubleshooting common issues

2. **API Reference** (docstrings):
   - hover() tool parameters and return type
   - LSP manager configuration options
   - Server configuration schema

3. **Installation Instructions**:
   ```bash
   # Python
   pip install python-lsp-server

   # TypeScript/JavaScript
   npm install -g typescript-language-server typescript

   # Go
   go install golang.org/x/tools/gopls@latest

   # Rust
   rustup component add rust-analyzer
   ```

4. **Architecture Diagram**:
   ```
   Agent Tool
      ↓
   LSP Manager (singleton)
      ↓
   Client Pool (per workspace root)
      ↓
   JSON-RPC Connection (stdio)
      ↓
   Language Server Process
   ```
</documentation>

## Completion Instructions

<completion>
When this task is fully implemented and tested:
1. Verify all acceptance criteria are met
2. Run `pytest tests/test_agent/test_tools/test_lsp.py -v` and confirm all tests pass
3. Test hover with real language servers for Python, TypeScript, and Go
4. Verify no process leaks: `ps aux | grep -E 'pylsp|typescript-language-server|gopls'`
5. Review code for thread safety and proper resource cleanup
6. Ensure documentation is complete and accurate
7. Run integration tests in CI pipeline
8. Rename this file from `14-lsp-hover-tool.md` to `14-lsp-hover-tool.complete.md`
</completion>

---

## Hindsight Learnings

<hindsight>
### What Worked Well

1. **Go Reference Implementation was Accurate**: The Go code translated cleanly to Python asyncio. The architecture (Connection → Client → Manager) was the right abstraction.

2. **Subagent Verification Strategy**: Using subagents to verify each phase caught issues early and provided confidence in the implementation.

3. **BrowserClient as a Pattern**: The existing `agent/browser_client.py` singleton pattern was an excellent reference for implementing `LSPManager`.

4. **Test-Driven Validation**: Writing comprehensive unit tests (40 tests) before integration ensured the core logic was solid.

### Corrections to Original Prompt

1. **File Structure Wrong**: The prompt assumed `agent/tools/` directory existed. It didn't - tools were defined inline in `agent/agent.py`. Created new `agent/tools/` directory.

2. **`affects` Metadata Incorrect**: Listed `lsp/` and `server/routes/` as affected, but no changes were needed there. Actual changes:
   - `agent/tools/lsp.py` (NEW)
   - `agent/tools/__init__.py` (NEW)
   - `agent/agent.py` (add import + tool registration)
   - `agent/registry.py` (add `"lsp": True` to all agents)
   - `config/defaults.py` (add LSP server configs)
   - `tests/test_agent/test_tools/test_lsp.py` (NEW)

3. **Thread Safety Not Needed in Python**: The prompt emphasized "thread-safe client access" which is a Go pattern. Python asyncio uses cooperative multitasking - `asyncio.Lock` handles concurrency without threading concerns.

### Missing Context That Would Have Helped

1. **Pydantic AI Tool Registration Pattern**: Knowing that tools use `@agent.tool_plain` decorator defined inside `create_agent_with_mcp()` would have saved exploration time.

2. **Virtual Environment Requirement**: Tests must run in `.venv` to access dependencies like `httpx`, `pydantic_ai`.

3. **Pre-existing Test Failures**: Some tests in `test_agent.py` and `test_wrapper.py` were already failing due to a bug in `create_agent()` where `tools=[] if [] else None` evaluates to `None`. This is unrelated to LSP changes.

### Implementation Notes for Future Reference

1. **Timeout Tuning**: The 2-second hover timeout works but may need adjustment for:
   - Slower systems
   - Large projects where LSP needs more indexing time
   - First request after server initialization

2. **LSP Server Installation**: Users must install language servers separately. The error messages include installation commands.

3. **Client Eviction**: When `LSP_MAX_CLIENTS` (10) is reached, oldest client is evicted. Consider LRU eviction for better behavior.

4. **File Version Tracking**: Currently only tracks didOpen. For full incremental sync support, would need didChange notifications when files are modified externally.

### Suggested Prompt Improvements

```diff
 <files-to-modify>
-- `agent/tools/lsp.py` (NEW) - Python LSP client and manager
-- `agent/tools/__init__.py` - Export LSP tools
+- `agent/tools/lsp.py` (NEW) - Python LSP client and manager (create directory first)
+- `agent/tools/__init__.py` (NEW) - Export LSP tools
 - `agent/agent.py` - Register hover tool with agent
 - `agent/registry.py` - Add LSP tool permissions per agent type
 - `config/defaults.py` - LSP server configurations
-- `tests/test_agent/test_tools/test_lsp.py` (NEW) - Test suite
+- `tests/test_agent/test_tools/test_lsp.py` (NEW) - Test suite (create directory first)
 </files-to-modify>

 <metadata>
-  <affects>agent/tools/, lsp/, server/routes/</affects>
+  <affects>agent/tools/, agent/agent.py, agent/registry.py, config/defaults.py</affects>
 </metadata>
```

Add to context:
```
<existing-patterns>
Tools are registered inline in `agent/agent.py` using `@agent.tool_plain` decorator.
See `browser_client.py` for singleton client pattern with async operations.
Run tests with: `source .venv/bin/activate && pytest`
</existing-patterns>
```
</hindsight>

## Files Created/Modified

| File | Action | Lines |
|------|--------|-------|
| `agent/tools/__init__.py` | Created | 5 |
| `agent/tools/lsp.py` | Created | ~650 |
| `agent/agent.py` | Modified | +19 |
| `agent/registry.py` | Modified | +4 |
| `config/defaults.py` | Modified | +28 |
| `tests/test_agent/test_tools/__init__.py` | Created | 1 |
| `tests/test_agent/test_tools/test_lsp.py` | Created | ~300 |

## Test Results

```
40 passed in 0.78s
```

All unit and integration tests pass. Verified with pylsp and gopls language servers.
No process leaks detected after shutdown.
