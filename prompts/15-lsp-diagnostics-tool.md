# LSP Diagnostics Tool

<metadata>
  <priority>high</priority>
  <category>tools</category>
  <estimated-complexity>high</estimated-complexity>
  <affects>agent/tools/, lsp/, server/</affects>
</metadata>

## Objective

Implement an LSP (Language Server Protocol) diagnostics tool that provides real-time errors, warnings, and hints from language servers (TypeScript, Go, etc.) to help the agent understand code issues before attempting fixes.

<context>
Language servers provide rich diagnostic information about code issues. By integrating LSP diagnostics into the agent's toolset, the agent can:
- Understand what errors exist before attempting to fix them
- Get precise line/column information for issues
- Differentiate between errors, warnings, info, and hints
- Validate that fixes actually resolve the reported issues

This is critical for improving the agent's code editing capabilities and reducing failed fix attempts.
</context>

## Requirements

<functional-requirements>
1. LSP Diagnostics Tool that can:
   - Start LSP servers for supported languages (TypeScript, Go)
   - Open files in the LSP server and receive diagnostics
   - Return formatted diagnostic information to the agent
   - Handle multiple file types with appropriate language servers
   - Provide both summary and detailed diagnostic views

2. Diagnostic Information:
   - Severity level (Error, Warning, Info, Hint)
   - File path and line/column position
   - Diagnostic message
   - Source (LSP server name)
   - Code (optional error code)

3. Tool Interface:
   - `get_diagnostics(file_path: str) -> DiagnosticResult` - Get diagnostics for a specific file
   - `get_all_diagnostics(root_path: str) -> Dict[str, DiagnosticResult]` - Get diagnostics for all files in a project
   - Results formatted as human-readable text with severity indicators

4. Error Handling:
   - Graceful fallback when LSP server not available
   - Timeout handling for slow language servers
   - Clear error messages when tools are missing

5. Server Management:
   - Auto-detect project roots (package.json, go.mod, etc.)
   - Reuse existing LSP clients when possible
   - Clean shutdown of LSP servers
   - Handle multiple files from the same project efficiently
</functional-requirements>

<technical-requirements>
1. LSP Client Implementation (reuse from reference):
   - Connection management with JSON-RPC over stdio
   - Request/response handling with ID tracking
   - Notification handling (textDocument/publishDiagnostics)
   - File version tracking for didOpen/didChange
   - Thread-safe diagnostic storage

2. Server Configuration:
   - TypeScript: typescript-language-server with tsserver.js detection
   - Go: gopls with auto-install capability
   - Root finding logic using NearestRoot pattern matching
   - Configurable extensions mapping

3. Python Integration:
   - Create `agent/tools/lsp_diagnostics.py` module
   - Register tool in agent's tool registry
   - Use asyncio for non-blocking LSP operations
   - JSON serialization of diagnostic results

4. Data Types:
   - DiagnosticSeverity enum (1=Error, 2=Warning, 3=Info, 4=Hint)
   - Position struct (0-based line/character)
   - Range struct (start/end positions)
   - Diagnostic struct with range, severity, message, source

5. Output Format:
   - Pretty-printed diagnostics: "ERROR [10:5] Expected ';'"
   - Grouped by file path
   - Color-coded severity indicators (if terminal supports)
   - Summary statistics (X errors, Y warnings)
</technical-requirements>

<reference-implementation>
The reference implementation provides a complete Go-based LSP client. Key components:

## LSP Client (client.go)

```go
type Client struct {
    ServerID   string
    Root       string
    process    *exec.Cmd
    connection *Connection

    // Diagnostics storage
    diagnostics     map[string][]Diagnostic
    diagnosticsMux  sync.RWMutex
    diagnosticsChan chan DiagnosticsEvent

    // File version tracking
    fileVersions    map[string]int
    fileVersionsMux sync.Mutex
}

// Key methods:
// - NewClient(serverID, root, cmd, initOptions) - Initialize LSP client
// - OpenFile(filePath) - Send textDocument/didOpen
// - WaitForDiagnostics(filePath, timeout) - Wait for diagnostics update
// - GetDiagnostics() - Retrieve all stored diagnostics
// - Shutdown() - Gracefully close connection
```

Handler setup for publishDiagnostics notification:

```go
func (c *Client) setupHandlers() {
    c.connection.OnNotification("textDocument/publishDiagnostics", func(params interface{}) {
        var diagParams PublishDiagnosticsParams
        // Parse params...

        // Extract file path from URI
        filePath := diagParams.URI
        if len(filePath) > 7 && filePath[:7] == "file://" {
            filePath = filePath[7:]
        }

        // Store diagnostics
        c.diagnosticsMux.Lock()
        c.diagnostics[filePath] = diagParams.Diagnostics
        c.diagnosticsMux.Unlock()

        // Notify listeners
        c.diagnosticsChan <- DiagnosticsEvent{Path: filePath, ServerID: c.ServerID}
    })
}
```

## LSP Types (types.go)

```go
type DiagnosticSeverity int

const (
    DiagnosticSeverityError   DiagnosticSeverity = 1
    DiagnosticSeverityWarning DiagnosticSeverity = 2
    DiagnosticSeverityInfo    DiagnosticSeverity = 3
    DiagnosticSeverityHint    DiagnosticSeverity = 4
)

type Position struct {
    Line      int `json:"line"`      // 0-based
    Character int `json:"character"` // 0-based
}

type Range struct {
    Start Position `json:"start"`
    End   Position `json:"end"`
}

type Diagnostic struct {
    Range    Range              `json:"range"`
    Severity DiagnosticSeverity `json:"severity"`
    Code     interface{}        `json:"code,omitempty"`
    Source   string             `json:"source,omitempty"`
    Message  string             `json:"message"`
    Tags     []int              `json:"tags,omitempty"`
    Data     interface{}        `json:"data,omitempty"`
}

func PrettyDiagnostic(d Diagnostic) string {
    severityMap := map[DiagnosticSeverity]string{
        DiagnosticSeverityError:   "ERROR",
        DiagnosticSeverityWarning: "WARN",
        DiagnosticSeverityInfo:    "INFO",
        DiagnosticSeverityHint:    "HINT",
    }

    severity := severityMap[d.Severity]
    line := d.Range.Start.Line + 1  // Convert to 1-based
    col := d.Range.Start.Character + 1

    return fmt.Sprintf("%s [%d:%d] %s", severity, line, col, d.Message)
}
```

## Server Configuration (server.go)

```go
type ServerConfig struct {
    ID         string
    Extensions []string
    RootFinder func(filePath string) (string, error)
    Spawner    func(root string) (*exec.Cmd, interface{}, error)
}

func NearestRoot(includePatterns []string, excludePatterns []string) func(string) (string, error) {
    return func(filePath string) (string, error) {
        dir := filepath.Dir(filePath)
        cwd, _ := os.Getwd()

        // Check exclude patterns first
        // Then search up for include patterns
        // Return found root or default to cwd
    }
}

// Example TypeScript configuration:
servers["typescript"] = &ServerConfig{
    ID:         "typescript",
    Extensions: []string{".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs"},
    RootFinder: NearestRoot(
        []string{"package-lock.json", "package.json"},
        []string{"deno.json", "deno.jsonc"},
    ),
    Spawner: func(root string) (*exec.Cmd, interface{}, error) {
        tsserverPath := filepath.Join(root, "node_modules", "typescript", "lib", "tsserver.js")
        cmd := exec.Command("npx", "typescript-language-server", "--stdio")
        cmd.Dir = root

        initOptions := map[string]interface{}{
            "tsserver": map[string]interface{}{
                "path": tsserverPath,
            },
        }

        return cmd, initOptions, nil
    },
}
```

## Initialization Flow

1. Detect file extension -> Select appropriate LSP server
2. Find project root using RootFinder
3. Spawn LSP server process with Spawner
4. Create Connection over stdin/stdout
5. Send initialize request with client capabilities
6. Send initialized notification
7. Register textDocument/publishDiagnostics handler
8. Send textDocument/didOpen for target file
9. Wait for diagnostics via diagnosticsChan
10. Return formatted diagnostics to caller
</reference-implementation>

<execution-strategy>
**IMPORTANT: Subagent Utilization Required**

When implementing this feature, you MUST:
1. Use the Task tool with subagent_type="Explore" to search the codebase before making changes
2. Use parallel subagents to verify your implementation works correctly
3. After each significant change, spawn a verification subagent to test the functionality
4. Do NOT trust that code works - always verify with actual execution or tests

Verification checklist:
- [ ] Spawn subagent to find all files that need modification
- [ ] Spawn subagent to verify the implementation compiles
- [ ] Spawn subagent to run related tests
- [ ] Spawn subagent to check for regressions

Implementation phases:

**Phase 1: LSP Client Infrastructure (Go)**
1. Create `lsp/` package in project root
2. Port Connection implementation (JSON-RPC over stdio)
   - `lsp/connection.go` - Request/response handling
   - Message ID tracking and routing
   - Notification vs request handling
3. Port Client implementation
   - `lsp/client.go` - Client with diagnostic storage
   - Thread-safe diagnostic map with mutex
   - File version tracking for didOpen/didChange
   - Handler registration for publishDiagnostics
4. Port type definitions
   - `lsp/types.go` - All LSP protocol types
   - Diagnostic, Position, Range structs
   - InitializeParams, capabilities, etc.
5. Port server configurations
   - `lsp/server.go` - ServerConfig registry
   - TypeScript and Go server configs
   - Root finder logic

**Phase 2: Python Tool Integration**
1. Create `agent/tools/lsp_diagnostics.py`
2. Implement subprocess management for Go LSP client
   - Spawn `lsp-diagnostics` CLI tool
   - Parse JSON output
   - Handle timeouts and errors
3. Register tool with agent framework
   - Use `@agent.tool_plain` decorator
   - Define input schema (file_path, timeout)
   - Format output for agent consumption
4. Add tool to agent registry
   - Update `agent/registry.py` if needed
   - Configure tool permissions

**Phase 3: CLI Tool (Go)**
1. Create `cmd/lsp-diagnostics/main.go`
2. Implement command interface:
   - `lsp-diagnostics check <file>` - Single file diagnostics
   - `lsp-diagnostics check-all <root>` - Project-wide diagnostics
   - JSON output format
3. Build integration:
   - Add to `build.zig` or Makefile
   - Ensure binary is available in PATH

**Phase 4: Testing & Validation**
1. Create test fixtures (files with known errors)
2. Unit tests for LSP client:
   - Connection message handling
   - Diagnostic parsing
   - Root finding logic
3. Integration tests:
   - Full TypeScript diagnostic flow
   - Full Go diagnostic flow
   - Timeout handling
4. Agent tool tests:
   - Python tool invocation
   - Error handling
   - Output formatting
</execution-strategy>

## Example Usage

```python
# Agent tool usage
@agent.tool_plain
async def get_diagnostics(file_path: str) -> str:
    """Get LSP diagnostics (errors, warnings, hints) for a file.

    Args:
        file_path: Absolute path to the file to analyze

    Returns:
        Formatted diagnostic information with severity, location, and message
    """
    # Run LSP diagnostics CLI tool
    result = await run_lsp_diagnostics(file_path, timeout=5.0)

    if result.error:
        return f"Failed to get diagnostics: {result.error}"

    if not result.diagnostics:
        return f"No diagnostics found for {file_path}"

    # Format output
    output = [f"Diagnostics for {file_path}:"]
    error_count = warning_count = 0

    for diag in result.diagnostics:
        if diag.severity == 1:
            error_count += 1
        elif diag.severity == 2:
            warning_count += 1

        output.append(format_diagnostic(diag))

    output.insert(1, f"\nSummary: {error_count} errors, {warning_count} warnings\n")

    return "\n".join(output)

def format_diagnostic(diag: Diagnostic) -> str:
    """Format a single diagnostic for display."""
    severity_map = {1: "ERROR", 2: "WARN", 3: "INFO", 4: "HINT"}
    severity = severity_map.get(diag.severity, "ERROR")

    # Convert 0-based to 1-based for display
    line = diag.range.start.line + 1
    col = diag.range.start.character + 1

    source = f"[{diag.source}] " if diag.source else ""

    return f"  {severity} {source}[{line}:{col}] {diag.message}"
```

Example output:

```
Diagnostics for /Users/user/project/src/main.ts:

Summary: 2 errors, 1 warning

  ERROR [typescript] [15:10] Expected ';'
  ERROR [typescript] [23:5] Property 'foo' does not exist on type 'Bar'
  WARN [typescript] [45:1] 'unusedVar' is declared but never used
```

## Acceptance Criteria

<criteria>
- [ ] LSP client can connect to typescript-language-server
- [ ] LSP client can connect to gopls
- [ ] Client correctly receives and stores diagnostics from publishDiagnostics notifications
- [ ] Root finding logic correctly identifies TypeScript and Go project roots
- [ ] Python tool successfully invokes LSP CLI and parses output
- [ ] Diagnostics include severity, line/column, message, and source
- [ ] Tool handles missing language servers gracefully
- [ ] Tool respects timeout configuration
- [ ] Agent can use tool to check files before editing
- [ ] Verification: Run tool on a file with known TypeScript errors and confirm correct output
- [ ] Verification: Run tool on a file with known Go errors and confirm correct output
- [ ] Performance: Diagnostics returned within 5 seconds for typical files
- [ ] Multiple files from same project reuse LSP client connection
</criteria>

## Files to Create/Modify

<files-to-create>
- `lsp/connection.go` - JSON-RPC connection over stdio
- `lsp/client.go` - LSP client with diagnostic handling
- `lsp/types.go` - LSP protocol type definitions
- `lsp/server.go` - Server configuration registry
- `lsp/util.go` - Helper functions (language ID detection, etc.)
- `cmd/lsp-diagnostics/main.go` - CLI tool for diagnostics
- `agent/tools/lsp_diagnostics.py` - Python tool wrapper
- `tests/test_lsp/` - Test suite for LSP functionality
</files-to-create>

<files-to-modify>
- `agent/agent.py` - Register LSP diagnostics tool
- `build.zig` - Add LSP CLI build target
- `CLAUDE.md` - Document LSP tool usage
</files-to-modify>

## Edge Cases & Considerations

1. **Multiple Language Servers**: Handle files that might match multiple servers (e.g., .jsx could be TypeScript or JavaScript)

2. **Project Detection**: Some files may not be in a project (standalone scripts) - fall back gracefully

3. **Server Lifecycle**: Reuse LSP clients when checking multiple files from the same project to avoid startup overhead

4. **Diagnostic Timing**: TypeScript may send empty diagnostics on first open, then update - implement wait logic with timeout

5. **Environment Variables**: Support `OPENCODE_DISABLE_LSP_DOWNLOAD` to prevent auto-installing language servers

6. **Path Normalization**: Handle file:// URI conversion consistently across platforms (Windows vs Unix paths)

7. **Concurrent Access**: Ensure thread-safe access to diagnostic storage when multiple goroutines query diagnostics

8. **Workspace Folders**: Some servers need workspace folders configured - include in initialize params

9. **Server Crashes**: Detect and report if LSP server crashes during initialization or operation

10. **Large Files**: Set reasonable timeouts to avoid hanging on very large files

## Testing Strategy

1. **Unit Tests (Go)**:
   - Connection message parsing
   - Diagnostic deserialization
   - Root finding with various project structures
   - Pretty-print formatting

2. **Integration Tests (Go)**:
   - Full TypeScript flow with real typescript-language-server
   - Full Go flow with real gopls
   - Timeout handling

3. **Tool Tests (Python)**:
   - Tool invocation and output parsing
   - Error handling
   - Agent integration

4. **E2E Tests**:
   - Agent uses tool to detect errors before fixing
   - Agent validates fixes resolved reported diagnostics

## Completion Instructions

<completion>
When this task is fully implemented and tested:
1. Verify all acceptance criteria are met
2. Run `zig build` to ensure all components compile
3. Test with real TypeScript and Go projects
4. Verify agent can successfully use the tool in conversation
5. Update documentation in CLAUDE.md
6. Rename this file from `15-lsp-diagnostics-tool.md` to `15-lsp-diagnostics-tool.complete.md`
</completion>
