package tool

import (
	"fmt"
	"math"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

// EditTool creates the file editing tool
func EditTool() *ToolDefinition {
	return &ToolDefinition{
		ID:   "edit",
		Name: "edit",
		Description: `Performs exact string replacements in files.

Usage:
- You must use your Read tool at least once in the conversation before editing. This tool will error if you attempt an edit without reading the file.
- When editing text from Read tool output, ensure you preserve the exact indentation (tabs/spaces) as it appears AFTER the line number prefix. The line number prefix format is: spaces + line number + tab. Everything after that tab is the actual file content to match. Never include any part of the line number prefix in the oldString or newString.
- ALWAYS prefer editing existing files in the codebase. NEVER write new files unless explicitly required.
- Only use emojis if the user explicitly requests it. Avoid adding emojis to files unless asked.
- The edit will FAIL if oldString is not found in the file with an error "oldString not found in content".
- The edit will FAIL if oldString is found multiple times in the file with an error "oldString found multiple times and requires more code context to uniquely identify the intended match". Either provide a larger string with more surrounding context to make it unique or use replaceAll to change every instance of oldString.
- Use replaceAll for replacing and renaming strings across the file. This parameter is useful if you want to rename a variable for instance.`,
		InputSchema: map[string]interface{}{
			"type": "object",
			"properties": map[string]interface{}{
				"file_path": map[string]interface{}{
					"type":        "string",
					"description": "The absolute path to the file to modify",
				},
				"old_string": map[string]interface{}{
					"type":        "string",
					"description": "The text to replace",
				},
				"new_string": map[string]interface{}{
					"type":        "string",
					"description": "The text to replace it with (must be different from oldString)",
				},
				"replace_all": map[string]interface{}{
					"type":        "boolean",
					"description": "Replace all occurrences of oldString (default false)",
				},
			},
			"required": []string{"file_path", "old_string", "new_string"},
		},
		Execute: executeEdit,
	}
}

func executeEdit(params map[string]interface{}, ctx ToolContext) (ToolResult, error) {
	filePath, ok := params["file_path"].(string)
	if !ok {
		return ToolResult{}, fmt.Errorf("file_path parameter is required")
	}

	oldString, ok := params["old_string"].(string)
	if !ok {
		return ToolResult{}, fmt.Errorf("old_string parameter is required")
	}

	newString, ok := params["new_string"].(string)
	if !ok {
		return ToolResult{}, fmt.Errorf("new_string parameter is required")
	}

	if oldString == newString {
		return ToolResult{}, fmt.Errorf("oldString and newString must be different")
	}

	replaceAll := false
	if replaceAllParam, ok := params["replace_all"].(bool); ok {
		replaceAll = replaceAllParam
	}

	// Make path absolute if it isn't
	if !filepath.IsAbs(filePath) {
		cwd, err := os.Getwd()
		if err != nil {
			return ToolResult{}, fmt.Errorf("failed to get current directory: %v", err)
		}
		filePath = filepath.Join(cwd, filePath)
	}

	// Verify file is within working directory
	cwd, err := os.Getwd()
	if err != nil {
		return ToolResult{}, fmt.Errorf("failed to get current directory: %v", err)
	}

	absFilePath, err := filepath.Abs(filePath)
	if err != nil {
		return ToolResult{}, fmt.Errorf("failed to resolve file path: %v", err)
	}

	absCwd, err := filepath.Abs(cwd)
	if err != nil {
		return ToolResult{}, fmt.Errorf("failed to resolve working directory: %v", err)
	}

	relPath, err := filepath.Rel(absCwd, absFilePath)
	if err != nil || strings.HasPrefix(relPath, "..") {
		return ToolResult{}, fmt.Errorf("file %s is not in the current working directory", filePath)
	}

	var contentOld, contentNew string
	var diff string

	// Handle empty oldString case (create new file)
	if oldString == "" {
		contentNew = newString
		diff = createDiff(filePath, contentOld, contentNew)

		// Write new file
		err = os.WriteFile(absFilePath, []byte(contentNew), 0644)
		if err != nil {
			return ToolResult{}, fmt.Errorf("failed to write file: %v", err)
		}

		return ToolResult{
			Title:  relPath,
			Output: "",
			Metadata: map[string]interface{}{
				"filePath": absFilePath,
				"diff":     diff,
			},
		}, nil
	}

	// Check if file exists
	info, err := os.Stat(absFilePath)
	if err != nil {
		if os.IsNotExist(err) {
			return ToolResult{}, fmt.Errorf("file not found: %s", absFilePath)
		}
		return ToolResult{}, fmt.Errorf("failed to stat file: %v", err)
	}

	if info.IsDir() {
		return ToolResult{}, fmt.Errorf("path is a directory, not a file: %s", absFilePath)
	}

	// Read the file content
	contentBytes, err := os.ReadFile(absFilePath)
	if err != nil {
		return ToolResult{}, fmt.Errorf("failed to read file: %v", err)
	}
	contentOld = string(contentBytes)

	// Perform the replacement using multiple strategies
	contentNew, err = replace(contentOld, oldString, newString, replaceAll)
	if err != nil {
		return ToolResult{}, err
	}

	// Generate diff before writing
	diff = createDiff(filePath, contentOld, contentNew)

	// Write the new content back to the file
	err = os.WriteFile(absFilePath, []byte(contentNew), info.Mode())
	if err != nil {
		return ToolResult{}, fmt.Errorf("failed to write file: %v", err)
	}

	// Re-read to ensure diff accuracy after write
	contentBytes, err = os.ReadFile(absFilePath)
	if err == nil {
		contentNew = string(contentBytes)
		diff = createDiff(filePath, contentOld, contentNew)
	}

	return ToolResult{
		Title:  relPath,
		Output: "",
		Metadata: map[string]interface{}{
			"filePath": absFilePath,
			"diff":     diff,
		},
	}, nil
}

// replace performs the string replacement using multiple fallback strategies
func replace(content, oldString, newString string, replaceAll bool) (string, error) {
	if oldString == newString {
		return "", fmt.Errorf("oldString and newString must be different")
	}

	notFound := true

	// Try replacers in order
	replacers := []func(string, string) []string{
		simpleReplacer,
		lineTrimmedReplacer,
		blockAnchorReplacer,
		whitespaceNormalizedReplacer,
		indentationFlexibleReplacer,
		escapeNormalizedReplacer,
		trimmedBoundaryReplacer,
		contextAwareReplacer,
		multiOccurrenceReplacer,
	}

	for _, replacer := range replacers {
		matches := replacer(content, oldString)
		for _, search := range matches {
			index := strings.Index(content, search)
			if index == -1 {
				continue
			}
			notFound = false

			if replaceAll {
				return strings.ReplaceAll(content, search, newString), nil
			}

			lastIndex := strings.LastIndex(content, search)
			if index != lastIndex {
				continue
			}

			return content[:index] + newString + content[index+len(search):], nil
		}
	}

	if notFound {
		return "", fmt.Errorf("oldString not found in content")
	}

	return "", fmt.Errorf("oldString found multiple times and requires more code context to uniquely identify the intended match")
}

// simpleReplacer tries to find exact matches
func simpleReplacer(content, find string) []string {
	if strings.Contains(content, find) {
		return []string{find}
	}
	return nil
}

// lineTrimmedReplacer matches lines with trimmed whitespace
func lineTrimmedReplacer(content, find string) []string {
	originalLines := strings.Split(content, "\n")
	searchLines := strings.Split(find, "\n")

	if len(searchLines) > 0 && searchLines[len(searchLines)-1] == "" {
		searchLines = searchLines[:len(searchLines)-1]
	}

	var matches []string

	for i := 0; i <= len(originalLines)-len(searchLines); i++ {
		allMatch := true

		for j := 0; j < len(searchLines); j++ {
			originalTrimmed := strings.TrimSpace(originalLines[i+j])
			searchTrimmed := strings.TrimSpace(searchLines[j])

			if originalTrimmed != searchTrimmed {
				allMatch = false
				break
			}
		}

		if allMatch {
			matchStartIndex := 0
			for k := 0; k < i; k++ {
				matchStartIndex += len(originalLines[k]) + 1
			}

			matchEndIndex := matchStartIndex
			for k := 0; k < len(searchLines); k++ {
				matchEndIndex += len(originalLines[i+k])
				if k < len(searchLines)-1 {
					matchEndIndex++
				}
			}

			matches = append(matches, content[matchStartIndex:matchEndIndex])
		}
	}

	return matches
}

// blockAnchorReplacer matches blocks using first and last line anchors
func blockAnchorReplacer(content, find string) []string {
	originalLines := strings.Split(content, "\n")
	searchLines := strings.Split(find, "\n")

	if len(searchLines) < 3 {
		return nil
	}

	if len(searchLines) > 0 && searchLines[len(searchLines)-1] == "" {
		searchLines = searchLines[:len(searchLines)-1]
	}

	firstLineSearch := strings.TrimSpace(searchLines[0])
	lastLineSearch := strings.TrimSpace(searchLines[len(searchLines)-1])
	searchBlockSize := len(searchLines)

	// Collect all candidate positions
	type candidate struct {
		startLine int
		endLine   int
	}
	var candidates []candidate

	for i := 0; i < len(originalLines); i++ {
		if strings.TrimSpace(originalLines[i]) != firstLineSearch {
			continue
		}

		for j := i + 2; j < len(originalLines); j++ {
			if strings.TrimSpace(originalLines[j]) == lastLineSearch {
				candidates = append(candidates, candidate{startLine: i, endLine: j})
				break
			}
		}
	}

	if len(candidates) == 0 {
		return nil
	}

	// Single candidate with relaxed threshold
	if len(candidates) == 1 {
		c := candidates[0]
		actualBlockSize := c.endLine - c.startLine + 1

		similarity := 0.0
		linesToCheck := min(searchBlockSize-2, actualBlockSize-2)

		if linesToCheck > 0 {
			for j := 1; j < searchBlockSize-1 && j < actualBlockSize-1; j++ {
				originalLine := strings.TrimSpace(originalLines[c.startLine+j])
				searchLine := strings.TrimSpace(searchLines[j])
				maxLen := max(len(originalLine), len(searchLine))
				if maxLen == 0 {
					continue
				}
				distance := levenshtein(originalLine, searchLine)
				similarity += (1.0 - float64(distance)/float64(maxLen)) / float64(linesToCheck)

				if similarity >= 0.0 {
					break
				}
			}
		} else {
			similarity = 1.0
		}

		if similarity >= 0.0 {
			matchStartIndex := 0
			for k := 0; k < c.startLine; k++ {
				matchStartIndex += len(originalLines[k]) + 1
			}
			matchEndIndex := matchStartIndex
			for k := c.startLine; k <= c.endLine; k++ {
				matchEndIndex += len(originalLines[k])
				if k < c.endLine {
					matchEndIndex++
				}
			}
			return []string{content[matchStartIndex:matchEndIndex]}
		}
		return nil
	}

	// Multiple candidates - find best match
	var bestMatch *candidate
	maxSimilarity := -1.0

	for _, c := range candidates {
		actualBlockSize := c.endLine - c.startLine + 1
		similarity := 0.0
		linesToCheck := min(searchBlockSize-2, actualBlockSize-2)

		if linesToCheck > 0 {
			for j := 1; j < searchBlockSize-1 && j < actualBlockSize-1; j++ {
				originalLine := strings.TrimSpace(originalLines[c.startLine+j])
				searchLine := strings.TrimSpace(searchLines[j])
				maxLen := max(len(originalLine), len(searchLine))
				if maxLen == 0 {
					continue
				}
				distance := levenshtein(originalLine, searchLine)
				similarity += 1.0 - float64(distance)/float64(maxLen)
			}
			similarity /= float64(linesToCheck)
		} else {
			similarity = 1.0
		}

		if similarity > maxSimilarity {
			maxSimilarity = similarity
			bestMatch = &c
		}
	}

	if maxSimilarity >= 0.3 && bestMatch != nil {
		matchStartIndex := 0
		for k := 0; k < bestMatch.startLine; k++ {
			matchStartIndex += len(originalLines[k]) + 1
		}
		matchEndIndex := matchStartIndex
		for k := bestMatch.startLine; k <= bestMatch.endLine; k++ {
			matchEndIndex += len(originalLines[k])
			if k < bestMatch.endLine {
				matchEndIndex++
			}
		}
		return []string{content[matchStartIndex:matchEndIndex]}
	}

	return nil
}

// whitespaceNormalizedReplacer matches with normalized whitespace
func whitespaceNormalizedReplacer(content, find string) []string {
	normalizeWhitespace := func(text string) string {
		re := regexp.MustCompile(`\s+`)
		return strings.TrimSpace(re.ReplaceAllString(text, " "))
	}

	normalizedFind := normalizeWhitespace(find)
	var matches []string

	// Single line matches
	lines := strings.Split(content, "\n")
	for _, line := range lines {
		if normalizeWhitespace(line) == normalizedFind {
			matches = append(matches, line)
		} else {
			normalizedLine := normalizeWhitespace(line)
			if strings.Contains(normalizedLine, normalizedFind) {
				words := strings.Fields(find)
				if len(words) > 0 {
					pattern := ""
					for i, word := range words {
						pattern += regexp.QuoteMeta(word)
						if i < len(words)-1 {
							pattern += `\s+`
						}
					}
					re, err := regexp.Compile(pattern)
					if err == nil {
						match := re.FindString(line)
						if match != "" {
							matches = append(matches, match)
						}
					}
				}
			}
		}
	}

	// Multi-line matches
	findLines := strings.Split(find, "\n")
	if len(findLines) > 1 {
		for i := 0; i <= len(lines)-len(findLines); i++ {
			block := strings.Join(lines[i:i+len(findLines)], "\n")
			if normalizeWhitespace(block) == normalizedFind {
				matches = append(matches, block)
			}
		}
	}

	return matches
}

// indentationFlexibleReplacer matches with flexible indentation
func indentationFlexibleReplacer(content, find string) []string {
	removeIndentation := func(text string) string {
		lines := strings.Split(text, "\n")
		nonEmptyLines := []string{}
		for _, line := range lines {
			if strings.TrimSpace(line) != "" {
				nonEmptyLines = append(nonEmptyLines, line)
			}
		}
		if len(nonEmptyLines) == 0 {
			return text
		}

		minIndent := math.MaxInt32
		for _, line := range nonEmptyLines {
			re := regexp.MustCompile(`^(\s*)`)
			match := re.FindString(line)
			if len(match) < minIndent {
				minIndent = len(match)
			}
		}

		result := []string{}
		for _, line := range lines {
			if strings.TrimSpace(line) == "" {
				result = append(result, line)
			} else {
				if len(line) >= minIndent {
					result = append(result, line[minIndent:])
				} else {
					result = append(result, line)
				}
			}
		}
		return strings.Join(result, "\n")
	}

	normalizedFind := removeIndentation(find)
	contentLines := strings.Split(content, "\n")
	findLines := strings.Split(find, "\n")

	var matches []string
	for i := 0; i <= len(contentLines)-len(findLines); i++ {
		block := strings.Join(contentLines[i:i+len(findLines)], "\n")
		if removeIndentation(block) == normalizedFind {
			matches = append(matches, block)
		}
	}

	return matches
}

// escapeNormalizedReplacer handles escape sequences
func escapeNormalizedReplacer(content, find string) []string {
	unescapeString := func(str string) string {
		re := regexp.MustCompile(`\\(n|t|r|'|"|` + "`" + `|\\|\n|\$)`)
		return re.ReplaceAllStringFunc(str, func(match string) string {
			if len(match) < 2 {
				return match
			}
			switch match[1] {
			case 'n':
				return "\n"
			case 't':
				return "\t"
			case 'r':
				return "\r"
			case '\'':
				return "'"
			case '"':
				return "\""
			case '`':
				return "`"
			case '\\':
				return "\\"
			case '\n':
				return "\n"
			case '$':
				return "$"
			default:
				return match
			}
		})
	}

	unescapedFind := unescapeString(find)
	var matches []string

	if strings.Contains(content, unescapedFind) {
		matches = append(matches, unescapedFind)
	}

	lines := strings.Split(content, "\n")
	findLines := strings.Split(unescapedFind, "\n")

	for i := 0; i <= len(lines)-len(findLines); i++ {
		block := strings.Join(lines[i:i+len(findLines)], "\n")
		unescapedBlock := unescapeString(block)

		if unescapedBlock == unescapedFind {
			matches = append(matches, block)
		}
	}

	return matches
}

// trimmedBoundaryReplacer tries trimmed versions
func trimmedBoundaryReplacer(content, find string) []string {
	trimmedFind := strings.TrimSpace(find)

	if trimmedFind == find {
		return nil
	}

	var matches []string
	if strings.Contains(content, trimmedFind) {
		matches = append(matches, trimmedFind)
	}

	lines := strings.Split(content, "\n")
	findLines := strings.Split(find, "\n")

	for i := 0; i <= len(lines)-len(findLines); i++ {
		block := strings.Join(lines[i:i+len(findLines)], "\n")
		if strings.TrimSpace(block) == trimmedFind {
			matches = append(matches, block)
		}
	}

	return matches
}

// contextAwareReplacer uses context anchors
func contextAwareReplacer(content, find string) []string {
	findLines := strings.Split(find, "\n")
	if len(findLines) < 3 {
		return nil
	}

	if len(findLines) > 0 && findLines[len(findLines)-1] == "" {
		findLines = findLines[:len(findLines)-1]
	}

	contentLines := strings.Split(content, "\n")
	firstLine := strings.TrimSpace(findLines[0])
	lastLine := strings.TrimSpace(findLines[len(findLines)-1])

	for i := 0; i < len(contentLines); i++ {
		if strings.TrimSpace(contentLines[i]) != firstLine {
			continue
		}

		for j := i + 2; j < len(contentLines); j++ {
			if strings.TrimSpace(contentLines[j]) == lastLine {
				blockLines := contentLines[i : j+1]
				if len(blockLines) == len(findLines) {
					matchingLines := 0
					totalNonEmptyLines := 0

					for k := 1; k < len(blockLines)-1; k++ {
						blockLine := strings.TrimSpace(blockLines[k])
						findLine := strings.TrimSpace(findLines[k])

						if len(blockLine) > 0 || len(findLine) > 0 {
							totalNonEmptyLines++
							if blockLine == findLine {
								matchingLines++
							}
						}
					}

					if totalNonEmptyLines == 0 || float64(matchingLines)/float64(totalNonEmptyLines) >= 0.5 {
						block := strings.Join(blockLines, "\n")
						return []string{block}
					}
				}
				break
			}
		}
	}

	return nil
}

// multiOccurrenceReplacer finds all exact matches
func multiOccurrenceReplacer(content, find string) []string {
	var matches []string
	startIndex := 0

	for {
		index := strings.Index(content[startIndex:], find)
		if index == -1 {
			break
		}
		matches = append(matches, find)
		startIndex += index + len(find)
	}

	return matches
}

// levenshtein calculates the Levenshtein distance between two strings
func levenshtein(a, b string) int {
	if a == "" || b == "" {
		return max(len(a), len(b))
	}

	matrix := make([][]int, len(a)+1)
	for i := range matrix {
		matrix[i] = make([]int, len(b)+1)
		if i == 0 {
			for j := range matrix[i] {
				matrix[i][j] = j
			}
		} else {
			matrix[i][0] = i
		}
	}

	for i := 1; i <= len(a); i++ {
		for j := 1; j <= len(b); j++ {
			cost := 0
			if a[i-1] != b[j-1] {
				cost = 1
			}
			matrix[i][j] = min(
				matrix[i-1][j]+1,
				min(matrix[i][j-1]+1, matrix[i-1][j-1]+cost),
			)
		}
	}

	return matrix[len(a)][len(b)]
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

func max(a, b int) int {
	if a > b {
		return a
	}
	return b
}

// createDiff creates a unified diff between old and new content
func createDiff(filePath, oldContent, newContent string) string {
	if oldContent == newContent {
		return ""
	}

	oldLines := strings.Split(oldContent, "\n")
	newLines := strings.Split(newContent, "\n")

	// Simple unified diff header
	diff := fmt.Sprintf("--- %s\n+++ %s\n", filePath, filePath)

	// Generate context and changes
	var changes []string
	i := 0
	maxLen := len(oldLines)
	if len(newLines) > maxLen {
		maxLen = len(newLines)
	}

	for i < maxLen {
		// Find start of difference
		if i < len(oldLines) && i < len(newLines) && oldLines[i] == newLines[i] {
			i++
			continue
		}

		// Found a difference
		contextStart := i
		if contextStart > 3 {
			contextStart = i - 3
		} else {
			contextStart = 0
		}

		// Find end of difference
		j := i
		for j < len(oldLines) || j < len(newLines) {
			if j >= len(oldLines) || j >= len(newLines) {
				j++
				continue
			}
			if oldLines[j] != newLines[j] {
				j++
				continue
			}
			break
		}

		contextEnd := j + 3
		if contextEnd > len(oldLines) && contextEnd > len(newLines) {
			if len(oldLines) > len(newLines) {
				contextEnd = len(oldLines)
			} else {
				contextEnd = len(newLines)
			}
		}

		// Build hunk
		oldStart := contextStart + 1
		oldCount := min(contextEnd, len(oldLines)) - contextStart
		newStart := contextStart + 1
		newCount := min(contextEnd, len(newLines)) - contextStart

		changes = append(changes, fmt.Sprintf("@@ -%d,%d +%d,%d @@", oldStart, oldCount, newStart, newCount))

		// Add context and changes
		for k := contextStart; k < contextEnd; k++ {
			if k < i || (k < len(oldLines) && k < len(newLines) && oldLines[k] == newLines[k]) {
				// Context line
				if k < len(oldLines) {
					changes = append(changes, " "+oldLines[k])
				} else if k < len(newLines) {
					changes = append(changes, " "+newLines[k])
				}
			} else {
				// Changed lines
				if k < len(oldLines) && (k >= len(newLines) || oldLines[k] != newLines[k]) {
					changes = append(changes, "-"+oldLines[k])
				}
				if k < len(newLines) && (k >= len(oldLines) || oldLines[k] != newLines[k]) {
					changes = append(changes, "+"+newLines[k])
				}
			}
		}

		i = contextEnd
	}

	if len(changes) > 0 {
		diff += strings.Join(changes, "\n")
	}

	return trimDiff(diff)
}

// trimDiff removes common leading whitespace from diff output
func trimDiff(diff string) string {
	lines := strings.Split(diff, "\n")
	contentLines := []string{}

	for _, line := range lines {
		if (strings.HasPrefix(line, "+") || strings.HasPrefix(line, "-") || strings.HasPrefix(line, " ")) &&
			!strings.HasPrefix(line, "---") && !strings.HasPrefix(line, "+++") {
			contentLines = append(contentLines, line)
		}
	}

	if len(contentLines) == 0 {
		return diff
	}

	// Find minimum indentation
	minIndent := math.MaxInt32
	for _, line := range contentLines {
		content := ""
		if len(line) > 0 {
			content = line[1:]
		}
		if strings.TrimSpace(content) != "" {
			re := regexp.MustCompile(`^(\s*)`)
			match := re.FindString(content)
			if len(match) < minIndent {
				minIndent = len(match)
			}
		}
	}

	if minIndent == math.MaxInt32 || minIndent == 0 {
		return diff
	}

	// Trim common indentation
	trimmedLines := []string{}
	for _, line := range lines {
		if (strings.HasPrefix(line, "+") || strings.HasPrefix(line, "-") || strings.HasPrefix(line, " ")) &&
			!strings.HasPrefix(line, "---") && !strings.HasPrefix(line, "+++") {
			prefix := ""
			content := ""
			if len(line) > 0 {
				prefix = string(line[0])
				if len(line) > 1 {
					content = line[1:]
				}
			}
			if len(content) >= minIndent {
				trimmedLines = append(trimmedLines, prefix+content[minIndent:])
			} else {
				trimmedLines = append(trimmedLines, line)
			}
		} else {
			trimmedLines = append(trimmedLines, line)
		}
	}

	return strings.Join(trimmedLines, "\n")
}
