# Keyboard Shortcuts

## 10) Shortcuts

### Global (both windows)

| Shortcut | Action |
|----------|--------|
| ⌘S | Save current file |
| ⌘⇧S | Save all |
| ⌘⇧O | Open folder |
| ⌘P | Go to file (opens IDE + palette if needed) |
| ⌘⇧F | Search in files (opens IDE + search panel if needed) |
| ⌘K | Focus chat composer (any window) |
| ⌘Q | Quit Smithers (explicit, not window close) |

### Chat window

| Shortcut | Action |
|----------|--------|
| Return | Send (or Steer if agent running) |
| Tab | Queue follow-up (if agent running) |
| ⇧Return | New line |
| ⌘N | New chat |
| ⌘V | Paste image |
| Esc | Interrupt (running) / defocus |
| ⌘↑/⌘↓ | Jump between messages |

### IDE window

| Shortcut | Action |
|----------|--------|
| ⌘B | Toggle sidebar |
| ⌘` | New terminal |
| ⌘⇧N | Toggle Neovim mode |
| ⌘/ | Toggle shortcuts panel |

### Tmux-style prefix (Ctrl+A)

`TmuxKeyHandler` monitors `NSEvent.addLocalMonitorForEvents`. Ctrl+A enters prefix mode awaits follow-up. **Critical TUI-native experience** — tmux users expect identical keybindings.

| Follow-up | Action |
|-----------|--------|
| c | New terminal |
| n | Next tab |
| p | Previous tab |
| 1–9 | Select tab by index |
| & | Close current tab |
| z | Toggle terminal zoom (full-pane) |
| \| | Split vertical |
| - | Split horizontal |

Prefix timeout 1s no follow-up cancels; "PREFIX" indicator status bar while active (6.4)

**Terminal always one keystroke away:** Ctrl+A c opens terminal immediately any context, must feel instantaneous

### TUI-native keyboard philosophy

Every core action achievable without mouse. Flow:

- Ctrl+A c → new terminal (always, any window)
- Cmd+` → new terminal (macOS-native alternative)
- Cmd+P → command palette (fuzzy find: files, commands, settings)
- Cmd+K → focus chat composer (any window)
- Esc → dismiss overlay / return previous context
- Tab / Shift+Tab → cycle panes within window

Goal: user never touches mouse feels at home in Smithers
