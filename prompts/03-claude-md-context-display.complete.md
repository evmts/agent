# CLAUDE.md Context Display

<metadata>
  <priority>high</priority>
  <category>ui-enhancement</category>
  <estimated-complexity>medium</estimated-complexity>
  <affects>tui/internal/components/sidebar/, tui/internal/components/dialog/</affects>
</metadata>

## Objective

Display the contents of CLAUDE.md (project instructions) prominently in the TUI, allowing users to see what context the agent is working with.

<context>
Claude Code shows project instructions from CLAUDE.md files, helping users understand:
- What instructions the agent follows
- Project-specific guidelines and patterns
- Custom tool configurations
- Memory and context that persists across sessions

This transparency builds trust and helps users write better CLAUDE.md files.
</context>

## Requirements

<functional-requirements>
1. Add "Context" tab to sidebar showing CLAUDE.md contents
2. Support hierarchical CLAUDE.md display:
   - `~/.claude/CLAUDE.md` (global)
   - `./CLAUDE.md` (project root)
   - `./.claude/CLAUDE.md` (project config)
3. Show which files were found and loaded
4. Allow viewing full content in a dialog (for long files)
5. Indicate when CLAUDE.md is missing with helpful prompt
6. Auto-refresh when CLAUDE.md changes
</functional-requirements>

<technical-requirements>
1. Create `ContextTab` component in sidebar
2. Add file watcher for CLAUDE.md changes
3. Parse and render markdown content
4. Create `ContextDialog` for full-screen view
5. Add keybinding to quickly view context (`ctrl+.` or similar)
</technical-requirements>

## Implementation Guide

<files-to-modify>
- `tui/internal/components/sidebar/model.go` - Add Context tab
- `tui/internal/components/sidebar/context.go` - New file for context display
- `tui/internal/components/dialog/context.go` - Full context dialog
- `tui/internal/app/app.go` - Load CLAUDE.md on startup
- `tui/internal/app/update.go` - Handle context refresh
</files-to-modify>

<file-search-order>
```go
// Search order for CLAUDE.md files
var claudeMdPaths = []string{
    ".claude/CLAUDE.md",      // Project .claude directory
    "CLAUDE.md",              // Project root
    "~/.claude/CLAUDE.md",    // Global user config
}

type ContextSource struct {
    Path     string
    Content  string
    Priority int  // Lower = higher priority
    Exists   bool
}
```
</file-search-order>

<example-ui>
```
┌─ Context ────────────────────────┐
│ 📄 Project Instructions          │
│ ────────────────────────────────│
│ # My Project                     │
│                                  │
│ ## Guidelines                    │
│ - Use TypeScript strict mode     │
│ - Follow REST conventions        │
│ - Write tests for all features   │
│                                  │
│ ## File Structure                │
│ src/                             │
│   components/  - React components│
│   api/         - API handlers    │
│ ────────────────────────────────│
│ ℹ Loaded from: ./CLAUDE.md       │
│ 📏 245 lines · Updated 2m ago    │
│                                  │
│ [Press Ctrl+. for full view]     │
└──────────────────────────────────┘
```
</example-ui>

<missing-state-ui>
```
┌─ Context ────────────────────────┐
│ ⚠ No CLAUDE.md found             │
│                                  │
│ Create a CLAUDE.md file to give  │
│ the agent project-specific       │
│ instructions.                    │
│                                  │
│ Searched:                        │
│   ✗ .claude/CLAUDE.md            │
│   ✗ CLAUDE.md                    │
│   ✗ ~/.claude/CLAUDE.md          │
│                                  │
│ [Press N to create one]          │
└──────────────────────────────────┘
```
</missing-state-ui>

## Acceptance Criteria

<criteria>
- [ ] Sidebar shows Context tab with CLAUDE.md preview
- [ ] Multiple CLAUDE.md files are merged/displayed hierarchically
- [ ] Full dialog view available via keybinding
- [ ] Missing file state shows helpful guidance
- [ ] Content updates when file changes (file watcher)
- [ ] Markdown is rendered properly in preview
- [ ] Source file path is displayed
</criteria>

## Completion Instructions

<completion>
When this task is fully implemented and tested:
1. Verify all acceptance criteria are met
2. Run `zig build build-go` to ensure compilation succeeds
3. Test with various CLAUDE.md configurations
4. Rename this file from `03-claude-md-context-display.md` to `03-claude-md-context-display.complete.md`
</completion>
