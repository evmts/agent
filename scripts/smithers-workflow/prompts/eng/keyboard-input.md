# Keyboard Shortcuts & Input

## 14. Keyboard Shortcuts & Input

### 14.1 Global shortcuts (both windows)

Defined as `.commands { }` in the `SmithersApp` scene builder:

| Shortcut | Action | Implementation |
|----------|--------|----------------|
| Cmd+S | Save current file | `appModel.workspace?.saveCurrentFile()` |
| Cmd+Shift+S | Save all files | `appModel.workspace?.saveAllFiles()` |
| Cmd+Shift+O | Open folder | System open panel → `appModel.openDirectory(url)` |
| Cmd+P | Go to file | Opens workspace panel if needed, then shows command palette |
| Cmd+Shift+F | Search in files | Opens workspace panel if needed, then shows search panel |

### 14.2 Chat window shortcuts

Handled within the chat view hierarchy:

| Shortcut | Action | Implementation |
|----------|--------|----------------|
| Return | Send message | Composer `.onSubmit` |
| Shift+Return | Insert newline | Default multiline TextField behavior |
| Cmd+N | New chat | `appModel.workspace?.chat.createNewSession()` |
| Cmd+V | Paste image | `.onPasteCommand(of: [UTType.image])` |
| Esc | Interrupt / defocus | If streaming: `appModel.workspace?.chat.interruptTurn()`. Else: `@FocusState = false` |

### 14.3 Workspace panel shortcuts

Handled within the workspace panel view hierarchy:

| Shortcut | Action | Implementation |
|----------|--------|----------------|
| Cmd+B | Toggle sidebar | SwiftUI NavigationSplitView sidebar visibility |
| Cmd+` | New terminal | `appModel.workspace?.tabs.openTerminal()` |
| Cmd+Shift+N | Toggle Neovim mode | `appModel.services.nvim?.toggle()` |
| Cmd+/ | Toggle shortcuts panel | `showShortcutsPanel.toggle()` |

### 14.4 Tmux-style prefix key

`TmuxKeyHandler` monitors keyboard events at the app level via `NSEvent.addLocalMonitorForEvents`. When Ctrl+A is pressed, it enters prefix mode and waits for the follow-up key:

- `c` → new terminal
- `n` → next tab
- `p` → previous tab
- `1`-`9` → select tab by index
- `&` → close tab
- `z` → toggle terminal zoom (full-pane)
- `|` → split vertical
- `-` → split horizontal

Timeout: if no follow-up key within 1s, cancel prefix mode. Show a subtle "Prefix" indicator in the status bar while in prefix mode.

**This is critical for the TUI-native experience.** Users coming from tmux expect these keybindings to work identically. The terminal should always be one keystroke away: Ctrl+A c opens a new terminal immediately.

### 14.5 Responder chain considerations

In a multi-window app, keyboard shortcuts need to route correctly. Global shortcuts (Cmd+S, Cmd+Shift+O) are defined in `.commands { }` and work regardless of which window is focused. Window-specific shortcuts (Cmd+B for IDE sidebar, Return for chat send) are handled by the focused window's responder chain.

The `NSEvent.addLocalMonitorForEvents` approach for tmux keys works across all windows. When in a terminal tab, Ctrl+A is intercepted by our handler (not passed to the terminal) — matching tmux behavior.

### 14.6 TUI-native keyboard philosophy

Every core action must be achievable without a mouse. The keyboard navigation flow:

- **Ctrl+A c** → new terminal (always, from any window)
- **Cmd+`** → new terminal (macOS-native alternative)
- **Cmd+P** → command palette (fuzzy find anything: files, commands, settings)
- **Cmd+K** → focus chat composer (from any window)
- **Esc** → dismiss current overlay / return to previous context
- **Tab / Shift+Tab** → cycle through panes within a window

The goal: a user who never touches their mouse should feel at home in Smithers.
