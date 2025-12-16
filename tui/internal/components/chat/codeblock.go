package chat

import (
	"fmt"
	"regexp"
	"strings"

	"github.com/charmbracelet/lipgloss"
	"github.com/williamcory/agent/tui/internal/styles"
)

// CodeBlock represents a code block in the chat
type CodeBlock struct {
	MessageIndex int    // Index of the message containing this block
	PartIndex    int    // Index of the part within the message
	BlockIndex   int    // Index of this block within the part (for multiple blocks)
	Language     string // Programming language (e.g., "go", "python")
	Content      string // The actual code content (without ``` markers)
	StartLine    int    // Line number where block starts in the rendered text
	EndLine      int    // Line number where block ends in the rendered text
}

// CodeBlockState tracks code block navigation and selection
type CodeBlockState struct {
	Blocks       []CodeBlock // All code blocks in the current chat
	CurrentIndex int         // Index of currently selected block (-1 if none)
}

// NewCodeBlockState creates a new empty code block state
func NewCodeBlockState() CodeBlockState {
	return CodeBlockState{
		Blocks:       []CodeBlock{},
		CurrentIndex: -1,
	}
}

// ExtractCodeBlocks extracts all code blocks from messages
func (s *CodeBlockState) ExtractCodeBlocks(messages []Message) {
	s.Blocks = []CodeBlock{}
	s.CurrentIndex = -1

	// Regex to match fenced code blocks: ```language\n...code...```
	codeBlockRegex := regexp.MustCompile("(?s)```([a-zA-Z0-9_+-]*)\n(.*?)```")

	for msgIdx, msg := range messages {
		for partIdx, part := range msg.Parts {
			// Only extract from text and tool output parts
			var textContent string
			if part.IsText() {
				textContent = part.Text
			} else if part.IsTool() && part.State != nil && part.State.Output != "" {
				textContent = part.State.Output
			} else {
				continue
			}

			if textContent == "" {
				continue
			}

			// Find all code blocks in this part
			matches := codeBlockRegex.FindAllStringSubmatchIndex(textContent, -1)
			for blockIdx, match := range matches {
				// match[0] and match[1] are the full match positions
				// match[2] and match[3] are the language capture group positions
				// match[4] and match[5] are the content capture group positions

				language := ""
				if match[2] != -1 && match[3] != -1 {
					language = textContent[match[2]:match[3]]
				}

				content := ""
				if match[4] != -1 && match[5] != -1 {
					content = textContent[match[4]:match[5]]
				}

				s.Blocks = append(s.Blocks, CodeBlock{
					MessageIndex: msgIdx,
					PartIndex:    partIdx,
					BlockIndex:   blockIdx,
					Language:     language,
					Content:      content,
					StartLine:    -1, // Will be set during rendering if needed
					EndLine:      -1,
				})
			}
		}
	}

	// Set current index to first block if any exist
	if len(s.Blocks) > 0 {
		s.CurrentIndex = 0
	}
}

// NextBlock moves to the next code block
func (s *CodeBlockState) NextBlock() bool {
	if len(s.Blocks) == 0 {
		return false
	}
	if s.CurrentIndex < len(s.Blocks)-1 {
		s.CurrentIndex++
		return true
	}
	return false
}

// PrevBlock moves to the previous code block
func (s *CodeBlockState) PrevBlock() bool {
	if len(s.Blocks) == 0 {
		return false
	}
	if s.CurrentIndex > 0 {
		s.CurrentIndex--
		return true
	}
	return false
}

// HasBlocks returns true if there are any code blocks
func (s CodeBlockState) HasBlocks() bool {
	return len(s.Blocks) > 0
}

// GetCurrentBlock returns the currently selected code block
func (s CodeBlockState) GetCurrentBlock() *CodeBlock {
	if s.CurrentIndex >= 0 && s.CurrentIndex < len(s.Blocks) {
		return &s.Blocks[s.CurrentIndex]
	}
	return nil
}

// GetBlockCount returns the total number of code blocks
func (s CodeBlockState) GetBlockCount() int {
	return len(s.Blocks)
}

// IsBlockSelected returns true if a block is at the given indices
func (s CodeBlockState) IsBlockSelected(msgIdx, partIdx, blockIdx int) bool {
	block := s.GetCurrentBlock()
	if block == nil {
		return false
	}
	return block.MessageIndex == msgIdx &&
		block.PartIndex == partIdx &&
		block.BlockIndex == blockIdx
}

// RenderCodeBlockWithHighlight renders a code block with optional selection highlight
// This is used by the message renderer to highlight selected blocks
func RenderCodeBlockWithHighlight(language, content string, isSelected bool, width int) string {
	theme := styles.GetCurrentTheme()

	// Language header style
	langStyle := lipgloss.NewStyle().
		Foreground(theme.Muted).
		Italic(true)

	// Border style - use thicker/different style for selected blocks
	var borderStyle lipgloss.Style
	if isSelected {
		borderStyle = lipgloss.NewStyle().
			Border(lipgloss.ThickBorder()).
			BorderForeground(theme.Accent).
			Padding(0, 1).
			Width(width - 4)
	} else {
		borderStyle = lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(theme.Border).
			Padding(0, 1).
			Width(width - 4)
	}

	// Content style
	contentStyle := lipgloss.NewStyle().
		Foreground(theme.TextPrimary)

	// Build the code block display
	var sb strings.Builder

	// Language header
	if language != "" {
		sb.WriteString(langStyle.Render(language))
		sb.WriteString("\n")
	}

	// Code content
	sb.WriteString(contentStyle.Render(content))

	// Wrap in border
	result := borderStyle.Render(sb.String())

	// Add copy hint if selected
	if isSelected {
		hintStyle := lipgloss.NewStyle().
			Foreground(theme.Accent).
			Bold(true)
		copyHint := hintStyle.Render("  Press 'c' to copy")
		result = result + "\n" + copyHint
	}

	return result
}

// GetCodeBlockInfo returns a formatted string with block count and current index
func (s CodeBlockState) GetCodeBlockInfo() string {
	if !s.HasBlocks() {
		return ""
	}
	theme := styles.GetCurrentTheme()
	return lipgloss.NewStyle().
		Foreground(theme.Muted).
		Render(fmt.Sprintf("[%d/%d] Press 'c' to copy · '[' prev · ']' next",
			s.CurrentIndex+1, len(s.Blocks)))
}
