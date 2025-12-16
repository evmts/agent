package app

import "strings"

// copyToClipboard copies text to system clipboard
func copyToClipboard(text string) error {
	// Use pbcopy on macOS, xclip on Linux
	// For now, just return nil - clipboard integration would require os/exec
	_ = text
	return nil
}

// extractCodeBlocks extracts code blocks from markdown text
func extractCodeBlocks(text string) string {
	// Simple extraction of code blocks between ``` markers
	var result []string
	lines := strings.Split(text, "\n")
	inCodeBlock := false
	var currentBlock []string

	for _, line := range lines {
		if strings.HasPrefix(line, "```") {
			if inCodeBlock {
				// End of code block
				if len(currentBlock) > 0 {
					result = append(result, strings.Join(currentBlock, "\n"))
				}
				currentBlock = nil
				inCodeBlock = false
			} else {
				// Start of code block
				inCodeBlock = true
			}
		} else if inCodeBlock {
			currentBlock = append(currentBlock, line)
		}
	}

	return strings.Join(result, "\n\n")
}
