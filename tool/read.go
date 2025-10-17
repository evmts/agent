package tool

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

const (
	DefaultReadLimit = 2000
	MaxLineLength    = 2000
)

// ReadTool creates the file reading tool
func ReadTool() *ToolDefinition {
	return &ToolDefinition{
		ID:   "read",
		Name: "read",
		Description: `Read a file from the local filesystem. You can access any file directly by using this tool.

Usage:
- The file_path parameter must be an absolute path, not a relative path
- By default, it reads up to 2000 lines starting from the beginning of the file
- You can optionally specify a line offset and limit (especially handy for long files)
- Any lines longer than 2000 characters will be truncated
- Results are returned using cat -n format, with line numbers starting at 1

This tool can only read files, not directories.`,
		InputSchema: map[string]interface{}{
			"type": "object",
			"properties": map[string]interface{}{
				"file_path": map[string]interface{}{
					"type":        "string",
					"description": "The absolute path to the file to read",
				},
				"offset": map[string]interface{}{
					"type":        "number",
					"description": "The line number to start reading from (0-based). Only provide if the file is too large to read at once.",
				},
				"limit": map[string]interface{}{
					"type":        "number",
					"description": "The number of lines to read. Only provide if the file is too large to read at once.",
				},
			},
			"required": []string{"file_path"},
		},
		Execute: executeRead,
	}
}

func executeRead(params map[string]interface{}, ctx ToolContext) (ToolResult, error) {
	filePath, ok := params["file_path"].(string)
	if !ok {
		return ToolResult{}, fmt.Errorf("file_path parameter is required")
	}

	// Make path absolute if it isn't
	if !filepath.IsAbs(filePath) {
		cwd, err := os.Getwd()
		if err != nil {
			return ToolResult{}, fmt.Errorf("failed to get current directory: %v", err)
		}
		filePath = filepath.Join(cwd, filePath)
	}

	offset := 0
	if offsetParam, ok := params["offset"].(float64); ok {
		offset = int(offsetParam)
	}

	limit := DefaultReadLimit
	if limitParam, ok := params["limit"].(float64); ok {
		limit = int(limitParam)
	}

	// Check if file exists
	info, err := os.Stat(filePath)
	if err != nil {
		if os.IsNotExist(err) {
			return ToolResult{}, fmt.Errorf("file not found: %s", filePath)
		}
		return ToolResult{}, fmt.Errorf("failed to stat file: %v", err)
	}

	if info.IsDir() {
		return ToolResult{}, fmt.Errorf("path is a directory, not a file: %s", filePath)
	}

	// Open file
	file, err := os.Open(filePath)
	if err != nil {
		return ToolResult{}, fmt.Errorf("failed to open file: %v", err)
	}
	defer file.Close()

	// Read lines
	scanner := bufio.NewScanner(file)
	var output strings.Builder
	lineNum := 1
	linesRead := 0

	for scanner.Scan() {
		// Skip lines before offset
		if lineNum <= offset {
			lineNum++
			continue
		}

		// Stop if we've read enough lines
		if linesRead >= limit {
			break
		}

		line := scanner.Text()

		// Truncate long lines
		if len(line) > MaxLineLength {
			line = line[:MaxLineLength] + "... (line truncated)"
		}

		// Format with line number (cat -n format)
		output.WriteString(fmt.Sprintf("%6d\t%s\n", lineNum, line))

		lineNum++
		linesRead++
	}

	if err := scanner.Err(); err != nil {
		return ToolResult{}, fmt.Errorf("error reading file: %v", err)
	}

	// Get relative path for title if possible
	cwd, _ := os.Getwd()
	relPath, err := filepath.Rel(cwd, filePath)
	if err != nil {
		relPath = filePath
	}

	title := relPath
	if offset > 0 || linesRead >= limit {
		title = fmt.Sprintf("%s (lines %d-%d)", relPath, offset+1, offset+linesRead)
	}

	return ToolResult{
		Title:  title,
		Output: output.String(),
		Metadata: map[string]interface{}{
			"path":       filePath,
			"lines_read": linesRead,
			"offset":     offset,
		},
	}, nil
}
