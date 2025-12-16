# Compact/Conversation View Toggle

<metadata>
  <priority>high</priority>
  <category>ui-enhancement</category>
  <estimated-complexity>medium</estimated-complexity>
  <affects>tui/internal/components/chat/, tui/internal/app/</affects>
</metadata>

## Objective

Implement a compact view mode for the chat interface that collapses older messages to save vertical space, similar to Claude Code's conversation view.

<context>
Claude Code allows users to collapse conversation history to focus on recent messages. This is essential for long conversations where scrolling through hundreds of messages becomes unwieldy. The feature shows a "X messages hidden" indicator that can be expanded on demand.
</context>

## Requirements

<functional-requirements>
1. Add a toggle keybinding (`ctrl+shift+c` or similar) to switch between normal and compact view
2. In compact view:
   - Show only the last N messages (configurable, default 5)
   - Display a collapsible header: "▶ X earlier messages (click to expand)"
   - When expanded, show all messages with option to collapse again
3. Persist compact view preference in settings
4. Show visual indicator in status bar when compact mode is active
5. Auto-expand when user scrolls up past the collapsed section
</functional-requirements>

<technical-requirements>
1. Add `compactMode bool` and `compactMessageCount int` fields to chat Model
2. Create `renderCompactHeader()` function in `tui/internal/components/chat/`
3. Modify `View()` to conditionally render collapsed messages
4. Add keybinding to `tui/internal/keybind/actions.go` and `keybind.go`
5. Handle expansion/collapse state transitions
</technical-requirements>

## Implementation Guide

<files-to-modify>
- `tui/internal/components/chat/model.go` - Add compact mode state
- `tui/internal/components/chat/view.go` or equivalent - Render logic
- `tui/internal/app/update_keys.go` - Handle toggle keybinding
- `tui/internal/keybind/actions.go` - Add ActionToggleCompact
- `tui/internal/keybind/keybind.go` - Bind key to action
</files-to-modify>

<example-ui>
```
┌─────────────────────────────────────────┐
│ ▶ 23 earlier messages (press E to expand)│
├─────────────────────────────────────────┤
│ You                                      │
│ Can you help me fix the login bug?       │
│                                          │
│ Assistant                                │
│ I'll help you fix the login bug...       │
│ ● Read(src/auth/login.ts)                │
│ └ Read 45 lines                          │
└─────────────────────────────────────────┘
```
</example-ui>

## Acceptance Criteria

<criteria>
- [ ] Keybinding toggles compact mode on/off
- [ ] Collapsed header shows accurate message count
- [ ] Pressing expand key or clicking shows hidden messages
- [ ] Scroll behavior works correctly with collapsed messages
- [ ] Status bar indicates when compact mode is active
- [ ] Settings persist across sessions
- [ ] No performance degradation with large message histories
</criteria>

## Completion Instructions

<completion>
When this task is fully implemented and tested:
1. Verify all acceptance criteria are met
2. Run `zig build build-go` to ensure compilation succeeds
3. Test the feature manually in the TUI
4. Rename this file from `01-compact-view-toggle.md` to `01-compact-view-toggle.complete.md`
</completion>
