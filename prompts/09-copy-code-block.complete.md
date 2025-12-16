# Copy Code Block

<metadata>
  <priority>medium</priority>
  <category>ux-enhancement</category>
  <estimated-complexity>low</estimated-complexity>
  <affects>tui/internal/components/chat/</affects>
</metadata>

## Objective

Enable users to easily copy code blocks from chat messages to their clipboard with a single keypress or click.

<context>
Currently, the TUI shows "[Code block - select to copy]" hints but lacks actual copy functionality. Users must manually select text, which is cumbersome in terminal environments. Claude Code allows quick copying of code blocks via keyboard shortcuts.
</context>

## Requirements

<functional-requirements>
1. Detect and index all code blocks in messages
2. Navigate between code blocks with `[` and `]` keys
3. Copy current/selected code block with `c` or `ctrl+c` (when not in input)
4. Visual indication of selected code block (border highlight)
5. Show toast notification on copy: "Copied to clipboard!"
6. Support copying:
   - Fenced code blocks (```)
   - Inline code (`code`)
   - Tool output sections
7. Copy without the language identifier (just the code content)
</functional-requirements>

<technical-requirements>
1. Parse code blocks from markdown content
2. Track "focused" code block index
3. Implement clipboard access (OS-specific)
4. Add visual selection state to code block rendering
5. Handle multi-line code blocks properly
</technical-requirements>

## Implementation Guide

<files-to-modify>
- `tui/internal/components/chat/codeblock.go` - Code block detection and rendering
- `tui/internal/components/chat/model.go` - Track selected code block
- `tui/internal/clipboard/clipboard.go` - Cross-platform clipboard access
- `tui/internal/app/update_keys.go` - Handle copy keybindings
</files-to-modify>

<code-block-detection>
```go
type CodeBlock struct {
    MessageIndex int
    BlockIndex   int
    Language     string
    Content      string
    StartLine    int
    EndLine      int
}

func ExtractCodeBlocks(messages []Message) []CodeBlock {
    var blocks []CodeBlock
    codeBlockRegex := regexp.MustCompile("(?s)```(\\w*)\\n(.*?)```")

    for msgIdx, msg := range messages {
        for _, part := range msg.Parts {
            if part.IsText() {
                matches := codeBlockRegex.FindAllStringSubmatchIndex(part.Text, -1)
                for blockIdx, match := range matches {
                    lang := part.Text[match[2]:match[3]]
                    content := part.Text[match[4]:match[5]]
                    blocks = append(blocks, CodeBlock{
                        MessageIndex: msgIdx,
                        BlockIndex:   blockIdx,
                        Language:     lang,
                        Content:      content,
                    })
                }
            }
        }
    }
    return blocks
}
```
</code-block-detection>

<clipboard-implementation>
```go
// clipboard/clipboard.go
package clipboard

import (
    "os/exec"
    "runtime"
    "strings"
)

func Copy(text string) error {
    var cmd *exec.Cmd

    switch runtime.GOOS {
    case "darwin":
        cmd = exec.Command("pbcopy")
    case "linux":
        // Try xclip first, fall back to xsel
        if _, err := exec.LookPath("xclip"); err == nil {
            cmd = exec.Command("xclip", "-selection", "clipboard")
        } else {
            cmd = exec.Command("xsel", "--clipboard", "--input")
        }
    case "windows":
        cmd = exec.Command("clip")
    default:
        return fmt.Errorf("unsupported platform: %s", runtime.GOOS)
    }

    cmd.Stdin = strings.NewReader(text)
    return cmd.Run()
}
```
</clipboard-implementation>

<example-ui>
```
┌─────────────────────────────────────────────────────┐
│ Assistant                                           │
│                                                     │
│ Here's how to implement the function:               │
│                                                     │
│ ┌─ typescript ────────────────────────────────────┐ │
│ │ function calculateTotal(items: Item[]): number {│ │
│ │   return items.reduce((sum, item) => {          │ │
│ │     return sum + item.price * item.quantity;    │ │
│ │   }, 0);                                        │ │
│ │ }                                               │ │
│ └─────────────────────────────────────────────────┘ │
│ [1/3] Press 'c' to copy · '[' prev · ']' next       │
│                                                     │
│ And here's the test:                                │
│                                                     │
│ ┌─ typescript ────────────────────────────────────┐ │
│ │ describe('calculateTotal', () => {              │ │
│ │   it('should sum item totals', () => {          │ │
│ │     const items = [{price: 10, quantity: 2}];   │ │
│ │     expect(calculateTotal(items)).toBe(20);     │ │
│ │   });                                           │ │
│ │ });                                             │ │
│ └─────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────┘
```

Selected state (code block 1 highlighted):
```
│ ┏━ typescript ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓ │
│ ┃ function calculateTotal(items: Item[]): number {┃ │
│ ┃   return items.reduce((sum, item) => {          ┃ │
│ ┃     return sum + item.price * item.quantity;    ┃ │
│ ┃   }, 0);                                        ┃ │
│ ┃ }                                               ┃ │
│ ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛ │
│ [1/3] Press 'c' to copy                             │
```
</example-ui>

## Acceptance Criteria

<criteria>
- [ ] Code blocks detected in all messages
- [ ] `[` and `]` navigate between code blocks
- [ ] Selected code block has visible highlight
- [ ] `c` copies selected block to clipboard
- [ ] Toast shows "Copied to clipboard!"
- [ ] Works on macOS, Linux, and Windows
- [ ] Copies content only (no ``` markers or language tag)
- [ ] Tool outputs can also be copied
</criteria>

## Completion Instructions

<completion>
When this task is fully implemented and tested:
1. Verify all acceptance criteria are met
2. Run `zig build build-go` to ensure compilation succeeds
3. Test copy functionality on your OS
4. Rename this file from `09-copy-code-block.md` to `09-copy-code-block.complete.md`
</completion>
