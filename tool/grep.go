package tool

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

const (
	MaxGrepMatches = 100
)

// GrepTool creates the grep/ripgrep search tool
func GrepTool() *ToolDefinition {
	return &ToolDefinition{
		ID:   "grep",
		Name: "grep",
		Description: `Fast content search tool that works with any codebase size.

Usage:
- Searches file contents using regular expressions
- Supports full regex syntax (eg. "log.*Error", "function\s+\w+", etc.)
- Filter files by pattern with the include parameter (eg. "*.js", "*.{ts,tsx}")
- Returns file paths with at least one match sorted by modification time
- Use this tool when you need to find files containing specific patterns
- If you need to identify/count the number of matches within files, use the Bash tool with rg (ripgrep) directly. Do NOT use grep.`,
		InputSchema: map[string]interface{}{
			"type": "object",
			"properties": map[string]interface{}{
				"pattern": map[string]interface{}{
					"type":        "string",
					"description": "The regex pattern to search for in file contents",
				},
				"path": map[string]interface{}{
					"type":        "string",
					"description": "The directory to search in. Defaults to the current working directory.",
				},
				"include": map[string]interface{}{
					"type":        "string",
					"description": `File pattern to include in the search (e.g. "*.js", "*.{ts,tsx}")`,
				},
			},
			"required": []string{"pattern"},
		},
		Execute: executeGrep,
	}
}

type grepMatch struct {
	path     string
	modTime  int64
	lineNum  int
	lineText string
}

func executeGrep(params map[string]interface{}, ctx ToolContext) (ToolResult, error) {
	pattern, ok := params["pattern"].(string)
	if !ok {
		return ToolResult{}, fmt.Errorf("pattern parameter is required")
	}

	// Get search path
	searchPath, _ := params["path"].(string)
	if searchPath == "" {
		cwd, err := os.Getwd()
		if err != nil {
			return ToolResult{}, fmt.Errorf("failed to get current directory: %v", err)
		}
		searchPath = cwd
	}

	// Make path absolute if it isn't
	if !filepath.IsAbs(searchPath) {
		cwd, err := os.Getwd()
		if err != nil {
			return ToolResult{}, fmt.Errorf("failed to get current directory: %v", err)
		}
		searchPath = filepath.Join(cwd, searchPath)
	}

	// Build ripgrep command
	args := []string{"-nH", "--field-match-separator=|", pattern}

	// Add include pattern if specified
	if include, ok := params["include"].(string); ok && include != "" {
		args = append(args, "--glob", include)
	}

	args = append(args, searchPath)

	// Execute ripgrep
	execCtx, cancel := context.WithTimeout(ctx.Abort, DefaultTimeout)
	defer cancel()

	cmd := exec.CommandContext(execCtx, "rg", args...)
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	err := cmd.Run()
	exitCode := 0
	if err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			exitCode = exitErr.ExitCode()
		} else {
			return ToolResult{}, fmt.Errorf("failed to execute ripgrep: %v", err)
		}
	}

	// Exit code 1 means no matches found
	if exitCode == 1 {
		return ToolResult{
			Title:  pattern,
			Output: "No files found",
			Metadata: map[string]interface{}{
				"matches":   0,
				"truncated": false,
			},
		}, nil
	}

	// Any other non-zero exit code is an error
	if exitCode != 0 {
		return ToolResult{}, fmt.Errorf("ripgrep failed: %s", stderr.String())
	}

	// Parse output
	output := stdout.String()
	lines := strings.Split(strings.TrimSpace(output), "\n")
	matches := []grepMatch{}

	for _, line := range lines {
		if line == "" {
			continue
		}

		// Split on | separator
		parts := strings.SplitN(line, "|", 3)
		if len(parts) < 3 {
			continue
		}

		filePath := parts[0]
		lineNumStr := parts[1]
		lineText := parts[2]

		lineNum, err := strconv.Atoi(lineNumStr)
		if err != nil {
			continue
		}

		// Get file modification time
		info, err := os.Stat(filePath)
		if err != nil {
			continue
		}

		matches = append(matches, grepMatch{
			path:     filePath,
			modTime:  info.ModTime().UnixMilli(),
			lineNum:  lineNum,
			lineText: lineText,
		})
	}

	// Sort by modification time (most recent first)
	sort.Slice(matches, func(i, j int) bool {
		return matches[i].modTime > matches[j].modTime
	})

	// Truncate if necessary
	truncated := len(matches) > MaxGrepMatches
	if truncated {
		matches = matches[:MaxGrepMatches]
	}

	if len(matches) == 0 {
		return ToolResult{
			Title:  pattern,
			Output: "No files found",
			Metadata: map[string]interface{}{
				"matches":   0,
				"truncated": false,
			},
		}, nil
	}

	// Format output
	var outputLines []string
	outputLines = append(outputLines, fmt.Sprintf("Found %d matches", len(matches)))

	currentFile := ""
	for _, match := range matches {
		if currentFile != match.path {
			if currentFile != "" {
				outputLines = append(outputLines, "")
			}
			currentFile = match.path
			outputLines = append(outputLines, fmt.Sprintf("%s:", match.path))
		}
		outputLines = append(outputLines, fmt.Sprintf("  Line %d: %s", match.lineNum, match.lineText))
	}

	if truncated {
		outputLines = append(outputLines, "")
		outputLines = append(outputLines, "(Results are truncated. Consider using a more specific path or pattern.)")
	}

	return ToolResult{
		Title:  pattern,
		Output: strings.Join(outputLines, "\n"),
		Metadata: map[string]interface{}{
			"matches":   len(matches),
			"truncated": truncated,
		},
	}, nil
}
