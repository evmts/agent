# Multi-Language LSP Manager

<metadata>
  <priority>high</priority>
  <category>developer-tools</category>
  <estimated-complexity>high</estimated-complexity>
  <affects>agent/, tools/, core/</affects>
</metadata>

## Objective

Implement a comprehensive multi-language LSP (Language Server Protocol) manager that provides real-time diagnostics, code intelligence, and language server lifecycle management for Go, Python, Rust, TypeScript, JavaScript, and other languages.

<context>
Language Server Protocol (LSP) is a standardized protocol for providing IDE features like diagnostics, hover information, code completion, and symbol search. A robust LSP manager:

1. **Automatically detects** the appropriate language server based on file extension
2. **Manages server lifecycle** - spawns, initializes, and gracefully shuts down servers
3. **Maintains state** - tracks which files are open, manages diagnostics, handles version tracking
4. **Supports multiple languages** - Go (gopls), TypeScript/JavaScript (typescript-language-server), Python (pyright/pylsp), Rust (rust-analyzer)
5. **Handles workspace detection** - finds project roots using markers like go.mod, package.json, Cargo.toml, etc.
6. **Provides diagnostic aggregation** - collects and formats errors/warnings from all active servers
7. **Implements JSON-RPC 2.0** - LSP communication protocol over stdio

This is essential for providing real-time code analysis, type checking, and intelligent code assistance in the agent platform.
</context>

## Requirements

<functional-requirements>
1. **Language Server Management**
   - Auto-detect and spawn appropriate language servers based on file extensions
   - Support for Go (gopls), TypeScript/JavaScript (typescript-language-server), Python (pyright), Rust (rust-analyzer)
   - Automatic installation of missing language servers (with opt-out via OPENCODE_DISABLE_LSP_DOWNLOAD)
   - Graceful server lifecycle management (initialize, shutdown, cleanup)

2. **Workspace Detection**
   - Find project roots using language-specific markers:
     - Go: go.mod, go.sum, go.work
     - TypeScript/JavaScript: package.json, tsconfig.json, package-lock.json, yarn.lock
     - Python: pyproject.toml, setup.py, requirements.txt
     - Rust: Cargo.toml
   - Handle monorepos and multi-workspace setups
   - Exclude patterns (e.g., don't use Deno LSP for TypeScript in npm projects)

3. **Diagnostics System**
   - Collect diagnostics (errors, warnings, info, hints) from all active servers
   - Real-time diagnostic updates via notification handlers
   - Aggregate diagnostics across multiple servers for the same file
   - Format diagnostics for human-readable display
   - Support waiting for diagnostics with configurable timeout

4. **File Operations**
   - Open files in appropriate LSP servers (textDocument/didOpen)
   - Track file versions for incremental updates
   - Support file change notifications (textDocument/didChange)
   - Handle concurrent access to multiple files

5. **Code Intelligence Features**
   - Hover information (textDocument/hover)
   - Workspace symbol search (workspace/symbol)
   - Document symbol navigation (textDocument/documentSymbol)
   - Extensible for future features (completion, go-to-definition, etc.)

6. **Error Handling & Resilience**
   - Track "broken" server+root combinations to avoid repeated failures
   - Graceful degradation when servers are unavailable
   - Proper cleanup of zombie processes
   - Thread-safe operations with mutex protection
</functional-requirements>

<technical-requirements>
1. **Architecture**
   - Singleton Manager pattern with thread-safe access
   - Client-per-server-per-workspace model (avoid redundant server instances)
   - JSON-RPC 2.0 connection layer with request/response matching
   - Event-driven notification system

2. **Key Components**
   - `Manager`: Global singleton managing all LSP clients
   - `Client`: Individual LSP server connection handler
   - `Connection`: JSON-RPC 2.0 communication layer
   - `ServerConfig`: Language server configuration and spawning logic
   - Type definitions for LSP protocol structures

3. **Concurrency Safety**
   - Use sync.RWMutex for shared state access
   - Atomic operations for ID generation
   - Channel-based communication for responses and notifications
   - Proper goroutine lifecycle management

4. **Integration Points**
   - Create Python agent tool for LSP diagnostics access
   - Add TouchFile helper for pre-checking files before operations
   - Expose GetAllDiagnostics for IDE-like error reporting
   - Support streaming diagnostic updates

5. **Configuration**
   - Environment variable: OPENCODE_DISABLE_LSP_DOWNLOAD (disable auto-install)
   - Per-language server configurations in GetAllServers()
   - Configurable timeouts for initialization and requests
   - Language ID mapping from file extensions
</technical-requirements>

## Reference Implementation

<reference-implementation>
The reference implementation from `/Users/williamcory/agent-bak-bak/lsp/` provides a complete, production-ready LSP manager:

### manager.go - Core Manager Implementation

```go
package lsp

import (
	"fmt"
	"log"
	"path/filepath"
	"sync"
	"time"
)

// Manager manages all LSP clients
type Manager struct {
	servers map[string]*ServerConfig
	clients []*Client
	broken  map[string]bool // tracks broken server+root combinations
	mu      sync.RWMutex
}

var (
	globalManager *Manager
	managerOnce   sync.Once
)

// GetManager returns the global LSP manager instance
func GetManager() *Manager {
	managerOnce.Do(func() {
		globalManager = &Manager{
			servers: GetAllServers(),
			clients: make([]*Client, 0),
			broken:  make(map[string]bool),
		}
	})
	return globalManager
}

// Init initializes the LSP manager
func Init() error {
	manager := GetManager()
	log.Printf("LSP manager initialized with %d servers", len(manager.servers))
	return nil
}

// Shutdown shuts down all LSP clients
func Shutdown() error {
	manager := GetManager()
	manager.mu.Lock()
	defer manager.mu.Unlock()

	for _, client := range manager.clients {
		if err := client.Shutdown(); err != nil {
			log.Printf("Error shutting down LSP client %s: %v", client.ServerID, err)
		}
	}
	manager.clients = nil
	return nil
}

// GetClients returns LSP clients that should handle the given file
func (m *Manager) GetClients(filePath string) ([]*Client, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	ext := filepath.Ext(filePath)
	if ext == "" {
		ext = filepath.Base(filePath) // Handle files like "Makefile"
	}

	var result []*Client

	for _, server := range m.servers {
		// Check if this server handles this extension
		handles := false
		for _, serverExt := range server.Extensions {
			if serverExt == ext {
				handles = true
				break
			}
		}
		if !handles {
			continue
		}

		// Find root directory for this file
		root, err := server.RootFinder(filePath)
		if err != nil || root == "" {
			continue
		}

		// Check if this server+root combination is broken
		brokenKey := root + server.ID
		if m.broken[brokenKey] {
			continue
		}

		// Check if we already have a client for this server+root
		var existingClient *Client
		for _, client := range m.clients {
			if client.ServerID == server.ID && client.Root == root {
				existingClient = client
				break
			}
		}

		if existingClient != nil {
			result = append(result, existingClient)
			continue
		}

		// Spawn a new client
		cmd, initOptions, err := server.Spawner(root)
		if err != nil {
			log.Printf("Failed to spawn LSP server %s: %v", server.ID, err)
			m.broken[brokenKey] = true
			continue
		}

		client, err := NewClient(server.ID, root, cmd, initOptions)
		if err != nil {
			log.Printf("Failed to create LSP client %s: %v", server.ID, err)
			m.broken[brokenKey] = true
			continue
		}

		log.Printf("Started LSP server: %s at %s", server.ID, root)
		m.clients = append(m.clients, client)
		result = append(result, client)
	}

	return result, nil
}

// TouchFile opens a file in all relevant LSP servers and optionally waits for diagnostics
func TouchFile(filePath string, waitForDiagnostics bool) error {
	manager := GetManager()
	clients, err := manager.GetClients(filePath)
	if err != nil {
		return err
	}

	for _, client := range clients {
		// Open the file
		if err := client.OpenFile(filePath); err != nil {
			log.Printf("Failed to open file %s in LSP %s: %v", filePath, client.ServerID, err)
			continue
		}

		// Wait for diagnostics if requested
		if waitForDiagnostics {
			if err := client.WaitForDiagnostics(filePath, 3*time.Second); err != nil {
				log.Printf("Timeout waiting for diagnostics for %s from %s", filePath, client.ServerID)
			}
		}
	}

	return nil
}

// GetAllDiagnostics returns all diagnostics from all LSP clients
func GetAllDiagnostics() map[string][]Diagnostic {
	manager := GetManager()
	manager.mu.RLock()
	defer manager.mu.RUnlock()

	result := make(map[string][]Diagnostic)

	for _, client := range manager.clients {
		clientDiags := client.GetDiagnostics()
		for path, diags := range clientDiags {
			existing := result[path]
			result[path] = append(existing, diags...)
		}
	}

	return result
}

// Hover sends a hover request to relevant LSP servers
func Hover(filePath string, line, character int) (interface{}, error) {
	manager := GetManager()
	clients, err := manager.GetClients(filePath)
	if err != nil {
		return nil, err
	}

	if len(clients) == 0 {
		return nil, fmt.Errorf("no LSP server available for file: %s", filePath)
	}

	// Use the first client
	return clients[0].Hover(filePath, line, character)
}

// FormatDiagnostics formats diagnostics for display
func FormatDiagnostics(diagnostics []Diagnostic) string {
	if len(diagnostics) == 0 {
		return "No errors found"
	}

	result := ""
	for i, diag := range diagnostics {
		if i > 0 {
			result += "\n"
		}
		result += PrettyDiagnostic(diag)
	}
	return result
}
```

### server.go - Server Configuration

```go
package lsp

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// ServerConfig defines an LSP server configuration
type ServerConfig struct {
	ID         string
	Extensions []string
	RootFinder func(filePath string) (string, error)
	Spawner    func(root string) (*exec.Cmd, interface{}, error) // Returns cmd, initOptions, error
}

// NearestRoot creates a root finder that searches up the directory tree
func NearestRoot(includePatterns []string, excludePatterns []string) func(string) (string, error) {
	return func(filePath string) (string, error) {
		dir := filepath.Dir(filePath)
		cwd, err := os.Getwd()
		if err != nil {
			return "", err
		}

		// Check for exclude patterns first
		if len(excludePatterns) > 0 {
			current := dir
			for {
				for _, pattern := range excludePatterns {
					checkPath := filepath.Join(current, pattern)
					if _, err := os.Stat(checkPath); err == nil {
						// Found exclude pattern, return empty
						return "", nil
					}
				}

				parent := filepath.Dir(current)
				if parent == current || !strings.HasPrefix(current, cwd) {
					break
				}
				current = parent
			}
		}

		// Search for include patterns
		current := dir
		for {
			for _, pattern := range includePatterns {
				checkPath := filepath.Join(current, pattern)
				if _, err := os.Stat(checkPath); err == nil {
					return current, nil
				}
			}

			parent := filepath.Dir(current)
			if parent == current || !strings.HasPrefix(current, cwd) {
				break
			}
			current = parent
		}

		// Default to working directory
		return cwd, nil
	}
}

// GetAllServers returns all configured LSP servers
func GetAllServers() map[string]*ServerConfig {
	servers := make(map[string]*ServerConfig)

	// TypeScript Language Server
	servers["typescript"] = &ServerConfig{
		ID:         "typescript",
		Extensions: []string{".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs", ".mts", ".cts"},
		RootFinder: NearestRoot(
			[]string{"package-lock.json", "bun.lockb", "bun.lock", "pnpm-lock.yaml", "yarn.lock", "package.json"},
			[]string{"deno.json", "deno.jsonc"},
		),
		Spawner: func(root string) (*exec.Cmd, interface{}, error) {
			// Try to find typescript in node_modules
			tsserverPath := filepath.Join(root, "node_modules", "typescript", "lib", "tsserver.js")
			if _, err := os.Stat(tsserverPath); err != nil {
				// Typescript not found
				return nil, nil, fmt.Errorf("typescript not found in project")
			}

			// Find npx or use node directly
			npx, err := exec.LookPath("npx")
			var cmd *exec.Cmd
			if err == nil {
				cmd = exec.Command(npx, "typescript-language-server", "--stdio")
			} else {
				// Fall back to checking if typescript-language-server is installed globally
				tslsPath, err := exec.LookPath("typescript-language-server")
				if err != nil {
					return nil, nil, fmt.Errorf("typescript-language-server not found")
				}
				cmd = exec.Command(tslsPath, "--stdio")
			}
			cmd.Dir = root

			initOptions := map[string]interface{}{
				"tsserver": map[string]interface{}{
					"path": tsserverPath,
				},
			}

			return cmd, initOptions, nil
		},
	}

	// Gopls (Go Language Server)
	servers["gopls"] = &ServerConfig{
		ID:         "gopls",
		Extensions: []string{".go"},
		RootFinder: func(filePath string) (string, error) {
			// First look for go.work
			workRoot := NearestRoot([]string{"go.work"}, nil)
			if root, err := workRoot(filePath); err == nil && root != "" {
				cwd, _ := os.Getwd()
				if root != cwd {
					return root, nil
				}
			}

			// Then look for go.mod or go.sum
			return NearestRoot([]string{"go.mod", "go.sum"}, nil)(filePath)
		},
		Spawner: func(root string) (*exec.Cmd, interface{}, error) {
			// Check if gopls is installed
			goplsPath, err := exec.LookPath("gopls")
			if err != nil {
				// Try to install gopls if go is available
				goPath, goErr := exec.LookPath("go")
				if goErr != nil {
					return nil, nil, fmt.Errorf("gopls not found and go not available for installation")
				}

				// Check if auto-install is disabled
				if os.Getenv("OPENCODE_DISABLE_LSP_DOWNLOAD") == "true" {
					return nil, nil, fmt.Errorf("gopls not found and auto-install is disabled")
				}

				// Install gopls
				installCmd := exec.Command(goPath, "install", "golang.org/x/tools/gopls@latest")
				if err := installCmd.Run(); err != nil {
					return nil, nil, fmt.Errorf("failed to install gopls: %w", err)
				}

				// Try to find gopls again
				goplsPath, err = exec.LookPath("gopls")
				if err != nil {
					return nil, nil, fmt.Errorf("gopls not found after installation")
				}
			}

			cmd := exec.Command(goplsPath)
			cmd.Dir = root

			return cmd, nil, nil
		},
	}

	// Add more servers here as needed (ESLint, Pyright, etc.)
	// For now, we'll focus on TypeScript and Go for the initial implementation

	return servers
}

// IsLSPDownloadDisabled checks if LSP auto-download is disabled
func IsLSPDownloadDisabled() bool {
	return os.Getenv("OPENCODE_DISABLE_LSP_DOWNLOAD") == "true"
}
```

### client.go - LSP Client Implementation

```go
package lsp

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
	"time"
)

// Client represents an LSP client connected to a server
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

// DiagnosticsEvent represents a diagnostics update event
type DiagnosticsEvent struct {
	Path     string
	ServerID string
}

// NewClient creates a new LSP client
func NewClient(serverID string, root string, cmd *exec.Cmd, initOptions interface{}) (*Client, error) {
	// Get stdout and stdin pipes
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return nil, fmt.Errorf("failed to get stdout pipe: %w", err)
	}

	stdin, err := cmd.StdinPipe()
	if err != nil {
		return nil, fmt.Errorf("failed to get stdin pipe: %w", err)
	}

	// Start the process
	if err := cmd.Start(); err != nil {
		return nil, fmt.Errorf("failed to start LSP server: %w", err)
	}

	// Create connection
	conn := NewConnection(stdout, stdin)
	conn.Listen()

	client := &Client{
		ServerID:        serverID,
		Root:            root,
		process:         cmd,
		connection:      conn,
		diagnostics:     make(map[string][]Diagnostic),
		diagnosticsChan: make(chan DiagnosticsEvent, 100),
		fileVersions:    make(map[string]int),
	}

	// Register notification handlers
	client.setupHandlers()

	// Initialize the LSP server
	if err := client.initialize(initOptions); err != nil {
		client.Shutdown()
		return nil, fmt.Errorf("failed to initialize LSP client: %w", err)
	}

	return client, nil
}

// setupHandlers registers handlers for LSP notifications
func (c *Client) setupHandlers() {
	// Handle publishDiagnostics notifications
	c.connection.OnNotification("textDocument/publishDiagnostics", func(params interface{}) {
		// Parse the params
		data, err := json.Marshal(params)
		if err != nil {
			return
		}

		var diagParams PublishDiagnosticsParams
		if err := json.Unmarshal(data, &diagParams); err != nil {
			return
		}

		// Extract file path from URI
		filePath := diagParams.URI
		if len(filePath) > 7 && filePath[:7] == "file://" {
			filePath = filePath[7:]
		}

		// Store diagnostics
		c.diagnosticsMux.Lock()
		exists := len(c.diagnostics[filePath]) > 0
		c.diagnostics[filePath] = diagParams.Diagnostics
		c.diagnosticsMux.Unlock()

		// Skip first diagnostic event for TypeScript (matches OpenCode behavior)
		if !exists && c.ServerID == "typescript" {
			return
		}

		// Notify listeners
		select {
		case c.diagnosticsChan <- DiagnosticsEvent{Path: filePath, ServerID: c.ServerID}:
		default:
		}
	})

	// Handle window/workDoneProgress/create requests
	c.connection.OnRequest("window/workDoneProgress/create", func(params interface{}) (interface{}, error) {
		return nil, nil
	})

	// Handle workspace/configuration requests
	c.connection.OnRequest("workspace/configuration", func(params interface{}) (interface{}, error) {
		// Return empty configuration for now
		return []interface{}{}, nil
	})
}

// initialize sends the initialize request to the LSP server
func (c *Client) initialize(initOptions interface{}) error {
	pid := os.Getpid()
	params := InitializeParams{
		ProcessID: &pid,
		RootURI:   "file://" + c.Root,
		InitializationOptions: initOptions,
		Capabilities: ClientCapabilities{
			Window: &WindowClientCapabilities{
				WorkDoneProgress: true,
			},
			Workspace: &WorkspaceClientCapabilities{
				Configuration: true,
			},
			TextDocument: &TextDocumentClientCapabilities{
				Synchronization: &TextDocumentSyncClientCapabilities{
					DidOpen:   true,
					DidChange: true,
				},
				PublishDiagnostics: &PublishDiagnosticsClientCapabilities{
					VersionSupport: true,
				},
			},
		},
		WorkspaceFolders: []WorkspaceFolder{
			{
				URI:  "file://" + c.Root,
				Name: "workspace",
			},
		},
	}

	// Send initialize request with timeout
	done := make(chan struct{})
	var initErr error

	go func() {
		_, err := c.connection.SendRequest("initialize", params)
		initErr = err
		close(done)
	}()

	select {
	case <-done:
		if initErr != nil {
			return fmt.Errorf("initialize request failed: %w", initErr)
		}
	case <-time.After(5 * time.Second):
		return fmt.Errorf("initialize request timed out")
	}

	// Send initialized notification
	if err := c.connection.SendNotification("initialized", map[string]interface{}{}); err != nil {
		return fmt.Errorf("initialized notification failed: %w", err)
	}

	// Send workspace/didChangeConfiguration if we have init options
	if initOptions != nil {
		_ = c.connection.SendNotification("workspace/didChangeConfiguration", map[string]interface{}{
			"settings": initOptions,
		})
	}

	return nil
}

// OpenFile opens a file in the LSP server
func (c *Client) OpenFile(filePath string) error {
	// Read file content
	content, err := os.ReadFile(filePath)
	if err != nil {
		return fmt.Errorf("failed to read file: %w", err)
	}

	// Get language ID
	ext := filepath.Ext(filePath)
	languageID := GetLanguageID(ext)

	// Get or increment version
	c.fileVersionsMux.Lock()
	version, exists := c.fileVersions[filePath]
	if exists {
		// File already open, send didChange instead
		version++
		c.fileVersions[filePath] = version
		c.fileVersionsMux.Unlock()

		return c.connection.SendNotification("textDocument/didChange", DidChangeTextDocumentParams{
			TextDocument: VersionedTextDocumentIdentifier{
				TextDocumentIdentifier: TextDocumentIdentifier{URI: "file://" + filePath},
				Version:                version,
			},
			ContentChanges: []TextDocumentContentChangeEvent{
				{Text: string(content)},
			},
		})
	}

	c.fileVersions[filePath] = 0
	c.fileVersionsMux.Unlock()

	// Clear previous diagnostics
	c.diagnosticsMux.Lock()
	delete(c.diagnostics, filePath)
	c.diagnosticsMux.Unlock()

	// Send didOpen notification
	return c.connection.SendNotification("textDocument/didOpen", DidOpenTextDocumentParams{
		TextDocument: TextDocumentItem{
			URI:        "file://" + filePath,
			LanguageID: languageID,
			Version:    0,
			Text:       string(content),
		},
	})
}

// WaitForDiagnostics waits for diagnostics to be published for a file
func (c *Client) WaitForDiagnostics(filePath string, timeout time.Duration) error {
	timer := time.NewTimer(timeout)
	defer timer.Stop()

	for {
		select {
		case event := <-c.diagnosticsChan:
			if event.Path == filePath && event.ServerID == c.ServerID {
				return nil
			}
		case <-timer.C:
			// Timeout is not an error, just return
			return nil
		}
	}
}

// GetDiagnostics returns diagnostics for all files
func (c *Client) GetDiagnostics() map[string][]Diagnostic {
	c.diagnosticsMux.RLock()
	defer c.diagnosticsMux.RUnlock()

	// Create a copy
	result := make(map[string][]Diagnostic)
	for path, diags := range c.diagnostics {
		result[path] = append([]Diagnostic{}, diags...)
	}
	return result
}

// Hover sends a textDocument/hover request
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

// WorkspaceSymbol sends a workspace/symbol request
func (c *Client) WorkspaceSymbol(query string) ([]Symbol, error) {
	params := WorkspaceSymbolParams{
		Query: query,
	}

	result, err := c.connection.SendRequest("workspace/symbol", params)
	if err != nil {
		return nil, err
	}

	// Parse result as []Symbol
	data, err := json.Marshal(result)
	if err != nil {
		return nil, err
	}

	var symbols []Symbol
	if err := json.Unmarshal(data, &symbols); err != nil {
		return nil, err
	}

	return symbols, nil
}

// DocumentSymbol sends a textDocument/documentSymbol request
func (c *Client) DocumentSymbol(uri string) (interface{}, error) {
	params := DocumentSymbolParams{
		TextDocument: TextDocumentIdentifier{
			URI: uri,
		},
	}

	return c.connection.SendRequest("textDocument/documentSymbol", params)
}

// Shutdown gracefully shuts down the LSP client
func (c *Client) Shutdown() error {
	// Send shutdown request
	_, _ = c.connection.SendRequest("shutdown", nil)

	// Send exit notification
	_ = c.connection.SendNotification("exit", nil)

	// Close connection
	c.connection.Close()

	// Kill the process if it's still running
	if c.process != nil && c.process.Process != nil {
		_ = c.process.Process.Kill()
		_ = c.process.Wait()
	}

	return nil
}
```

### jsonrpc.go - JSON-RPC 2.0 Communication Layer

```go
package lsp

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
)

// JSONRPCVersion is the JSON-RPC version
const JSONRPCVersion = "2.0"

// Request represents a JSON-RPC request
type Request struct {
	JSONRPC string      `json:"jsonrpc"`
	ID      interface{} `json:"id,omitempty"` // Can be string, number, or null
	Method  string      `json:"method"`
	Params  interface{} `json:"params,omitempty"`
}

// Response represents a JSON-RPC response
type Response struct {
	JSONRPC string      `json:"jsonrpc"`
	ID      interface{} `json:"id,omitempty"`
	Result  interface{} `json:"result,omitempty"`
	Error   *RPCError   `json:"error,omitempty"`
}

// Notification represents a JSON-RPC notification (no ID, no response expected)
type Notification struct {
	JSONRPC string      `json:"jsonrpc"`
	Method  string      `json:"method"`
	Params  interface{} `json:"params,omitempty"`
}

// RPCError represents a JSON-RPC error
type RPCError struct {
	Code    int         `json:"code"`
	Message string      `json:"message"`
	Data    interface{} `json:"data,omitempty"`
}

func (e *RPCError) Error() string {
	return fmt.Sprintf("RPC error %d: %s", e.Code, e.Message)
}

// Connection represents a JSON-RPC connection over stdio
type Connection struct {
	reader io.Reader
	writer io.Writer

	// Request/response handling
	nextID          atomic.Int64
	pendingRequests sync.Map // map[interface{}]chan *Response

	// Notification handlers
	notificationHandlers sync.Map // map[string]func(params interface{})

	// For reading incoming messages
	done chan struct{}
	wg   sync.WaitGroup
}

// NewConnection creates a new JSON-RPC connection
func NewConnection(reader io.Reader, writer io.Writer) *Connection {
	conn := &Connection{
		reader: reader,
		writer: writer,
		done:   make(chan struct{}),
	}
	return conn
}

// Listen starts listening for incoming messages
func (c *Connection) Listen() {
	c.wg.Add(1)
	go c.readLoop()
}

// Close closes the connection
func (c *Connection) Close() {
	close(c.done)
	c.wg.Wait()
}

// SendRequest sends a request and waits for the response
func (c *Connection) SendRequest(method string, params interface{}) (interface{}, error) {
	id := c.nextID.Add(1)

	request := Request{
		JSONRPC: JSONRPCVersion,
		ID:      id,
		Method:  method,
		Params:  params,
	}

	// Create a channel for the response
	responseChan := make(chan *Response, 1)
	c.pendingRequests.Store(id, responseChan)
	defer c.pendingRequests.Delete(id)

	// Send the request
	if err := c.sendMessage(request); err != nil {
		return nil, fmt.Errorf("failed to send request: %w", err)
	}

	// Wait for response
	select {
	case response := <-responseChan:
		if response.Error != nil {
			return nil, response.Error
		}
		return response.Result, nil
	case <-c.done:
		return nil, fmt.Errorf("connection closed")
	}
}

// SendNotification sends a notification (no response expected)
func (c *Connection) SendNotification(method string, params interface{}) error {
	notification := Notification{
		JSONRPC: JSONRPCVersion,
		Method:  method,
		Params:  params,
	}
	return c.sendMessage(notification)
}

// OnNotification registers a handler for a notification method
func (c *Connection) OnNotification(method string, handler func(params interface{})) {
	c.notificationHandlers.Store(method, handler)
}

// OnRequest registers a handler for a request method
func (c *Connection) OnRequest(method string, handler func(params interface{}) (interface{}, error)) {
	c.OnNotification(method, func(params interface{}) {
		// For requests, we need to send a response
		// This is a simplified implementation - in production you'd track request IDs
		result, err := handler(params)
		response := Response{
			JSONRPC: JSONRPCVersion,
			Result:  result,
		}
		if err != nil {
			response.Error = &RPCError{
				Code:    -32603, // Internal error
				Message: err.Error(),
			}
		}
		// Send response (ignoring errors for simplicity)
		_ = c.sendMessage(response)
	})
}

// sendMessage sends a JSON-RPC message
func (c *Connection) sendMessage(message interface{}) error {
	data, err := json.Marshal(message)
	if err != nil {
		return fmt.Errorf("failed to marshal message: %w", err)
	}

	// LSP uses Content-Length header
	header := fmt.Sprintf("Content-Length: %d\r\n\r\n", len(data))

	if _, err := c.writer.Write([]byte(header)); err != nil {
		return fmt.Errorf("failed to write header: %w", err)
	}
	if _, err := c.writer.Write(data); err != nil {
		return fmt.Errorf("failed to write body: %w", err)
	}

	return nil
}

// readLoop reads incoming messages
func (c *Connection) readLoop() {
	defer c.wg.Done()

	scanner := bufio.NewScanner(c.reader)
	scanner.Split(scanLSPMessage)

	for scanner.Scan() {
		select {
		case <-c.done:
			return
		default:
		}

		data := scanner.Bytes()
		c.handleMessage(data)
	}

	if err := scanner.Err(); err != nil && err != io.EOF {
		log.Printf("LSP reader error: %v", err)
	}
}

// handleMessage handles an incoming message
func (c *Connection) handleMessage(data []byte) {
	// Try to determine if it's a response or notification/request
	var base struct {
		JSONRPC string          `json:"jsonrpc"`
		ID      interface{}     `json:"id"`
		Method  string          `json:"method"`
		Result  json.RawMessage `json:"result"`
		Error   *RPCError       `json:"error"`
	}

	if err := json.Unmarshal(data, &base); err != nil {
		log.Printf("Failed to unmarshal message: %v", err)
		return
	}

	// If it has a result or error, it's a response
	if base.Result != nil || base.Error != nil {
		var response Response
		if err := json.Unmarshal(data, &response); err != nil {
			log.Printf("Failed to unmarshal response: %v", err)
			return
		}
		c.handleResponse(&response)
		return
	}

	// If it has a method, it's a notification or request
	if base.Method != "" {
		var notification struct {
			Method string          `json:"method"`
			Params json.RawMessage `json:"params"`
		}
		if err := json.Unmarshal(data, &notification); err != nil {
			log.Printf("Failed to unmarshal notification: %v", err)
			return
		}

		// Unmarshal params as generic interface{}
		var params interface{}
		if notification.Params != nil {
			if err := json.Unmarshal(notification.Params, &params); err != nil {
				log.Printf("Failed to unmarshal params: %v", err)
				return
			}
		}

		c.handleNotification(notification.Method, params)
	}
}

// handleResponse handles a response message
func (c *Connection) handleResponse(response *Response) {
	if response.ID == nil {
		return
	}

	// Find the pending request
	value, ok := c.pendingRequests.Load(response.ID)
	if !ok {
		log.Printf("Received response for unknown request ID: %v", response.ID)
		return
	}

	responseChan := value.(chan *Response)
	select {
	case responseChan <- response:
	default:
		log.Printf("Response channel full for request ID: %v", response.ID)
	}
}

// handleNotification handles a notification message
func (c *Connection) handleNotification(method string, params interface{}) {
	value, ok := c.notificationHandlers.Load(method)
	if !ok {
		// No handler registered, ignore
		return
	}

	handler := value.(func(params interface{}))
	handler(params)
}

// scanLSPMessage is a custom scanner split function for LSP messages
func scanLSPMessage(data []byte, atEOF bool) (advance int, token []byte, err error) {
	// LSP messages use Content-Length header
	// Format: "Content-Length: <length>\r\n\r\n<json>"

	if atEOF && len(data) == 0 {
		return 0, nil, nil
	}

	// Look for the header separator
	headerEnd := strings.Index(string(data), "\r\n\r\n")
	if headerEnd == -1 {
		// Need more data
		return 0, nil, nil
	}

	// Parse the header
	header := string(data[:headerEnd])
	lines := strings.Split(header, "\r\n")

	var contentLength int
	for _, line := range lines {
		if strings.HasPrefix(line, "Content-Length:") {
			lengthStr := strings.TrimSpace(strings.TrimPrefix(line, "Content-Length:"))
			contentLength, err = strconv.Atoi(lengthStr)
			if err != nil {
				return 0, nil, fmt.Errorf("invalid Content-Length: %w", err)
			}
			break
		}
	}

	if contentLength == 0 {
		return 0, nil, fmt.Errorf("missing Content-Length header")
	}

	// Calculate total message size
	messageStart := headerEnd + 4 // +4 for "\r\n\r\n"
	messageEnd := messageStart + contentLength

	if len(data) < messageEnd {
		// Need more data
		return 0, nil, nil
	}

	// Return the message body (without headers)
	token = data[messageStart:messageEnd]
	return messageEnd, token, nil
}
```

### types.go - LSP Type Definitions

```go
package lsp

import (
	"encoding/json"
	"fmt"
)

// DiagnosticSeverity represents the severity of a diagnostic
type DiagnosticSeverity int

const (
	DiagnosticSeverityError   DiagnosticSeverity = 1
	DiagnosticSeverityWarning DiagnosticSeverity = 2
	DiagnosticSeverityInfo    DiagnosticSeverity = 3
	DiagnosticSeverityHint    DiagnosticSeverity = 4
)

// Position represents a position in a text document
type Position struct {
	Line      int `json:"line"`      // 0-based line number
	Character int `json:"character"` // 0-based character offset
}

// Range represents a range in a text document
type Range struct {
	Start Position `json:"start"`
	End   Position `json:"end"`
}

// Diagnostic represents a diagnostic message from an LSP server
type Diagnostic struct {
	Range    Range              `json:"range"`
	Severity DiagnosticSeverity `json:"severity"`
	Code     interface{}        `json:"code,omitempty"`     // Can be string or number
	Source   string             `json:"source,omitempty"`   // Name of the LSP server
	Message  string             `json:"message"`            // The diagnostic message
	Tags     []int              `json:"tags,omitempty"`     // DiagnosticTag values
	Data     interface{}        `json:"data,omitempty"`     // Additional metadata
}

// PrettyDiagnostic formats a diagnostic for human-readable output
func PrettyDiagnostic(d Diagnostic) string {
	severityMap := map[DiagnosticSeverity]string{
		DiagnosticSeverityError:   "ERROR",
		DiagnosticSeverityWarning: "WARN",
		DiagnosticSeverityInfo:    "INFO",
		DiagnosticSeverityHint:    "HINT",
	}

	severity := severityMap[d.Severity]
	if severity == "" {
		severity = "ERROR"
	}

	// LSP uses 0-based line/character, display as 1-based
	line := d.Range.Start.Line + 1
	col := d.Range.Start.Character + 1

	return fmt.Sprintf("%s [%d:%d] %s", severity, line, col, d.Message)
}

// DiagnosticsToJSON converts diagnostics to JSON string
func DiagnosticsToJSON(diagnostics []Diagnostic) (string, error) {
	data, err := json.MarshalIndent(diagnostics, "", "  ")
	if err != nil {
		return "", err
	}
	return string(data), nil
}

// [Additional LSP protocol type definitions - InitializeParams, ClientCapabilities, etc.]
// See full implementation in reference code above
```

### language.go - Language ID Mapping

```go
package lsp

// LanguageExtensions maps file extensions to LSP language IDs
// This matches OpenCode's LANGUAGE_EXTENSIONS constant
var LanguageExtensions = map[string]string{
	".go":        "go",
	".py":        "python",
	".pyi":       "python",
	".rs":        "rust",
	".ts":        "typescript",
	".tsx":       "typescriptreact",
	".js":        "javascript",
	".jsx":       "javascriptreact",
	".mjs":       "javascript",
	".cjs":       "javascript",
	".mts":       "typescript",
	".cts":       "typescript",
	".java":      "java",
	".c":         "c",
	".cpp":       "cpp",
	".h":         "c",
	".hpp":       "cpp",
	".cs":        "csharp",
	".rb":        "ruby",
	".php":       "php",
	".swift":     "swift",
	".kt":        "kotlin",
	".scala":     "scala",
	".r":         "r",
	".lua":       "lua",
	".dart":      "dart",
	".zig":       "zig",
	".zon":       "zig",
	".sh":        "shellscript",
	".bash":      "shellscript",
	".zsh":       "shellscript",
	".yaml":      "yaml",
	".yml":       "yaml",
	".json":      "json",
	".xml":       "xml",
	".html":      "html",
	".css":       "css",
	".scss":      "scss",
	".sass":      "sass",
	".less":      "less",
	".md":        "markdown",
	".markdown":  "markdown",
	".sql":       "sql",
	".toml":      "toml",
	".ini":       "ini",
	".dockerfile": "dockerfile",
	"makefile":   "makefile",
	".makefile":  "makefile",
}

// GetLanguageID returns the LSP language ID for a file extension
// Returns "plaintext" if the extension is not recognized
func GetLanguageID(extension string) string {
	if langID, ok := LanguageExtensions[extension]; ok {
		return langID
	}
	return "plaintext"
}
```

</reference-implementation>

## Implementation Strategy

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

**Implementation Steps:**

### Phase 1: Core Infrastructure (Python Backend)
1. **Create LSP Package Structure**
   ```
   agent/lsp/
   ├── __init__.py          # Package exports
   ├── manager.py           # Manager singleton
   ├── client.py            # LSP client per server
   ├── connection.py        # JSON-RPC 2.0 layer
   ├── types.py             # LSP protocol types
   ├── server_config.py     # Server configurations
   └── language.py          # Extension-to-language mapping
   ```

2. **Implement JSON-RPC 2.0 Layer** (`connection.py`)
   - Async connection class using asyncio streams
   - Content-Length header parsing for LSP protocol
   - Request/response matching with async/await
   - Notification handler registration
   - Proper cleanup and error handling

3. **Implement LSP Client** (`client.py`)
   - Per-server-per-workspace client instances
   - Initialize sequence with capabilities negotiation
   - textDocument/didOpen and didChange notifications
   - Diagnostic collection from publishDiagnostics
   - Hover, symbol search methods
   - Graceful shutdown with process cleanup

4. **Implement Manager** (`manager.py`)
   - Singleton pattern with thread safety
   - GetClients(file_path) - lazy client spawning
   - Broken server tracking to avoid repeated failures
   - Diagnostic aggregation across all clients
   - TouchFile helper for pre-checking
   - Global shutdown on exit

5. **Server Configurations** (`server_config.py`)
   - ServerConfig dataclass with ID, extensions, root_finder, spawner
   - NearestRoot helper for workspace detection
   - TypeScript configuration (typescript-language-server)
   - Go configuration (gopls with auto-install)
   - Python configuration (pyright or pylsp)
   - Rust configuration (rust-analyzer)

### Phase 2: Integration with Agent Tools
1. **Create LSP Diagnostic Tool** (`agent/tools/lsp_diagnostics.py`)
   ```python
   @agent.tool_plain
   async def get_lsp_diagnostics(file_path: str | None = None) -> str:
       """Get LSP diagnostics (errors/warnings) for files.

       Args:
           file_path: Optional path to specific file. If None, returns all diagnostics.
       """
       # Implementation
   ```

2. **Create TouchFile Helper** (`agent/tools/lsp_touch.py`)
   ```python
   @agent.tool_plain
   async def check_file_errors(file_path: str) -> str:
       """Check a file for errors before editing.

       Useful before making changes to ensure you understand current state.
       """
       # Implementation
   ```

3. **Integrate with Main Agent** (`agent/agent.py`)
   - Initialize LSP manager on agent startup
   - Register LSP tools with agent
   - Add shutdown hook for cleanup

### Phase 3: Testing & Documentation
1. **Unit Tests** (`tests/test_lsp/`)
   - Test JSON-RPC message parsing
   - Test client initialization
   - Test diagnostic collection
   - Mock LSP servers for testing

2. **Integration Tests**
   - Test with real gopls for Go files
   - Test with typescript-language-server for TS files
   - Test diagnostic accuracy
   - Test concurrent file handling

3. **Documentation**
   - Update CLAUDE.md with LSP integration details
   - Add environment variables section
   - Document supported languages
   - Add troubleshooting guide

### Phase 4: Additional Language Support
1. **Python (Pyright)**
   - Configuration for pyproject.toml/setup.py detection
   - Spawner with pyright installation check

2. **Rust (rust-analyzer)**
   - Configuration for Cargo.toml detection
   - Spawner with rustup component check

3. **Additional Languages** (optional)
   - ESLint for JavaScript linting
   - Deno LSP for Deno projects
   - Clangd for C/C++
</execution-strategy>

## Acceptance Criteria

<criteria>
### Core Functionality
- [ ] Manager singleton initializes with all configured servers
- [ ] Automatic language server detection based on file extension
- [ ] Lazy server spawning only when files are accessed
- [ ] Proper workspace root detection using project markers
- [ ] Multiple servers can run concurrently for different workspaces
- [ ] Broken server tracking prevents repeated spawn failures

### JSON-RPC Protocol
- [ ] Correct Content-Length header parsing for LSP messages
- [ ] Request/response ID matching works correctly
- [ ] Notifications are handled without blocking
- [ ] Async request/response with proper timeout handling
- [ ] Error responses are properly propagated

### Diagnostics
- [ ] textDocument/publishDiagnostics notifications are received
- [ ] Diagnostics are aggregated across multiple servers
- [ ] Severity levels (error, warning, info, hint) are preserved
- [ ] File paths are correctly extracted from file:// URIs
- [ ] GetAllDiagnostics returns complete diagnostic map
- [ ] FormatDiagnostics produces human-readable output

### Language Support
- [ ] Go files (.go) use gopls
- [ ] TypeScript files (.ts, .tsx) use typescript-language-server
- [ ] JavaScript files (.js, .jsx) use typescript-language-server
- [ ] Python files (.py) use pyright or pylsp (if implemented)
- [ ] Rust files (.rs) use rust-analyzer (if implemented)
- [ ] Language ID mapping covers all common extensions

### Server Lifecycle
- [ ] Servers spawn with correct working directory
- [ ] Initialize request completes within 5 second timeout
- [ ] Servers accept textDocument/didOpen notifications
- [ ] Servers send diagnostics after file opens
- [ ] Shutdown sequence (shutdown request + exit notification + process kill) works
- [ ] No zombie processes after shutdown

### Integration
- [ ] LSP tools are registered with Pydantic AI agent
- [ ] get_lsp_diagnostics tool returns formatted errors
- [ ] check_file_errors tool waits for diagnostics
- [ ] Manager initializes on agent startup
- [ ] Manager shuts down on agent cleanup

### Error Handling
- [ ] Missing language servers fail gracefully
- [ ] Auto-install works for gopls (when enabled)
- [ ] OPENCODE_DISABLE_LSP_DOWNLOAD environment variable disables auto-install
- [ ] Network/communication errors don't crash the manager
- [ ] Malformed JSON-RPC messages are logged and ignored

### Performance
- [ ] Concurrent file operations don't block each other
- [ ] Diagnostic updates are async and non-blocking
- [ ] Memory usage is reasonable with multiple servers
- [ ] No memory leaks after repeated spawn/shutdown cycles

### Testing
- [ ] Unit tests pass for JSON-RPC parsing
- [ ] Unit tests pass for diagnostic handling
- [ ] Integration tests work with real gopls
- [ ] Integration tests work with typescript-language-server
- [ ] Mock tests work without real servers installed
</criteria>

## Notes

### Design Decisions

1. **Why Singleton Manager?**
   - Prevents duplicate server instances for same workspace
   - Centralizes lifecycle management
   - Simplifies access from agent tools

2. **Why Per-Workspace Clients?**
   - Each workspace needs its own LSP server instance
   - Server configuration depends on project structure
   - Allows concurrent work in multiple projects

3. **Why JSON-RPC 2.0?**
   - LSP spec requires JSON-RPC 2.0
   - Enables bidirectional communication
   - Standard protocol for request/response matching

4. **Why Async Architecture?**
   - Non-blocking I/O for multiple servers
   - Better performance with concurrent operations
   - Matches Pydantic AI's async patterns

### Common Pitfalls

1. **File URI Handling**
   - Always use `file://` prefix for URIs
   - Strip prefix when converting back to paths
   - Handle platform-specific path separators

2. **Process Management**
   - Always kill process in Shutdown()
   - Use stdin/stdout pipes, not subprocess.PIPE
   - Handle zombie processes with wait()

3. **Thread Safety**
   - Protect diagnostics dict with locks
   - Use atomic operations for ID generation
   - Be careful with concurrent client spawning

4. **TypeScript Quirks**
   - Skip first diagnostic event (matches OpenCode)
   - Require typescript in node_modules
   - Pass tsserver path in initOptions

### Future Enhancements

1. **Additional LSP Methods**
   - textDocument/completion
   - textDocument/definition
   - textDocument/references
   - textDocument/formatting

2. **Performance Optimizations**
   - Cache workspace root lookups
   - Lazy-load diagnostics
   - Debounce file change events

3. **Enhanced Diagnostics**
   - Quick fixes (textDocument/codeAction)
   - Related information
   - Diagnostic tags (deprecated, unnecessary)

4. **UI Integration**
   - Real-time diagnostic streaming to TUI
   - Status indicators for active servers
   - Progress notifications

## Completion Instructions

<completion>
When this task is fully implemented and tested:
1. Verify all acceptance criteria are met
2. Run `pytest tests/test_lsp/` to ensure all tests pass
3. Test with real language servers (gopls, typescript-language-server)
4. Verify diagnostics appear correctly for syntax errors
5. Check that servers shut down cleanly (no zombie processes)
6. Update CLAUDE.md with LSP integration documentation
7. Rename this file from `16-lsp-manager.md` to `16-lsp-manager.complete.md`
</completion>
