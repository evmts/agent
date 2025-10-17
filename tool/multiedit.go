package tool

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// MultiEditTool creates the multi-edit tool for making multiple edits to a single file
func MultiEditTool() *ToolDefinition {
	return &ToolDefinition{
		ID:   "multiedit",
		Name: "multiedit",
		Description: `This is a tool for making multiple edits to a single file in one operation. It allows you to perform multiple find-and-replace operations efficiently. Prefer this tool over the Edit tool when you need to make multiple edits to the same file.

Before using this tool:

1. Use the Read tool to understand the file's contents and context
2. Verify the directory path is correct

To make multiple file edits, provide the following:
1. file_path: The absolute path to the file to modify (must be absolute, not relative)
2. edits: An array of edit operations to perform, where each edit contains:
   - old_string: The text to replace (must match the file contents exactly, including all whitespace and indentation)
   - new_string: The edited text to replace the old_string
   - replace_all: Replace all occurrences of old_string. This parameter is optional and defaults to false.

IMPORTANT:
- All edits are applied in sequence, in the order they are provided
- Each edit operates on the result of the previous edit
- All edits must be valid for the operation to succeed - if any edit fails, none will be applied
- This tool is ideal when you need to make several changes to different parts of the same file

CRITICAL REQUIREMENTS:
1. All edits follow the same requirements as the single Edit tool
2. The edits are atomic - either all succeed or none are applied
3. Plan your edits carefully to avoid conflicts between sequential operations

WARNING:
- The tool will fail if old_string doesn't match the file contents exactly (including whitespace)
- The tool will fail if old_string and new_string are the same
- Since edits are applied in sequence, ensure that earlier edits don't affect the text that later edits are trying to find

When making edits:
- Ensure all edits result in idiomatic, correct code
- Do not leave the code in a broken state
- Always use absolute file paths (starting with /)
- Only use emojis if the user explicitly requests it. Avoid adding emojis to files unless asked.
- Use replace_all for replacing and renaming strings across the file. This parameter is useful if you want to rename a variable for instance.`,
		InputSchema: map[string]interface{}{
			"type": "object",
			"properties": map[string]interface{}{
				"file_path": map[string]interface{}{
					"type":        "string",
					"description": "The absolute path to the file to modify",
				},
				"edits": map[string]interface{}{
					"type":        "array",
					"description": "Array of edit operations to perform sequentially on the file",
					"items": map[string]interface{}{
						"type": "object",
						"properties": map[string]interface{}{
							"old_string": map[string]interface{}{
								"type":        "string",
								"description": "The text to replace",
							},
							"new_string": map[string]interface{}{
								"type":        "string",
								"description": "The text to replace it with (must be different from old_string)",
							},
							"replace_all": map[string]interface{}{
								"type":        "boolean",
								"description": "Replace all occurrences of old_string (default false)",
							},
						},
						"required": []string{"old_string", "new_string"},
					},
				},
			},
			"required": []string{"file_path", "edits"},
		},
		Execute: executeMultiEdit,
	}
}

// EditOperation represents a single edit operation
type EditOperation struct {
	OldString  string
	NewString  string
	ReplaceAll bool
}

func executeMultiEdit(params map[string]interface{}, ctx ToolContext) (ToolResult, error) {
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

	// Parse edits array
	editsParam, ok := params["edits"].([]interface{})
	if !ok {
		return ToolResult{}, fmt.Errorf("edits parameter is required and must be an array")
	}

	if len(editsParam) == 0 {
		return ToolResult{}, fmt.Errorf("edits array cannot be empty")
	}

	// Convert to EditOperation structs
	var edits []EditOperation
	for i, editInterface := range editsParam {
		editMap, ok := editInterface.(map[string]interface{})
		if !ok {
			return ToolResult{}, fmt.Errorf("edit at index %d is not a valid object", i)
		}

		oldString, ok := editMap["old_string"].(string)
		if !ok {
			return ToolResult{}, fmt.Errorf("edit at index %d is missing old_string", i)
		}

		newString, ok := editMap["new_string"].(string)
		if !ok {
			return ToolResult{}, fmt.Errorf("edit at index %d is missing new_string", i)
		}

		if oldString == newString {
			return ToolResult{}, fmt.Errorf("edit at index %d has identical old_string and new_string", i)
		}

		replaceAll := false
		if replaceAllParam, ok := editMap["replace_all"].(bool); ok {
			replaceAll = replaceAllParam
		}

		edits = append(edits, EditOperation{
			OldString:  oldString,
			NewString:  newString,
			ReplaceAll: replaceAll,
		})
	}

	// Read the file
	content, err := os.ReadFile(filePath)
	if err != nil {
		if os.IsNotExist(err) {
			// If file doesn't exist and first edit has empty old_string, create new file
			if edits[0].OldString == "" {
				content = []byte{}
			} else {
				return ToolResult{}, fmt.Errorf("file not found: %s", filePath)
			}
		} else {
			return ToolResult{}, fmt.Errorf("failed to read file: %v", err)
		}
	}

	// Check if path is a directory
	info, err := os.Stat(filePath)
	if err == nil && info.IsDir() {
		return ToolResult{}, fmt.Errorf("path is a directory, not a file: %s", filePath)
	}

	// Apply edits sequentially
	currentContent := string(content)
	var editResults []string

	for i, edit := range edits {
		newContent, err := applyEdit(currentContent, edit)
		if err != nil {
			return ToolResult{}, fmt.Errorf("edit %d failed: %v", i+1, err)
		}
		currentContent = newContent
		editResults = append(editResults, fmt.Sprintf("Edit %d: Applied successfully", i+1))
	}

	// Write the modified content back to the file
	err = os.WriteFile(filePath, []byte(currentContent), 0644)
	if err != nil {
		return ToolResult{}, fmt.Errorf("failed to write file: %v", err)
	}

	// Get relative path for title if possible
	cwd, _ := os.Getwd()
	relPath, err := filepath.Rel(cwd, filePath)
	if err != nil {
		relPath = filePath
	}

	output := fmt.Sprintf("Successfully applied %d edit(s) to %s\n\n%s",
		len(edits), relPath, strings.Join(editResults, "\n"))

	return ToolResult{
		Title:  relPath,
		Output: output,
		Metadata: map[string]interface{}{
			"file_path":   filePath,
			"edits_count": len(edits),
		},
	}, nil
}

// applyEdit applies a single edit operation to the content
func applyEdit(content string, edit EditOperation) (string, error) {
	// Handle file creation case (empty old_string)
	if edit.OldString == "" {
		if content != "" {
			return "", fmt.Errorf("old_string is empty but file already has content")
		}
		return edit.NewString, nil
	}

	// Check if old_string exists in content
	if !strings.Contains(content, edit.OldString) {
		return "", fmt.Errorf("old_string not found in content")
	}

	// Count occurrences
	count := strings.Count(content, edit.OldString)

	if edit.ReplaceAll {
		// Replace all occurrences
		return strings.ReplaceAll(content, edit.OldString, edit.NewString), nil
	}

	// For single replacement, ensure uniqueness
	if count > 1 {
		return "", fmt.Errorf("old_string found %d times, use replace_all: true or provide more context to make it unique", count)
	}

	// Replace single occurrence
	return strings.Replace(content, edit.OldString, edit.NewString, 1), nil
}
