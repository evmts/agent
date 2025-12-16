# Interrupt Details Display

<metadata>
  <priority>medium</priority>
  <category>ux-enhancement</category>
  <estimated-complexity>low</estimated-complexity>
  <affects>tui/internal/app/, tui/internal/components/chat/</affects>
</metadata>

## Objective

When a user interrupts/cancels a streaming response, display details about what operation was in progress and allow resumption.

<context>
Claude Code shows what the agent was doing when interrupted:
- "Interrupted while: Reading src/auth/login.ts"
- "Interrupted while: Executing bash command"
- "Interrupted during: Thinking about implementation..."

This helps users understand:
- What work may be incomplete
- Whether to resume or start fresh
- What context might be lost
</context>

## Requirements

<functional-requirements>
1. Track current operation during streaming:
   - Tool executions (which tool, what arguments)
   - Thinking/reasoning state
   - Text generation
2. On interrupt (Esc/Ctrl+C), display:
   - What was being done: "Interrupted while: {operation}"
   - Partial progress if available
   - Options: [R] Resume, [N] New message, [Enter] Continue chatting
3. Show interrupted state in message with visual indicator
4. Allow resumption with "please continue" or [R] key
5. Log interrupted operations for debugging
</functional-requirements>

<technical-requirements>
1. Add `currentOperation` tracking to streaming state
2. Create `InterruptedMessage` display component
3. Store interrupt context for resume capability
4. Add visual styling for interrupted state
5. Handle various interrupt scenarios gracefully
</technical-requirements>

## Implementation Guide

<files-to-modify>
- `tui/internal/app/app.go` - Add interrupt tracking state
- `tui/internal/components/chat/interrupted.go` - Interrupted message display
- `tui/internal/app/update_keys.go` - Enhanced interrupt handling
- `tui/internal/app/commands_message.go` - Resume logic
</files-to-modify>

<interrupt-tracking>
```go
type InterruptContext struct {
    Timestamp   time.Time
    Operation   OperationType
    Description string
    ToolName    string
    ToolInput   map[string]interface{}
    PartialText string
    TokensUsed  int
    CanResume   bool
}

type OperationType int

const (
    OpThinking OperationType = iota
    OpGenerating
    OpToolExecution
    OpToolWaiting
)

func (m *Model) captureInterruptContext() InterruptContext {
    ctx := InterruptContext{
        Timestamp: time.Now(),
        CanResume: true,
    }

    // Determine current operation from streaming state
    if m.chat.IsThinking() {
        ctx.Operation = OpThinking
        ctx.Description = "Thinking about the response"
    } else if tool := m.chat.GetCurrentTool(); tool != nil {
        ctx.Operation = OpToolExecution
        ctx.ToolName = tool.Name
        ctx.ToolInput = tool.Input
        ctx.Description = fmt.Sprintf("Executing %s", tool.Name)
    } else {
        ctx.Operation = OpGenerating
        ctx.Description = "Generating response"
        ctx.PartialText = m.chat.GetPartialText()
    }

    return ctx
}
```
</interrupt-tracking>

<example-ui>
```
┌─────────────────────────────────────────────────────┐
│ Assistant                                           │
│                                                     │
│ I'll help you refactor the authentication module.   │
│ Let me start by reading the current implementation. │
│                                                     │
│ ● Read(src/auth/login.ts)                           │
│ └ Reading...                                        │
│                                                     │
│ ⚠ INTERRUPTED                                       │
│ ┌─────────────────────────────────────────────────┐ │
│ │ Stopped while: Reading src/auth/login.ts        │ │
│ │ Progress: 45% (234 of 520 lines)                │ │
│ │ Tokens used: 1,247                              │ │
│ │                                                 │ │
│ │ [R] Resume   [N] New message   [Enter] Continue │ │
│ └─────────────────────────────────────────────────┘ │
│                                                     │
└─────────────────────────────────────────────────────┘
```

For thinking interrupt:
```
│ ⚠ INTERRUPTED                                       │
│ ┌─────────────────────────────────────────────────┐ │
│ │ Stopped while: Thinking about implementation    │ │
│ │ Duration: 3.2s                                  │ │
│ │                                                 │ │
│ │ [R] Resume   [N] New message   [Enter] Continue │ │
│ └─────────────────────────────────────────────────┘ │
```

For text generation interrupt:
```
│ ⚠ INTERRUPTED                                       │
│ ┌─────────────────────────────────────────────────┐ │
│ │ Stopped while: Generating response              │ │
│ │ Partial output saved (847 characters)           │ │
│ │                                                 │ │
│ │ [R] Resume   [N] New message   [Enter] Continue │ │
│ └─────────────────────────────────────────────────┘ │
```
</example-ui>

<visual-styling>
```go
func renderInterruptedBanner(ctx InterruptContext, width int) string {
    theme := styles.GetCurrentTheme()

    // Warning banner style
    bannerStyle := lipgloss.NewStyle().
        Border(lipgloss.RoundedBorder()).
        BorderForeground(theme.Warning).
        Padding(0, 1).
        Width(width - 4)

    headerStyle := lipgloss.NewStyle().
        Foreground(theme.Warning).
        Bold(true)

    header := headerStyle.Render("⚠ INTERRUPTED")

    var content strings.Builder
    content.WriteString(fmt.Sprintf("Stopped while: %s\n", ctx.Description))

    if ctx.TokensUsed > 0 {
        content.WriteString(fmt.Sprintf("Tokens used: %s\n", formatTokens(ctx.TokensUsed)))
    }

    content.WriteString("\n[R] Resume   [N] New message   [Enter] Continue")

    return header + "\n" + bannerStyle.Render(content.String())
}
```
</visual-styling>

## Acceptance Criteria

<criteria>
- [ ] Current operation tracked during streaming
- [ ] Interrupt shows what was being done
- [ ] Tool name and arguments shown for tool interrupts
- [ ] Progress percentage shown when available
- [ ] [R] key resumes the operation
- [ ] [N] key allows new message input
- [ ] [Enter] returns to normal chat mode
- [ ] Interrupted messages visually distinct
- [ ] Partial output preserved and visible
</criteria>

## Completion Instructions

<completion>
When this task is fully implemented and tested:
1. Verify all acceptance criteria are met
2. Run `zig build build-go` to ensure compilation succeeds
3. Test interrupting various operation types
4. Rename this file from `10-interrupt-details.md` to `10-interrupt-details.complete.md`
</completion>
