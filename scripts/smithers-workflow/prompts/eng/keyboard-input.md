# Keyboard Shortcuts & Input

## 14. Keyboard

### 14.1 Global (both windows)

`.commands { }` in `SmithersApp`:

| Shortcut | Action | Impl |
|----------|--------|------|
| Cmd+S | Save file | `appModel.workspace?.saveCurrentFile()` |
| Cmd+Shift+S | Save all | `appModel.workspace?.saveAllFiles()` |
| Cmd+Shift+O | Open folder | Open panel → `appModel.openDirectory(url)` |
| Cmd+P | Go to file | Open workspace if needed → command palette |
| Cmd+Shift+F | Search | Open workspace if needed → search panel |

### 14.2 Chat window

| Shortcut | Action | Impl |
|----------|--------|------|
| Return | Send | Composer `.onSubmit` |
| Shift+Return | Newline | Default multiline TextField |
| Cmd+N | New chat | `appModel.workspace?.chat.createNewSession()` |
| Cmd+V | Paste image | `.onPasteCommand(of: [UTType.image])` |
| Esc | Interrupt/defocus | Streaming: `chat.interruptTurn()`. Else: `@FocusState = false` |

### 14.3 Workspace panel

| Shortcut | Action | Impl |
|----------|--------|------|
| Cmd+B | Toggle sidebar | NavigationSplitView visibility |
| Cmd+` | New terminal | `workspace?.tabs.openTerminal()` |
| Cmd+Shift+N | Toggle Neovim | `services.nvim?.toggle()` |
| Cmd+/ | Shortcuts panel | `showShortcutsPanel.toggle()` |

### 14.4 Tmux prefix

`TmuxKeyHandler` monitors `NSEvent.addLocalMonitorForEvents`. Ctrl+A → prefix mode, wait follow-up:

`c` = new terminal; `n` = next tab; `p` = prev tab; `1-9` = tab by index; `&` = close tab; `z` = zoom terminal; `|` = split vert; `-` = split horiz.

Timeout 1s → cancel. Show "Prefix" in status bar during mode.

**Critical TUI-native.** tmux users expect identical bindings. Terminal one keystroke: Ctrl+A c.

### 14.5 Responder chain

Multi-window routing: global (Cmd+S, Cmd+Shift+O) in `.commands { }` work regardless focus. Window-specific (Cmd+B IDE, Return chat) via focused responder chain.

`NSEvent.addLocalMonitorForEvents` tmux keys work all windows. Terminal tab Ctrl+A intercepted (not passed) — tmux behavior.

### 14.6 TUI philosophy

Every action no-mouse. Nav flow: **Ctrl+A c** = terminal (always); **Cmd+`** = terminal (macOS alt); **Cmd+P** = palette (files, commands, settings); **Cmd+K** = chat composer (any window); **Esc** = dismiss/prev context; **Tab/Shift+Tab** = cycle panes.

Goal: mouse-free users at home.
