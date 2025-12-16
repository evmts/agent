# Keyboard Shortcuts Overlay

<metadata>
  <priority>low</priority>
  <category>ux-enhancement</category>
  <estimated-complexity>low</estimated-complexity>
  <affects>tui/internal/components/dialog/</affects>
</metadata>

## Objective

Create a quick-reference keyboard shortcuts overlay that appears on `?` and shows all available keybindings organized by category.

<context>
While a help dialog exists, Claude Code provides a cleaner, more scannable shortcuts overlay that:
- Groups shortcuts by function
- Uses consistent formatting
- Can be quickly dismissed
- Shows context-sensitive shortcuts

This helps users discover and remember keybindings without leaving their workflow.
</context>

## Requirements

<functional-requirements>
1. Trigger with `?` key (when not typing in input)
2. Display shortcuts in organized columns:
   - Navigation
   - Session Management
   - View Controls
   - Actions
3. Show key combination prominently, description secondary
4. Dismiss with any key press
5. Semi-transparent overlay (don't completely hide chat)
6. Context-aware: show different shortcuts based on current state
7. Indicate shortcuts that are currently disabled
</functional-requirements>

<technical-requirements>
1. Create `ShortcutsOverlay` component (different from full HelpDialog)
2. Read shortcuts from KeyMap dynamically
3. Categorize shortcuts for display
4. Implement semi-transparent overlay rendering
5. Handle state-dependent shortcut availability
</technical-requirements>

## Implementation Guide

<files-to-modify>
- `tui/internal/components/dialog/shortcuts.go` - New shortcuts overlay
- `tui/internal/keybind/keybind.go` - Add category metadata to bindings
- `tui/internal/app/view.go` - Render overlay
- `tui/internal/app/update_keys.go` - Handle ? key
</files-to-modify>

<shortcut-categories>
```go
type ShortcutCategory string

const (
    CategoryNavigation ShortcutCategory = "Navigation"
    CategorySession    ShortcutCategory = "Session"
    CategoryView       ShortcutCategory = "View"
    CategoryActions    ShortcutCategory = "Actions"
    CategoryInput      ShortcutCategory = "Input"
    CategoryDialogs    ShortcutCategory = "Dialogs"
)

type CategorizedBinding struct {
    KeyBinding
    Category  ShortcutCategory
    Available bool  // Based on current state
}

func CategorizeBindings(km *KeyMap, state State) []CategorizedBinding {
    // Group bindings by category and mark availability
}
```
</shortcut-categories>

<example-ui>
```
┌─────────────────────────────────────────────────────────────────┐
│                      ⌨  Keyboard Shortcuts                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Navigation              Session                 View           │
│  ─────────────────       ───────────────         ──────────     │
│  j/k     Scroll          ctrl+n  New session     ctrl+/  Sidebar│
│  g/G     Top/bottom      ctrl+s  Switch session  ctrl+t  Think  │
│  PgUp    Page up         ctrl+f  Fork session    ctrl+r  Markdown│
│  PgDn    Page down       F2      Rename          T       Theme  │
│                          ctrl+z  Revert                         │
│                                                                 │
│  Actions                 Dialogs                 Input          │
│  ─────────────────       ───────────────         ──────────     │
│  Enter   Send message    ctrl+k  Commands        Esc     Cancel │
│  c       Copy code       ctrl+,  Settings        ctrl+u  Clear  │
│  ctrl+d  Show diff       ctrl+i  Status          ↑/↓     History│
│  m       Message menu    ctrl+m  Models          Tab     Complete│
│                          ctrl+a  Agents                         │
│                                                                 │
│  ───────────────────────────────────────────────────────────── │
│  shift+tab  Cycle permissions mode                              │
│                                                                 │
│                    Press any key to close                       │
└─────────────────────────────────────────────────────────────────┘
```

Overlay style (semi-transparent):
```
╔═══════════════════════════════════════════════════════════════════╗
║                                                                   ░
║  ┌─────────────────────────────────────────────────────────────┐ ░
║  │                  ⌨  Keyboard Shortcuts                       │ ░
║  │                                                               │ ░
║  │  [Content as above]                                           │ ░
║  │                                                               │ ░
║  └─────────────────────────────────────────────────────────────┘ ░
║                                                                   ░
╚═══════════════════════════════════════════════════════════════════╝
  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
```
</example-ui>

<context-aware-shortcuts>
```go
// Example: Show different shortcuts when streaming
func getContextualShortcuts(state State) []CategorizedBinding {
    base := getBaseShortcuts()

    switch state {
    case StateStreaming:
        // Add streaming-specific shortcuts
        return append(base, CategorizedBinding{
            KeyBinding: KeyBinding{Key: "Esc", Description: "Cancel streaming"},
            Category:   CategoryActions,
            Available:  true,
        })
    case StateIdle:
        // All shortcuts available
        return base
    default:
        return base
    }
}
```
</context-aware-shortcuts>

## Acceptance Criteria

<criteria>
- [ ] `?` opens shortcuts overlay
- [ ] Shortcuts organized in clear columns
- [ ] Key combinations prominently displayed
- [ ] Any key dismisses the overlay
- [ ] Overlay is semi-transparent (chat visible behind)
- [ ] Shortcuts grouped by category
- [ ] Disabled shortcuts shown as dimmed (if applicable)
- [ ] Responsive to terminal width
</criteria>

## Completion Instructions

<completion>
When this task is fully implemented and tested:
1. Verify all acceptance criteria are met
2. Run `zig build build-go` to ensure compilation succeeds
3. Test overlay at various terminal sizes
4. Rename this file from `11-keyboard-shortcuts-overlay.md` to `11-keyboard-shortcuts-overlay.complete.md`
</completion>
