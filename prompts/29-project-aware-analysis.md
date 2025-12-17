# Project-Aware LSP Analysis

<metadata>
  <priority>high</priority>
  <category>code-intelligence</category>
  <estimated-complexity>high</estimated-complexity>
  <affects>agent/tools/, lsp/, tui/internal/components/</affects>
</metadata>

## Objective

Implement cross-file intelligence using LSP for understanding project structure, imports, and dependencies to enable project-aware code analysis and navigation.

<context>
The LSP manager and client in the agent-bak-bak codebase demonstrate sophisticated cross-file analysis capabilities. By leveraging Language Server Protocol, the agent can understand symbol relationships, track dependencies across files, resolve imports, and provide context-aware code intelligence. This enables features like:
- Finding all references to a symbol across the entire project
- Understanding import chains and dependency graphs
- Providing accurate hover information with type definitions
- Navigating to definitions across file boundaries
- Detecting breaking changes when modifying shared code
</context>

## Requirements

<functional-requirements>
1. Integrate LSP manager to spawn and manage language servers per project root
2. Implement workspace symbol search to find symbols across the entire project
3. Add "Go to Definition" functionality that works across file boundaries
4. Implement "Find References" to locate all usages of symbols project-wide
5. Provide hover information with type definitions and documentation
6. Track file dependencies and imports to understand code relationships
7. Display diagnostics from LSP servers in the agent's responses
8. Support multiple language servers simultaneously (TypeScript, Python, Go, etc.)
9. Cache and reuse LSP clients for the same project root
10. Handle LSP server lifecycle (startup, shutdown, error recovery)
</functional-requirements>

<technical-requirements>
1. Port or integrate LSP manager from `agent-bak-bak/lsp/manager.go`
2. Implement LSP client lifecycle management with connection pooling
3. Add LSP protocol message handlers (initialize, hover, symbols, references, definitions)
4. Create tool wrappers for agent to invoke LSP operations:
   - `workspace_symbol(query: str)` - Search symbols across project
   - `go_to_definition(file: str, line: int, char: int)` - Navigate to definition
   - `find_references(file: str, line: int, char: int)` - Find all references
   - `hover_info(file: str, line: int, char: int)` - Get hover information
5. Implement diagnostic aggregation from multiple LSP servers
6. Add support for textDocument/didOpen and didChange to keep LSP in sync
7. Handle LSP server configuration per language (Python via pyrightconfig, TypeScript via tsconfig, etc.)
8. Implement timeout and error handling for LSP requests
9. Track broken server+root combinations to avoid repeated failures
10. Add file version tracking for incremental updates
</technical-requirements>

## Implementation Guide

<files-to-modify>
- `agent/tools/lsp_tools.py` (new) - LSP tool implementations for agent
- `lsp/manager.py` (new/port) - Manager for LSP client lifecycle
- `lsp/client.py` (new/port) - LSP client with protocol implementation
- `lsp/connection.py` (new/port) - JSON-RPC connection handler
- `lsp/protocol.py` (new) - LSP protocol types and message definitions
- `lsp/servers.py` (new) - Configuration for supported language servers
- `agent/agent.py` - Register LSP tools with agent
- `config/settings.py` - Add LSP configuration options
</files-to-modify>

<lsp-capabilities>
The implementation should support these LSP capabilities:

**Workspace Operations:**
- workspace/symbol - Search for symbols across workspace
- workspace/configuration - Get workspace configuration

**Text Document Operations:**
- textDocument/didOpen - Notify server when file is opened
- textDocument/didChange - Notify server of file changes
- textDocument/hover - Get hover information at position
- textDocument/definition - Go to definition
- textDocument/references - Find all references
- textDocument/documentSymbol - Get symbols in document
- textDocument/publishDiagnostics - Receive diagnostics from server

**Server Lifecycle:**
- initialize - Initialize connection with capabilities
- initialized - Confirm initialization complete
- shutdown - Gracefully shutdown server
- exit - Exit server process
</lsp-capabilities>

<server-configuration>
Configure language servers for common languages:

**TypeScript/JavaScript:**
- Command: `typescript-language-server --stdio`
- Extensions: `.ts`, `.tsx`, `.js`, `.jsx`
- Root finder: Look for `package.json`, `tsconfig.json`, or `jsconfig.json`

**Python:**
- Command: `pyright-langserver --stdio`
- Extensions: `.py`, `.pyi`
- Root finder: Look for `pyproject.toml`, `setup.py`, or `.git`

**Go:**
- Command: `gopls serve`
- Extensions: `.go`
- Root finder: Look for `go.mod` or `.git`

**Rust:**
- Command: `rust-analyzer`
- Extensions: `.rs`
- Root finder: Look for `Cargo.toml`
</server-configuration>

<example-usage>
```python
# Agent using LSP to analyze code structure
@agent.tool_plain
async def analyze_symbol_usage(symbol_name: str, file_path: str) -> str:
    """Analyze how a symbol is used across the project.

    Args:
        symbol_name: Name of the symbol to analyze
        file_path: File containing the symbol definition

    Returns:
        Analysis of symbol usage including references and dependencies
    """
    # Get LSP client for this file
    clients = await get_lsp_clients(file_path)
    if not clients:
        return f"No LSP server available for {file_path}"

    client = clients[0]

    # Find the symbol definition
    symbols = await client.workspace_symbol(symbol_name)
    if not symbols:
        return f"Symbol '{symbol_name}' not found"

    # Get all references to the symbol
    references = []
    for symbol in symbols:
        refs = await client.find_references(
            symbol.location.uri,
            symbol.location.range.start.line,
            symbol.location.range.start.character
        )
        references.extend(refs)

    # Analyze the references
    analysis = f"Symbol '{symbol_name}' analysis:\n"
    analysis += f"- Definition: {symbols[0].location.uri}\n"
    analysis += f"- Total references: {len(references)}\n"
    analysis += f"- Used in {len(set(r.uri for r in references))} files\n"

    return analysis
```
</example-usage>

<diagnostic-integration>
Integrate LSP diagnostics into agent workflow:

```python
# After editing a file, check for LSP diagnostics
async def check_diagnostics_after_edit(file_path: str) -> list[Diagnostic]:
    """Check for diagnostics after editing a file."""
    # Open file in LSP server
    await touch_file(file_path, wait_for_diagnostics=True)

    # Get diagnostics from all servers
    all_diagnostics = await get_all_diagnostics()

    # Filter to this file
    file_diagnostics = all_diagnostics.get(file_path, [])

    # Format for agent response
    if file_diagnostics:
        formatted = format_diagnostics(file_diagnostics)
        return formatted

    return []
```
</diagnostic-integration>

## Architecture

<component-diagram>
```
┌─────────────────────────────────────────────────────────┐
│                     Agent Tools                          │
│  (workspace_symbol, go_to_definition, find_references)  │
└───────────────────────┬─────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────┐
│                   LSP Manager                            │
│  - Manages client lifecycle                             │
│  - Routes requests to appropriate clients               │
│  - Handles server spawning and shutdown                 │
│  - Tracks broken server+root combinations               │
└───────────────────────┬─────────────────────────────────┘
                        │
            ┌───────────┼───────────┐
            ▼           ▼           ▼
    ┌──────────┐ ┌──────────┐ ┌──────────┐
    │  Client  │ │  Client  │ │  Client  │
    │   (TS)   │ │   (Py)   │ │   (Go)   │
    └────┬─────┘ └────┬─────┘ └────┬─────┘
         │            │            │
         ▼            ▼            ▼
    ┌──────────┐ ┌──────────┐ ┌──────────┐
    │Connection│ │Connection│ │Connection│
    │ (stdio)  │ │ (stdio)  │ │ (stdio)  │
    └────┬─────┘ └────┬─────┘ └────┬─────┘
         │            │            │
         ▼            ▼            ▼
    ┌──────────┐ ┌──────────┐ ┌──────────┐
    │ typescript│ │ pyright  │ │  gopls   │
    │-lang-srv │ │-langserv │ │          │
    └──────────┘ └──────────┘ └──────────┘
```
</component-diagram>

<state-management>
Key state to maintain:

1. **Manager State:**
   - Map of server ID -> ServerConfig
   - List of active clients
   - Map of broken server+root combinations

2. **Client State:**
   - Server ID and root directory
   - Connection to language server process
   - Map of file path -> diagnostics
   - Map of file path -> version number
   - Diagnostic event channel

3. **Connection State:**
   - Stdin/stdout pipes to server
   - Map of request ID -> pending response future
   - Notification handlers by method name
   - Request handlers by method name
</state-management>

## Error Handling

<error-scenarios>
1. **Server Not Found:**
   - Detect when language server binary is not installed
   - Provide helpful error message with installation instructions
   - Mark server as broken to avoid repeated attempts

2. **Initialization Timeout:**
   - Implement 5-second timeout for initialize request
   - Fall back gracefully if server doesn't respond
   - Log warning and continue without LSP for that file

3. **Server Crash:**
   - Detect when server process exits unexpectedly
   - Clean up client resources
   - Mark server+root as broken temporarily
   - Retry after cooldown period

4. **Protocol Errors:**
   - Handle malformed JSON-RPC messages
   - Validate LSP response structures
   - Gracefully degrade if response format is unexpected

5. **Multiple Servers:**
   - Handle conflicts when multiple servers provide diagnostics
   - Merge diagnostics from different sources
   - Deduplicate similar diagnostics
</error-scenarios>

## Performance Considerations

<optimizations>
1. **Client Pooling:**
   - Reuse LSP clients for the same project root
   - Only spawn one client per server+root combination
   - Cache client instances in manager

2. **Lazy Initialization:**
   - Don't spawn LSP servers until first file is opened
   - Only initialize servers for languages actually in use
   - Shutdown idle servers after timeout

3. **Incremental Updates:**
   - Use didChange with incremental updates when possible
   - Track file versions to avoid sending duplicate updates
   - Only send changed portions of files

4. **Diagnostic Batching:**
   - Batch diagnostic updates to avoid flooding
   - Use channel with buffer for diagnostic events
   - Debounce rapid diagnostic updates

5. **Root Finding:**
   - Cache root directory lookups
   - Walk up directory tree efficiently
   - Stop at first match for common patterns
</optimizations>

## Testing Strategy

<test-cases>
1. **Unit Tests:**
   - Test LSP protocol message serialization/deserialization
   - Test client state management (file versions, diagnostics)
   - Test manager routing logic for file extensions
   - Test connection request/response handling

2. **Integration Tests:**
   - Spawn real language servers and test communication
   - Test initialize/initialized handshake
   - Test didOpen/didChange notifications
   - Test hover, definition, references requests
   - Test diagnostic publishing

3. **Error Tests:**
   - Test behavior when server binary not found
   - Test timeout handling for slow servers
   - Test recovery from server crashes
   - Test handling of malformed responses

4. **Performance Tests:**
   - Test with large codebases (1000+ files)
   - Measure client pooling effectiveness
   - Test memory usage with multiple servers
   - Test concurrent request handling
</test-cases>

## Acceptance Criteria

<criteria>
- [ ] LSP manager spawns and manages language servers correctly
- [ ] Client pooling works - same server+root reuses client
- [ ] workspace/symbol searches across entire project
- [ ] textDocument/definition navigates to correct location
- [ ] textDocument/references finds all usages
- [ ] textDocument/hover provides accurate information
- [ ] Diagnostics are collected and formatted correctly
- [ ] Multiple language servers can run simultaneously
- [ ] Server crashes are handled gracefully
- [ ] Broken servers are marked and not repeatedly retried
- [ ] File version tracking works for incremental updates
- [ ] Performance is acceptable with large projects (< 500ms for most operations)
- [ ] Agent can use LSP tools to analyze code structure
- [ ] TUI can display LSP diagnostics inline (optional enhancement)
</criteria>

## Execution Strategy

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
</execution-strategy>

<implementation-phases>
**Phase 1: Core Protocol (2-3 days)**
- Implement LSP protocol types and message structures
- Create JSON-RPC connection handler
- Implement basic client with initialize/shutdown

**Phase 2: Manager & Lifecycle (2-3 days)**
- Implement LSP manager with client pooling
- Add server configuration for common languages
- Implement root finding logic
- Add error handling and recovery

**Phase 3: Text Operations (2-3 days)**
- Implement didOpen/didChange notifications
- Add hover, definition, references requests
- Implement diagnostic handling
- Add file version tracking

**Phase 4: Agent Integration (1-2 days)**
- Create agent tool wrappers
- Register tools with agent
- Add configuration options
- Test agent workflows

**Phase 5: Testing & Polish (2-3 days)**
- Write unit and integration tests
- Test with real language servers
- Performance optimization
- Documentation
</implementation-phases>

## Related Resources

<references>
- LSP Specification: https://microsoft.github.io/language-server-protocol/
- Reference Implementation: `/Users/williamcory/agent-bak-bak/lsp/`
- TypeScript Language Server: https://github.com/typescript-language-server/typescript-language-server
- Pyright: https://github.com/microsoft/pyright
- gopls: https://github.com/golang/tools/tree/master/gopls
- JSON-RPC 2.0 Spec: https://www.jsonrpc.org/specification
</references>

## Completion Instructions

<completion>
When this task is fully implemented and tested:
1. Verify all acceptance criteria are met
2. Run `pytest tests/test_lsp/` to ensure all LSP tests pass
3. Test with at least 3 different language servers (TS, Python, Go)
4. Verify agent can successfully use LSP tools for code analysis
5. Measure performance with a real project (500+ files)
6. Document LSP tool usage in agent documentation
7. Rename this file from `29-project-aware-analysis.md` to `29-project-aware-analysis.complete.md`
</completion>
