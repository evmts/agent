package tool

import (
	"encoding/json"
	"fmt"
	"path/filepath"
)

// LspHoverTool creates the LSP hover tool
// Note: This is a placeholder implementation as LSP integration is not yet available
// The TypeScript version indicates this tool should not be used (lsp-hover.txt: "do not use")
func LspHoverTool() *ToolDefinition {
	return &ToolDefinition{
		ID:   "lsp_hover",
		Name: "lsp_hover",
		Description: `Get hover information from Language Server Protocol for a specific position in a file.

Usage:
- The file parameter is the path to the file to get hover information for
- The line parameter is the line number (0-based)
- The character parameter is the character position within the line (0-based)
- Returns type information, documentation, and other hover details from the LSP server

Note: LSP integration is not yet implemented in this Go version. This tool returns placeholder data.`,
		InputSchema: map[string]interface{}{
			"type": "object",
			"properties": map[string]interface{}{
				"file": map[string]interface{}{
					"type":        "string",
					"description": "The path to the file to get hover information for",
				},
				"line": map[string]interface{}{
					"type":        "number",
					"description": "The line number (0-based)",
				},
				"character": map[string]interface{}{
					"type":        "number",
					"description": "The character position within the line (0-based)",
				},
			},
			"required": []string{"file", "line", "character"},
		},
		Execute: executeLspHover,
	}
}

func executeLspHover(params map[string]interface{}, ctx ToolContext) (ToolResult, error) {
	file, ok := params["file"].(string)
	if !ok {
		return ToolResult{}, fmt.Errorf("file parameter is required")
	}

	line, ok := params["line"].(float64)
	if !ok {
		return ToolResult{}, fmt.Errorf("line parameter is required")
	}

	character, ok := params["character"].(float64)
	if !ok {
		return ToolResult{}, fmt.Errorf("character parameter is required")
	}

	// Convert relative paths to absolute
	absFile := file
	if !filepath.IsAbs(file) {
		var err error
		absFile, err = filepath.Abs(file)
		if err != nil {
			return ToolResult{}, fmt.Errorf("failed to resolve absolute path: %v", err)
		}
	}

	// Create a placeholder result
	// In the TypeScript implementation, this would call:
	// - LSP.touchFile(file, true) to open the file in the LSP server
	// - LSP.hover() which sends a textDocument/hover request to the LSP server
	result := map[string]interface{}{
		"error":   "LSP integration not yet implemented",
		"message": "This tool is a placeholder. LSP hover functionality requires an LSP server integration.",
		"request": map[string]interface{}{
			"file":      absFile,
			"line":      int(line),
			"character": int(character),
		},
	}

	// Format the output as JSON
	output, err := json.MarshalIndent(result, "", "  ")
	if err != nil {
		return ToolResult{}, fmt.Errorf("failed to marshal result: %v", err)
	}

	// Create title similar to TypeScript implementation
	// TypeScript: path.relative(Instance.worktree, file) + ":" + args.line + ":" + args.character
	title := fmt.Sprintf("%s:%d:%d", filepath.Base(file), int(line), int(character))

	return ToolResult{
		Title:  title,
		Output: string(output),
		Metadata: map[string]interface{}{
			"result": result,
		},
	}, nil
}
