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
		Name: "Grep",
		Description: `A powerful search tool built on ripgrep

  Usage:
  - ALWAYS use Grep for search tasks. NEVER invoke ` + "`grep`" + ` or ` + "`rg`" + ` as a Bash command. The Grep tool has been optimized for correct permissions and access.
  - Supports full regex syntax (e.g., "log.*Error", "function\s+\w+")
  - Filter files with glob parameter (e.g., "*.js", "**/*.tsx") or type parameter (e.g., "js", "py", "rust")
  - Output modes: "content" shows matching lines, "files_with_matches" shows only file paths (default), "count" shows match counts
  - Use Task tool for open-ended searches requiring multiple rounds
  - Pattern syntax: Uses ripgrep (not grep) - literal braces need escaping (use ` + "`interface\\{\\}`" + ` to find ` + "`interface{}`" + ` in Go code)
  - Multiline matching: By default patterns match within single lines only. For cross-line patterns like ` + "`struct \\{[\\s\\S]*?field`" + `, use ` + "`multiline: true`" + `
`,
		InputSchema: map[string]interface{}{
			"type": "object",
			"properties": map[string]interface{}{
				"pattern": map[string]interface{}{
					"type":        "string",
					"description": "The regular expression pattern to search for in file contents",
				},
				"path": map[string]interface{}{
					"type":        "string",
					"description": "File or directory to search in (rg PATH). Defaults to current working directory.",
				},
				"glob": map[string]interface{}{
					"type":        "string",
					"description": `Glob pattern to filter files (e.g. "*.js", "*.{ts,tsx}") - maps to rg --glob`,
				},
				"type": map[string]interface{}{
					"type":        "string",
					"description": "File type to search (rg --type). Common types: js, py, rust, go, java, etc. More efficient than include for standard file types.",
				},
				"output_mode": map[string]interface{}{
					"type":        "string",
					"description": `Output mode: "content" shows matching lines (supports -A/-B/-C context, -n line numbers, head_limit), "files_with_matches" shows file paths (supports head_limit), "count" shows match counts (supports head_limit). Defaults to "files_with_matches".`,
					"enum":        []string{"content", "files_with_matches", "count"},
				},
				"-i": map[string]interface{}{
					"type":        "boolean",
					"description": "Case insensitive search (rg -i)",
				},
				"-n": map[string]interface{}{
					"type":        "boolean",
					"description": `Show line numbers in output (rg -n). Requires output_mode: "content", ignored otherwise.`,
				},
				"-A": map[string]interface{}{
					"type":        "number",
					"description": `Number of lines to show after each match (rg -A). Requires output_mode: "content", ignored otherwise.`,
				},
				"-B": map[string]interface{}{
					"type":        "number",
					"description": `Number of lines to show before each match (rg -B). Requires output_mode: "content", ignored otherwise.`,
				},
				"-C": map[string]interface{}{
					"type":        "number",
					"description": `Number of lines to show before and after each match (rg -C). Requires output_mode: "content", ignored otherwise.`,
				},
				"head_limit": map[string]interface{}{
					"type":        "number",
					"description": `Limit output to first N lines/entries, equivalent to "| head -N". Works across all output modes: content (limits output lines), files_with_matches (limits file paths), count (limits count entries). When unspecified, shows all results from ripgrep.`,
				},
				"multiline": map[string]interface{}{
					"type":        "boolean",
					"description": "Enable multiline mode where . matches newlines and patterns can span lines (rg -U --multiline-dotall). Default: false.",
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
	count    int
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

	// Get output mode (default: files_with_matches)
	outputMode, _ := params["output_mode"].(string)
	if outputMode == "" {
		outputMode = "files_with_matches"
	}

	// Build ripgrep command
	args := []string{}

	// Add case insensitive flag
	if caseInsensitive, ok := params["-i"].(bool); ok && caseInsensitive {
		args = append(args, "-i")
	}

	// Add multiline mode
	if multiline, ok := params["multiline"].(bool); ok && multiline {
		args = append(args, "-U", "--multiline-dotall")
	}

	// Add output mode specific flags
	switch outputMode {
	case "content":
		// Show line numbers by default for content mode, or if -n is explicitly set
		showLineNumbers := true
		if n, ok := params["-n"].(bool); ok {
			showLineNumbers = n
		}
		if showLineNumbers {
			args = append(args, "-n")
		}

		// Add context lines
		if c, ok := params["-C"].(float64); ok && c > 0 {
			args = append(args, "-C", fmt.Sprintf("%d", int(c)))
		} else {
			if a, ok := params["-A"].(float64); ok && a > 0 {
				args = append(args, "-A", fmt.Sprintf("%d", int(a)))
			}
			if b, ok := params["-B"].(float64); ok && b > 0 {
				args = append(args, "-B", fmt.Sprintf("%d", int(b)))
			}
		}

		args = append(args, "-H", "--field-match-separator=|")

	case "files_with_matches":
		args = append(args, "-l") // List files with matches

	case "count":
		args = append(args, "-c") // Count matches per file
	}

	// Add type filter if specified
	if typeFilter, ok := params["type"].(string); ok && typeFilter != "" {
		args = append(args, "--type", typeFilter)
	}

	// Add glob pattern if specified
	if globPattern, ok := params["glob"].(string); ok && globPattern != "" {
		args = append(args, "--glob", globPattern)
	}

	// Add pattern and search path
	args = append(args, pattern, searchPath)

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
			Output: "No matches found",
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

	// Parse output based on mode
	output := stdout.String()

	// Apply head_limit if specified
	headLimit := -1
	if limit, ok := params["head_limit"].(float64); ok && limit > 0 {
		headLimit = int(limit)
	}

	switch outputMode {
	case "content":
		return formatContentOutput(pattern, output, headLimit)
	case "files_with_matches":
		return formatFilesOutput(pattern, output, headLimit)
	case "count":
		return formatCountOutput(pattern, output, headLimit)
	default:
		return ToolResult{}, fmt.Errorf("invalid output_mode: %s", outputMode)
	}
}

func formatContentOutput(pattern, output string, headLimit int) (ToolResult, error) {
	lines := strings.Split(strings.TrimSpace(output), "\n")

	// Apply head limit
	truncated := false
	if headLimit > 0 && len(lines) > headLimit {
		lines = lines[:headLimit]
		truncated = true
	}

	if len(lines) == 0 {
		return ToolResult{
			Title:  pattern,
			Output: "No matches found",
			Metadata: map[string]interface{}{
				"matches":   0,
				"truncated": false,
			},
		}, nil
	}

	// Parse matches with line numbers
	matches := []grepMatch{}
	for _, line := range lines {
		if line == "" {
			continue
		}

		// Check if it's a separator line (context separator)
		if line == "--" {
			matches = append(matches, grepMatch{
				lineText: "--",
			})
			continue
		}

		// Split on | separator
		parts := strings.SplitN(line, "|", 3)
		if len(parts) < 2 {
			// Line without separator, might be context line
			matches = append(matches, grepMatch{
				lineText: line,
			})
			continue
		}

		filePath := parts[0]
		lineNumStr := parts[1]
		lineText := ""
		if len(parts) >= 3 {
			lineText = parts[2]
		}

		lineNum := 0
		if lineNumStr != "" {
			num, err := strconv.Atoi(lineNumStr)
			if err == nil {
				lineNum = num
			}
		}

		matches = append(matches, grepMatch{
			path:     filePath,
			lineNum:  lineNum,
			lineText: lineText,
		})
	}

	// Format output
	var outputLines []string
	currentFile := ""
	for _, match := range matches {
		// Separator line
		if match.lineText == "--" {
			outputLines = append(outputLines, "")
			continue
		}

		// New file
		if match.path != "" && currentFile != match.path {
			if currentFile != "" {
				outputLines = append(outputLines, "")
			}
			currentFile = match.path
			outputLines = append(outputLines, fmt.Sprintf("%s:", match.path))
		}

		// Format line
		if match.lineNum > 0 {
			outputLines = append(outputLines, fmt.Sprintf("  %d: %s", match.lineNum, match.lineText))
		} else {
			outputLines = append(outputLines, fmt.Sprintf("  %s", match.lineText))
		}
	}

	if truncated {
		outputLines = append(outputLines, "")
		outputLines = append(outputLines, fmt.Sprintf("(Output truncated to first %d lines)", headLimit))
	}

	result := strings.Join(outputLines, "\n")
	return ToolResult{
		Title:  pattern,
		Output: result,
		Metadata: map[string]interface{}{
			"matches":   len(matches),
			"truncated": truncated,
		},
	}, nil
}

func formatFilesOutput(pattern, output string, headLimit int) (ToolResult, error) {
	lines := strings.Split(strings.TrimSpace(output), "\n")

	// Remove empty lines
	files := []string{}
	for _, line := range lines {
		if line != "" {
			files = append(files, line)
		}
	}

	// Sort by modification time (most recent first)
	type fileInfo struct {
		path    string
		modTime int64
	}
	fileInfos := []fileInfo{}
	for _, filePath := range files {
		info, err := os.Stat(filePath)
		if err != nil {
			// If we can't stat, still include it but with zero time
			fileInfos = append(fileInfos, fileInfo{path: filePath, modTime: 0})
			continue
		}
		fileInfos = append(fileInfos, fileInfo{
			path:    filePath,
			modTime: info.ModTime().UnixMilli(),
		})
	}

	sort.Slice(fileInfos, func(i, j int) bool {
		return fileInfos[i].modTime > fileInfos[j].modTime
	})

	// Apply head limit
	truncated := false
	if headLimit > 0 && len(fileInfos) > headLimit {
		fileInfos = fileInfos[:headLimit]
		truncated = true
	}

	if len(fileInfos) == 0 {
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
	outputLines = append(outputLines, fmt.Sprintf("Found %d files", len(fileInfos)))
	for _, fi := range fileInfos {
		outputLines = append(outputLines, fi.path)
	}

	if truncated {
		outputLines = append(outputLines, "")
		outputLines = append(outputLines, fmt.Sprintf("(Results truncated to first %d files)", headLimit))
	}

	return ToolResult{
		Title:  pattern,
		Output: strings.Join(outputLines, "\n"),
		Metadata: map[string]interface{}{
			"matches":   len(fileInfos),
			"truncated": truncated,
		},
	}, nil
}

func formatCountOutput(pattern, output string, headLimit int) (ToolResult, error) {
	lines := strings.Split(strings.TrimSpace(output), "\n")

	// Parse count output (format: file:count)
	counts := []grepMatch{}
	for _, line := range lines {
		if line == "" {
			continue
		}

		parts := strings.SplitN(line, ":", 2)
		if len(parts) != 2 {
			continue
		}

		filePath := parts[0]
		countStr := parts[1]

		count, err := strconv.Atoi(countStr)
		if err != nil {
			continue
		}

		// Get file modification time
		info, err := os.Stat(filePath)
		modTime := int64(0)
		if err == nil {
			modTime = info.ModTime().UnixMilli()
		}

		counts = append(counts, grepMatch{
			path:    filePath,
			modTime: modTime,
			count:   count,
		})
	}

	// Sort by modification time (most recent first)
	sort.Slice(counts, func(i, j int) bool {
		return counts[i].modTime > counts[j].modTime
	})

	// Apply head limit
	truncated := false
	if headLimit > 0 && len(counts) > headLimit {
		counts = counts[:headLimit]
		truncated = true
	}

	if len(counts) == 0 {
		return ToolResult{
			Title:  pattern,
			Output: "No matches found",
			Metadata: map[string]interface{}{
				"matches":   0,
				"truncated": false,
			},
		}, nil
	}

	// Format output
	var outputLines []string
	totalMatches := 0
	for _, match := range counts {
		outputLines = append(outputLines, fmt.Sprintf("%s: %d", match.path, match.count))
		totalMatches += match.count
	}

	outputLines = append([]string{fmt.Sprintf("Found %d matches in %d files", totalMatches, len(counts)), ""}, outputLines...)

	if truncated {
		outputLines = append(outputLines, "")
		outputLines = append(outputLines, fmt.Sprintf("(Results truncated to first %d files)", headLimit))
	}

	return ToolResult{
		Title:  pattern,
		Output: strings.Join(outputLines, "\n"),
		Metadata: map[string]interface{}{
			"matches":   len(counts),
			"total":     totalMatches,
			"truncated": truncated,
		},
	}, nil
}
