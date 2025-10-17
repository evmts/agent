package tool

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
)

const (
	GlobLimit = 100
)

// GlobTool creates the glob file pattern matching tool
func GlobTool() *ToolDefinition {
	return &ToolDefinition{
		ID:   "glob",
		Name: "glob",
		Description: `Fast file pattern matching tool that works with any codebase size.

Usage:
- Supports glob patterns like "**/*.js" or "src/**/*.ts"
- Returns matching file paths sorted by modification time
- Use this tool when you need to find files by name patterns
- When you are doing an open ended search that may require multiple rounds of globbing and grepping, use the Task tool instead
- You have the capability to call multiple tools in a single response. It is always better to speculatively perform multiple searches as a batch that are potentially useful.`,
		InputSchema: map[string]interface{}{
			"type": "object",
			"properties": map[string]interface{}{
				"pattern": map[string]interface{}{
					"type":        "string",
					"description": "The glob pattern to match files against",
				},
				"path": map[string]interface{}{
					"type":        "string",
					"description": `The directory to search in. If not specified, the current working directory will be used. IMPORTANT: Omit this field to use the default directory. DO NOT enter "undefined" or "null" - simply omit it for the default behavior. Must be a valid directory path if provided.`,
				},
			},
			"required": []string{"pattern"},
		},
		Execute: executeGlob,
	}
}

type fileInfo struct {
	path  string
	mtime int64
}

func executeGlob(params map[string]interface{}, ctx ToolContext) (ToolResult, error) {
	pattern, ok := params["pattern"].(string)
	if !ok {
		return ToolResult{}, fmt.Errorf("pattern parameter is required")
	}

	// Determine search directory
	searchDir := ""
	if pathParam, ok := params["path"].(string); ok && pathParam != "" {
		searchDir = pathParam
	} else {
		cwd, err := os.Getwd()
		if err != nil {
			return ToolResult{}, fmt.Errorf("failed to get current directory: %v", err)
		}
		searchDir = cwd
	}

	// Make search directory absolute if it isn't
	if !filepath.IsAbs(searchDir) {
		cwd, err := os.Getwd()
		if err != nil {
			return ToolResult{}, fmt.Errorf("failed to get current directory: %v", err)
		}
		searchDir = filepath.Join(cwd, searchDir)
	}

	// Check if search directory exists
	if info, err := os.Stat(searchDir); err != nil {
		return ToolResult{}, fmt.Errorf("search directory does not exist: %s", searchDir)
	} else if !info.IsDir() {
		return ToolResult{}, fmt.Errorf("search path is not a directory: %s", searchDir)
	}

	// Use ripgrep to find files matching the glob pattern
	files, truncated, err := findFilesWithRipgrep(searchDir, pattern, ctx.Abort)
	if err != nil {
		return ToolResult{}, fmt.Errorf("failed to search files: %v", err)
	}

	// Build output
	output := []string{}
	if len(files) == 0 {
		output = append(output, "No files found")
	} else {
		for _, file := range files {
			output = append(output, file.path)
		}
		if truncated {
			output = append(output, "")
			output = append(output, "(Results are truncated. Consider using a more specific path or pattern.)")
		}
	}

	// Get relative path for title
	cwd, _ := os.Getwd()
	relPath, err := filepath.Rel(cwd, searchDir)
	if err != nil {
		relPath = searchDir
	}

	return ToolResult{
		Title:  relPath,
		Output: strings.Join(output, "\n"),
		Metadata: map[string]interface{}{
			"count":     len(files),
			"truncated": truncated,
		},
	}, nil
}

// findFilesWithRipgrep uses ripgrep to find files matching a glob pattern
func findFilesWithRipgrep(searchDir, pattern string, ctx context.Context) ([]fileInfo, bool, error) {
	// Build ripgrep command for file listing
	args := []string{
		"--files",
		"--follow",
		"--hidden",
		"--glob=!.git/*",
		fmt.Sprintf("--glob=%s", pattern),
	}

	cmd := exec.CommandContext(ctx, "rg", args...)
	cmd.Dir = searchDir

	var stdout bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = nil // Ignore stderr

	// Run the command
	err := cmd.Run()
	if err != nil {
		// ripgrep returns exit code 1 when no matches are found, which is not an error
		if exitErr, ok := err.(*exec.ExitError); ok && exitErr.ExitCode() == 1 {
			return []fileInfo{}, false, nil
		}
		// Check if ripgrep is not installed
		if _, ok := err.(*exec.Error); ok {
			return nil, false, fmt.Errorf("ripgrep (rg) is not installed or not in PATH")
		}
		return nil, false, err
	}

	// Parse output - each line is a file path relative to searchDir
	output := stdout.String()
	lines := strings.Split(strings.TrimSpace(output), "\n")

	files := make([]fileInfo, 0, len(lines))
	truncated := false

	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}

		// Stop if we've hit the limit
		if len(files) >= GlobLimit {
			truncated = true
			break
		}

		// Get absolute path
		fullPath := filepath.Join(searchDir, line)

		// Get file modification time
		mtime := int64(0)
		if info, err := os.Stat(fullPath); err == nil {
			mtime = info.ModTime().UnixNano()
		}

		files = append(files, fileInfo{
			path:  fullPath,
			mtime: mtime,
		})
	}

	// Sort by modification time (newest first)
	sort.Slice(files, func(i, j int) bool {
		return files[i].mtime > files[j].mtime
	})

	return files, truncated, nil
}
