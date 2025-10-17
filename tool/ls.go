package tool

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

const (
	FileLimit = 100
)

var ignorePatterns = []string{
	"node_modules",
	"__pycache__",
	".git",
	"dist",
	"build",
	"target",
	"vendor",
	"bin",
	"obj",
	".idea",
	".vscode",
	".zig-cache",
	"zig-out",
	".coverage",
	"coverage",
	"tmp",
	"temp",
	".cache",
	"cache",
	"logs",
	".venv",
	"venv",
	"env",
}

// ListTool creates the list/ls tool for listing directory contents
func ListTool() *ToolDefinition {
	return &ToolDefinition{
		ID:          "list",
		Name:        "list",
		Description: `Lists files and directories in a given path. The path parameter must be absolute; omit it to use the current workspace directory. You can optionally provide an array of glob patterns to ignore with the ignore parameter. You should generally prefer the Glob and Grep tools, if you know which directories to search.`,
		InputSchema: map[string]interface{}{
			"type": "object",
			"properties": map[string]interface{}{
				"path": map[string]interface{}{
					"type":        "string",
					"description": "The absolute path to the directory to list (must be absolute, not relative)",
				},
				"ignore": map[string]interface{}{
					"type": "array",
					"items": map[string]interface{}{
						"type": "string",
					},
					"description": "List of glob patterns to ignore",
				},
			},
		},
		Execute: executeList,
	}
}

func executeList(params map[string]interface{}, ctx ToolContext) (ToolResult, error) {
	// Get search path
	searchPath := ""
	if pathParam, ok := params["path"].(string); ok {
		searchPath = pathParam
	} else {
		cwd, err := os.Getwd()
		if err != nil {
			return ToolResult{}, fmt.Errorf("failed to get current directory: %v", err)
		}
		searchPath = cwd
	}

	// Make path absolute
	if !filepath.IsAbs(searchPath) {
		cwd, err := os.Getwd()
		if err != nil {
			return ToolResult{}, fmt.Errorf("failed to get current directory: %v", err)
		}
		searchPath = filepath.Join(cwd, searchPath)
	}

	// Check if path exists and is a directory
	info, err := os.Stat(searchPath)
	if err != nil {
		if os.IsNotExist(err) {
			return ToolResult{}, fmt.Errorf("path not found: %s", searchPath)
		}
		return ToolResult{}, fmt.Errorf("failed to stat path: %v", err)
	}
	if !info.IsDir() {
		return ToolResult{}, fmt.Errorf("path is not a directory: %s", searchPath)
	}

	// Get ignore patterns
	ignoreList := make([]string, len(ignorePatterns))
	copy(ignoreList, ignorePatterns)
	if ignoreParam, ok := params["ignore"].([]interface{}); ok {
		for _, pattern := range ignoreParam {
			if str, ok := pattern.(string); ok {
				ignoreList = append(ignoreList, str)
			}
		}
	}

	// Collect files
	files := []string{}
	err = filepath.Walk(searchPath, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return nil // Skip errors
		}

		// Get relative path
		relPath, err := filepath.Rel(searchPath, path)
		if err != nil {
			return nil
		}

		// Skip root directory
		if relPath == "." {
			return nil
		}

		// Check if should ignore
		if shouldIgnore(relPath, ignoreList) {
			if info.IsDir() {
				return filepath.SkipDir
			}
			return nil
		}

		// Only add files (not directories)
		if !info.IsDir() {
			files = append(files, relPath)
			if len(files) >= FileLimit {
				return filepath.SkipAll
			}
		}

		return nil
	})

	if err != nil && err != filepath.SkipAll {
		return ToolResult{}, fmt.Errorf("failed to walk directory: %v", err)
	}

	// Build directory structure
	dirs := make(map[string]bool)
	filesByDir := make(map[string][]string)

	for _, file := range files {
		dir := filepath.Dir(file)

		// Normalize path separators to forward slashes
		dir = filepath.ToSlash(dir)
		file = filepath.ToSlash(file)

		// Add all parent directories
		parts := []string{}
		if dir != "." {
			parts = strings.Split(dir, "/")
		}

		for i := 0; i <= len(parts); i++ {
			var dirPath string
			if i == 0 {
				dirPath = "."
			} else {
				dirPath = strings.Join(parts[:i], "/")
			}
			dirs[dirPath] = true
		}

		// Add file to its directory
		if _, exists := filesByDir[dir]; !exists {
			filesByDir[dir] = []string{}
		}
		filesByDir[dir] = append(filesByDir[dir], filepath.Base(file))
	}

	// Build output
	output := searchPath + "/\n" + renderDir(".", 0, dirs, filesByDir)

	// Get relative path for title
	cwd, _ := os.Getwd()
	relPath, err := filepath.Rel(cwd, searchPath)
	if err != nil {
		relPath = searchPath
	}

	return ToolResult{
		Title:  relPath,
		Output: output,
		Metadata: map[string]interface{}{
			"count":     len(files),
			"truncated": len(files) >= FileLimit,
		},
	}, nil
}

func shouldIgnore(path string, ignoreList []string) bool {
	// Normalize to forward slashes for consistent matching
	path = filepath.ToSlash(path)

	parts := strings.Split(path, "/")
	for _, part := range parts {
		for _, pattern := range ignoreList {
			if matched, _ := filepath.Match(pattern, part); matched {
				return true
			}
			// Also check exact match
			if part == pattern {
				return true
			}
		}
	}
	return false
}

func renderDir(dirPath string, depth int, dirs map[string]bool, filesByDir map[string][]string) string {
	indent := strings.Repeat("  ", depth)
	var output strings.Builder

	if depth > 0 {
		output.WriteString(fmt.Sprintf("%s%s/\n", indent, filepath.Base(dirPath)))
	}

	childIndent := strings.Repeat("  ", depth+1)

	// Get child directories
	children := []string{}
	for d := range dirs {
		parent := filepath.Dir(d)
		if parent == dirPath && d != dirPath {
			children = append(children, d)
		}
	}
	sort.Strings(children)

	// Render subdirectories first
	for _, child := range children {
		output.WriteString(renderDir(child, depth+1, dirs, filesByDir))
	}

	// Render files
	if fileList, exists := filesByDir[dirPath]; exists {
		sort.Strings(fileList)
		for _, file := range fileList {
			output.WriteString(fmt.Sprintf("%s%s\n", childIndent, file))
		}
	}

	return output.String()
}
