package tool

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

const lspDiagnosticsDescription = `Get LSP diagnostics (errors, warnings, etc.) for a specific file.

Usage:
- The path parameter is the path to the file to get diagnostics for
- The path can be relative (will be resolved against working directory) or absolute
- Returns diagnostics in a human-readable format showing severity, line, column, and message
- If no diagnostics are found, returns "No errors found"

Note: This tool requires an LSP server to be running for the file's language.`

// Diagnostic represents a single diagnostic message from an LSP server
type Diagnostic struct {
	Range    DiagnosticRange `json:"range"`
	Severity int             `json:"severity"` // 1=Error, 2=Warning, 3=Info, 4=Hint
	Message  string          `json:"message"`
	Source   string          `json:"source,omitempty"`
}

// DiagnosticRange represents a range in a document
type DiagnosticRange struct {
	Start Position `json:"start"`
	End   Position `json:"end"`
}

// Position represents a position in a document
type Position struct {
	Line      int `json:"line"`
	Character int `json:"character"`
}

// LspDiagnosticsTool creates the LSP diagnostics tool
func LspDiagnosticsTool() *ToolDefinition {
	return &ToolDefinition{
		ID:          "lsp_diagnostics",
		Name:        "lsp_diagnostics",
		Description: lspDiagnosticsDescription,
		InputSchema: map[string]interface{}{
			"type": "object",
			"properties": map[string]interface{}{
				"path": map[string]interface{}{
					"type":        "string",
					"description": "The path to the file to get diagnostics.",
				},
			},
			"required": []string{"path"},
		},
		Execute: executeLspDiagnostics,
	}
}

func executeLspDiagnostics(params map[string]interface{}, ctx ToolContext) (ToolResult, error) {
	filePath, ok := params["path"].(string)
	if !ok {
		return ToolResult{}, fmt.Errorf("path parameter is required")
	}

	// Normalize path to absolute
	normalized := filePath
	if !filepath.IsAbs(filePath) {
		cwd, err := os.Getwd()
		if err != nil {
			return ToolResult{}, fmt.Errorf("failed to get current directory: %v", err)
		}
		normalized = filepath.Join(cwd, filePath)
	}

	// Check if file exists
	if _, err := os.Stat(normalized); err != nil {
		if os.IsNotExist(err) {
			return ToolResult{}, fmt.Errorf("file not found: %s", normalized)
		}
		return ToolResult{}, fmt.Errorf("failed to stat file: %v", err)
	}

	// Get diagnostics from LSP (stub implementation)
	// In a real implementation, this would:
	// 1. Call LSP.touchFile(normalized, true) to open/update the file and wait for diagnostics
	// 2. Call LSP.diagnostics() to get all diagnostics
	// 3. Extract diagnostics for the specific file
	diagnostics, err := getLspDiagnostics(normalized)
	if err != nil {
		return ToolResult{}, fmt.Errorf("failed to get diagnostics: %v", err)
	}

	// Get relative path for title
	cwd, _ := os.Getwd()
	relPath, err := filepath.Rel(cwd, normalized)
	if err != nil {
		relPath = normalized
	}

	// Format output
	var output string
	if len(diagnostics) == 0 {
		output = "No errors found"
	} else {
		output = formatDiagnostics(diagnostics)
	}

	// Prepare metadata with all diagnostics
	allDiagnostics := map[string]interface{}{
		normalized: diagnostics,
	}

	return ToolResult{
		Title:  relPath,
		Output: output,
		Metadata: map[string]interface{}{
			"diagnostics": allDiagnostics,
		},
	}, nil
}

// getLspDiagnostics retrieves diagnostics for a file from the LSP server
// This is a stub implementation - in production this would interact with an actual LSP client
func getLspDiagnostics(filePath string) ([]Diagnostic, error) {
	// Stub implementation - returns empty diagnostics
	// In a real implementation, this would:
	// 1. Connect to or get existing LSP client for the file type
	// 2. Send textDocument/didOpen or textDocument/didChange notification
	// 3. Wait for textDocument/publishDiagnostics notification
	// 4. Return the diagnostics for this file
	return []Diagnostic{}, nil
}

// formatDiagnostics formats diagnostics into human-readable output
func formatDiagnostics(diagnostics []Diagnostic) string {
	if len(diagnostics) == 0 {
		return "No errors found"
	}

	severityMap := map[int]string{
		1: "ERROR",
		2: "WARN",
		3: "INFO",
		4: "HINT",
	}

	var result string
	for i, diag := range diagnostics {
		if i > 0 {
			result += "\n"
		}

		severity := severityMap[diag.Severity]
		if severity == "" {
			severity = "ERROR" // Default to ERROR if unknown
		}

		// LSP uses 0-based line/character, display as 1-based
		line := diag.Range.Start.Line + 1
		col := diag.Range.Start.Character + 1

		result += fmt.Sprintf("%s [%d:%d] %s", severity, line, col, diag.Message)
	}

	return result
}

// PrettyDiagnostic formats a single diagnostic in a human-readable way
func PrettyDiagnostic(diag Diagnostic) string {
	diagnostics := []Diagnostic{diag}
	return formatDiagnostics(diagnostics)
}

// DiagnosticsToJSON converts diagnostics to JSON string
func DiagnosticsToJSON(diagnostics []Diagnostic) (string, error) {
	data, err := json.MarshalIndent(diagnostics, "", "  ")
	if err != nil {
		return "", err
	}
	return string(data), nil
}
