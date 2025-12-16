# Search in Chat History

<metadata>
  <priority>high</priority>
  <category>ui-enhancement</category>
  <estimated-complexity>medium</estimated-complexity>
  <affects>tui/internal/components/chat/, tui/internal/components/dialog/</affects>
</metadata>

## Objective

Implement full-text search within chat history, allowing users to find specific messages, code snippets, or tool outputs from their conversation.

<context>
Long conversations with AI agents can span hundreds of messages. Users need to quickly find:
- Previous code examples the agent provided
- Specific instructions they gave
- Tool outputs from earlier in the session
- Error messages that were discussed

Claude Code provides `ctrl+f` search functionality that highlights matches and allows navigation between results.
</context>

## Requirements

<functional-requirements>
1. Activate search with `ctrl+f` keybinding
2. Show search input overlay at top of chat area
3. Real-time filtering as user types
4. Highlight matching text in messages (yellow background)
5. Show match count: "3 of 12 matches"
6. Navigate between matches with `Enter`/`Shift+Enter` or `n`/`N`
7. Press `Esc` to close search and return to normal view
8. Search across:
   - User messages
   - Assistant text
   - Tool names and outputs
   - Code blocks
</functional-requirements>

<technical-requirements>
1. Create `SearchOverlay` component
2. Add search state to chat Model (`searchQuery`, `searchMatches`, `currentMatchIndex`)
3. Implement case-insensitive text search across message parts
4. Add highlight rendering in message display
5. Scroll to current match automatically
6. Support regex search (optional, advanced)
</technical-requirements>

## Implementation Guide

<files-to-modify>
- `tui/internal/components/chat/search.go` - New search component
- `tui/internal/components/chat/model.go` - Add search state
- `tui/internal/components/chat/message.go` - Add highlight rendering
- `tui/internal/app/update_keys.go` - Handle search keybinding
- `tui/internal/keybind/actions.go` - Add ActionSearch
</files-to-modify>

<search-state-structure>
```go
type SearchState struct {
    Active       bool
    Query        string
    Matches      []SearchMatch
    CurrentIndex int
    CaseSensitive bool
    UseRegex     bool
}

type SearchMatch struct {
    MessageIndex int
    PartIndex    int
    StartPos     int
    EndPos       int
    Preview      string  // Context around match
}
```
</search-state-structure>

<example-ui>
```
┌─────────────────────────────────────────────────────┐
│ 🔍 Search: login bug                    3 of 12 ▲▼  │
├─────────────────────────────────────────────────────┤
│ You                                                 │
│ Can you help me fix the [login bug]?                │
│                                     ^^^^^^^^^^      │
│                                     (highlighted)   │
│ Assistant                                           │
│ I found the [login bug] in the authentication...    │
│              ^^^^^^^^^^                             │
│ ● Read(src/auth/login.ts)                          │
│ └ Read 45 lines                                     │
│                                                     │
│ The [login bug] is caused by...                     │
│      ^^^^^^^^^^                                     │
└─────────────────────────────────────────────────────┘
  [Enter: next match] [Shift+Enter: prev] [Esc: close]
```
</example-ui>

<highlight-rendering>
```go
func highlightMatches(text string, query string, theme Theme) string {
    if query == "" {
        return text
    }

    highlightStyle := lipgloss.NewStyle().
        Background(theme.Warning).
        Foreground(theme.Background)

    // Case-insensitive search
    lowerText := strings.ToLower(text)
    lowerQuery := strings.ToLower(query)

    var result strings.Builder
    lastEnd := 0

    for {
        idx := strings.Index(lowerText[lastEnd:], lowerQuery)
        if idx == -1 {
            result.WriteString(text[lastEnd:])
            break
        }

        matchStart := lastEnd + idx
        matchEnd := matchStart + len(query)

        result.WriteString(text[lastEnd:matchStart])
        result.WriteString(highlightStyle.Render(text[matchStart:matchEnd]))
        lastEnd = matchEnd
    }

    return result.String()
}
```
</highlight-rendering>

## Acceptance Criteria

<criteria>
- [ ] `ctrl+f` opens search overlay
- [ ] Search updates results in real-time as user types
- [ ] Matches are highlighted in yellow/gold
- [ ] Match count displayed accurately
- [ ] `Enter`/`n` navigates to next match
- [ ] `Shift+Enter`/`N` navigates to previous match
- [ ] View scrolls to show current match
- [ ] `Esc` closes search and clears highlights
- [ ] Empty search shows all messages
- [ ] Search works across all message types (text, tools, code)
</criteria>

## Completion Instructions

<completion>
When this task is fully implemented and tested:
1. Verify all acceptance criteria are met
2. Run `zig build build-go` to ensure compilation succeeds
3. Test search with various query patterns
4. Rename this file from `04-search-chat-history.md` to `04-search-chat-history.complete.md`
</completion>
