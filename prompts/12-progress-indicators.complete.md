# Progress Indicators

<metadata>
  <priority>low</priority>
  <category>ux-enhancement</category>
  <estimated-complexity>medium</estimated-complexity>
  <affects>tui/internal/components/chat/, tui/internal/components/progress/</affects>
</metadata>

## Objective

Add detailed progress indicators for long-running operations, showing percentage complete, estimated time, and operation details.

<context>
Claude Code shows progress for operations like:
- File reading: "Reading file... (234/520 lines)"
- Command execution: "Running command... (3.2s)"
- Search operations: "Searching... (checked 45/120 files)"

This feedback helps users understand:
- That the operation is progressing
- How long they might need to wait
- Whether to interrupt slow operations
</context>

## Requirements

<functional-requirements>
1. Show progress for:
   - File reads: line count progress
   - Glob/search: files checked count
   - Bash commands: elapsed time
   - Large file writes: bytes written
   - Web fetches: download progress
2. Display formats:
   - Percentage bar: `[████████░░] 80%`
   - Count: `(45/120 files)`
   - Time elapsed: `(3.2s)`
   - Size: `(2.3 MB / 10 MB)`
3. Update progress in real-time (minimum 100ms intervals)
4. Show estimated time remaining for long operations
5. Allow cancellation of slow operations
</functional-requirements>

<technical-requirements>
1. Extend tool state to include progress information
2. Backend must emit progress events via SSE
3. Create progress bar variants for different use cases
4. Debounce UI updates to prevent flicker
5. Calculate ETA based on progress rate
</technical-requirements>

## Implementation Guide

<files-to-modify>
- `tui/internal/components/progress/model.go` - Enhance progress component
- `tui/internal/components/chat/message.go` - Show progress in tool display
- `sdk/agent/types.go` - Add progress fields to tool state
- `tui/internal/components/chat/streaming.go` - Handle progress events
</files-to-modify>

<progress-state>
```go
type ToolProgress struct {
    Type         ProgressType
    Current      int64
    Total        int64
    Unit         string  // "lines", "files", "bytes"
    StartTime    time.Time
    LastUpdate   time.Time
    BytesPerSec  float64  // For ETA calculation
}

type ProgressType int

const (
    ProgressNone ProgressType = iota
    ProgressCount     // X of Y items
    ProgressBytes     // X of Y bytes
    ProgressTime      // Elapsed time only
    ProgressIndeterminate  // Spinner only
)

func (p ToolProgress) Percentage() float64 {
    if p.Total == 0 {
        return 0
    }
    return float64(p.Current) / float64(p.Total) * 100
}

func (p ToolProgress) ETA() time.Duration {
    if p.BytesPerSec == 0 || p.Current == 0 {
        return 0
    }
    remaining := p.Total - p.Current
    return time.Duration(float64(remaining) / p.BytesPerSec) * time.Second
}
```
</progress-state>

<progress-bar-rendering>
```go
func RenderProgressBar(progress ToolProgress, width int) string {
    theme := styles.GetCurrentTheme()

    pct := progress.Percentage()
    barWidth := width - 10  // Leave room for percentage

    filled := int(float64(barWidth) * pct / 100)
    empty := barWidth - filled

    bar := strings.Repeat("█", filled) + strings.Repeat("░", empty)

    barStyle := lipgloss.NewStyle().Foreground(theme.Success)
    pctStyle := lipgloss.NewStyle().Foreground(theme.TextSecondary)

    return fmt.Sprintf("[%s] %s",
        barStyle.Render(bar),
        pctStyle.Render(fmt.Sprintf("%3.0f%%", pct)))
}

func RenderCountProgress(current, total int64, unit string) string {
    return fmt.Sprintf("(%d/%d %s)", current, total, unit)
}

func RenderTimeProgress(elapsed time.Duration) string {
    if elapsed < time.Second {
        return fmt.Sprintf("(%.0fms)", float64(elapsed.Milliseconds()))
    }
    return fmt.Sprintf("(%.1fs)", elapsed.Seconds())
}
```
</progress-bar-rendering>

<example-ui>
```
# File reading with line progress:
● Read(src/components/DataTable.tsx)
└ Reading... [████████░░░░░░░░░░░░] 42% (210/500 lines)

# Glob search with file count:
● Glob(pattern: "**/*.ts")
└ Searching... (45/120 files checked)

# Bash command with elapsed time:
● Bash(npm install)
└ Running... (12.3s elapsed)

# Large file download:
● WebFetch(https://example.com/large-file.zip)
└ Downloading... [██████████████░░░░░░] 70% (7.0 MB / 10 MB) ETA: 8s

# Indeterminate progress (unknown total):
● Task(Analyzing codebase)
└ Processing... ⣾ (analyzing dependencies)
```
</example-ui>

<sse-progress-event>
```json
{
  "event": "tool.progress",
  "data": {
    "tool_id": "abc123",
    "progress": {
      "type": "count",
      "current": 45,
      "total": 120,
      "unit": "files",
      "message": "Searching for TypeScript files"
    }
  }
}
```
</sse-progress-event>

## Acceptance Criteria

<criteria>
- [ ] File reads show line count progress
- [ ] Glob/search shows files checked count
- [ ] Bash commands show elapsed time
- [ ] Web fetches show download progress with size
- [ ] Progress bar renders correctly at various widths
- [ ] ETA calculated for long operations
- [ ] Updates are smooth (no flicker)
- [ ] Indeterminate spinner for unknown totals
- [ ] Progress visible in tool output display
</criteria>

## Completion Instructions

<completion>
When this task is fully implemented and tested:
1. Verify all acceptance criteria are met
2. Run `zig build build-go` to ensure compilation succeeds
3. Test progress display with various operations
4. Rename this file from `12-progress-indicators.md` to `12-progress-indicators.complete.md`
</completion>
