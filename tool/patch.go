package tool

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

// PatchTool creates the patch application tool
func PatchTool() *ToolDefinition {
	return &ToolDefinition{
		ID:   "patch",
		Name: "patch",
		Description: `Apply a patch to modify multiple files. Supports adding, updating, and deleting files with context-aware changes.

Usage:
- The patchText parameter contains the full patch text in the custom format
- Patch format uses markers: *** Begin Patch, *** End Patch
- Supports operations: Add File, Delete File, Update File
- Update operations support context-aware chunk replacement
- File moves are supported with *** Move to: directive

Patch Format:
*** Begin Patch
*** Add File: path/to/new/file.go
+line 1 content
+line 2 content

*** Update File: path/to/existing/file.go
@@ context line for finding location
-old line to remove
+new line to add
 unchanged line

*** Delete File: path/to/old/file.go
*** End Patch`,
		InputSchema: map[string]interface{}{
			"type": "object",
			"properties": map[string]interface{}{
				"patchText": map[string]interface{}{
					"type":        "string",
					"description": "The full patch text that describes all changes to be made",
				},
			},
			"required": []string{"patchText"},
		},
		Execute: executePatch,
	}
}

// Hunk represents a file operation in the patch
type Hunk interface {
	GetPath() string
	GetType() string
}

// AddHunk represents adding a new file
type AddHunk struct {
	Path     string
	Contents string
}

func (h *AddHunk) GetPath() string { return h.Path }
func (h *AddHunk) GetType() string { return "add" }

// DeleteHunk represents deleting a file
type DeleteHunk struct {
	Path string
}

func (h *DeleteHunk) GetPath() string { return h.Path }
func (h *DeleteHunk) GetType() string { return "delete" }

// UpdateHunk represents updating an existing file
type UpdateHunk struct {
	Path     string
	MovePath string
	Chunks   []UpdateFileChunk
}

func (h *UpdateHunk) GetPath() string { return h.Path }
func (h *UpdateHunk) GetType() string { return "update" }

// UpdateFileChunk represents a single change within a file update
type UpdateFileChunk struct {
	OldLines       []string
	NewLines       []string
	ChangeContext  string
	IsEndOfFile    bool
}

// parsePatch parses the patch text into hunks
func parsePatch(patchText string) ([]Hunk, error) {
	lines := strings.Split(patchText, "\n")
	var hunks []Hunk

	// Find begin/end markers
	beginIdx := -1
	endIdx := -1
	for i, line := range lines {
		if strings.TrimSpace(line) == "*** Begin Patch" {
			beginIdx = i
		}
		if strings.TrimSpace(line) == "*** End Patch" {
			endIdx = i
		}
	}

	if beginIdx == -1 || endIdx == -1 || beginIdx >= endIdx {
		return nil, fmt.Errorf("invalid patch format: missing Begin/End markers")
	}

	// Parse content between markers
	i := beginIdx + 1
	for i < endIdx {
		line := lines[i]

		if strings.HasPrefix(line, "*** Add File:") {
			filePath := strings.TrimSpace(strings.TrimPrefix(line, "*** Add File:"))
			i++
			content, nextIdx := parseAddFileContent(lines, i, endIdx)
			hunks = append(hunks, &AddHunk{
				Path:     filePath,
				Contents: content,
			})
			i = nextIdx
		} else if strings.HasPrefix(line, "*** Delete File:") {
			filePath := strings.TrimSpace(strings.TrimPrefix(line, "*** Delete File:"))
			hunks = append(hunks, &DeleteHunk{
				Path: filePath,
			})
			i++
		} else if strings.HasPrefix(line, "*** Update File:") {
			filePath := strings.TrimSpace(strings.TrimPrefix(line, "*** Update File:"))
			i++

			// Check for move directive
			var movePath string
			if i < len(lines) && strings.HasPrefix(lines[i], "*** Move to:") {
				movePath = strings.TrimSpace(strings.TrimPrefix(lines[i], "*** Move to:"))
				i++
			}

			chunks, nextIdx := parseUpdateFileChunks(lines, i, endIdx)
			hunks = append(hunks, &UpdateHunk{
				Path:     filePath,
				MovePath: movePath,
				Chunks:   chunks,
			})
			i = nextIdx
		} else {
			i++
		}
	}

	if len(hunks) == 0 {
		return nil, fmt.Errorf("no file changes found in patch")
	}

	return hunks, nil
}

// parseAddFileContent parses the content for an Add File operation
func parseAddFileContent(lines []string, startIdx, endIdx int) (string, int) {
	var content strings.Builder
	i := startIdx

	for i < endIdx && !strings.HasPrefix(lines[i], "***") {
		if strings.HasPrefix(lines[i], "+") {
			content.WriteString(lines[i][1:])
			content.WriteString("\n")
		}
		i++
	}

	// Remove trailing newline
	result := content.String()
	if strings.HasSuffix(result, "\n") {
		result = result[:len(result)-1]
	}

	return result, i
}

// parseUpdateFileChunks parses the chunks for an Update File operation
func parseUpdateFileChunks(lines []string, startIdx, endIdx int) ([]UpdateFileChunk, int) {
	var chunks []UpdateFileChunk
	i := startIdx

	for i < endIdx && !strings.HasPrefix(lines[i], "***") {
		if strings.HasPrefix(lines[i], "@@") {
			// Parse context line
			contextLine := strings.TrimSpace(strings.TrimPrefix(lines[i], "@@"))
			i++

			var oldLines, newLines []string
			isEndOfFile := false

			// Parse change lines
			for i < endIdx && !strings.HasPrefix(lines[i], "@@") && !strings.HasPrefix(lines[i], "***") {
				changeLine := lines[i]

				if changeLine == "*** End of File" {
					isEndOfFile = true
					i++
					break
				}

				if strings.HasPrefix(changeLine, " ") {
					// Keep line - appears in both old and new
					content := changeLine[1:]
					oldLines = append(oldLines, content)
					newLines = append(newLines, content)
				} else if strings.HasPrefix(changeLine, "-") {
					// Remove line - only in old
					oldLines = append(oldLines, changeLine[1:])
				} else if strings.HasPrefix(changeLine, "+") {
					// Add line - only in new
					newLines = append(newLines, changeLine[1:])
				}

				i++
			}

			chunks = append(chunks, UpdateFileChunk{
				OldLines:      oldLines,
				NewLines:      newLines,
				ChangeContext: contextLine,
				IsEndOfFile:   isEndOfFile,
			})
		} else {
			i++
		}
	}

	return chunks, i
}

// deriveNewContentsFromChunks applies update chunks to a file
func deriveNewContentsFromChunks(filePath string, chunks []UpdateFileChunk) (string, error) {
	// Read original file
	content, err := os.ReadFile(filePath)
	if err != nil {
		return "", fmt.Errorf("failed to read file %s: %v", filePath, err)
	}

	originalLines := strings.Split(string(content), "\n")

	// Drop trailing empty element for consistent line counting
	if len(originalLines) > 0 && originalLines[len(originalLines)-1] == "" {
		originalLines = originalLines[:len(originalLines)-1]
	}

	replacements, err := computeReplacements(originalLines, filePath, chunks)
	if err != nil {
		return "", err
	}

	newLines := applyReplacements(originalLines, replacements)

	// Ensure trailing newline
	if len(newLines) == 0 || newLines[len(newLines)-1] != "" {
		newLines = append(newLines, "")
	}

	return strings.Join(newLines, "\n"), nil
}

// Replacement represents a line replacement operation
type Replacement struct {
	StartIdx   int
	OldLen     int
	NewSegment []string
}

// computeReplacements determines what replacements to make
func computeReplacements(originalLines []string, filePath string, chunks []UpdateFileChunk) ([]Replacement, error) {
	var replacements []Replacement
	lineIndex := 0

	for _, chunk := range chunks {
		// Handle context-based seeking
		if chunk.ChangeContext != "" {
			contextIdx := seekSequence(originalLines, []string{chunk.ChangeContext}, lineIndex)
			if contextIdx == -1 {
				return nil, fmt.Errorf("failed to find context '%s' in %s", chunk.ChangeContext, filePath)
			}
			lineIndex = contextIdx
		}

		// Handle pure addition (no old lines)
		if len(chunk.OldLines) == 0 {
			insertionIdx := len(originalLines)
			if len(originalLines) > 0 && originalLines[len(originalLines)-1] == "" {
				insertionIdx = len(originalLines) - 1
			}
			replacements = append(replacements, Replacement{
				StartIdx:   insertionIdx,
				OldLen:     0,
				NewSegment: chunk.NewLines,
			})
			continue
		}

		// Try to match old lines in the file
		pattern := chunk.OldLines
		newSlice := chunk.NewLines
		found := seekSequence(originalLines, pattern, lineIndex)

		// Retry without trailing empty line if not found
		if found == -1 && len(pattern) > 0 && pattern[len(pattern)-1] == "" {
			pattern = pattern[:len(pattern)-1]
			if len(newSlice) > 0 && newSlice[len(newSlice)-1] == "" {
				newSlice = newSlice[:len(newSlice)-1]
			}
			found = seekSequence(originalLines, pattern, lineIndex)
		}

		if found != -1 {
			replacements = append(replacements, Replacement{
				StartIdx:   found,
				OldLen:     len(pattern),
				NewSegment: newSlice,
			})
			lineIndex = found + len(pattern)
		} else {
			return nil, fmt.Errorf("failed to find expected lines in %s:\n%s",
				filePath, strings.Join(chunk.OldLines, "\n"))
		}
	}

	return replacements, nil
}

// applyReplacements applies a set of replacements to lines
func applyReplacements(lines []string, replacements []Replacement) []string {
	result := make([]string, len(lines))
	copy(result, lines)

	// Apply replacements in reverse order to avoid index shifting
	for i := len(replacements) - 1; i >= 0; i-- {
		r := replacements[i]

		// Build new slice: before + new segment + after
		before := result[:r.StartIdx]
		after := result[r.StartIdx+r.OldLen:]

		result = make([]string, 0, len(before)+len(r.NewSegment)+len(after))
		result = append(result, before...)
		result = append(result, r.NewSegment...)
		result = append(result, after...)
	}

	return result
}

// seekSequence finds the first occurrence of a pattern in lines starting from startIndex
func seekSequence(lines []string, pattern []string, startIndex int) int {
	if len(pattern) == 0 {
		return -1
	}

	// Try exact match first
	for i := startIndex; i <= len(lines)-len(pattern); i++ {
		matches := true

		for j := 0; j < len(pattern); j++ {
			if lines[i+j] != pattern[j] {
				matches = false
				break
			}
		}

		if matches {
			return i
		}
	}

	// If exact match fails, try trimmed match (more flexible)
	for i := startIndex; i <= len(lines)-len(pattern); i++ {
		matches := true

		for j := 0; j < len(pattern); j++ {
			if strings.TrimSpace(lines[i+j]) != strings.TrimSpace(pattern[j]) {
				matches = false
				break
			}
		}

		if matches {
			return i
		}
	}

	return -1
}

// FileChange represents a single file change for validation and diff generation
type FileChange struct {
	FilePath   string
	OldContent string
	NewContent string
	Type       string // "add", "update", "delete", "move"
	MovePath   string
}

// executePatch applies the patch
func executePatch(params map[string]interface{}, ctx ToolContext) (ToolResult, error) {
	patchText, ok := params["patchText"].(string)
	if !ok || patchText == "" {
		return ToolResult{}, fmt.Errorf("patchText parameter is required")
	}

	// Parse the patch
	hunks, err := parsePatch(patchText)
	if err != nil {
		return ToolResult{}, fmt.Errorf("failed to parse patch: %v", err)
	}

	// Get current working directory
	cwd, err := os.Getwd()
	if err != nil {
		return ToolResult{}, fmt.Errorf("failed to get working directory: %v", err)
	}

	// First pass: validate all operations and prepare file changes
	var fileChanges []FileChange
	var totalDiff strings.Builder

	for _, hunk := range hunks {
		switch h := hunk.(type) {
		case *AddHunk:
			filePath := filepath.Join(cwd, h.Path)

			// Validate that path is within working directory
			if !isPathWithinDirectory(filePath, cwd) {
				return ToolResult{}, fmt.Errorf("file %s is not in the current working directory", h.Path)
			}

			oldContent := ""
			newContent := h.Contents

			fileChanges = append(fileChanges, FileChange{
				FilePath:   filePath,
				OldContent: oldContent,
				NewContent: newContent,
				Type:       "add",
			})

			// Generate diff for metadata
			diff := generateDiff(filePath, oldContent, newContent)
			totalDiff.WriteString(diff)
			totalDiff.WriteString("\n")

		case *DeleteHunk:
			filePath := filepath.Join(cwd, h.Path)

			// Validate that path is within working directory
			if !isPathWithinDirectory(filePath, cwd) {
				return ToolResult{}, fmt.Errorf("file %s is not in the current working directory", h.Path)
			}

			// Check if file exists and read content
			fileInfo, err := os.Stat(filePath)
			if err != nil {
				if os.IsNotExist(err) {
					return ToolResult{}, fmt.Errorf("file not found or is directory: %s", filePath)
				}
				return ToolResult{}, fmt.Errorf("failed to stat file %s: %v", h.Path, err)
			}

			if fileInfo.IsDir() {
				return ToolResult{}, fmt.Errorf("file not found or is directory: %s", filePath)
			}

			oldContent, err := os.ReadFile(filePath)
			if err != nil {
				return ToolResult{}, fmt.Errorf("failed to read file for deletion %s: %v", h.Path, err)
			}

			fileChanges = append(fileChanges, FileChange{
				FilePath:   filePath,
				OldContent: string(oldContent),
				NewContent: "",
				Type:       "delete",
			})

			// Generate diff for metadata
			diff := generateDiff(filePath, string(oldContent), "")
			totalDiff.WriteString(diff)
			totalDiff.WriteString("\n")

		case *UpdateHunk:
			filePath := filepath.Join(cwd, h.Path)

			// Validate that path is within working directory
			if !isPathWithinDirectory(filePath, cwd) {
				return ToolResult{}, fmt.Errorf("file %s is not in the current working directory", h.Path)
			}

			// Check if file exists
			fileInfo, err := os.Stat(filePath)
			if err != nil {
				if os.IsNotExist(err) {
					return ToolResult{}, fmt.Errorf("file not found or is directory: %s", filePath)
				}
				return ToolResult{}, fmt.Errorf("failed to stat file %s: %v", h.Path, err)
			}

			if fileInfo.IsDir() {
				return ToolResult{}, fmt.Errorf("file not found or is directory: %s", filePath)
			}

			oldContent, err := os.ReadFile(filePath)
			if err != nil {
				return ToolResult{}, fmt.Errorf("failed to read file %s: %v", h.Path, err)
			}

			// Apply chunks to get new content
			newContent, err := deriveNewContentsFromChunks(filePath, h.Chunks)
			if err != nil {
				return ToolResult{}, fmt.Errorf("failed to apply update to %s: %v", h.Path, err)
			}

			changeType := "update"
			movePath := ""
			if h.MovePath != "" {
				changeType = "move"
				movePath = filepath.Join(cwd, h.MovePath)

				// Validate move destination is within working directory
				if !isPathWithinDirectory(movePath, cwd) {
					return ToolResult{}, fmt.Errorf("move destination %s is not in the current working directory", h.MovePath)
				}
			}

			fileChanges = append(fileChanges, FileChange{
				FilePath:   filePath,
				OldContent: string(oldContent),
				NewContent: newContent,
				Type:       changeType,
				MovePath:   movePath,
			})

			// Generate diff for metadata
			diff := generateDiff(filePath, string(oldContent), newContent)
			totalDiff.WriteString(diff)
			totalDiff.WriteString("\n")
		}
	}

	// Second pass: apply all changes
	var changedFiles []string

	for _, change := range fileChanges {
		switch change.Type {
		case "add":
			// Create parent directories
			dir := filepath.Dir(change.FilePath)
			if err := os.MkdirAll(dir, 0755); err != nil {
				return ToolResult{}, fmt.Errorf("failed to create directory for %s: %v", change.FilePath, err)
			}

			// Write file
			if err := os.WriteFile(change.FilePath, []byte(change.NewContent), 0644); err != nil {
				return ToolResult{}, fmt.Errorf("failed to write %s: %v", change.FilePath, err)
			}

			changedFiles = append(changedFiles, change.FilePath)

		case "update":
			// Write updated content
			if err := os.WriteFile(change.FilePath, []byte(change.NewContent), 0644); err != nil {
				return ToolResult{}, fmt.Errorf("failed to write updated file %s: %v", change.FilePath, err)
			}

			changedFiles = append(changedFiles, change.FilePath)

		case "move":
			// Create parent directories for destination
			dir := filepath.Dir(change.MovePath)
			if err := os.MkdirAll(dir, 0755); err != nil {
				return ToolResult{}, fmt.Errorf("failed to create directory for move %s: %v", change.MovePath, err)
			}

			// Write to new location
			if err := os.WriteFile(change.MovePath, []byte(change.NewContent), 0644); err != nil {
				return ToolResult{}, fmt.Errorf("failed to write moved file %s: %v", change.MovePath, err)
			}

			// Remove original
			if err := os.Remove(change.FilePath); err != nil {
				return ToolResult{}, fmt.Errorf("failed to remove original file %s: %v", change.FilePath, err)
			}

			changedFiles = append(changedFiles, change.MovePath)

		case "delete":
			// Delete file
			if err := os.Remove(change.FilePath); err != nil {
				return ToolResult{}, fmt.Errorf("failed to delete %s: %v", change.FilePath, err)
			}

			changedFiles = append(changedFiles, change.FilePath)
		}
	}

	// Generate relative paths for output
	var relativePaths []string
	for _, filePath := range changedFiles {
		relPath, err := filepath.Rel(cwd, filePath)
		if err != nil {
			relPath = filePath
		}
		relativePaths = append(relativePaths, relPath)
	}

	// Generate output
	summary := fmt.Sprintf("%d files changed", len(fileChanges))
	output := fmt.Sprintf("Patch applied successfully. %s:\n", summary)
	for _, relPath := range relativePaths {
		output += fmt.Sprintf("  %s\n", relPath)
	}

	result := ToolResult{
		Title:  summary,
		Output: output,
		Metadata: map[string]interface{}{
			"diff": totalDiff.String(),
		},
	}

	return result, nil
}

// isPathWithinDirectory checks if a path is within a given directory
func isPathWithinDirectory(filePath, dir string) bool {
	absFilePath, err := filepath.Abs(filePath)
	if err != nil {
		return false
	}

	absDir, err := filepath.Abs(dir)
	if err != nil {
		return false
	}

	// Clean both paths to normalize them
	absFilePath = filepath.Clean(absFilePath)
	absDir = filepath.Clean(absDir)

	// Check if filePath starts with dir
	rel, err := filepath.Rel(absDir, absFilePath)
	if err != nil {
		return false
	}

	// If the relative path starts with "..", it's outside the directory
	return !strings.HasPrefix(rel, ".."+string(filepath.Separator)) && rel != ".."
}

// generateDiff creates a simple unified diff between old and new content
func generateDiff(filePath, oldContent, newContent string) string {
	var diff strings.Builder

	diff.WriteString(fmt.Sprintf("--- %s\n", filePath))
	diff.WriteString(fmt.Sprintf("+++ %s\n", filePath))
	diff.WriteString("@@ -1 +1 @@\n")

	oldLines := strings.Split(oldContent, "\n")
	newLines := strings.Split(newContent, "\n")

	maxLen := len(oldLines)
	if len(newLines) > maxLen {
		maxLen = len(newLines)
	}

	for i := 0; i < maxLen; i++ {
		var oldLine, newLine string
		if i < len(oldLines) {
			oldLine = oldLines[i]
		}
		if i < len(newLines) {
			newLine = newLines[i]
		}

		if oldLine != newLine {
			if oldLine != "" {
				diff.WriteString(fmt.Sprintf("-%s\n", oldLine))
			}
			if newLine != "" {
				diff.WriteString(fmt.Sprintf("+%s\n", newLine))
			}
		} else if oldLine != "" {
			diff.WriteString(fmt.Sprintf(" %s\n", oldLine))
		}
	}

	return diff.String()
}

// MaybeApplyPatchResult represents the result of trying to parse an apply_patch command
type MaybeApplyPatchResult struct {
	Type   string // "Body", "PatchParseError", "NotApplyPatch"
	Patch  string
	Hunks  []Hunk
	Error  error
}

// MaybeParseApplyPatch attempts to detect and parse apply_patch commands
func MaybeParseApplyPatch(argv []string) MaybeApplyPatchResult {
	applyPatchCommands := []string{"apply_patch", "applypatch"}

	// Direct invocation: apply_patch <patch>
	if len(argv) == 2 {
		for _, cmd := range applyPatchCommands {
			if argv[0] == cmd {
				hunks, err := parsePatch(argv[1])
				if err != nil {
					return MaybeApplyPatchResult{
						Type:  "PatchParseError",
						Error: err,
					}
				}
				return MaybeApplyPatchResult{
					Type:  "Body",
					Patch: argv[1],
					Hunks: hunks,
				}
			}
		}
	}

	// Bash heredoc form: bash -lc 'apply_patch <<"EOF" ...'
	if len(argv) == 3 && argv[0] == "bash" && argv[1] == "-lc" {
		// Extract heredoc content using regex
		script := argv[2]
		heredocRegex := regexp.MustCompile(`apply_patch\s*<<['"]?(\w+)['"]?\s*\n([\s\S]*?)\n\1`)
		matches := heredocRegex.FindStringSubmatch(script)

		if matches != nil && len(matches) >= 3 {
			patchContent := matches[2]
			hunks, err := parsePatch(patchContent)
			if err != nil {
				return MaybeApplyPatchResult{
					Type:  "PatchParseError",
					Error: err,
				}
			}
			return MaybeApplyPatchResult{
				Type:  "Body",
				Patch: patchContent,
				Hunks: hunks,
			}
		}
	}

	return MaybeApplyPatchResult{
		Type: "NotApplyPatch",
	}
}

// ApplyPatchFileChange represents a validated file change ready to be applied
type ApplyPatchFileChange struct {
	Type        string // "add", "delete", "update"
	Content     string
	UnifiedDiff string
	MovePath    string
	NewContent  string
}

// MaybeApplyPatchVerifiedResult represents the result of validating an apply_patch command
type MaybeApplyPatchVerifiedResult struct {
	Type    string // "Body", "CorrectnessError", "NotApplyPatch"
	Changes map[string]*ApplyPatchFileChange
	Patch   string
	Cwd     string
	Error   error
}

// MaybeParseApplyPatchVerified attempts to parse and verify an apply_patch command
func MaybeParseApplyPatchVerified(argv []string, cwd string) MaybeApplyPatchVerifiedResult {
	// Detect implicit patch invocation (raw patch without apply_patch command)
	if len(argv) == 1 {
		_, err := parsePatch(argv[0])
		if err == nil {
			// It's a valid patch but called implicitly - this is an error
			return MaybeApplyPatchVerifiedResult{
				Type:  "CorrectnessError",
				Error: fmt.Errorf("implicit invocation: patch must be invoked with apply_patch command"),
			}
		}
		// Not a patch, continue
	}

	result := MaybeParseApplyPatch(argv)

	switch result.Type {
	case "Body":
		effectiveCwd := cwd
		changes := make(map[string]*ApplyPatchFileChange)

		for _, hunk := range result.Hunks {
			var resolvedPath string
			var change *ApplyPatchFileChange

			switch h := hunk.(type) {
			case *AddHunk:
				resolvedPath = filepath.Join(effectiveCwd, h.Path)
				change = &ApplyPatchFileChange{
					Type:    "add",
					Content: h.Contents,
				}

			case *DeleteHunk:
				resolvedPath = filepath.Join(effectiveCwd, h.Path)
				deletePath := resolvedPath

				content, err := os.ReadFile(deletePath)
				if err != nil {
					return MaybeApplyPatchVerifiedResult{
						Type:  "CorrectnessError",
						Error: fmt.Errorf("failed to read file for deletion: %s: %v", deletePath, err),
					}
				}

				change = &ApplyPatchFileChange{
					Type:    "delete",
					Content: string(content),
				}

			case *UpdateHunk:
				updatePath := filepath.Join(effectiveCwd, h.Path)

				newContent, err := deriveNewContentsFromChunks(updatePath, h.Chunks)
				if err != nil {
					return MaybeApplyPatchVerifiedResult{
						Type:  "CorrectnessError",
						Error: fmt.Errorf("failed to apply update to %s: %v", updatePath, err),
					}
				}

				oldContent, err := os.ReadFile(updatePath)
				if err != nil {
					return MaybeApplyPatchVerifiedResult{
						Type:  "CorrectnessError",
						Error: fmt.Errorf("failed to read file for update: %s: %v", updatePath, err),
					}
				}

				unifiedDiff := generateDiff(updatePath, string(oldContent), newContent)

				if h.MovePath != "" {
					resolvedPath = filepath.Join(effectiveCwd, h.MovePath)
					change = &ApplyPatchFileChange{
						Type:        "update",
						UnifiedDiff: unifiedDiff,
						MovePath:    resolvedPath,
						NewContent:  newContent,
					}
				} else {
					resolvedPath = updatePath
					change = &ApplyPatchFileChange{
						Type:        "update",
						UnifiedDiff: unifiedDiff,
						NewContent:  newContent,
					}
				}
			}

			if change != nil {
				changes[resolvedPath] = change
			}
		}

		return MaybeApplyPatchVerifiedResult{
			Type:    "Body",
			Changes: changes,
			Patch:   result.Patch,
			Cwd:     effectiveCwd,
		}

	case "PatchParseError":
		return MaybeApplyPatchVerifiedResult{
			Type:  "CorrectnessError",
			Error: result.Error,
		}

	case "NotApplyPatch":
		return MaybeApplyPatchVerifiedResult{
			Type: "NotApplyPatch",
		}
	}

	return MaybeApplyPatchVerifiedResult{
		Type: "NotApplyPatch",
	}
}

// ApplyHunksToFiles applies a list of hunks directly to the filesystem
func ApplyHunksToFiles(hunks []Hunk, cwd string) (added []string, modified []string, deleted []string, err error) {
	if len(hunks) == 0 {
		return nil, nil, nil, fmt.Errorf("no files were modified")
	}

	for _, hunk := range hunks {
		switch h := hunk.(type) {
		case *AddHunk:
			filePath := filepath.Join(cwd, h.Path)

			// Create parent directories
			dir := filepath.Dir(filePath)
			if dir != "." && dir != "/" {
				if err := os.MkdirAll(dir, 0755); err != nil {
					return nil, nil, nil, fmt.Errorf("failed to create directory for %s: %v", h.Path, err)
				}
			}

			if err := os.WriteFile(filePath, []byte(h.Contents), 0644); err != nil {
				return nil, nil, nil, fmt.Errorf("failed to write added file %s: %v", h.Path, err)
			}

			added = append(added, filePath)

		case *DeleteHunk:
			filePath := filepath.Join(cwd, h.Path)

			if err := os.Remove(filePath); err != nil {
				return nil, nil, nil, fmt.Errorf("failed to delete file %s: %v", h.Path, err)
			}

			deleted = append(deleted, filePath)

		case *UpdateHunk:
			filePath := filepath.Join(cwd, h.Path)

			newContent, err := deriveNewContentsFromChunks(filePath, h.Chunks)
			if err != nil {
				return nil, nil, nil, fmt.Errorf("failed to derive new contents for %s: %v", h.Path, err)
			}

			if h.MovePath != "" {
				// Handle file move
				newPath := filepath.Join(cwd, h.MovePath)
				dir := filepath.Dir(newPath)
				if dir != "." && dir != "/" {
					if err := os.MkdirAll(dir, 0755); err != nil {
						return nil, nil, nil, fmt.Errorf("failed to create directory for move %s: %v", h.MovePath, err)
					}
				}

				if err := os.WriteFile(newPath, []byte(newContent), 0644); err != nil {
					return nil, nil, nil, fmt.Errorf("failed to write moved file %s: %v", h.MovePath, err)
				}

				if err := os.Remove(filePath); err != nil {
					return nil, nil, nil, fmt.Errorf("failed to remove original file %s: %v", h.Path, err)
				}

				modified = append(modified, newPath)
			} else {
				// Regular update
				if err := os.WriteFile(filePath, []byte(newContent), 0644); err != nil {
					return nil, nil, nil, fmt.Errorf("failed to write updated file %s: %v", h.Path, err)
				}

				modified = append(modified, filePath)
			}
		}
	}

	return added, modified, deleted, nil
}

// ApplyPatch is a convenience function to parse and apply a patch in one call
func ApplyPatch(patchText string, cwd string) (added []string, modified []string, deleted []string, err error) {
	hunks, err := parsePatch(patchText)
	if err != nil {
		return nil, nil, nil, fmt.Errorf("failed to parse patch: %v", err)
	}

	return ApplyHunksToFiles(hunks, cwd)
}
