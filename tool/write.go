package tool

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// WriteTool creates the file writing tool
func WriteTool() *ToolDefinition {
	return &ToolDefinition{
		ID:   "write",
		Name: "write",
		Description: `Writes a file to the local filesystem.

Usage:
- This tool will overwrite the existing file if there is one at the provided path.
- If this is an existing file, you MUST use the Read tool first to read the file's contents. This tool will fail if you did not read the file first.
- ALWAYS prefer editing existing files in the codebase. NEVER write new files unless explicitly required.
- NEVER proactively create documentation files (*.md) or README files. Only create documentation files if explicitly requested by the User.
- Only use emojis if the user explicitly requests it. Avoid writing emojis to files unless asked.`,
		InputSchema: map[string]interface{}{
			"type": "object",
			"properties": map[string]interface{}{
				"file_path": map[string]interface{}{
					"type":        "string",
					"description": "The absolute path to the file to write (must be absolute, not relative)",
				},
				"content": map[string]interface{}{
					"type":        "string",
					"description": "The content to write to the file",
				},
			},
			"required": []string{"file_path", "content"},
		},
		Execute: executeWrite,
	}
}

type fileTimeTracker struct {
	lastRead map[string]time.Time
}

var globalFileTimeTracker = &fileTimeTracker{
	lastRead: make(map[string]time.Time),
}

func (ft *fileTimeTracker) markRead(filePath string) {
	// Normalize the path to handle symlinks and get canonical path
	absPath, err := filepath.Abs(filePath)
	if err == nil {
		filePath = absPath
	}
	// Evaluate symlinks to get the real path
	realPath, err := filepath.EvalSymlinks(filePath)
	if err == nil {
		filePath = realPath
	}

	info, err := os.Stat(filePath)
	if err == nil {
		ft.lastRead[filePath] = info.ModTime()
	}
}

func (ft *fileTimeTracker) assertNotModified(filePath string) error {
	// Normalize the path to handle symlinks and get canonical path
	absPath, err := filepath.Abs(filePath)
	if err == nil {
		filePath = absPath
	}
	// Evaluate symlinks to get the real path
	realPath, err := filepath.EvalSymlinks(filePath)
	if err == nil {
		filePath = realPath
	}

	lastRead, exists := ft.lastRead[filePath]
	if !exists {
		return fmt.Errorf("file %s has not been read in this session. You MUST use the Read tool first before writing to existing files", filePath)
	}

	info, err := os.Stat(filePath)
	if err != nil {
		if os.IsNotExist(err) {
			// File was deleted, that's okay
			return nil
		}
		return fmt.Errorf("failed to stat file: %v", err)
	}

	if info.ModTime().After(lastRead) {
		return fmt.Errorf("file %s has been modified since it was last read. Please use the Read tool again to get the latest contents", filePath)
	}

	return nil
}

// MarkFileRead marks a file as having been read (used by ReadTool)
func MarkFileRead(filePath string) {
	globalFileTimeTracker.markRead(filePath)
}

func executeWrite(params map[string]interface{}, ctx ToolContext) (ToolResult, error) {
	filePath, ok := params["file_path"].(string)
	if !ok {
		return ToolResult{}, fmt.Errorf("file_path parameter is required")
	}

	content, ok := params["content"].(string)
	if !ok {
		return ToolResult{}, fmt.Errorf("content parameter is required")
	}

	// Make path absolute if it isn't
	if !filepath.IsAbs(filePath) {
		cwd, err := os.Getwd()
		if err != nil {
			return ToolResult{}, fmt.Errorf("failed to get current directory: %v", err)
		}
		filePath = filepath.Join(cwd, filePath)
	}

	// Validate that the file path is within the current working directory
	cwd, err := os.Getwd()
	if err != nil {
		return ToolResult{}, fmt.Errorf("failed to get current directory: %v", err)
	}
	relPath, err := filepath.Rel(cwd, filePath)
	if err != nil || strings.HasPrefix(relPath, "..") {
		return ToolResult{}, fmt.Errorf("file %s is not in the current working directory", filePath)
	}

	// Check if file exists
	info, err := os.Stat(filePath)
	exists := err == nil

	if exists {
		if info.IsDir() {
			return ToolResult{}, fmt.Errorf("path is a directory, not a file: %s", filePath)
		}

		// Assert the file hasn't been modified since last read
		if err := globalFileTimeTracker.assertNotModified(filePath); err != nil {
			return ToolResult{}, err
		}
	}

	// Read old content for diff generation (if file exists)
	var oldContent string
	if exists {
		oldBytes, err := os.ReadFile(filePath)
		if err != nil {
			return ToolResult{}, fmt.Errorf("failed to read existing file: %v", err)
		}
		oldContent = string(oldBytes)
	}

	// Create parent directory if it doesn't exist
	dir := filepath.Dir(filePath)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return ToolResult{}, fmt.Errorf("failed to create parent directory: %v", err)
	}

	// Write the file
	if err := os.WriteFile(filePath, []byte(content), 0644); err != nil {
		return ToolResult{}, fmt.Errorf("failed to write file: %v", err)
	}

	// Mark the file as read with current timestamp
	globalFileTimeTracker.markRead(filePath)

	// Generate diff
	diff := generateDiff(filePath, oldContent, content)
	diff = trimDiff(diff)

	// Get relative path for title if possible
	relPath = filePath
	if cwdPath, err := os.Getwd(); err == nil {
		if rel, err := filepath.Rel(cwdPath, filePath); err == nil {
			relPath = rel
		}
	}

	output := ""
	if diff != "" {
		output = diff
	}

	return ToolResult{
		Title:  relPath,
		Output: output,
		Metadata: map[string]interface{}{
			"filepath": filePath,
			"exists":   exists,
		},
	}, nil
}
