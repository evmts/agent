package tool

import (
	"fmt"
	"os"
	"path/filepath"
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
			lineIndex = contextIdx + 1
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

	return -1
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

	// Apply hunks
	var changedFiles []string
	var errors []string

	for _, hunk := range hunks {
		switch h := hunk.(type) {
		case *AddHunk:
			filePath := filepath.Join(cwd, h.Path)

			// Create parent directories
			dir := filepath.Dir(filePath)
			if err := os.MkdirAll(dir, 0755); err != nil {
				errors = append(errors, fmt.Sprintf("failed to create directory for %s: %v", h.Path, err))
				continue
			}

			// Write file
			if err := os.WriteFile(filePath, []byte(h.Contents), 0644); err != nil {
				errors = append(errors, fmt.Sprintf("failed to write %s: %v", h.Path, err))
				continue
			}

			changedFiles = append(changedFiles, h.Path)

		case *DeleteHunk:
			filePath := filepath.Join(cwd, h.Path)

			// Check if file exists
			if _, err := os.Stat(filePath); os.IsNotExist(err) {
				errors = append(errors, fmt.Sprintf("file not found for deletion: %s", h.Path))
				continue
			}

			// Delete file
			if err := os.Remove(filePath); err != nil {
				errors = append(errors, fmt.Sprintf("failed to delete %s: %v", h.Path, err))
				continue
			}

			changedFiles = append(changedFiles, h.Path)

		case *UpdateHunk:
			filePath := filepath.Join(cwd, h.Path)

			// Check if file exists
			if _, err := os.Stat(filePath); os.IsNotExist(err) {
				errors = append(errors, fmt.Sprintf("file not found for update: %s", h.Path))
				continue
			}

			// Apply chunks to get new content
			newContent, err := deriveNewContentsFromChunks(filePath, h.Chunks)
			if err != nil {
				errors = append(errors, fmt.Sprintf("failed to apply update to %s: %v", h.Path, err))
				continue
			}

			if h.MovePath != "" {
				// Handle file move
				newPath := filepath.Join(cwd, h.MovePath)
				newDir := filepath.Dir(newPath)

				if err := os.MkdirAll(newDir, 0755); err != nil {
					errors = append(errors, fmt.Sprintf("failed to create directory for move %s: %v", h.MovePath, err))
					continue
				}

				// Write to new location
				if err := os.WriteFile(newPath, []byte(newContent), 0644); err != nil {
					errors = append(errors, fmt.Sprintf("failed to write moved file %s: %v", h.MovePath, err))
					continue
				}

				// Remove original
				if err := os.Remove(filePath); err != nil {
					errors = append(errors, fmt.Sprintf("failed to remove original file %s: %v", h.Path, err))
					continue
				}

				changedFiles = append(changedFiles, h.MovePath)
			} else {
				// Regular update
				if err := os.WriteFile(filePath, []byte(newContent), 0644); err != nil {
					errors = append(errors, fmt.Sprintf("failed to write updated file %s: %v", h.Path, err))
					continue
				}

				changedFiles = append(changedFiles, h.Path)
			}
		}
	}

	// Generate output
	var output strings.Builder
	if len(errors) > 0 {
		output.WriteString("Patch applied with errors:\n\n")
		output.WriteString("Errors:\n")
		for _, err := range errors {
			output.WriteString(fmt.Sprintf("  - %s\n", err))
		}
		output.WriteString("\n")
	}

	if len(changedFiles) > 0 {
		output.WriteString(fmt.Sprintf("Successfully modified %d file(s):\n", len(changedFiles)))
		for _, file := range changedFiles {
			output.WriteString(fmt.Sprintf("  %s\n", file))
		}
	} else {
		output.WriteString("No files were modified.\n")
	}

	title := fmt.Sprintf("%d files changed", len(changedFiles))
	if len(errors) > 0 {
		title += fmt.Sprintf(" (%d errors)", len(errors))
	}

	result := ToolResult{
		Title:  title,
		Output: output.String(),
		Metadata: map[string]interface{}{
			"files_changed": len(changedFiles),
			"errors":        len(errors),
		},
	}

	if len(errors) > 0 && len(changedFiles) == 0 {
		result.Error = fmt.Errorf("patch failed with %d errors", len(errors))
	}

	return result, nil
}
