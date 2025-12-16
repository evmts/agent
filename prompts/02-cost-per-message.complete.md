# Cost Per Message Display

<metadata>
  <priority>high</priority>
  <category>ui-enhancement</category>
  <estimated-complexity>low</estimated-complexity>
  <affects>tui/internal/components/chat/, sdk/agent/</affects>
</metadata>

## Objective

Display token usage and cost information for each individual message, not just session totals. This helps users understand which queries are expensive.

<context>
Claude Code shows token usage per response (e.g., "↑ 5.0k tokens") alongside each assistant message. This transparency helps users:
- Understand cost drivers
- Optimize their prompts
- Track context window usage
- Make informed decisions about conversation length
</context>

## Requirements

<functional-requirements>
1. Display token count for each assistant message: `↑ 2.3k tokens`
2. Optionally show cost per message: `$0.0023`
3. Show input vs output token breakdown on hover/expand
4. Aggregate to show cumulative cost in message header
5. Color-code expensive messages (e.g., >10k tokens = yellow, >50k = red)
</functional-requirements>

<technical-requirements>
1. Extend `Message` struct to include `InputTokens`, `OutputTokens`, `Cost` fields
2. Parse token information from API response in streaming handler
3. Update `RenderWithFullOptions()` to display token info
4. Add token info to message header or footer
5. Ensure SDK types support token metadata from API
</technical-requirements>

## Implementation Guide

<files-to-modify>
- `tui/internal/components/chat/message.go` - Add token display to message render
- `tui/internal/components/chat/model.go` - Update Message struct
- `tui/internal/components/chat/streaming.go` - Capture token info from events
- `sdk/agent/types.go` - Ensure token fields exist in response types
- `tui/internal/app/commands_message.go` - Pass token info to chat
</files-to-modify>

<example-ui>
```
Assistant (claude-sonnet-4-20250514)                    ↑ 2.3k tokens · $0.012
I'll help you implement the feature. Let me start by...

● Read(src/components/Button.tsx)
└ Read 89 lines

The Button component needs the following changes...
```
</example-ui>

<token-display-format>
```go
// Format examples:
// Small: "↑ 234 tokens"
// Medium: "↑ 2.3k tokens"
// Large: "↑ 15.2k tokens" (yellow)
// Very large: "↑ 52.1k tokens" (red)

func formatTokensWithColor(count int, theme Theme) string {
    formatted := formatTokens(count)
    style := lipgloss.NewStyle()

    switch {
    case count > 50000:
        style = style.Foreground(theme.Error)
    case count > 10000:
        style = style.Foreground(theme.Warning)
    default:
        style = style.Foreground(theme.Muted)
    }

    return style.Render("↑ " + formatted + " tokens")
}
```
</token-display-format>

## Acceptance Criteria

<criteria>
- [ ] Each assistant message shows token count
- [ ] Token count updates in real-time during streaming
- [ ] Cost is calculated and displayed (optional, based on model pricing)
- [ ] Large token counts are color-coded as warnings
- [ ] Total session tokens still shown in header/status bar
- [ ] Token info doesn't clutter the UI (subtle styling)
</criteria>

## Completion Instructions

<completion>
When this task is fully implemented and tested:
1. Verify all acceptance criteria are met
2. Run `zig build build-go` to ensure compilation succeeds
3. Test with various message sizes to verify formatting
4. Rename this file from `02-cost-per-message.md` to `02-cost-per-message.complete.md`
</completion>
